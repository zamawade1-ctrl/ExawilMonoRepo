package com.moneyexchange.moneyexchange_app.forwarding

import android.os.Handler
import android.os.Looper

/**
 * In-process fan-out of newly recorded [TransactionStore] events to whoever is
 * listening — in practice the Flutter EventChannel sink registered by
 * MainActivity while the app is in the foreground. Lets the dashboard's
 * "today's forwarded" counter tick up the instant a forward completes, without
 * polling. Everything runs in the one app process, so a plain in-memory listener
 * list is enough (no LocalBroadcastManager / IPC needed).
 *
 * Emissions are marshalled to the main thread because the recorder is usually a
 * background service/receiver thread, but the EventChannel sink must be fed on
 * the platform (main) thread.
 */
object TransactionEvents {

    private val main = Handler(Looper.getMainLooper())
    private val listeners = java.util.concurrent.CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()

    fun addListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.addIfAbsent(listener)
    }

    fun removeListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.remove(listener)
    }

    fun emit(event: Map<String, Any?>) {
        if (listeners.isEmpty()) return
        main.post {
            for (l in listeners) {
                runCatching { l(event) }
            }
        }
    }
}
