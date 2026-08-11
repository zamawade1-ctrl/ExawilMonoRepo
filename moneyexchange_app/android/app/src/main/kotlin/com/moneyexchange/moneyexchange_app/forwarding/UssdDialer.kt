package com.moneyexchange.moneyexchange_app.forwarding

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.SystemClock
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Places the two USSD calls of one balance-sweep cycle:
 *
 *   - [dialBalanceCheck] dials `*800#` — the interactive balance menu. The
 *     [UssdAccessibilityService] then types the primary PIN, picks menu option 1,
 *     and reads the balance + account number off the result screen.
 *   - [dialSend] dials `*806*<destination>*<amount>*<secondaryPin>#` — the send
 *     command, whose confirmation popup the accessibility service completes by
 *     typing the primary PIN.
 *
 * We dial via ACTION_CALL (not TelephonyManager.sendUssdRequest) because both
 * flows are interactive multi-step dialogs that sendUssdRequest can't answer.
 * Session state (which step we're on, which PINs to type) lives in [UssdSession];
 * the dialer itself only places calls and never holds a PIN.
 *
 * On dual-SIM phones the call is routed onto the SIM chosen in the app via the
 * resolved [android.telecom.PhoneAccountHandle] (see [SimCards]); -1 uses the
 * system default.
 */
object UssdDialer {

    private const val TAG = "Xawil/UssdDialer"

    /** Balance-check short code: `*800#`. */
    private const val BALANCE_PREFIX = "800"

    /** Send-money short code: `*806*dest*amount*secondaryPin#`. */
    private const val SEND_PREFIX = "806"

    fun buildBalanceCheck(): String = "*$BALANCE_PREFIX#"

    fun buildSend(destination: String, amount: String, secondaryPin: String): String =
        "*$SEND_PREFIX*$destination*$amount*$secondaryPin#"

    /** Dials `*800#` to open the balance menu. */
    fun dialBalanceCheck(context: Context, subscriptionId: Int): Boolean =
        dial(context, buildBalanceCheck(), subscriptionId)

    /** Dials `*806*destination*amount*secondaryPin#` to send the swept balance. */
    fun dialSend(
        context: Context,
        destination: String,
        amount: String,
        secondaryPin: String,
        subscriptionId: Int,
    ): Boolean = dial(context, buildSend(destination, amount, secondaryPin), subscriptionId)

    /**
     * Places the USSD call, retrying if the system rejects it with the "Connection
     * problem or invalid MMI code." dialog. That rejection (radio busy / a prior USSD
     * session not fully torn down / dialed too fast) is a PRE-submission failure — no
     * money moved — so re-dialing is safe and recovers a forward that would otherwise
     * be recorded as failed. Must be called from a context that currently has
     * background-activity-start privilege (the foreground service) or the foreground,
     * and from a background thread (it blocks briefly to watch the dial's outcome).
     */
    private fun dial(context: Context, ussd: String, subscriptionId: Int): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "CALL_PHONE not granted; cannot dial USSD.")
            return false
        }

        // '#' must be percent-encoded (%23) or the dialer truncates the code.
        val uri = Uri.parse("tel:" + Uri.encode(ussd))
        // Progress = the a11y service acted on the freshly-dialed dialog and moved the
        // session forward; compared against the step as it stands right before we dial.
        val stepBefore = UssdSession.step

        for (attempt in 1..MAX_DIAL_ATTEMPTS) {
            // Sweep away any leftover result/error dialog still on screen (from a prior
            // cycle or a just-rejected attempt) so it can't block this call, then let
            // the radio / prior USSD session settle before dialing — dialing on top of
            // a not-yet-torn-down session is what triggers the MMI-error rejection.
            UssdAccessibilityService.clearLeftoverResultDialog()
            SystemClock.sleep(if (attempt == 1) FIRST_SETTLE_MS else RETRY_SETTLE_MS)
            UssdSession.clearMmiError()

            val placed = try {
                val intent = Intent(Intent.ACTION_CALL, uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    SimCards.phoneAccountHandle(context, subscriptionId)?.let { handle ->
                        putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                    }
                }
                context.startActivity(intent)
                Log.i(TAG, "Dialed USSD ${redact(ussd)} on sub=$subscriptionId (attempt $attempt).")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to place USSD call (attempt $attempt).", e)
                false
            }
            if (!placed) continue

            // Watch briefly: an MMI-error rejection → retry; forward progress (or no
            // clear signal) → treat as dialed and let the caller's await drive on.
            if (!awaitMmiError(stepBefore)) return true
            Log.w(TAG, "USSD dial rejected as MMI error; retrying (attempt $attempt/$MAX_DIAL_ATTEMPTS).")
        }

        Log.e(TAG, "USSD dial still rejected after $MAX_DIAL_ATTEMPTS attempts.")
        return false
    }

    /**
     * After a call is placed, watches the shared session for a short window and
     * returns true ONLY if the dial was rejected with an MMI-error dialog (so the
     * caller retries). Returns false as soon as the a11y service makes forward
     * progress (step advanced or balance captured → the dial succeeded), or if the
     * window elapses with no signal (a slow-but-fine dial — the caller's own step
     * timeout is the backstop).
     */
    private fun awaitMmiError(stepBefore: UssdSession.Step): Boolean {
        val deadline = SystemClock.elapsedRealtime() + DIAL_WATCH_MS
        while (SystemClock.elapsedRealtime() < deadline) {
            if (UssdSession.mmiError) return true
            if (UssdSession.step != stepBefore || UssdSession.balanceUsd != null) return false
            SystemClock.sleep(DIAL_POLL_MS)
        }
        return false
    }

    /** The send command embeds the secondary PIN inline; keep it out of logs. */
    private fun redact(ussd: String): String =
        if (ussd.startsWith("*$SEND_PREFIX")) "*$SEND_PREFIX*…#" else ussd

    /** How many times to (re-)dial when the system rejects the code with an MMI error. */
    private const val MAX_DIAL_ATTEMPTS = 3

    /** Settle before the first dial — lets the leftover-dialog clear run + radio breathe. */
    private const val FIRST_SETTLE_MS = 350L

    /** Longer settle before a retry, to give a busy radio / prior session time to clear. */
    private const val RETRY_SETTLE_MS = 1_500L

    /** How long after a dial to watch for an MMI-error rejection vs. forward progress. */
    private const val DIAL_WATCH_MS = 6_000L
    private const val DIAL_POLL_MS = 200L
}
