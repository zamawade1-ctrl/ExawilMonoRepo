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
 * *When* a sweep runs depends on [ForwardingSettings.mode]:
 *  - [ForwardingMode.AUTO_FORWARD]: on a timer, every `intervalMinutes`, for as
 *    long as forwarding stays enabled — this is the persistent, always-on poller.
 *  - [ForwardingMode.MESSAGE_CHECK]: never on a timer. The service only ever
 *    receives [ACTION_SWEEP_NOW], fired by [SmsReceiver] when a money-in SMS
 *    arrives (or by the app's manual test action), and stops itself again right
 *    after so it doesn't linger as a foreground service between messages.
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

            ACTION_SWEEP_NOW ->
                // Manual pull-to-refresh (or a money-in SMS): run the USSD NOW,
                // ignoring the interval timer, using whichever mode/method/
                // destination is currently saved (runOneSweep reads settings fresh).
                // Never dropped — if a sweep is running it's queued to run the
                // instant that one finishes. When done, the interval re-anchors to
                // now (see [sweepWorker]) so the manual refresh and the timer don't
                // double-run or block each other.
                requestManualSweep()

            ACTION_FORWARD_AMOUNT -> {
                // Check-messages (898) path: forward the amount read from the SMS
                // directly. Runs only if idle (a running sweep already moves the
                // money); stops the service after if it isn't the auto-forward poller.
                val balance = intent.getDoubleExtra(EXTRA_BALANCE_USD, 0.0)
                requestDirectSend(balance)
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
            // do until SmsReceiver fires ACTION_SWEEP_NOW, so just stop again.
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
                    withWakeLock { runOneSweep() }
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
     * 898 direct send (check-messages). Runs only if idle; a running sweep already
     * moves the balance, so skipping a colliding 898 is safe. Stops the service
     * afterward unless it's the persistent auto-forward poller.
     */
    private fun requestDirectSend(balance: Double) {
        synchronized(sweepLock) {
            if (sweepRunning) {
                Log.i(TAG, "Sweep running; skipping 898 direct send.")
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
                withWakeLock { runDirectSend(balance) }
            } catch (e: Throwable) {
                Log.e(TAG, "898 direct send failed", e)
            } finally {
                synchronized(sweepLock) { sweepRunning = false }
                stopIfNotAutoForwardPoller()
            }
        }
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
    private fun runOneSweep() {
        val settings = ForwardingSettings(this)
        val primary = settings.pin
        if (!settings.isReady() || primary == null) {
            Log.w(TAG, "Sweep requested but settings incomplete/disabled; skipping.")
            return
        }
        val subscriptionId = settings.simSubscriptionId
        if (inCooldown()) return

        Log.i(TAG, "Starting balance sweep on sub=$subscriptionId.")
        // Phase 1 — balance check, identical for both methods: *800# → primary PIN →
        // menu option 1 → read balance + account number. The session's destination /
        // secondary PIN are unused for bank, so pass placeholders there.
        UssdSession.beginBalanceCheck(primary, settings.secondaryPin ?: "", settings.destination ?: "")
        if (!UssdDialer.dialBalanceCheck(this, subscriptionId)) {
            UssdSession.finish()
            return
        }

        if (!awaitStep(UssdSession.Step.BALANCE_CAPTURED)) {
            Log.w(TAG, "Balance check timed out / failed; aborting cycle.")
            UssdSession.finish()
            return
        }

        val amount = computeForwardAmount(UssdSession.balanceUsd)
        if (amount == null) {
            UssdSession.finish()
            return
        }

        // Phase 2 — forward the swept balance, by destination method.
        if (settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT) {
            val bankPin = settings.bankPin
            if (bankPin == null) {
                Log.w(TAG, "Bank method selected but no bank PIN stored; skipping forward.")
                UssdSession.finish()
                return
            }
            Log.i(TAG, "Balance \$${UssdSession.balanceUsd} → bank-forwarding \$$amount (whole dollars).")
            performBankSend(primary, bankPin, amount, subscriptionId)
        } else {
            val destination = settings.destination
            val secondary = settings.secondaryPin
            if (destination == null || secondary == null) {
                UssdSession.finish()
                return
            }
            Log.i(TAG, "Balance \$${UssdSession.balanceUsd} → forwarding \$$amount (whole dollars) to $destination.")
            UssdSession.beginSend()
            performSend(destination, amount, secondary, subscriptionId)
        }
    }

    /**
     * Check-messages (898) path: the amount was already read from the incoming
     * SMS, so this skips the `*800#` balance check entirely and goes straight to
     * dialing `*806*destination*amount*secondaryPin#`, letting the accessibility
     * service auto-fill the primary PIN on the confirmation popup — the same
     * second step the sweep uses. [balanceUsd] is the balance parsed off the 898
     * message; it's floored to whole dollars and passed through the same
     * min/max/cooldown guards as a sweep.
     */
    private fun runDirectSend(balanceUsd: Double) {
        val settings = ForwardingSettings(this)
        val primary = settings.pin
        if (!settings.isReady() || primary == null) {
            Log.w(TAG, "898 forward requested but settings incomplete/disabled; skipping.")
            return
        }
        val subscriptionId = settings.simSubscriptionId
        if (inCooldown()) return

        val amount = computeForwardAmount(balanceUsd) ?: return

        if (settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT) {
            val bankPin = settings.bankPin
            if (bankPin == null) {
                Log.w(TAG, "898 bank forward but no bank PIN stored; skipping.")
                return
            }
            Log.i(TAG, "898 balance \$$balanceUsd → bank-forwarding \$$amount (whole dollars).")
            performBankSend(primary, bankPin, amount, subscriptionId)
        } else {
            val destination = settings.destination
            val secondary = settings.secondaryPin
            if (destination == null || secondary == null) {
                Log.w(TAG, "898 forward requested but mobile settings incomplete; skipping.")
                return
            }
            Log.i(TAG, "898 balance \$$balanceUsd → forwarding \$$amount (whole dollars) to $destination.")
            UssdSession.beginDirectSend(primary, secondary, destination)
            performSend(destination, amount, secondary, subscriptionId)
        }
    }

    /**
     * Post-forward cooldown: after we send, Zaad needs a moment to debit the
     * account before a fresh balance reflects it. Without this, a check that
     * fires before the balance updates would read the old (still-high) balance
     * and forward a SECOND time — a double-send. True = still cooling down, skip.
     */
    private fun inCooldown(): Boolean {
        val sinceForward = SystemClock.elapsedRealtime() - lastForwardAtMs
        if (lastForwardAtMs != 0L && sinceForward < FORWARD_COOLDOWN_MS) {
            Log.i(TAG, "In post-forward cooldown (${(FORWARD_COOLDOWN_MS - sinceForward) / 1000}s left); skipping.")
            return true
        }
        return false
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
    private fun performSend(destination: String, amount: String, secondaryPin: String, subscriptionId: Int) {
        if (!UssdDialer.dialSend(this, destination, amount, secondaryPin, subscriptionId)) {
            UssdSession.finish()
            return
        }
        // Start the cooldown the moment we've committed the send.
        lastForwardAtMs = SystemClock.elapsedRealtime()

        if (!awaitStep(UssdSession.Step.SEND_PIN_DONE)) {
            Log.w(TAG, "Send confirmation not completed within the window.")
        } else if (!awaitStep(UssdSession.Step.SEND_DONE, RESULT_CLOSE_CAP_MS)) {
            Log.w(TAG, "Result dialog did not appear/auto-close within ${RESULT_CLOSE_CAP_MS / 1000}s.")
        }
        UssdSession.finish()
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
    private fun performBankSend(primary: String, bankPin: String, amount: String, subscriptionId: Int) {
        UssdSession.beginBankSend(primary, bankPin, amount)
        if (!UssdDialer.dialBalanceCheck(this, subscriptionId)) { // bank deposit walk also starts at *800#
            UssdSession.finish()
            return
        }
        // Start the cooldown the moment we've committed to the deposit dial.
        lastForwardAtMs = SystemClock.elapsedRealtime()

        // The bank walk has ~7 dialogs, so give the whole sequence a generous cap;
        // a genuinely stuck step is still caught by the per-dialog window timeout.
        if (!awaitStep(UssdSession.Step.BANK_CONFIRM_DONE, BANK_AWAIT_CAP_MS)) {
            Log.w(TAG, "Bank forward not confirmed within the window.")
        } else if (!awaitStep(UssdSession.Step.BANK_DONE, RESULT_CLOSE_CAP_MS)) {
            Log.w(TAG, "Bank result dialog did not appear/auto-close within ${RESULT_CLOSE_CAP_MS / 1000}s.")
        }
        UssdSession.finish()
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
        const val ACTION_FORWARD_AMOUNT = "com.moneyexchange.forwarding.FORWARD_AMOUNT"

        /** Fired by [ForwardingTickReceiver] when the periodic exact alarm goes off. */
        const val ACTION_TICK = "com.moneyexchange.forwarding.TICK"

        /** Elapsed-realtime this tick was scheduled for; used to anchor fixed-rate scheduling. */
        const val EXTRA_SCHEDULED_AT = "scheduled_at"

        private const val EXTRA_BALANCE_USD = "balance_usd"

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

        /**
         * How long to wait after a send before another sweep may forward again,
         * so a not-yet-settled debit can't be double-forwarded on the next tick.
         */
        private const val FORWARD_COOLDOWN_MS = 3 * 60_000L

        /** Elapsed-realtime of the last send we committed; 0 = none this process. */
        @Volatile
        private var lastForwardAtMs = 0L

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

        /** Requests one immediate sweep without waiting for the next tick. */
        fun sweepNow(context: Context) = send(context, ACTION_SWEEP_NOW)

        /**
         * Check-messages (898) path: forwards [balanceUsd] directly via `*806#`,
         * skipping the balance-check dial. Started from [SmsReceiver] when a 898
         * balance SMS arrives in message-check mode.
         */
        fun forwardAmount(context: Context, balanceUsd: Double) {
            val intent = Intent(context, ForwardingForegroundService::class.java)
                .setAction(ACTION_FORWARD_AMOUNT)
                .putExtra(EXTRA_BALANCE_USD, balanceUsd)
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
