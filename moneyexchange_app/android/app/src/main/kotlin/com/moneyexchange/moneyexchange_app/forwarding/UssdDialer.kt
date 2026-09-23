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
     * Places EXACTLY ONE USSD call and returns whether it was placed. It does NOT retry
     * internally — a rejection/error (the "Connection problem / invalid MMI code" system
     * dialog, or a Zaad "Internal service error") is surfaced to the CALLER, whose own
     * await (balance read / send confirm) detects it via [UssdSession.mmiError] and
     * decides whether to retry. This keeps retry policy in ONE place: the balance read
     * does at most one spaced retry, a send its own bounded retry — so a single tick can
     * never burst a run of rapid `*800#` dials (the very thing that provokes the Zaad
     * error). Must be called from a context with background-activity-start privilege
     * (the foreground service) or the foreground, and from a background thread (it blocks
     * in [prepareForDial] to serialize + space the dial).
     *
     * ## Single-flight + cooldown (why Zaad stops erroring)
     * [prepareForDial] runs first and GUARANTEES we never dial on top of a live session —
     * the actual trigger for the error: it clears any leftover dialog, actively ends +
     * waits for ANY open telephony window to be GONE (not merely dismissed) so only one
     * `*800#` session is ever in flight, enforces a real minimum cooldown
     * ([MIN_DIAL_INTERVAL_MS], shared across balance/send and every caller so ticks,
     * the one retry and SMS forwards can't bunch up), then settles the radio.
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

        prepareForDial()
        UssdSession.clearMmiError()

        return try {
            val intent = Intent(Intent.ACTION_CALL, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                SimCards.phoneAccountHandle(context, subscriptionId)?.let { handle ->
                    putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                }
            }
            lastDialAtMs = SystemClock.elapsedRealtime()
            context.startActivity(intent)
            Log.i(TAG, "Dialed USSD ${redact(ussd)} on sub=$subscriptionId.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to place USSD call.", e)
            false
        }
    }

    /**
     * The gate every dial passes through, in order: clear leftovers → end + await any
     * open telephony window GONE → enforce the min cooldown measured from the PRIOR
     * SESSION'S END → settle the radio. Blocks the calling background thread. No
     * per-attempt backoff here — the caller owns retry spacing (a short backoff sleep
     * before its single retry) so this stays a plain "one dial, properly spaced" gate.
     */
    private fun prepareForDial() {
        // 1. Clear any leftover terminal result/error dialog (recognised-text janitor).
        UssdAccessibilityService.clearLeftoverResultDialog()

        // 2. Ensure NO telephony window is still open before we dial — actively ending a
        //    stale PIN/menu/confirm/balance dialog and waiting until it's gone, so this
        //    call never stacks on a half-torn-down session (Zaad's error trigger).
        awaitTelephonyWindowClear()

        // 3. Minimum cooldown measured from when the PREVIOUS USSD SESSION ENDED (its
        //    window last seen open), NOT from when the previous dial was placed. This is
        //    the fix for the real-transaction "Internal service error": a bank forward
        //    dials *800# twice per tick (balance read, then the deposit walk), and the
        //    ~13s spent driving the balance dialogs used to fully absorb a
        //    placement-anchored cooldown — so the deposit dial fired ~1.5s after the
        //    balance session's window closed, before Zaad had torn it down server-side.
        //    Anchoring to session-end guarantees a real quiet gap after the window is
        //    gone, however long the prior session ran. Falls back to the dial-placement
        //    clock only when the a11y service has never observed a USSD window (returns 0).
        val sessionEnd = UssdAccessibilityService.sessionEndAnchorMs()
        val anchor = if (sessionEnd > 0L) sessionEnd else lastDialAtMs
        val sinceEnd = SystemClock.elapsedRealtime() - anchor
        val wait = MIN_DIAL_INTERVAL_MS - sinceEnd
        if (wait > 0) {
            Log.i(TAG, "Cooldown before dial: waiting ${wait}ms (since prior session end).")
            SystemClock.sleep(wait)
        }

        // 4. Let the radio breathe after the window cleared, before placing the call.
        SystemClock.sleep(PRE_DIAL_SETTLE_MS)
    }

    /**
     * Blocks until no USSD/telephony dialog window is on screen, actively cancelling a
     * lingering one (a given-up attempt's PIN/menu/confirm, or the terminal balance
     * screen) each poll. Gives up after [WINDOW_CLEAR_TIMEOUT_MS] and dials anyway (the
     * cooldown + settle still space it out) rather than stalling the forward forever.
     */
    private fun awaitTelephonyWindowClear() {
        val deadline = SystemClock.elapsedRealtime() + WINDOW_CLEAR_TIMEOUT_MS
        while (SystemClock.elapsedRealtime() < deadline) {
            if (!UssdAccessibilityService.isTelephonyWindowOpen()) return
            UssdAccessibilityService.endOpenUssdDialog()
            SystemClock.sleep(WINDOW_POLL_MS)
        }
        Log.w(TAG, "A telephony window was still open after ${WINDOW_CLEAR_TIMEOUT_MS}ms; dialing anyway.")
    }

    /** The send command embeds the secondary PIN inline; keep it out of logs. */
    private fun redact(ussd: String): String =
        if (ussd.startsWith("*$SEND_PREFIX")) "*$SEND_PREFIX*…#" else ussd

    /**
     * Elapsed-realtime of the last USSD call we placed. FALLBACK cooldown anchor only —
     * used when the a11y service has never observed a USSD window (so it can't report a
     * session-end time). The primary anchor is
     * [UssdAccessibilityService.sessionEndAnchorMs] (see [prepareForDial]). `@Volatile`
     * because it's written on the sweep thread and could be read from another.
     */
    @Volatile
    private var lastDialAtMs: Long = 0L

    /**
     * Real minimum QUIET GAP between the end of one USSD session and the start of the
     * next dial. Zaad's gateway returns "Internal service error please try again" when a
     * `*800#` session is opened too soon after the previous one closed (its server-side
     * teardown lags the on-screen dialog close); this is the floor that prevents it.
     * Measured from session-END, so a long-running prior session no longer eats the gap.
     */
    private const val MIN_DIAL_INTERVAL_MS = 8_000L

    /** Fixed radio settle after the telephony window is confirmed clear, before dialing. */
    private const val PRE_DIAL_SETTLE_MS = 1_200L

    /** How long [awaitTelephonyWindowClear] waits for a lingering USSD window to close. */
    private const val WINDOW_CLEAR_TIMEOUT_MS = 8_000L
    private const val WINDOW_POLL_MS = 300L
}
