package com.moneyexchange.moneyexchange_app.forwarding

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.moneyexchange.moneyexchange_app.MainActivity

/**
 * Posts the Facebook/YouTube-style tappable alert shown when the user saves a
 * mobile forwarding-destination change. Tapping it deep-links straight into the
 * in-app confirmation screen (launching the app if it's closed) by re-launching
 * [com.moneyexchange.moneyexchange_app.MainActivity] with the [EXTRA_ROUTE] extra,
 * which the activity forwards to Flutter (see MainActivity's navigation channel).
 *
 * This reuses the app's existing notification infrastructure (the same
 * NotificationManager + POST_NOTIFICATIONS permission the foreground service uses);
 * it just adds a separate, user-visible channel so this security alert can actually
 * heads-up (the foreground-service channel is IMPORTANCE_LOW and stays silent).
 */
object DestinationChangeNotifications {

    /** Deep-link route the tapped notification asks the app to open. */
    const val EXTRA_ROUTE = "xawil_route"
    const val ROUTE_DESTINATION_CHANGE = "destination_change"

    private const val CHANNEL_ID = "xawil_destination_change"
    private const val NOTIF_ID = 4200
    private const val REQUEST_CODE = 4201

    /**
     * Shows the "destination changed — confirm to activate" alert for [newNumber].
     * No-op safe: if notifications are disabled the post is simply dropped by the OS.
     */
    fun post(context: Context, newNumber: String) {
        val appContext = context.applicationContext
        val manager = appContext.getSystemService(NotificationManager::class.java) ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Destination changes",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Confirm changes to where your money is forwarded."
            }
            manager.createNotificationChannel(channel)
        }

        // Re-launch MainActivity (singleTop) with the deep-link route. NEW_TASK so it
        // launches the app when closed; SINGLE_TOP + CLEAR_TOP so an already-running
        // app just delivers onNewIntent instead of stacking a second activity.
        val intent = Intent(appContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_ROUTE, ROUTE_DESTINATION_CHANGE)
        }
        var piFlags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) piFlags = piFlags or PendingIntent.FLAG_IMMUTABLE
        val contentIntent = PendingIntent.getActivity(appContext, REQUEST_CODE, intent, piFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(appContext, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(appContext)
        }

        val notification = builder
            .setContentTitle("Forwarding destination changed")
            .setContentText(
                "Money will be forwarded to $newNumber only after you confirm. Tap to review.",
            )
            .setStyle(
                Notification.BigTextStyle().bigText(
                    "Money will be forwarded to $newNumber only after you confirm. Tap to review.",
                ),
            )
            .setSmallIcon(appContext.applicationInfo.icon)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()

        manager.notify(NOTIF_ID, notification)
    }
}
