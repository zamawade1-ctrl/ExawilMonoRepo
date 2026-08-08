package com.moneyexchange.moneyexchange_app.forwarding

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Wakes on every incoming SMS (even when the app isn't running) and reacts based
 * on the configured [ForwardingMode]:
 *
 *  - [ForwardingMode.AUTO_FORWARD]: a Zaad (222) *money-in* message triggers an
 *    immediate balance sweep (dial `*800#`, read the balance, forward it), so
 *    money moves right away instead of waiting for the next interval tick.
 *
 *  - [ForwardingMode.MESSAGE_CHECK]: there's no timer at all — forwarding is
 *    driven entirely by an **898** balance message. When one arrives we read the
 *    balance straight out of that SMS and forward it via `*806#` directly,
 *    without dialing `*800#` first. The accessibility service still auto-fills
 *    the primary PIN on the `*806#` confirmation popup, exactly as in a sweep.
 *
 * Classification is safety-critical: the "you sent X" confirmation Zaad sends
 * after our own forward is treated as outgoing and ignored, so it never
 * re-triggers a forward (which would loop and drain the account) — see
 * [SmsMoneyParser].
 *
 * The forward itself runs in [ForwardingForegroundService], which holds the
 * background-activity-start privilege needed to launch the USSD call (a plain
 * broadcast receiver can't).
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        val sender = messages.first().originatingAddress?.trim().orEmpty()
        val body = messages.joinToString(separator = "") { it.messageBody ?: "" }

        val settings = ForwardingSettings(context)
        if (!settings.isReady()) {
            Log.d(TAG, "Money SMS seen but forwarding not fully configured/enabled; skipping.")
            return
        }

        when (settings.mode) {
            ForwardingMode.AUTO_FORWARD -> handleAutoForward(context, sender, body)
            ForwardingMode.MESSAGE_CHECK -> handleMessageCheck(context, sender, body)
        }
    }

    /** Auto-forward: a Zaad money-in SMS sweeps immediately (dial `*800#` then forward). */
    private fun handleAutoForward(context: Context, sender: String, body: String) {
        if (!isZaad(sender)) {
            Log.d(TAG, "Ignoring SMS from '$sender' (not Zaad).")
            return
        }
        val result = SmsMoneyParser.parse(body)
        Log.i(TAG, "Parse result: ${result.reason}")
        if (!result.isIncoming) return

        // The sweep re-reads the balance via *800#, so the SMS amount isn't used.
        ForwardingForegroundService.sweepNow(context)
    }

    /**
     * Message-check: an 898 balance SMS carries the amount to forward. Read the
     * balance out of it and forward that directly via `*806#` — no `*800#`.
     */
    private fun handleMessageCheck(context: Context, sender: String, body: String) {
        if (!is898(sender)) {
            Log.d(TAG, "Ignoring SMS from '$sender' (not 898).")
            return
        }
        // Hard block: never forward against our own send-confirmation / airtime.
        if (SmsMoneyParser.isOutgoingOrIgnorable(body)) {
            Log.i(TAG, "898 message is outgoing/ignorable; not forwarding.")
            return
        }
        val balance = BalanceParser.parse(body).balanceUsd
        if (balance == null) {
            Log.i(TAG, "898 message received but no balance could be parsed; skipping.")
            return
        }
        Log.i(TAG, "898 balance parsed ($balance); forwarding directly via *806#.")
        ForwardingForegroundService.forwardAmount(context, balance)
    }

    /** v1 targets Zaad Shilling, short code 222. */
    private fun isZaad(sender: String): Boolean =
        sender == "222" || sender.contains("ZAAD", ignoreCase = true)

    /** Check-messages mode keys off the balance short code 898. */
    private fun is898(sender: String): Boolean =
        sender == "898" || sender.contains("898")

    companion object {
        private const val TAG = "Xawil/SmsReceiver"
    }
}
