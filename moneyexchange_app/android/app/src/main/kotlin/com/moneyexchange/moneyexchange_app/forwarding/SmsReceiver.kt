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
 *  - [ForwardingMode.AUTO_FORWARD]: a Zaad *money-in* SMS triggers an immediate
 *    balance sweep (dial `*800#`, read the balance, forward it), on top of the
 *    periodic timer, so money moves right away instead of waiting for the next tick.
 *
 *  - [ForwardingMode.MESSAGE_CHECK]: there's no timer. Forwarding is driven ONLY by
 *    a **Zaad 898** dollar-exchange SMS ("…$X u sariftay…"). We read the exchanged
 *    dollar amount $X straight from that message and forward exactly $X to the
 *    destination (mobile `*806#` or the bank `*800#` deposit walk) — NO `*800#`
 *    balance check. **eDahab, and the duplicate 222 copy of the same exchange SMS,
 *    never trigger anything** — only the Zaad 898 copy.
 *
 * Safety: the same exchange is double-delivered (898 + 222, sometimes twice), so
 * forwards are deduped by the message's "Tixraac" reference to never double-send;
 * our own forward output ("…transferred $X to your bank account", "$X sent to …")
 * is not an exchange, so it never re-triggers a forward — see [SmsMoneyParser].
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
        // Always log the real sender + a body snippet: this line is what makes an
        // on-device diagnosis ("why didn't check-messages fire?") possible from
        // logcat without guessing at the exact originating address.
        Log.i(TAG, "SMS from '$sender' (mode=${settings.mode}, ready=${settings.isReady()}): '${body.take(80)}'")
        if (!settings.isReady()) {
            Log.d(TAG, "Money SMS seen but forwarding not fully configured/enabled; skipping.")
            return
        }
        // Plan gate: an expired trial/plan does nothing — no check-messages forward.
        if (!settings.isPlanActive()) {
            Log.i(TAG, "Money SMS seen but plan expired/inactive; skipping (no USSD).")
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
     * Check-messages: forward the exact dollar amount from a Zaad **898** exchange
     * SMS ("…$X u sariftay…"). We read $X ([SmsMoneyParser.exchangedUsd]) and forward
     * it straight to the destination (mobile `*806#` or the bank `*800#` deposit
     * walk) — NO `*800#` balance check.
     *
     * SAFETY: only sender 898 triggers (the identical 222 copy is ignored); the
     * "$X u sariftay" pattern excludes our own output ("transferred … to your bank
     * account", "$X sent to …"), cash-outs ("ka sarifatay"), and OTPs; and forwards
     * are deduped by the SMS "Tixraac" ref so a double-delivered exchange never
     * double-sends.
     */
    private fun handleMessageCheck(context: Context, sender: String, body: String) {
        // Only the Zaad 898 copy triggers (the identical 222 copy is ignored here).
        if (!SmsMoneyParser.isZaad898Sender(sender)) {
            Log.d(TAG, "Ignoring SMS from '$sender' (check-messages triggers only on Zaad 898, not eDahab/222).")
            return
        }
        // Read the exchanged dollar amount straight from the "$X u sariftay" message.
        val amount = SmsMoneyParser.exchangedUsd(body)
        if (amount == null) {
            Log.d(TAG, "898 SMS is not a dollar exchange ('\$X u sariftay'); ignoring.")
            return
        }
        // Dedup by a content SIGNATURE (dollars + shilling + counterparty phone) within a
        // time window: the same exchange is re-delivered — sometimes minutes apart with a
        // DIFFERENT "Tixraac" ref — and we must never forward, or count as received, the
        // same one twice. The signature is identical across every copy regardless of the
        // ref, so it catches the duplicates that ref-only dedup missed. The service
        // check-and-marks it atomically; [ref] still keys the ledger's RECEIVED/FORWARDED.
        val ref = SmsMoneyParser.exchangeRef(body)
        val signature = SmsMoneyParser.exchangeSignature(body) ?: SmsMoneyParser.dedupKey(body)
        Log.i(TAG, "898 exchange \$$amount (ref=${ref ?: "?"}, sig=$signature); forwarding that amount to the destination (no *800#).")
        ForwardingForegroundService.forwardAmountFromMessage(context, amount, signature, ref)
    }

    /** Auto-forward targets Zaad Shilling (sender 222 / "ZAAD"). */
    private fun isZaad(sender: String): Boolean =
        sender == "222" || sender.contains("ZAAD", ignoreCase = true)

    companion object {
        private const val TAG = "Xawil/SmsReceiver"
    }
}
