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

        // FORWARDED ledger source of truth: a Zaad 898 "…successfully transferred $X
        // to your bank account…" confirmation means exactly $X actually landed in the
        // bank. Record that (deduped by its Transfer-Id) as the FORWARDED event the
        // dashboard sums — instead of the amount we estimated at USSD-send time, which
        // could double-count across retries/sweeps. This is bookkeeping for money that
        // already left, so it's recorded regardless of mode and NOT gated on the plan
        // being active (a confirmation can land just after expiry). It never triggers a
        // forward: the body has no "received"/"u sariftay" marker, so both handlers
        // below ignore it. Then return — a confirmation is never itself a trigger.
        if (SmsMoneyParser.isZaad898Sender(sender) &&
            SmsMoneyParser.isBankTransferConfirmation(body)
        ) {
            recordBankConfirmation(context, body)
            return
        }

        // Mobile FORWARDED source of truth (mirrors the bank case above): a Zaad 898
        // "…$X sent to…" / "…$X ayaad u dirtay…" / "transferred $X to <name>" confirmation
        // means exactly $X actually left to the destination mobile number. Record that as
        // the FORWARDED event — the real, confirmed amount — instead of the send-time
        // estimate, which could count a transfer that never completed. Because that same
        // wording is ALSO what Zaad sends for the user's OWN manual sends, we only record
        // it when it matches a forward WE just drove (a pending mobile send); otherwise
        // it's ignored. Bookkeeping for money that already left, so it's not gated on the
        // plan being active, and it never triggers a forward (SENT marker). Then return.
        if (SmsMoneyParser.isZaad898Sender(sender) &&
            SmsMoneyParser.isMobileTransferConfirmation(body)
        ) {
            recordMobileConfirmation(context, settings, body)
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

    /**
     * Records the authoritative FORWARDED event off a Zaad bank-transfer confirmation
     * ("…successfully transferred $X to your bank account…"). The amount is the exact
     * `$X` that landed in the bank, and the ledger is deduped by the "Transfer-Id" so
     * a double-delivered confirmation (or the same one seen twice) counts once. The
     * whole-dollar send always confirms as a whole dollar, but we preserve whatever
     * `$X` the SMS states verbatim.
     */
    private fun recordBankConfirmation(context: Context, body: String) {
        val amount = SmsMoneyParser.bankTransferUsd(body) ?: return
        val ref = SmsMoneyParser.bankTransferRef(body)
        Log.i(TAG, "Bank-transfer confirmation: \$$amount landed in bank (Transfer-Id=${ref ?: "?"}); recording FORWARDED.")
        TransactionStore.record(
            context,
            TransactionStore.TYPE_FORWARDED,
            amount,
            destination = "Bank account",
            method = ForwardingMethod.BANK_ACCOUNT.ordinal,
            status = TransactionStore.STATUS_SUCCESS,
            provider = "Zaad",
            // Never-null key: the Transfer-Id when present, else a body hash — so a
            // re-delivered confirmation with no parseable id still can't double-count.
            dedupeKey = "fwd:${ref ?: "b:" + body.trim().replace(Regex("\\s+"), " ").hashCode()}",
        )
    }

    /**
     * Records the authoritative FORWARDED event off a Zaad mobile-forward confirmation
     * ("…$X sent to…", "…$X ayaad u dirtay…", or "transferred $X to <name>"). The amount
     * is the exact `$X` that left to the destination mobile number.
     *
     * SAFETY: a "sent to" SMS is also what Zaad sends for the user's OWN manual sends, so
     * we record it ONLY when it matches a forward WE drove — a pending mobile send parked
     * by [ForwardingForegroundService.recordForwarded]. No match ⇒ not ours ⇒ ignored, so
     * the dashboard's forwarded total is never inflated by unrelated sends. Deduped by the
     * confirmation's Ref/Transfer-Id (falling back to a body hash) so a double-delivered
     * confirmation counts once.
     */
    private fun recordMobileConfirmation(context: Context, settings: ForwardingSettings, body: String) {
        val amount = SmsMoneyParser.mobileTransferUsd(body) ?: return
        if (!settings.consumePendingMobileForward(amount)) {
            Log.i(TAG, "Mobile 'sent to' \$$amount confirmation with no matching pending forward; not ours, ignoring.")
            return
        }
        val ref = SmsMoneyParser.mobileTransferRef(body)
        Log.i(TAG, "Mobile-forward confirmation: \$$amount left to destination (Ref=${ref ?: "?"}); recording FORWARDED.")
        TransactionStore.record(
            context,
            TransactionStore.TYPE_FORWARDED,
            amount,
            destination = settings.destination,
            method = ForwardingMethod.MOBILE_NUMBER.ordinal,
            status = TransactionStore.STATUS_SUCCESS,
            provider = "Zaad",
            // Never-null key: the confirmation's Ref/Transfer-Id when present, else a body
            // hash — so a re-delivered confirmation with no parseable id still can't double-count.
            dedupeKey = "fwd:${ref ?: "b:" + body.trim().replace(Regex("\\s+"), " ").hashCode()}",
        )
    }

    /** Auto-forward targets Zaad Shilling (sender 222 / "ZAAD"). */
    private fun isZaad(sender: String): Boolean =
        sender == "222" || sender.contains("ZAAD", ignoreCase = true)

    companion object {
        private const val TAG = "Xawil/SmsReceiver"
    }
}
