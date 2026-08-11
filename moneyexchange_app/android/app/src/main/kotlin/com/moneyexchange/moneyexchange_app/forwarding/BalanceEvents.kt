package com.moneyexchange.moneyexchange_app.forwarding

import android.os.Handler
import android.os.Looper

/**
 * In-process fan-out of the account's **leftover balance** (read off the final
 * "…Your Balance is $X." result dialog by [UssdAccessibilityService]) to whoever
 * is listening — in practice the Flutter EventChannel sink registered by
 * MainActivity while the app is in the foreground. Lets the forwarding-mode
 * card's leftover-balance readout update the instant a forward completes, without
 * waiting for a pull-to-refresh. Mirrors [TransactionEvents]: one app process, so
 * a plain in-memory listener list is enough.
 *
 * Emissions are marshalled to the main thread because the capture happens on the
 * accessibility service thread, but the EventChannel sink must be fed on the
 * platform (main) thread.
 */
object BalanceEvents {

    private val main = Handler(Looper.getMainLooper())
    private val listeners = java.util.concurrent.CopyOnWriteArrayList<(Double) -> Unit>()

    fun addListener(listener: (Double) -> Unit) {
        listeners.addIfAbsent(listener)
    }

    fun removeListener(listener: (Double) -> Unit) {
        listeners.remove(listener)
    }

    fun emit(balanceUsd: Double) {
        if (listeners.isEmpty()) return
        main.post {
            for (l in listeners) {
                runCatching { l(balanceUsd) }
            }
        }
    }
}
