package com.moneyexchange.moneyexchange_app.forwarding

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * On-device ledger of money events, the single source of truth the dashboard and
 * the Transactions tab read from. The server-side [IncomingMoneyTransaction]
 * table only sees the backend polling fallback; the real on-device forwarder
 * (USSD/SMS) never touches it, so without this store there'd be nothing to chart.
 *
 * Two event kinds, both persisted as a JSON array in SharedPreferences (newest
 * appended last, capped at [MAX_EVENTS]):
 *   - [TYPE_RECEIVED]  — money arrived on the Zaad account (read off the money-in
 *     / 898 SMS). [amountUsd] is what came in.
 *   - [TYPE_FORWARDED] — we forwarded to the customer's destination. [amountUsd]
 *     is the whole-dollar amount sent, [destination] where, [status] the outcome.
 *
 * Every append fires [TransactionEvents] so a foreground dashboard can increment
 * live (e.g. "today's forwarded" ticking up the instant a forward completes).
 * All actors (SmsReceiver, the foreground service, MainActivity) share one app
 * process, so a synchronized read-modify-write here is safe across them.
 */
object TransactionStore {

    const val TYPE_RECEIVED = "received"
    const val TYPE_FORWARDED = "forwarded"

    const val STATUS_SUCCESS = "success"
    const val STATUS_FAILED = "failed"

    private const val PREFS = "xawil_transactions"
    private const val KEY_EVENTS = "events"
    private const val MAX_EVENTS = 1000
    private const val TAG = "Xawil/TxStore"

    private val lock = Any()

    /**
     * Appends one event and returns its map form (also handed to listeners). All
     * fields are primitives/String so they cross the Flutter method channel and
     * serialize to JSON unchanged.
     */
    fun record(
        context: Context,
        type: String,
        amountUsd: Double,
        destination: String? = null,
        method: Int? = null,
        status: String? = null,
        provider: String? = null,
        note: String? = null,
    ): Map<String, Any?> {
        val event = linkedMapOf<String, Any?>(
            "id" to System.currentTimeMillis(),
            "type" to type,
            "amountUsd" to amountUsd,
            "destination" to destination,
            "method" to method,
            "status" to status,
            "provider" to provider,
            "note" to note,
            "timestampMs" to System.currentTimeMillis(),
        )
        synchronized(lock) {
            val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = readArray(prefs)
            arr.put(JSONObject(event as Map<*, *>))
            // Trim oldest from the front so the array never grows unbounded.
            val trimmed = if (arr.length() > MAX_EVENTS) {
                JSONArray().apply {
                    for (i in (arr.length() - MAX_EVENTS) until arr.length()) put(arr.get(i))
                }
            } else {
                arr
            }
            prefs.edit().putString(KEY_EVENTS, trimmed.toString()).apply()
        }
        Log.i(TAG, "Recorded $type \$$amountUsd${destination?.let { " → $it" } ?: ""} (${status ?: "-"}).")
        TransactionEvents.emit(event)
        return event
    }

    /** All events as maps, in stored order (oldest first). Callers sort as needed. */
    fun all(context: Context): List<Map<String, Any?>> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = synchronized(lock) { readArray(prefs) }
        val out = ArrayList<Map<String, Any?>>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "id" to o.optLong("id"),
                    "type" to o.optString("type"),
                    "amountUsd" to o.optDouble("amountUsd", 0.0),
                    "destination" to o.optStringOrNull("destination"),
                    "method" to if (o.isNull("method")) null else o.optInt("method"),
                    "status" to o.optStringOrNull("status"),
                    "provider" to o.optStringOrNull("provider"),
                    "note" to o.optStringOrNull("note"),
                    "timestampMs" to o.optLong("timestampMs"),
                ),
            )
        }
        return out
    }

    /** Wipes the ledger — used on account deletion so no history outlives the account. */
    fun clear(context: Context) {
        synchronized(lock) {
            context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().remove(KEY_EVENTS).apply()
        }
    }

    private fun readArray(prefs: android.content.SharedPreferences): JSONArray {
        val raw = prefs.getString(KEY_EVENTS, null) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (e: Exception) {
            Log.w(TAG, "Corrupt ledger; starting fresh.", e)
            JSONArray()
        }
    }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (!has(key) || isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
}
