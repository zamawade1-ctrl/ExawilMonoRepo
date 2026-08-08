package com.moneyexchange.moneyexchange_app.forwarding

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock

/**
 * Receives the periodic exact alarm scheduled by [ForwardingForegroundService]
 * and hands it back to the service as a tick. Kept as a separate broadcast
 * receiver (rather than an alarm that targets the service directly) so the alarm
 * still fires and resurrects the service even if it was killed between ticks.
 *
 * The alarm carries [ForwardingForegroundService.EXTRA_SCHEDULED_AT] — the
 * elapsed-realtime it was meant to fire at — so the next tick can be anchored to
 * it and the cadence stays fixed-rate instead of drifting by each sweep's length.
 */
class ForwardingTickReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ForwardingForegroundService.ACTION_TICK) return
        val scheduledAt = intent.getLongExtra(
            ForwardingForegroundService.EXTRA_SCHEDULED_AT,
            SystemClock.elapsedRealtime(),
        )
        ForwardingForegroundService.tick(context, scheduledAt)
    }
}
