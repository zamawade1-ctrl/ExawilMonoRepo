package com.moneyexchange.moneyexchange_app.forwarding

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts the auto-forward poller after a reboot, so an overnight restart (OS
 * update, battery hiccup) doesn't silently stop forwarding until the user next
 * opens the app.
 *
 * Only [ForwardingMode.AUTO_FORWARD] needs anything restarted: it owns the
 * persistent timer + foreground service. [ForwardingMode.MESSAGE_CHECK] is driven
 * entirely by [SmsReceiver], a manifest-registered receiver that Android revives
 * on its own when an SMS arrives, so there's nothing to restart for it here.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            return
        }
        val settings = ForwardingSettings(context)
        if (settings.enabled && settings.isReady() && settings.mode == ForwardingMode.AUTO_FORWARD) {
            Log.i(TAG, "Boot completed; restarting the auto-forward poller.")
            ForwardingForegroundService.start(context)
        }
    }

    companion object {
        private const val TAG = "Xawil/BootReceiver"
    }
}
