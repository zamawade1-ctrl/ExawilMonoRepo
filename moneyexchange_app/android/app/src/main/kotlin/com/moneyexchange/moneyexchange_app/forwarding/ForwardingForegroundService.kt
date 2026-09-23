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
 *  - [ForwardingMode.AUTO_FORWARD]: on a timer, every `intervalSeconds` (as fast as
 *    every 30s), runs a full `*800#` **balance sweep** ([ACTION_SWEEP_NOW]) and
 *    forwards the balance — the persistent, always-on poller.
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
     * 898 forwards are QUEUED when busy (never dropped — see [pendingForwards]) and
     * drained the instant the current flow finishes, so the interval timer, a manual
     * refresh, and an incoming exchange can never jam or lose each other.
     */
    private val sweepLock = Any()
    private var sweepRunning = false
    private var manualQueued = false

    /**
     * FIFO of check-messages 898 forwards waiting to run because another USSD flow is
     * in progress. A forward is NEVER dropped when busy (that permanently lost the
     * exchange — it was marked-as-forwarded then skipped): it's queued here and drained
     * by [drainForwards] the moment the current flow finishes. Dedup is applied at
     * drain time (when the forward truly starts), not at enqueue, so a re-delivered
     * duplicate queued behind the original is still collapsed, and a genuine exchange
     * is never marked without being sent. Guarded by [sweepLock].
     */
    private val pendingForwards = ArrayDeque<PendingForward>()

    /** One queued check-messages forward: the exact amount + its dedup keys. */
    private data class PendingForward(val amountUsd: Double, val signature: String?, val ref: String?)

    /**
     * When a queued manual sweep must skip the fast cached-leftover deposit and do a
     * live `*800#` balance read instead (set by the pull-to-refresh). Latches true
     * while any queued manual sweep requested freshness; consumed by the worker.
     */
    private var manualForceFresh = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        ensureHandler()

        // Plan gate: an expired trial/paid plan does NO USSD work at all — no sweep,
        // no balance check, no SMS-triggered forward, no timer tick — even with the
        // app closed. Stay completely inert until Flutter pushes an active plan again
        // (setPlanActive). ACTION_STOP is always honoured so teardown still works.
        val requestedAction = intent?.action
        if (requestedAction != ACTION_STOP && !ForwardingSettings(this).isPlanActive()) {
            Log.i(TAG, "Plan expired/inactive — ignoring ${requestedAction ?: "start"} (no USSD).")
            stopEverything()
            return START_NOT_STICKY
        }

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
                requestManualSweep(intent.getBooleanExtra(EXTRA_FRESH, false))
            }

            ACTION_CHECK_BALANCE -> {
                // Check-messages refresh: dial *800#, read + publish the balance for
                // the leftover readout, and stop — no forward. Never re-anchors the
                // interval (that's an auto-forward concept).
                requestBalanceCheck()
            }

            ACTION_FORWARD_AMOUNT -> {
                // Check-messages: a Zaad 898 exchange SMS arrived; [SmsReceiver] already
                // read the exchanged dollar amount. Forward exactly that amount to the
                // destination — NO *800# balance check — deduped within a time window by
                // the exchange's content signature so a re-delivered exchange (even with a
                // different ref) can't double-send.
                val amount = intent.getDoubleExtra(EXTRA_AMOUNT_USD, 0.0)
                val signature = intent.getStringExtra(EXTRA_SIGNATURE)
                val ref = intent.getStringExtra(EXTRA_REF)
                requestDirectForward(amount, signature, ref)
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
    private fun requestManualSweep(forceFresh: Boolean = false) {
        synchronized(sweepLock) {
            manualQueued = true
            // Latch freshness so a queued fresh refresh isn't downgraded by a later
            // non-fresh one draining in the same worker pass.
            if (forceFresh) manualForceFresh = true
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
     * 898 exchange SMS — NO *800# balance check. Deduped by [signature] within a time
     * window. Deduped primarily by the exchange REF (a genuine repeat of the same
     * amount to the same person carries a NEW ref and IS forwarded), with a short
     * signature window catching a rapid different-ref re-delivery
     * ([ForwardingSettings.markExchangeIfNew], applied at drain-start under [sweepLock]).
     * NEVER dropped when busy: the request is queued ([pendingForwards]) and drained the
     * moment the current flow finishes, so an exchange that lands mid-forward isn't lost.
     */
    private fun requestDirectForward(amountUsd: Double, signature: String?, ref: String?) {
        synchronized(sweepLock) {
            // QUEUE the forward — never drop it when busy. Dedup is applied at drain
            // time (when it actually starts), NOT here: consuming the dedup mark now
            // and then skipping because another flow is running would mark the exchange
            // as forwarded without ever sending it, permanently losing it. A duplicate
            // queued behind the original is collapsed by the drain-time dedup instead.
            pendingForwards.addLast(PendingForward(amountUsd, signature, ref))
            if (sweepRunning) {
                Log.i(TAG, "Busy; queued 898 forward (ref=${ref ?: "?"}) to run right after the current flow.")
                return
            }
            sweepRunning = true
        }
        val h = handler
        if (h == null) {
            synchronized(sweepLock) { sweepRunning = false }
            return
        }
        h.post { drainForwards() }
    }

    /**
     * Drains [pendingForwards] on the worker thread, one at a time, applying the
     * ref/signature dedup as each forward STARTS (so a duplicate that queued behind the
     * original is collapsed here, and a genuine exchange is never marked without being
     * sent). Loops until the queue is empty, releasing the run slot atomically with the
     * emptiness check so a forward enqueued at that instant is either drained now or
     * starts a fresh worker — never lost, never overlapped.
     */
    private fun drainForwards() {
        try {
            while (true) {
                val next = synchronized(sweepLock) { pendingForwards.removeFirstOrNull() }
                if (next == null) {
                    val done = synchronized(sweepLock) {
                        if (pendingForwards.isEmpty()) { sweepRunning = false; true } else false
                    }
                    if (done) break else continue
                }
                if (next.signature != null &&
                    !ForwardingSettings(this).markExchangeIfNew(
                        next.ref,
                        next.signature,
                        EXCHANGE_REF_DEDUP_WINDOW_MS,
                        EXCHANGE_SIG_DEDUP_WINDOW_MS,
                    )
                ) {
                    Log.i(TAG, "Exchange ref=${next.ref ?: "?"} sig=${next.signature} already forwarded (ref/sig window); skipping duplicate.")
                    continue
                }
                try {
                    withWakeLock { runDirectForward(next.amountUsd, next.ref) }
                } catch (e: Throwable) {
                    Log.e(TAG, "898 exchange forward failed", e)
                }
            }
        } catch (e: Throwable) {
            // Safety net: never leave the run slot stuck true (which would jam every
            // future forward and sweep). We only reach here without having released.
            Log.e(TAG, "Forward drain crashed; releasing run slot", e)
            synchronized(sweepLock) { sweepRunning = false }
        }
        stopIfNotAutoForwardPoller()
    }

    /** Posts the forward-drain worker; releases the slot + stands down if the looper's gone. */
    private fun postDrainForwards() {
        val h = handler
        if (h != null) {
            h.post { drainForwards() }
        } else {
            synchronized(sweepLock) { sweepRunning = false }
            stopIfNotAutoForwardPoller()
        }
    }

    /**
     * End-of-worker tail for the balance-check / sweep workers: if check-messages 898
     * forwards queued up while the worker ran (an exchange SMS arrived mid-run), KEEP
     * the run slot and drain them; otherwise release the slot and stand the service
     * down when it isn't the auto-forward poller. Replaces the bare
     * `sweepRunning = false; stopIfNotAutoForwardPoller()` tail so a forward that landed
     * during a balance check or manual sweep is never left sitting in the queue.
     */
    private fun finishWorkerDrainingPending() {
        val drain = synchronized(sweepLock) {
            if (pendingForwards.isNotEmpty()) {
                true // keep sweepRunning = true; hand off to the drain
            } else {
                sweepRunning = false
                false
            }
        }
        if (drain) postDrainForwards() else stopIfNotAutoForwardPoller()
    }

    /**
     * Forwards the exact [amountUsd] (whole-dollar floored) that a Zaad 898 exchange
     * SMS reported — dialing the forwarding USSD directly (`*806#` one-shot for
     * mobile, or the `*800#` deposit walk for bank), with NO balance-check `*800#`.
     * Records the RECEIVED + FORWARDED events for the dashboard.
     */
    private fun runDirectForward(amountUsd: Double, ref: String?) {
        val settings = ForwardingSettings(this)
        val primary = settings.pin
        if (!settings.isReady() || primary == null) {
            Log.w(TAG, "898 exchange forward but settings incomplete/disabled; skipping.")
            return
        }
        val subscriptionId = settings.simSubscriptionId
        // Bank can forward to the cent (real numeric amount field); mobile *806 is
        // whole-dollar only (it strips the decimal separator).
        val allowCents = settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT
        val amount = computeForwardAmount(amountUsd, allowCents) ?: return

        // The exchanged dollars are money in — log RECEIVED, paired with FORWARDED below.
        // Key the RECEIVED by the exchange ref (recv:<ref>) so a double-delivered 898 can
        // never double-count the received total, even if the service-level ref dedup above
        // was bypassed (e.g. the process was recycled between the two deliveries). The
        // FORWARDED below is keyed fwd:<ref> — a DIFFERENT key so it isn't swallowed by the
        // received entry, while its own duplicate (the failed retry) is.
        TransactionStore.record(
            this,
            TransactionStore.TYPE_RECEIVED,
            amount.toDouble(),
            provider = "Zaad",
            dedupeKey = ref?.let { "recv:$it" },
        )

        if (settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT) {
            val bankPin = settings.bankPin
            if (bankPin == null) {
                Log.w(TAG, "898 exchange bank forward but no bank PIN stored; skipping.")
                return
            }
            Log.i(TAG, "898 exchange \$$amountUsd → bank-forwarding \$$amount (to the cent); no *800#.")
            // 898 has no interval tick to fall back on, so it keeps the in-flow retry.
            val ok = performBankSend(primary, bankPin, amount, subscriptionId, maxAttempts = FORWARD_898_ATTEMPTS)
            recordForwarded(amount, null, ForwardingMethod.BANK_ACCOUNT, ok, dedupeKey = ref?.let { "fwd:$it" })
        } else {
            val destination = settings.destination
            val secondary = settings.secondaryPin
            if (destination == null || secondary == null) {
                Log.w(TAG, "898 exchange forward but mobile settings incomplete; skipping.")
                return
            }
            Log.i(TAG, "898 exchange \$$amountUsd → forwarding \$$amount (whole dollars) to $destination; no *800#.")
            // 898 has no interval tick to fall back on, so it keeps the in-flow retry.
            val ok = performSend(destination, amount, primary, secondary, subscriptionId, maxAttempts = FORWARD_898_ATTEMPTS)
            recordForwarded(amount, destination, ForwardingMethod.MOBILE_NUMBER, ok, dedupeKey = ref?.let { "fwd:$it" })
        }
    }

    /**
     * Check-messages refresh: runs a balance-ONLY `*800#` read (no forward) on the
     * worker thread, gated by [sweepLock] so it never overlaps a real sweep/forward.
     * Skips if something is already running (that read/forward already refreshes the
     * balance), then stands the service down since this isn't the auto-forward poller.
     */
    private fun requestBalanceCheck() {
        synchronized(sweepLock) {
            if (sweepRunning) {
                Log.i(TAG, "Busy; skipping the balance-only check (a run is already refreshing it).")
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
                withWakeLock { runBalanceCheckOnly() }
            } catch (e: Throwable) {
                Log.e(TAG, "Balance-only check failed", e)
            } finally {
                // Drain any 898 forward that arrived during the balance check.
                finishWorkerDrainingPending()
            }
        }
    }

    /**
     * Dials `*800#`, lets the accessibility service read the balance (which persists
     * + live-publishes it as the leftover balance), then finishes — deliberately no
     * forward. This is the check-messages "refresh to see my balance" path.
     */
    private fun runBalanceCheckOnly() {
        val settings = ForwardingSettings(this)
        val primary = settings.pin
        if (primary == null) {
            Log.w(TAG, "Balance-only check but no primary PIN stored; skipping.")
            return
        }
        val subscriptionId = settings.simSubscriptionId
        Log.i(TAG, "Balance-only check on sub=$subscriptionId (no forward).")
        UssdSession.beginBalanceCheck(primary, settings.secondaryPin ?: "", settings.destination ?: "")
        if (!UssdDialer.dialBalanceCheck(this, subscriptionId)) {
            UssdSession.finish()
            return
        }
        // Wait until the balance is READ (readBalance publishes the leftover); then
        // stop without forwarding. A stalled read just times out — nothing is sent.
        if (!awaitBalanceRead()) {
            Log.w(TAG, "Balance-only check timed out / failed.")
        }
        UssdSession.finish()
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
        // When we exit the loop still holding the slot because a check-messages 898
        // forward queued during the sweep (e.g. a manual "Run sweep" overlapped an
        // exchange SMS), hand off to the forward drain instead of standing down.
        var handOffToDrain = false
        try {
            var done = false
            while (!done) {
                val wasManual: Boolean
                val forceFresh: Boolean
                synchronized(sweepLock) {
                    wasManual = manualQueued
                    forceFresh = manualForceFresh
                    manualQueued = false
                    manualForceFresh = false
                }
                try {
                    withWakeLock { runSweepOncePerTick(wasManual, forceFresh) }
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
                // the lock, atomically with the stop decision, so a manual refresh (or
                // a queued 898 forward) that arrives at this instant is either drained
                // by looping again / handed to the drain, or starts a fresh worker —
                // never lost, never overlapped.
                synchronized(sweepLock) {
                    if (!manualQueued) {
                        done = true
                        if (pendingForwards.isNotEmpty()) {
                            handOffToDrain = true // keep sweepRunning = true for the drain
                        } else {
                            sweepRunning = false
                        }
                    }
                }
            }
        } catch (e: Throwable) {
            // Safety net: an unexpected escape must never leave sweepRunning stuck
            // true (which would jam every future sweep). We only get here without
            // having released above, so no successor can be running to clobber. Any
            // queued forward isn't lost — the next exchange re-drains the queue.
            Log.e(TAG, "Sweep worker crashed; releasing run slot", e)
            synchronized(sweepLock) { sweepRunning = false }
            handOffToDrain = false
        }
        if (handOffToDrain) postDrainForwards() else stopIfNotAutoForwardPoller()
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
        // Seconds-based cadence: the auto-forward poller can now check as often as every 30
        // seconds (see [ForwardingSettings.intervalSeconds], already clamped to 30..3600s).
        val intervalMs = ForwardingSettings(this).intervalSeconds * 1000L
        val now = SystemClock.elapsedRealtime()
        val next = (anchorElapsedMs + intervalMs).coerceAtLeast(now + MIN_TICK_SLACK_MS)
        scheduleTickAt(next)
    }

    /** Schedules the tick alarm at an exact elapsed-realtime moment, Doze-piercing. */
    private fun scheduleTickAt(next: Long) {
        val now = SystemClock.elapsedRealtime()
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
    /**
     * Runs EXACTLY ONE sweep pass for this tick — no inline re-sweeping and no in-tick
     * retry anywhere.
     *
     * A tick makes a single `*800#` balance dial ([readFreshBalance], no retry) and, if
     * the balance is ≥ $1, a single forward attempt (no re-dial). If the balance dial
     * misses, or the forward doesn't complete, we do NOTHING more this tick — the next
     * fixed-rate 60s interval tick simply re-reads and re-forwards. Retrying inside a
     * tick meant extra rapid `*800#` sessions, which is what provoked Zaad's "Internal
     * service error"; relying solely on the 60s cadence keeps every tick to the minimum
     * number of sessions (one balance dial, and one deposit/send dial when forwarding).
     */
    private fun runSweepOncePerTick(isManual: Boolean, forceFresh: Boolean) {
        if (runOneSweep(isManual, forceFresh) == SweepOutcome.RETRY_SOON) {
            Log.i(TAG, "Sweep didn't complete a forward this tick; the next interval tick will retry (no inline re-dial).")
        }
    }

    private fun runOneSweep(isManual: Boolean, forceFresh: Boolean = false): SweepOutcome {
        val settings = ForwardingSettings(this)
        val primary = settings.pin
        if (!settings.isReady() || primary == null) {
            Log.w(TAG, "Sweep requested but settings incomplete/disabled; skipping.")
            return SweepOutcome.DONE
        }
        val subscriptionId = settings.simSubscriptionId

        // FAST manual bank sweep: skip the fresh *800# balance read and deposit the
        // balance the app ALREADY knows (the leftover readout). A fresh read needs its
        // own *800# session, and Zaad's balance screen is terminal (it ends the
        // session with no way back to the menu — confirmed on-device), so a
        // read-then-deposit sweep must dial *800# twice and pays the fixed ~10.5s Zaad
        // PIN authentication TWICE (~28s total). Depositing the known leftover in a
        // single session halves that (~15s). Only for a MANUAL bank sweep ("Run sweep")
        // and only once we HAVE a known balance — the periodic auto-forward poller and
        // the first-ever sweep still take the accurate fresh-read path below.
        // The pull-to-refresh (forceFresh) always takes the accurate fresh-read path
        // below so it re-checks the LIVE balance via *800# and forwards if ≥ $1 — the
        // fast cached deposit is only for the explicit "Run sweep" button.
        if (!forceFresh &&
            isManual &&
            settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT &&
            settings.lastLeftoverBalance != null
        ) {
            runFastBankSweep(settings, primary, subscriptionId)
            return SweepOutcome.DONE
        }

        Log.i(TAG, "Starting balance sweep on sub=$subscriptionId (manual=$isManual).")
        // Phase 1 — balance check, identical for both methods: *800# → primary PIN →
        // menu option 1 → read balance + account number. ONE dial, no in-tick retry: a
        // transient read miss just ends this tick and the next 60s tick re-reads. This
        // keeps a tick to a single balance session (no rapid second *800#), which is
        // what stops Zaad returning "Internal service error".
        val balance = readFreshBalance(primary, settings, subscriptionId)
        if (balance == null) {
            UssdSession.finish()
            // Missed this tick — a ≥ $1 balance (if any) stays on the account and the
            // next interval tick re-reads + forwards it. No inline re-sweep.
            return SweepOutcome.RETRY_SOON
        }
        // As soon as the balance is READ we move straight to the forward — no wait.
        // The leftover balance dialog is static (it fires no accessibility events,
        // so it can't be closed here anyway) and the fresh *800#/*806# dial below
        // supersedes it, so waiting for it to close was pure dead time (~6s) between
        // "balance confirmed" and "money forwarded". Forward immediately instead.
        // Bank forwards go through a real numeric "enter amount" dialog that accepts a
        // decimal, so they zero the account to the cent; mobile *806 strips the decimal
        // separator (a 100x over-send risk) so it can only forward whole dollars.
        val allowCents = settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT
        val amount = computeForwardAmount(balance, allowCents)
        if (amount == null) {
            UssdSession.finish()
            return SweepOutcome.DONE // below $1 / above cap: nothing to forward, not a failure
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

        // Phase 2 — forward the swept balance, by destination method. ONE forward
        // attempt, no re-dial: a pre-confirm failure moved no money but left the ≥ $1
        // balance sitting there, so we report RETRY_SOON and simply let the next 60s
        // interval tick re-read + re-forward it (no inline re-sweep, no extra *800#).
        if (settings.forwardingMethod == ForwardingMethod.BANK_ACCOUNT) {
            val bankPin = settings.bankPin
            if (bankPin == null) {
                Log.w(TAG, "Bank method selected but no bank PIN stored; skipping forward.")
                UssdSession.finish()
                return SweepOutcome.DONE
            }
            Log.i(TAG, "Balance \$$balance → bank-forwarding \$$amount (to the cent).")
            val ok = performBankSend(primary, bankPin, amount, subscriptionId)
            // Bank forwards go to the KAAFI bank account, NOT settings.destination
            // (which may hold a leftover mobile number) — label it as such.
            recordForwarded(amount, null, ForwardingMethod.BANK_ACCOUNT, ok)
            return if (ok) SweepOutcome.DONE else SweepOutcome.RETRY_SOON
        } else {
            val destination = settings.destination
            val secondary = settings.secondaryPin
            if (destination == null || secondary == null) {
                UssdSession.finish()
                return SweepOutcome.DONE
            }
            Log.i(TAG, "Balance \$$balance → forwarding \$$amount (whole dollars) to $destination.")
            val ok = performSend(destination, amount, primary, secondary, subscriptionId)
            recordForwarded(amount, destination, ForwardingMethod.MOBILE_NUMBER, ok)
            return if (ok) SweepOutcome.DONE else SweepOutcome.RETRY_SOON
        }
    }

    /**
     * Outcome of one [runOneSweep] pass. Purely informational now — the sweep does NOT
     * re-run inline on [RETRY_SOON]; the next fixed-rate interval tick is the retry (see
     * [runSweepOncePerTick]). Kept so the log distinguishes "nothing to do" from "a
     * ≥ $1 balance didn't get forwarded this tick".
     */
    private enum class SweepOutcome {
        /** Forwarded, or nothing to forward (< $1), or a config gap — nothing more to do now. */
        DONE,

        /** A ≥ $1 balance was present but the read/forward didn't complete — the next tick retries. */
        RETRY_SOON,
    }

    /**
     * Single-session manual bank sweep: forwards the whole-dollar floor of the
     * balance the app already knows ([ForwardingSettings.lastLeftoverBalance]) via
     * ONE `*800#` bank-deposit walk — no separate `*800#` balance read. This is the
     * "fast Run sweep": it pays Zaad's ~10.5s PIN authentication once instead of
     * twice (~15s instead of ~28s), at the cost of using the last-known balance
     * rather than a freshly-read one.
     *
     * ## Why this is safe against a double-send
     * On a successful send we IMMEDIATELY decrement the known balance by exactly the
     * amount forwarded ([ForwardingSettings.lastLeftoverBalance] -= amount) and push
     * it live. So a second Run sweep tapped right after can't re-forward the same
     * money: the known balance already reflects the debit (and drops below \$1 once
     * swept), and sweeps are serialized by [sweepLock] so the decrement always lands
     * before the next one reads it. If the known value is somehow stale-HIGH (money
     * spent outside the app), Zaad validates the amount against the real balance and
     * rejects the deposit — no wrong transfer, just a failed sweep the user re-runs
     * after a refresh. The result dialog's true remaining balance, if it carries one,
     * still refines the readout via the a11y janitor.
     */
    private fun runFastBankSweep(settings: ForwardingSettings, primary: String, subscriptionId: Int) {
        val known = settings.lastLeftoverBalance
        // Fast sweep is bank-only, so forward to the cent and zero the account.
        val amount = computeForwardAmount(known, allowCents = true)
        if (amount == null) {
            // Below \$1 (or unknown): nothing to forward. computeForwardAmount logged why.
            return
        }
        val bankPin = settings.bankPin
        if (bankPin == null) {
            Log.w(TAG, "Fast bank sweep but no bank PIN stored; skipping.")
            return
        }
        // Money leaving the account — log RECEIVED, paired with the FORWARDED event
        // below, mirroring the fresh-read sweep so the dashboard reflects it.
        TransactionStore.record(this, TransactionStore.TYPE_RECEIVED, amount.toDouble(), provider = "Zaad")
        Log.i(TAG, "Fast bank sweep: forwarding known leftover \$$known → \$$amount (to the cent); no *800# balance read.")

        val ok = performBankSend(primary, bankPin, amount, subscriptionId)
        recordForwarded(amount, null, ForwardingMethod.BANK_ACCOUNT, ok)

        if (ok) {
            // Debit the known balance by exactly what we sent so a repeat sweep can't
            // double-forward it, and push it live to the leftover readout. The a11y
            // janitor may later overwrite this with the result dialog's exact remaining
            // balance — both converge on the post-forward figure.
            val remaining = ((known ?: 0.0) - amount.toDouble()).coerceAtLeast(0.0)
            settings.lastLeftoverBalance = remaining
            settings.lastLeftoverAtMs = System.currentTimeMillis()
            BalanceEvents.emit(remaining)
        }
    }

    /**
     * Logs a FORWARDED event to the on-device ledger (the dashboard + Transactions
     * tab read it). [ok] is the send's success signal — whether the confirmation
     * PIN / bank confirm was actually driven — so a failed/timed-out cycle is
     * recorded as such rather than silently dropped.
     */
    private fun recordForwarded(
        amount: String,
        destination: String?,
        method: ForwardingMethod,
        ok: Boolean,
        dedupeKey: String? = null,
    ) {
        // A SUCCESSFUL forward is recorded off Zaad's confirmation SMS — the exact
        // amount that actually left the account — NOT this send-time estimate, so an
        // unconfirmed/failed transfer never inflates the dashboard's forwarded total:
        //   - Bank:   "…successfully transferred $X to your bank account…" (Transfer-Id)
        //   - Mobile: "…$X sent to…" / "…$X ayaad u dirtay…", matched to the pending
        //             send parked below so a user's own manual send is never counted.
        // Both are recorded in [SmsReceiver]. A FAILED drive gets no confirmation SMS, so
        // we still record that here (status FAILED) to keep the failure visible (and the
        // dashboard's duplicate-Received reconciliation keeps working).
        if (ok && (method == ForwardingMethod.BANK_ACCOUNT || method == ForwardingMethod.MOBILE_NUMBER)) {
            if (method == ForwardingMethod.MOBILE_NUMBER) {
                // Park this forward so its "sent to" confirmation is recognised as ours.
                ForwardingSettings(this).addPendingMobileForward(amount)
            }
            Log.i(TAG, "$method forward sent (\$$amount); FORWARDED will be recorded off the confirmation SMS.")
            return
        }
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
            // Only the 898 direct-forward path passes a key (fwd:<ref>) — a balance-sweep
            // forward has no transaction ref and each sweep is a distinct send, so it stays null.
            dedupeKey = dedupeKey,
        )
    }

    /**
     * Turns a parsed balance into the amount string to forward, or null (with a log
     * line) when nothing should be forwarded: below \$1, or above the sanity ceiling
     * (a value that high means the parser grabbed the wrong number, so we refuse
     * rather than send an absurd amount).
     *
     * [allowCents] picks the granularity we can safely send on the destination's rail:
     *  - Bank (`allowCents = true`): the deposit walk types the amount into a real
     *    numeric "enter amount" dialog that accepts a decimal point, so we forward to
     *    the CENT and truly zero the account. Any misparse is hard-capped by the
     *    balance — Zaad rejects a deposit larger than what's on the account.
     *  - Mobile (`allowCents = false`): the `*806` one-shot code STRIPS the decimal
     *    separator (…*5.18*… → 518 → a \$518 100x over-send), so it can only ever
     *    forward whole dollars; the sub-dollar remainder is un-sendable dust.
     */
    private fun computeForwardAmount(balance: Double?, allowCents: Boolean): String? {
        if (balance == null || balance < MIN_FORWARD_USD) {
            Log.i(TAG, "Balance ${balance ?: "unknown"} < \$$MIN_FORWARD_USD; nothing to forward.")
            return null
        }
        if (balance > MAX_FORWARD_USD) {
            Log.e(TAG, "Parsed balance \$$balance exceeds sanity cap \$$MAX_FORWARD_USD; refusing to forward (likely a misread).")
            return null
        }
        val amount = formatAmount(balance, allowCents)
        // Use a numeric (not integer) floor so a legitimate cents amount like "5.18"
        // is NOT mistaken for < \$1 and dropped.
        if ((amount.toDoubleOrNull() ?: 0.0) < MIN_FORWARD_USD) {
            Log.w(TAG, "Computed forward amount '$amount' < \$$MIN_FORWARD_USD; nothing to forward.")
            return null
        }
        return amount
    }

    /**
     * Dials `*806*destination*amount*secondaryPin#` and blocks only until the
     * confirmation PIN is auto-typed and the forward submitted (SEND_PIN_DONE) —
     * NOT until the "you sent…" result dialog closes, which the IDLE-state janitor
     * handles asynchronously so a completed forward isn't held up by cosmetics.
     * Shared by the sweep and the 898 flow; the caller must have already armed the
     * session's send step.
     */
    private fun performSend(
        destination: String,
        amount: String,
        primaryPin: String,
        secondaryPin: String,
        subscriptionId: Int,
        maxAttempts: Int = 1,
    ): Boolean {
        // Attempt the whole `*806#` send. A `false` means the confirmation PIN was never
        // typed (our success signal), so no money moved — re-dialing is safe. The
        // auto-forward sweep passes [maxAttempts] = 1 (single attempt; the next 60s tick
        // re-reads + re-forwards a ≥ $1 balance, so no rapid in-tick re-dial). The 898
        // check-messages flow — which has NO interval tick to fall back on — passes a
        // higher count so a transient glitch there still recovers the exchanged amount.
        for (attempt in 1..maxAttempts) {
            UssdSession.beginDirectSend(primaryPin, secondaryPin, destination)
            val dialed = UssdDialer.dialSend(this, destination, amount, secondaryPin, subscriptionId)

            // SEND_PIN_DONE = the confirmation PIN was auto-typed and the forward
            // submitted; that's our success signal AND our completion point. We do NOT
            // wait for the "you sent…" result dialog to render + auto-close: the money
            // has already moved, and blocking on that cosmetic screen added a whole USSD
            // round-trip (several seconds) to every forward. The IDLE-state janitor in
            // UssdAccessibilityService dismisses that dialog — and reads the leftover
            // balance off it — on its own accessibility events once we finish here.
            val submitted = dialed && awaitStep(UssdSession.Step.SEND_PIN_DONE)
            UssdSession.finish()
            if (submitted) return true

            Log.w(TAG, "Send confirmation not completed (attempt $attempt/$maxAttempts)" +
                if (attempt < maxAttempts) "; re-dialing after backoff." else "; giving up (next tick / SMS retries).")
            if (attempt < maxAttempts) SystemClock.sleep(retryBackoffMs(attempt))
        }
        return false
    }

    /**
     * Bank-account forward: re-dials `*800#` and lets [UssdAccessibilityService]
     * walk the deposit menu (primary PIN → "5" → "2" → amount → comment → bank PIN
     * → confirm "1"), then waits only for the confirmation to submit — not for the
     * result dialog to close, which the IDLE-state janitor clears asynchronously so
     * the forward completes as soon as the money moves. The account PIN reuses the
     * stored primary [pin]; the bank PIN is the customer's saved
     * [ForwardingSettings.bankPin]. The session's
     * bank step must already be armed by the caller via [UssdSession.beginBankSend]
     * — done here so the dial and the arm can't race.
     */
    private fun performBankSend(
        primary: String,
        bankPin: String,
        amount: String,
        subscriptionId: Int,
        maxAttempts: Int = 1,
    ): Boolean {
        // Attempt the WHOLE *800# deposit walk. A `false` here means we never typed the
        // "1 Yes" confirmation (our success signal is BANK_CONFIRM_DONE), so NO money
        // moved — re-dialing is safe. The auto-forward sweep passes [maxAttempts] = 1
        // (single attempt; the next 60s tick re-reads + re-forwards, so no rapid in-tick
        // re-dial). The 898 check-messages flow — which has NO interval tick — passes a
        // higher count so a transient mid-walk glitch there still recovers the amount.
        for (attempt in 1..maxAttempts) {
            UssdSession.beginBankSend(primary, bankPin, amount)
            val dialed = UssdDialer.dialBalanceCheck(this, subscriptionId) // bank walk also starts at *800#

            // BANK_CONFIRM_DONE = the deposit was confirmed/submitted; that's our success
            // signal AND our completion point. The bank walk has ~7 dialogs, so give the
            // whole sequence a generous cap; a genuinely stuck step is still caught by the
            // per-dialog window timeout, and awaitStep fails fast on a mid-walk MMI error.
            // Once confirmed we STOP here: the money has moved, so we never block the cycle
            // on the "successfully transferred… your balance is $X" result dialog — the
            // IDLE-state janitor dismisses that and reads the leftover balance afterwards.
            val confirmed = dialed && awaitStep(UssdSession.Step.BANK_CONFIRM_DONE, BANK_AWAIT_CAP_MS)
            UssdSession.finish()
            if (confirmed) return true

            Log.w(TAG, "Bank forward not confirmed (attempt $attempt/$maxAttempts)" +
                if (attempt < maxAttempts) "; re-dialing the whole walk after backoff." else "; giving up (next tick / SMS retries).")
            if (attempt < maxAttempts) SystemClock.sleep(retryBackoffMs(attempt))
        }
        return false
    }

    /**
     * Reads the LIVE `*800#` balance with EXACTLY ONE dial — no in-tick retry. If the
     * dial misses (a transient slow render, a focus-stealing notification frame, or a
     * Zaad rejection), we give up THIS tick and let the next 60-second interval tick try
     * again. This is deliberate: retrying inside a tick meant a second rapid `*800#`
     * session, which (with the forward's own second `*800#`) is what provoked Zaad's
     * "Internal service error"; relying on the fixed 60s cadence keeps every tick to a
     * single balance session.
     *
     * Returns the parsed balance (session left armed at BALANCE_CLOSING so the caller
     * can dial the send straight after), or null if the single dial missed.
     */
    private fun readFreshBalance(
        primary: String,
        settings: ForwardingSettings,
        subscriptionId: Int,
    ): Double? {
        // The session's destination / secondary PIN are unused for the read itself
        // (bank passes placeholders); beginBalanceCheck resets the parsed balance.
        UssdSession.beginBalanceCheck(primary, settings.secondaryPin ?: "", settings.destination ?: "")
        val dialed = UssdDialer.dialBalanceCheck(this, subscriptionId)
        if (dialed && awaitBalanceRead()) {
            return UssdSession.balanceUsd
        }
        Log.w(TAG, "Balance read not completed; the next interval tick will retry.")
        UssdSession.finish()
        return null
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
                // A mid-flow MMI error (the *800# session was dropped/rejected) can't be
                // recovered in place — bail now so the caller re-dials, instead of waiting
                // out the whole window. The initial dial's own rejection is already handled
                // (and cleared) inside UssdDialer, so seeing it here means a genuine drop.
                UssdSession.mmiError -> return false
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
                // Mid-walk MMI error → the USSD session died and can't be driven further;
                // fail fast so performBankSend/performSend re-dial the whole flow in ~2s
                // rather than waiting out the 45s dialog window (the abandoned-forward bug).
                UssdSession.mmiError -> return false
                UssdSession.isTimedOut() -> return false
            }
            SystemClock.sleep(POLL_MS)
        }
        return false
    }

    /**
     * Formats the swept balance into the amount string to type.
     *
     * When [allowCents] is false (mobile `*806`): WHOLE DOLLARS with no decimal
     * point. This is critical — Zaad's `*806` amount field strips the decimal
     * separator, so sending "10.00" is interpreted as 1000 (a 100x over-send). So we
     * floor to an integer dollar amount — e.g. a $10.0036 balance forwards "10", the
     * sub-dollar remainder being un-sendable dust.
     *
     * When [allowCents] is true (bank deposit walk): floor to 2 decimals — e.g. a
     * $5.1825 balance forwards "5.18", zeroing the account down to sub-cent dust that
     * no rail can transfer. Flooring (never rounding up) guarantees we never try to
     * send more than the balance. A whole-dollar value drops the ".00" so the field
     * sees the same "5" it always has (keeps the proven whole-dollar path unchanged
     * when there are no cents).
     */
    private fun formatAmount(balance: Double, allowCents: Boolean): String {
        if (!allowCents) return floor(balance).toLong().toString()
        val cents = floor(balance * 100.0 + 1e-6).toLong() // +epsilon: absorb fp noise like 5.1799999
        val whole = cents / 100
        val frac = cents % 100
        return if (frac == 0L) whole.toString() else "%d.%02d".format(whole, frac)
    }

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
         * Dials `*800#`, reads the balance, and updates the leftover readout — but
         * does NOT forward. Used by the check-messages refresh so pulling to refresh
         * shows the real-time balance without running a forward.
         */
        const val ACTION_CHECK_BALANCE = "com.moneyexchange.forwarding.CHECK_BALANCE"

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

        /** The SMS "Tixraac" ref, used to key the ledger entries, on [ACTION_FORWARD_AMOUNT]. */
        private const val EXTRA_REF = "exchange_ref"

        /** The exchange content signature, used for windowed dedup, on [ACTION_FORWARD_AMOUNT]. */
        private const val EXTRA_SIGNATURE = "exchange_signature"

        /**
         * How long the exact exchange REF (Tixraac id) is remembered as already
         * forwarded. Zaad byte-identically re-delivers the same 898 SMS (same ref)
         * sometimes minutes apart; a generous window collapses those. A GENUINE repeat
         * exchange always carries a new ref, so this never blocks a real repeat — that's
         * the fix for "the 898 message arrived but nothing was forwarded", where the old
         * signature-only 10-minute window swallowed real repeats of the same amount.
         */
        private const val EXCHANGE_REF_DEDUP_WINDOW_MS = 30 * 60_000L

        /**
         * SHORT content-signature window (dollars + shilling + counterparty, ref
         * excluded) guarding the rarer case where Zaad re-delivers the same exchange
         * with a DIFFERENT ref. Deliberately short — only a near-simultaneous
         * re-delivery — so a genuine repeat of the same amount to the same person made a
         * couple of minutes later is still forwarded rather than mistaken for a copy.
         */
        private const val EXCHANGE_SIG_DEDUP_WINDOW_MS = 90_000L

        /**
         * On [ACTION_SWEEP_NOW]: force a fresh `*800#` balance read instead of the
         * fast cached-leftover deposit. Set by the auto-forward pull-to-refresh, so a
         * swipe-down always re-checks the live balance and forwards if it's ≥ $1.
         */
        private const val EXTRA_FRESH = "force_fresh"

        private const val TAG = "Xawil/FgService"
        private const val CHANNEL_ID = "xawil_forwarding"
        private const val NOTIFICATION_ID = 4711

        /** Fixed request code so scheduling/cancelling always target the same alarm. */
        private const val TICK_REQUEST_CODE = 4712

        /** If the next tick's anchor is already in the past, fire this soon instead. */
        private const val MIN_TICK_SLACK_MS = 1_000L

        private const val WAKELOCK_TAG = "Xawil:forwarding"

        /**
         * Upper bound a sweep may hold the wake lock: one balance read (dial + at most
         * one spaced retry) plus one forward (with its own bounded send retries). Kept
         * generous so a slow-but-legitimate cycle is never cut off mid-forward.
         */
        private const val WAKELOCK_TIMEOUT_MS = 6 * 60_000L

        /** Only forward when at least this much USD is on the account. */
        private const val MIN_FORWARD_USD = 1.0

        /**
         * Sanity ceiling. A parsed balance above this is treated as a misread and
         * never forwarded — far above any plausible personal balance, but well
         * below an account-id-sized number a bad parse could produce.
         */
        private const val MAX_FORWARD_USD = 100_000.0

        /**
         * How many times the 898 CHECK-MESSAGES flow re-runs the whole forward when an
         * attempt never reaches the confirm step. That mode has NO interval tick to fall
         * back on, so it keeps an in-flow retry to recover a transient glitch. A
         * pre-confirm failure moved no money (our success signal is the confirm being
         * typed), so re-dialing is safe. The AUTO-FORWARD sweep does NOT use this — it
         * makes a single attempt per tick and relies on the next 60s tick (passing
         * `maxAttempts = 1` to [performSend]/[performBankSend]).
         */
        private const val FORWARD_898_ATTEMPTS = 3

        /**
         * Exponential backoff between the 898 flow's forward retries (the only remaining
         * in-flow retry). After a failure we wait progressively longer (base, 2×, 4×, …
         * capped) so a struggling Zaad gateway gets room to recover. This is ON TOP of
         * [UssdDialer]'s per-dial minimum cooldown. [attempt] is the attempt that just
         * failed (1-based).
         */
        private fun retryBackoffMs(attempt: Int): Long =
            (RETRY_BACKOFF_BASE_MS shl (attempt - 1)).coerceAtMost(RETRY_BACKOFF_CAP_MS)

        private const val RETRY_BACKOFF_BASE_MS = 3_000L
        private const val RETRY_BACKOFF_CAP_MS = 30_000L

        /** How long a single blocking wait for a step will poll before giving up. */
        private const val AWAIT_CAP_MS = 50_000L

        /**
         * Poll gap while the poller waits on a session step. Kept short so the
         * instant a step completes (balance read, confirm submitted) the poller
         * moves on with minimal detection lag — it costs only cheap volatile reads.
         */
        private const val POLL_MS = 100L

        /**
         * Ceiling for the whole multi-dialog bank deposit walk to reach the confirm
         * step. Larger than [AWAIT_CAP_MS] because it spans ~7 sequential dialogs;
         * a single stuck dialog still trips the per-window timeout well before this.
         */
        private const val BANK_AWAIT_CAP_MS = 120_000L

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
         * tick — the auto-forward manual refresh / "sweep now" action. When
         * [fresh] is true (the pull-to-refresh), forces a live `*800#` balance read
         * rather than depositing the cached leftover.
         */
        fun sweepNow(context: Context, fresh: Boolean = false) {
            val intent = Intent(context, ForwardingForegroundService::class.java)
                .setAction(ACTION_SWEEP_NOW)
                .putExtra(EXTRA_FRESH, fresh)
            startService(context, intent)
        }

        /**
         * Reads the balance via `*800#` and updates the leftover readout WITHOUT
         * forwarding — the check-messages refresh action.
         */
        fun checkBalance(context: Context) = send(context, ACTION_CHECK_BALANCE)

        /**
         * Check-messages path: forward exactly [amountUsd] (the dollars a Zaad 898
         * exchange SMS reported), with no *800# balance check. Deduped within a time
         * window by [signature] (the exchange's content signature, stable across a
         * re-delivery even when its ref differs); [ref] keys the ledger's RECEIVED /
         * FORWARDED entries. Started from [SmsReceiver.handleMessageCheck].
         */
        fun forwardAmountFromMessage(
            context: Context,
            amountUsd: Double,
            signature: String,
            ref: String?,
        ) {
            val intent = Intent(context, ForwardingForegroundService::class.java)
                .setAction(ACTION_FORWARD_AMOUNT)
                .putExtra(EXTRA_AMOUNT_USD, amountUsd)
                .putExtra(EXTRA_SIGNATURE, signature)
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
