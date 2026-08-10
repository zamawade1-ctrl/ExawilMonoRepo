package com.moneyexchange.moneyexchange_app.forwarding

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import kotlin.math.floor

/**
 * Foreground service that runs the balance-sweep auto-forwarder. Each sweep runs
 * one full cycle:
 *
 *   1. dial `*800#`, and via [UssdAccessibilityService]: type primary PIN, pick
 *      menu option 1, read the balance + account number;
 *   2. if the balance is at least $1, dial `*806*dest*amount*secondaryPin#` and
 *      type the primary PIN on the confirmation popup.
 *
 * The two modes forward differently:
 *  - [ForwardingMode.AUTO_FORWARD]: on a timer, every `intervalMinutes`, runs a
 *    full `*800#` **balance sweep** ([ACTION_SWEEP_NOW]) and forwards the balance —
 *    the persistent, always-on poller.
 *  - [ForwardingMode.MESSAGE_CHECK]: no timer, and NO `*800#` balance check. Each
 *    time [SmsReceiver] sees a **Zaad 898** dollar-exchange SMS it forwards the
 *    exact exchanged amount read from that SMS ([ACTION_FORWARD_AMOUNT]), then stops
 *    itself again. eDahab / the duplicate 222 copy never trigger anything; forwards
 *    are deduped by the SMS ref so a double-delivered exchange can't double-send.
 *
 * ## Interval accuracy (why AlarmManager, not postDelayed)
 * The periodic tick is driven by an **exact AlarmManager alarm**, scheduled at a
 * FIXED RATE anchored to each tick's scheduled time — not by re-posting a delayed
 * runnable after the sweep finishes. Two reasons, both of which previously made a
 * "1 minute" interval take much longer:
 *  1. A sweep blocks for up to ~1 minute (dial + drive dialogs). Re-posting
 *     `interval` *after* it returned made the real period `sweep + interval`.
 *     Anchoring the next alarm to the scheduled tick time keeps it start-to-start.
 *  2. `Handler.postDelayed` is suspended in Doze — exactly the "phone locked at
 *     night" case. `setExactAndAllowWhileIdle` fires through Doze (given the
 *     battery-optimization exemption the app requests).
 *
 * ## Running with the screen off / locked
 * Each sweep runs inside a [PowerManager.WakeLock] so the CPU can't sleep
 * mid-cycle when the screen is off, and the screen is woken so the interactive
 * USSD dialog can render and be driven at night. See [withWakeLock].
 *
 * All sweeps run on one background [HandlerThread] and are gated by [sweepBusy],
 * so a periodic tick and an on-demand sweep are serialized and never overlap or
 * pile up. The service carries the background-activity-start privilege the dialer
 * needs to launch USSD calls.
 */
class ForwardingForegroundService : Service() {

    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null

    /**
     * Serializes USSD work: the phone shows one USSD dialog at a time and the
     * accessibility service drives one flow, so two sweeps must never overlap
     * (overlapping money operations are dangerous). But a MANUAL pull-to-refresh
     * is never dropped — if a sweep is already running it's queued via
     * [manualQueued] and runs the instant that one finishes. Periodic ticks and
     * 898 sends simply skip when busy, since they recur on their own, so the
     * interval timer and a manual refresh can never jam each other.
     */
    private val sweepLock = Any()
    private var sweepRunning = false
    private var manualQueued = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        ensureHandler()

        when (intent?.action) {
            ACTION_STOP -> stopEverything()

            ACTION_SWEEP_NOW -> {
                // A sweep dials *800#, reads the REAL balance, and forwards it. This is
                // the auto-forward path (timer / manual refresh / manual "sweep now"
                // button). Check-messages does NOT use this — it forwards the exact
                // exchanged amount from the SMS (ACTION_FORWARD_AMOUNT). Only
                // auto-forward re-anchors its interval; after any non-poller sweep the
                // service stands itself down (see [stopIfNotAutoForwardPoller]).
                if (ForwardingSettings(this).mode == ForwardingMode.AUTO_FORWARD) {
                    resetIntervalCountdown()
                }
                requestManualSweep()
            }

            ACTION_FORWARD_AMOUNT -> {
                // Check-messages: a Zaad 898 exchange SMS arrived; [SmsReceiver] already
                // read the exchanged dollar amount. Forward exactly that amount to the
                // destination — NO *800# balance check — deduped by the SMS's ref so a
                // double-delivered exchange can't double-send.
                val amount = intent.getDoubleExtra(EXTRA_AMOUNT_USD, 0.0)
                val ref = intent.getStringExtra(EXTRA_REF)
                requestDirectForward(amount, ref)
            }

            ACTION_TICK -> {
                val settings = ForwardingSettings(this)
                if (!settings.enabled || settings.mode != ForwardingMode.AUTO_FORWARD) {
                    Log.i(TAG, "Tick fired but auto-forwarding is off/mode changed; stopping poller.")
                    stopEverything()
                } else {
                    // Schedule the NEXT tick immediately, anchored to THIS tick's
                    // scheduled time, so the cadence stays fixed-rate regardless of
                    // how long the sweep below takes. Then run the periodic sweep
                    // (skipped if one is already running — the next tick is set).
                    val scheduledAt = intent.getLongExtra(EXTRA_SCHEDULED_AT, SystemClock.elapsedRealtime())
                    scheduleNextTick(scheduledAt)
                    requestPeriodicSweep()
                }
            }

            // ACTION_START, or a sticky restart (null intent): only start the
            // timer in AUTO_FORWARD mode. In MESSAGE_CHECK mode there's nothing to
            // do until SmsReceiver fires ACTION_FORWARD_AMOUNT, so just stop again.
            else -> {
                if (ForwardingSettings(this).mode == ForwardingMode.AUTO_FORWARD) {
                    startPeriodic()
                } else {
                    stopEverything()
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handlerThread?.quitSafely()
        handlerThread = null
        handler = null
        super.onDestroy()
    }

    private fun ensureHandler() {
        if (handler != null) return
        val thread = HandlerThread("xawil-sweep").also { it.start() }
        handlerThread = thread
        handler = Handler(thread.looper)
    }

    /**
     * Manual pull-to-refresh sweep. NEVER dropped: sets [manualQueued] and, if no
     * sweep is running, starts the worker now; otherwise the running worker picks
     * it up the moment it finishes. So every swipe-down results in a USSD run —
     * immediately when idle, or right after the current sweep when busy — without
     * waiting for the interval timer.
     */
    private fun requestManualSweep() {
        synchronized(sweepLock) {
            manualQueued = true
            if (sweepRunning) {
                Log.i(TAG, "Sweep running; manual refresh queued to run right after.")
                return
            }
            sweepRunning = true
        }
        postSweepWorker()
    }

    /**
     * Periodic interval sweep. Runs only if idle — if a sweep is already running
     * we skip this tick (the next tick is already scheduled), so the timer never
     * stacks up behind or jams a manual refresh.
     */
    private fun requestPeriodicSweep() {
        synchronized(sweepLock) {
            if (sweepRunning) {
                Log.i(TAG, "Sweep already running; skipping this periodic tick.")
                return
            }
            sweepRunning = true
        }
        postSweepWorker()
    }

    /**
     * Check-messages direct forward: forward the exact [amountUsd] read from a Zaad
     * 898 exchange SMS — NO *800# balance check. Deduped by [ref]: the same exchange
     * is double-delivered, so we forward each ref at most once
     * ([ForwardingSettings.markRefForwardedIfNew], atomic under [sweepLock]). Runs
     * only if idle — an in-flight forward defers nothing, since the ref is only
     * consumed once the forward actually starts — then stands the service down.
     */
    private fun requestDirectForward(amountUsd: Double, ref: String?) {
        synchronized(sweepLock) {
            // Dedup FIRST, inside the lock, so two near-simultaneous deliveries of the
            // same ref can't both pass. Only consume the ref if we can start now.
            if (ref != null && !ForwardingSettings(this).markRefForwardedIfNew(ref)) {
                Log.i(TAG, "Exchange ref=$ref already forwarded; skipping duplicate.")
                stopIfNotAutoForwardPoller()
                return
            }
            if (sweepRunning) {
                Log.i(TAG, "Forward already running; skipping this 898-triggered forward (ref=$ref).")
                stopIfNotAutoForwardPoller()
                return
            }
            sweepRunning = true
        }
        val h = handler
        if (h == null) {
            synchronized(sweepLock) { sweepRunning = false }
            return
        }
        h.post {
            try {
                withWakeLock { runDirectForward(amountUsd) }
            } catch (e: Throwable) {
                Log.e(TAG, "898 exchange forward failed", e)
            } finally {
                synchronized(sweepLock) { sweepRunning = false }
                stopIfNotAutoForwardPoller()
            }
        }
    }

    /**
     * Forwards the exact [amountUsd] (whole-dollar floored) that a Zaad 898 exchange
     * SMS reported — dialing the forwarding USSD directly (`*806#` one-shot for
     * mobile, or the `*800#` deposit walk for bank), with NO balance-check `*800#`.
     * Records the RECEIVED + FORWARDED events for the dashboard.
     */
    private fun runDirectForward(amountUsd: Double) {
        val settings = ForwardingSettings(this)
        val primary = settings.pin
        if (!settings.isReady() || primary == null) {
            Log.w(TAG, "898 exchange forward but settings incomplete/disabled; skipping.")
            return
        }
        val subscriptionId = settings.simSubscriptionId
        val amount = computeForwardAmount(amountUsd) ?: return

        // The exchanged dollars are money in — log RECEIVED, paired with FORWARDED below.
        TransactionStore.record(this, TransactionStore.TYPE_RECEIVED, amount.toDouble(), provider = "Zaad")

        if (settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT) {
            val bankPin = settings.bankPin
            if (bankPin == null) {
                Log.w(TAG, "898 exchange bank forward but no bank PIN stored; skipping.")
                return
            }
            Log.i(TAG, "898 exchange \$$amountUsd → bank-forwarding \$$amount (whole dollars); no *800#.")
            val ok = performBankSend(primary, bankPin, amount, subscriptionId)
            recordForwarded(amount, null, ForwardingMethod.BANK_ACCOUNT, ok)
        } else {
            val destination = settings.destination
            val secondary = settings.secondaryPin
            if (destination == null || secondary == null) {
                Log.w(TAG, "898 exchange forward but mobile settings incomplete; skipping.")
                return
            }
            Log.i(TAG, "898 exchange \$$amountUsd → forwarding \$$amount (whole dollars) to $destination; no *800#.")
            UssdSession.beginDirectSend(primary, secondary, destination)
            val ok = performSend(destination, amount, secondary, subscriptionId)
            recordForwarded(amount, destination, ForwardingMethod.MOBILE_NUMBER, ok)
        }
    }

    private fun postSweepWorker() {
        val h = handler
        if (h == null) {
            synchronized(sweepLock) { sweepRunning = false }
            return
        }
        h.post { sweepWorker() }
    }

    /**
     * Drains the sweep queue on the background thread. Each pass consumes the
     * [manualQueued] flag: a pass triggered (or interrupted-by) a manual refresh
     * re-anchors the interval to now when it finishes, so the periodic timer
     * restarts fresh and never double-runs with the refresh. Keeps looping while a
     * manual refresh is queued, so a swipe that lands DURING a sweep still runs
     * right after it — then releases [sweepRunning].
     */
    private fun sweepWorker() {
        try {
            var done = false
            while (!done) {
                val wasManual: Boolean
                synchronized(sweepLock) {
                    wasManual = manualQueued
                    manualQueued = false
                }
                try {
                    withWakeLock { runOneSweep(wasManual) }
                    if (wasManual) {
                        val settings = ForwardingSettings(this)
                        if (settings.enabled && settings.mode == ForwardingMode.AUTO_FORWARD) {
                            Log.i(TAG, "Manual sweep done; re-anchoring the interval to now.")
                            scheduleNextTick(SystemClock.elapsedRealtime())
                        }
                    }
                } catch (e: Throwable) {
                    Log.e(TAG, "Sweep iteration failed", e)
                }
                // Release the run slot ONLY when nothing new is queued. Done inside
                // the lock, atomically with the stop decision, so a manual refresh
                // that arrives at this instant is either drained by looping again or
                // starts a fresh worker — never lost, never overlapped.
                synchronized(sweepLock) {
                    if (!manualQueued) {
                        sweepRunning = false
                        done = true
                    }
                }
            }
        } catch (e: Throwable) {
            // Safety net: an unexpected escape must never leave sweepRunning stuck
            // true (which would jam every future sweep). We only get here without
            // having released above, so no successor can be running to clobber.
            Log.e(TAG, "Sweep worker crashed; releasing run slot", e)
            synchronized(sweepLock) { sweepRunning = false }
        }
        stopIfNotAutoForwardPoller()
    }

    /**
     * Tears the service down when it isn't the persistent auto-forward poller
     * (i.e. check-messages mode, or forwarding disabled), so a one-off sweep
     * doesn't leave a foreground service lingering.
     */
    private fun stopIfNotAutoForwardPoller() {
        val settings = ForwardingSettings(this)
        if (!(settings.enabled && settings.mode == ForwardingMode.AUTO_FORWARD)) {
            stopEverything()
        }
    }

    /**
     * Resets the periodic-interval countdown to a full interval starting now, so a
     * manual pull-to-refresh is authoritative over the timer: any pending tick is
     * replaced (same PendingIntent, FLAG_UPDATE_CURRENT) so it can't fire during or
     * right after the refresh, and the interval counts fresh from the refresh. No-op
     * unless the auto-forward poller is active (message-check mode has no timer).
     */
    private fun resetIntervalCountdown() {
        val settings = ForwardingSettings(this)
        if (settings.enabled && settings.mode == ForwardingMode.AUTO_FORWARD) {
            Log.i(TAG, "Manual refresh: resetting the interval countdown to now.")
            scheduleNextTick(SystemClock.elapsedRealtime())
        }
    }

    private fun startPeriodic() {
        cancelTick()
        // Fire the first sweep now, and anchor the next tick one interval after
        // this start so the cadence is exact from the outset.
        val now = SystemClock.elapsedRealtime()
        scheduleNextTick(now)
        requestPeriodicSweep()
    }

    private fun stopEverything() {
        cancelTick()
        stopForegroundCompat()
        stopSelf()
    }

    /**
     * Schedules the next periodic tick as an exact, Doze-piercing alarm at a fixed
     * rate: `anchor + interval`. If that moment already passed (the last sweep ran
     * longer than the interval), it fires as soon as possible instead of stacking
     * up — the serialized worker still prevents overlap.
     */
    private fun scheduleNextTick(anchorElapsedMs: Long) {
        val intervalMs = ForwardingSettings(this).intervalMinutes.coerceIn(1, 60) * 60_000L
        val now = SystemClock.elapsedRealtime()
        val next = (anchorElapsedMs + intervalMs).coerceAtLeast(now + MIN_TICK_SLACK_MS)

        val am = getSystemService(AlarmManager::class.java)
        val pi = tickPendingIntent(next)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, next, pi)
            } else {
                am.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, next, pi)
            }
        } catch (e: SecurityException) {
            // Exact-alarm permission not granted (Android 12+ without the battery
            // exemption / USE_EXACT_ALARM): fall back to an inexact-but-Doze-aware
            // alarm so forwarding still runs, just with looser timing.
            Log.w(TAG, "Exact alarm denied; falling back to inexact allow-while-idle.", e)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, next, pi)
            } else {
                am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, next, pi)
            }
        }
        Log.i(TAG, "Next sweep tick scheduled in ${(next - now) / 1000}s.")
    }

    private fun cancelTick() {
        val am = getSystemService(AlarmManager::class.java)
        var flags = PendingIntent.FLAG_NO_CREATE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        val intent = Intent(this, ForwardingTickReceiver::class.java).setAction(ACTION_TICK)
        PendingIntent.getBroadcast(this, TICK_REQUEST_CODE, intent, flags)?.let {
            am.cancel(it)
            it.cancel()
        }
    }

    private fun tickPendingIntent(scheduledAt: Long): PendingIntent {
        val intent = Intent(this, ForwardingTickReceiver::class.java)
            .setAction(ACTION_TICK)
            .putExtra(EXTRA_SCHEDULED_AT, scheduledAt)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(this, TICK_REQUEST_CODE, intent, flags)
    }

    /**
     * Runs [block] holding a wake lock so a sweep completes even with the screen
     * off, and wakes the screen so the interactive system USSD dialog can render
     * and be driven while the phone is locked at night. The lock is time-bounded
     * so a wedged cycle can never hold it indefinitely, and always released.
     */
    private fun withWakeLock(block: () -> Unit) {
        val pm = getSystemService(PowerManager::class.java)
        // PARTIAL keeps the CPU running (non-deprecated, the essential guarantee);
        // the screen-on lock is best-effort to surface the USSD dialog at night.
        val cpuLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$WAKELOCK_TAG:cpu")
        @Suppress("DEPRECATION")
        val screenLock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "$WAKELOCK_TAG:screen",
        )
        cpuLock.setReferenceCounted(false)
        screenLock.setReferenceCounted(false)
        try {
            cpuLock.acquire(WAKELOCK_TIMEOUT_MS)
            try {
                screenLock.acquire(WAKELOCK_TIMEOUT_MS)
            } catch (e: Exception) {
                Log.w(TAG, "Could not acquire screen wake lock (continuing on CPU lock).", e)
            }
            block()
        } finally {
            if (screenLock.isHeld) screenLock.release()
            if (cpuLock.isHeld) cpuLock.release()
        }
    }

    /**
     * Runs exactly one balance-check → (maybe) forward cycle, blocking on this
     * background thread while the accessibility service drives the dialogs.
     */
    private fun runOneSweep(isManual: Boolean) {
        val settings = ForwardingSettings(this)
        val primary = settings.pin
        if (!settings.isReady() || primary == null) {
            Log.w(TAG, "Sweep requested but settings incomplete/disabled; skipping.")
            return
        }
        val subscriptionId = settings.simSubscriptionId

        Log.i(TAG, "Starting balance sweep on sub=$subscriptionId (manual=$isManual).")
        // Phase 1 — balance check, identical for both methods: *800# → primary PIN →
        // menu option 1 → read balance + account number. The session's destination /
        // secondary PIN are unused for bank, so pass placeholders there.
        UssdSession.beginBalanceCheck(primary, settings.secondaryPin ?: "", settings.destination ?: "")
        if (!UssdDialer.dialBalanceCheck(this, subscriptionId)) {
            UssdSession.finish()
            return
        }

        // Wait until the balance has actually been READ. The balance-dialog close
        // that follows is best-effort and must NOT gate the forward: a stalled close
        // (its confirming accessibility frame never arrives) used to abort the whole
        // cycle right here, so a balance ≥ $1 was seen but never forwarded — the
        // intermittent "checks the balance, finds > $1, skips the forward, works a
        // few attempts later" bug. Now we forward whenever the balance was captured.
        if (!awaitBalanceRead()) {
            Log.w(TAG, "Balance check timed out / failed; aborting cycle.")
            UssdSession.finish()
            return
        }
        // As soon as the balance is READ we move straight to the forward — no wait.
        // The leftover balance dialog is static (it fires no accessibility events,
        // so it can't be closed here anyway) and the fresh *800#/*806# dial below
        // supersedes it, so waiting for it to close was pure dead time (~6s) between
        // "balance confirmed" and "money forwarded". Forward immediately instead.
        val amount = computeForwardAmount(UssdSession.balanceUsd)
        if (amount == null) {
            UssdSession.finish()
            return
        }
        // The balance we're about to forward is money that has arrived on the
        // account — log it as RECEIVED so the dashboard's received chart reflects
        // it, paired with the FORWARDED event the send below records.
        TransactionStore.record(this, TransactionStore.TYPE_RECEIVED, amount.toDouble(), provider = "Zaad")

        // No post-forward cooldown: every sweep re-reads the LIVE balance via *800#
        // (Zaad debits synchronously — the confirm dialog already shows the new
        // balance), sweeps are serialized by [sweepLock] so two never overlap, and
        // our own "transferred to bank" confirmation isn't a trigger. So a ≥ $1
        // balance is ALWAYS forwarded right away, and a stale re-read can't double-send.

        // Phase 2 — forward the swept balance, by destination method.
        if (settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT) {
            val bankPin = settings.bankPin
            if (bankPin == null) {
                Log.w(TAG, "Bank method selected but no bank PIN stored; skipping forward.")
                UssdSession.finish()
                return
            }
            Log.i(TAG, "Balance \$${UssdSession.balanceUsd} → bank-forwarding \$$amount (whole dollars).")
            val ok = performBankSend(primary, bankPin, amount, subscriptionId)
            // Bank forwards go to the KAAFI bank account, NOT settings.destination
            // (which may hold a leftover mobile number) — label it as such.
            recordForwarded(amount, null, ForwardingMethod.BANK_ACCOUNT, ok)
        } else {
            val destination = settings.destination
            val secondary = settings.secondaryPin
            if (destination == null || secondary == null) {
                UssdSession.finish()
                return
            }
            Log.i(TAG, "Balance \$${UssdSession.balanceUsd} → forwarding \$$amount (whole dollars) to $destination.")
            UssdSession.beginSend()
            val ok = performSend(destination, amount, secondary, subscriptionId)
            recordForwarded(amount, destination, ForwardingMethod.MOBILE_NUMBER, ok)
        }
    }

    /**
     * Logs a FORWARDED event to the on-device ledger (the dashboard + Transactions
     * tab read it). [ok] is the send's success signal — whether the confirmation
     * PIN / bank confirm was actually driven — so a failed/timed-out cycle is
     * recorded as such rather than silently dropped.
     */
    private fun recordForwarded(amount: String, destination: String?, method: ForwardingMethod, ok: Boolean) {
        val dest = when {
            !destination.isNullOrBlank() -> destination
            method == ForwardingMethod.BANK_ACCOUNT -> "Bank account"
            else -> null
        }
        TransactionStore.record(
            this,
            TransactionStore.TYPE_FORWARDED,
            amount.toDouble(),
            destination = dest,
            method = method.ordinal,
            status = if (ok) TransactionStore.STATUS_SUCCESS else TransactionStore.STATUS_FAILED,
            provider = "Zaad",
        )
    }

    /**
     * Turns a parsed balance into the whole-dollar amount string to forward, or
     * null (with a log line) when nothing should be forwarded: below \$1, or
     * above the sanity ceiling (a value that high means the parser grabbed the
     * wrong number, so we refuse rather than send an absurd amount).
     */
    private fun computeForwardAmount(balance: Double?): String? {
        if (balance == null || balance < MIN_FORWARD_USD) {
            Log.i(TAG, "Balance ${balance ?: "unknown"} < \$$MIN_FORWARD_USD; nothing to forward.")
            return null
        }
        if (balance > MAX_FORWARD_USD) {
            Log.e(TAG, "Parsed balance \$$balance exceeds sanity cap \$$MAX_FORWARD_USD; refusing to forward (likely a misread).")
            return null
        }
        val amount = formatAmount(balance)
        if ((amount.toLongOrNull() ?: 0L) < 1L) {
            Log.w(TAG, "Computed forward amount '$amount' < \$1; nothing to forward.")
            return null
        }
        return amount
    }

    /**
     * Dials `*806*destination*amount*secondaryPin#` and blocks until the send is
     * driven to completion: waits for the confirmation PIN to be auto-typed
     * (SEND_PIN_DONE), then for the accessibility service to auto-close the
     * "you sent…" result dialog (SEND_DONE). Shared by the sweep and the 898
     * flow; the caller must have already armed the session's send step.
     */
    private fun performSend(destination: String, amount: String, secondaryPin: String, subscriptionId: Int): Boolean {
        if (!UssdDialer.dialSend(this, destination, amount, secondaryPin, subscriptionId)) {
            UssdSession.finish()
            return false
        }

        // SEND_PIN_DONE = the confirmation PIN was auto-typed and the forward
        // submitted; that's our success signal. The later result-dialog close is
        // best-effort cosmetics and must not flip a submitted forward to "failed".
        val submitted = awaitStep(UssdSession.Step.SEND_PIN_DONE)
        if (!submitted) {
            Log.w(TAG, "Send confirmation not completed within the window.")
        } else if (!awaitStep(UssdSession.Step.SEND_DONE, RESULT_CLOSE_CAP_MS)) {
            Log.w(TAG, "Result dialog did not appear/auto-close within ${RESULT_CLOSE_CAP_MS / 1000}s.")
        }
        UssdSession.finish()
        return submitted
    }

    /**
     * Bank-account forward: re-dials `*800#` and lets [UssdAccessibilityService]
     * walk the deposit menu (primary PIN → "5" → "2" → amount → comment → bank PIN
     * → confirm "1"), then waits for the confirmation to submit and the result
     * dialog to auto-close. The account PIN reuses the stored primary [pin]; the
     * bank PIN is the customer's saved [ForwardingSettings.bankPin]. The session's
     * bank step must already be armed by the caller via [UssdSession.beginBankSend]
     * — done here so the dial and the arm can't race.
     */
    private fun performBankSend(primary: String, bankPin: String, amount: String, subscriptionId: Int): Boolean {
        UssdSession.beginBankSend(primary, bankPin, amount)
        if (!UssdDialer.dialBalanceCheck(this, subscriptionId)) { // bank deposit walk also starts at *800#
            UssdSession.finish()
            return false
        }

        // BANK_CONFIRM_DONE = the deposit was confirmed/submitted; success signal.
        // The bank walk has ~7 dialogs, so give the whole sequence a generous cap;
        // a genuinely stuck step is still caught by the per-dialog window timeout.
        val confirmed = awaitStep(UssdSession.Step.BANK_CONFIRM_DONE, BANK_AWAIT_CAP_MS)
        if (!confirmed) {
            Log.w(TAG, "Bank forward not confirmed within the window.")
        } else if (!awaitStep(UssdSession.Step.BANK_DONE, RESULT_CLOSE_CAP_MS)) {
            Log.w(TAG, "Bank result dialog did not appear/auto-close within ${RESULT_CLOSE_CAP_MS / 1000}s.")
        }
        UssdSession.finish()
        return confirmed
    }

    /**
     * Polls until the accessibility service has parsed a balance (the value the
     * forward decision needs), or the cycle fails / the dialog window times out.
     * Deliberately keys off the balance being READ, not the balance dialog being
     * closed, so a flaky close can't abort a forward that should happen.
     */
    private fun awaitBalanceRead(): Boolean {
        val deadline = SystemClock.elapsedRealtime() + AWAIT_CAP_MS
        while (SystemClock.elapsedRealtime() < deadline) {
            when {
                UssdSession.balanceUsd != null -> return true
                UssdSession.step == UssdSession.Step.FAILED -> return false
                UssdSession.isTimedOut() -> return false
            }
            SystemClock.sleep(POLL_MS)
        }
        return false
    }

    /** Polls the shared session until it reaches [target], fails, or times out. */
    private fun awaitStep(target: UssdSession.Step, capMs: Long = AWAIT_CAP_MS): Boolean {
        val deadline = SystemClock.elapsedRealtime() + capMs
        while (SystemClock.elapsedRealtime() < deadline) {
            when {
                UssdSession.step == target -> return true
                UssdSession.step == UssdSession.Step.FAILED -> return false
                UssdSession.isTimedOut() -> return false
            }
            SystemClock.sleep(POLL_MS)
        }
        return false
    }

    /**
     * Formats the swept balance for the `*806` command as WHOLE DOLLARS with no
     * decimal point. This is critical: Zaad's *806 amount field strips the
     * decimal separator, so sending "10.00" is interpreted as 1000 (a 100x
     * over-send). We therefore floor to an integer dollar amount — e.g. a
     * $10.0036 balance forwards "10" (→ $10), leaving a sub-dollar remainder that
     * the < $1 threshold ignores on the next sweep.
     */
    private fun formatAmount(balance: Double): String = floor(balance).toLong().toString()

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Auto-forwarding",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Shown while the balance sweep is active." }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val text = if (ForwardingSettings(this).mode == ForwardingMode.AUTO_FORWARD) {
            "Auto-forwarding is on. Checking your balance periodically."
        } else {
            "Auto-forwarding is on. Checking your balance now."
        }
        return builder
            .setContentTitle("e-Xawil")
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
    }

    companion object {
        const val ACTION_START = "com.moneyexchange.forwarding.START"
        const val ACTION_STOP = "com.moneyexchange.forwarding.STOP"
        const val ACTION_SWEEP_NOW = "com.moneyexchange.forwarding.SWEEP_NOW"

        /**
         * Fired by [SmsReceiver] on a Zaad 898 exchange SMS: forward the exact
         * exchanged amount to the destination, deduped by the SMS ref, no *800#.
         */
        const val ACTION_FORWARD_AMOUNT = "com.moneyexchange.forwarding.FORWARD_AMOUNT"

        /** Fired by [ForwardingTickReceiver] when the periodic exact alarm goes off. */
        const val ACTION_TICK = "com.moneyexchange.forwarding.TICK"

        /** Elapsed-realtime this tick was scheduled for; used to anchor fixed-rate scheduling. */
        const val EXTRA_SCHEDULED_AT = "scheduled_at"

        /** Exchanged USD amount (from the 898 SMS) to forward, on [ACTION_FORWARD_AMOUNT]. */
        private const val EXTRA_AMOUNT_USD = "amount_usd"

        /** The SMS "Tixraac" ref, for dedup, on [ACTION_FORWARD_AMOUNT]. */
        private const val EXTRA_REF = "exchange_ref"

        private const val TAG = "Xawil/FgService"
        private const val CHANNEL_ID = "xawil_forwarding"
        private const val NOTIFICATION_ID = 4711

        /** Fixed request code so scheduling/cancelling always target the same alarm. */
        private const val TICK_REQUEST_CODE = 4712

        /** If the next tick's anchor is already in the past, fire this soon instead. */
        private const val MIN_TICK_SLACK_MS = 1_000L

        private const val WAKELOCK_TAG = "Xawil:forwarding"

        /** Upper bound a sweep may hold the wake lock, above the bank walk's worst case. */
        private const val WAKELOCK_TIMEOUT_MS = 4 * 60_000L

        /** Only forward when at least this much USD is on the account. */
        private const val MIN_FORWARD_USD = 1.0

        /**
         * Sanity ceiling. A parsed balance above this is treated as a misread and
         * never forwarded — far above any plausible personal balance, but well
         * below an account-id-sized number a bad parse could produce.
         */
        private const val MAX_FORWARD_USD = 100_000.0

        /** How long a single blocking wait for a step will poll before giving up. */
        private const val AWAIT_CAP_MS = 50_000L
        private const val POLL_MS = 300L

        /**
         * Ceiling for the whole multi-dialog bank deposit walk to reach the confirm
         * step. Larger than [AWAIT_CAP_MS] because it spans ~7 sequential dialogs;
         * a single stuck dialog still trips the per-window timeout well before this.
         */
        private const val BANK_AWAIT_CAP_MS = 120_000L

        /**
         * How long to wait after a send for the result dialog to appear and be
         * auto-closed. Generous, since the USSD round-trip can take several
         * seconds; we exit as soon as SEND_DONE is signalled, so this is only the
         * ceiling for a slow/missing result.
         */
        private const val RESULT_CLOSE_CAP_MS = 15_000L

        /** Starts (or resumes) the periodic sweep poller. */
        fun start(context: Context) = send(context, ACTION_START)

        /** Stops the poller and tears the service down. */
        fun stop(context: Context) = send(context, ACTION_STOP)

        /**
         * Delivers a periodic tick from [ForwardingTickReceiver], carrying the
         * elapsed-realtime it was scheduled for so the service can anchor the next
         * tick at a fixed rate.
         */
        fun tick(context: Context, scheduledAt: Long) {
            val intent = Intent(context, ForwardingForegroundService::class.java)
                .setAction(ACTION_TICK)
                .putExtra(EXTRA_SCHEDULED_AT, scheduledAt)
            startService(context, intent)
        }

        /**
         * Requests one immediate `*800#` balance sweep without waiting for the next
         * tick — the auto-forward manual refresh / "sweep now" action.
         */
        fun sweepNow(context: Context) = send(context, ACTION_SWEEP_NOW)

        /**
         * Check-messages path: forward exactly [amountUsd] (the dollars a Zaad 898
         * exchange SMS reported), deduped by [ref], with no *800# balance check.
         * Started from [SmsReceiver.handleMessageCheck].
         */
        fun forwardAmountFromMessage(context: Context, amountUsd: Double, ref: String?) {
            val intent = Intent(context, ForwardingForegroundService::class.java)
                .setAction(ACTION_FORWARD_AMOUNT)
                .putExtra(EXTRA_AMOUNT_USD, amountUsd)
                .putExtra(EXTRA_REF, ref)
            startService(context, intent)
        }

        private fun send(context: Context, action: String) {
            startService(context, Intent(context, ForwardingForegroundService::class.java).setAction(action))
        }

        /**
         * Starts the service as a foreground service (O+). Wrapped in a try/catch
         * because a background-initiated foreground-service start can be refused on
         * Android 12+ if the process isn't currently in an allowed state; the fired
         * alarm and battery-optimization exemption normally grant that allowance,
         * but we never want a refused start to crash the alarm receiver.
         */
        private fun startService(context: Context, intent: Intent) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Could not start forwarding service", e)
            }
        }
    }
}
