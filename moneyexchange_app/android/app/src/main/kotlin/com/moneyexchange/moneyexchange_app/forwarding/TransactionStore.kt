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

    private const val KEY_EVENTS = "events"
    const val MAX_EVENTS = 1000
    private const val TAG = "Xawil/TxStore"

    /** Retention window for the "clear old" sweep: keep only the last ~month. */
    private const val RETENTION_DAYS = 31L
    private const val RETENTION_MS = RETENTION_DAYS * 24 * 60 * 60 * 1000L

    private val lock = Any()

    /**
     * Per-user ledger file: each signed-in user has their own transaction history,
     * keyed by the active user's namespace (see [SessionStore]). Signed out uses
     * "anon". Switching users switches which ledger the dashboard reads.
     */
    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(
            "xawil_transactions_${SessionStore.namespace(context)}",
            Context.MODE_PRIVATE,
        )

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
        dedupeKey: String? = null,
    ): Map<String, Any?>? {
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
            "dedupeKey" to dedupeKey,
        )
        synchronized(lock) {
            val prefs = prefs(context)
            val arr = readArray(prefs)
            // Idempotency: if this event carries a dedupe key already present in the
            // ledger, skip it — so re-reading the same 898 receipt (or the same
            // leftover balance) never double-counts the received total.
            if (dedupeKey != null && containsDedupeKey(arr, dedupeKey)) {
                Log.i(TAG, "Skipped duplicate $type (key=$dedupeKey).")
                return null
            }
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
        val prefs = prefs(context)
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
            prefs(context).edit().remove(KEY_EVENTS).apply()
        }
    }

    /**
     * Storage usage snapshot for the dashboard/settings progress bar: how many
     * events are stored out of [MAX_EVENTS], and the oldest event's timestamp.
     */
    fun storageInfo(context: Context): Map<String, Any?> {
        val prefs = prefs(context)
        val arr = synchronized(lock) { readArray(prefs) }
        var oldest = 0L
        for (i in 0 until arr.length()) {
            val ts = arr.optJSONObject(i)?.optLong("timestampMs") ?: continue
            if (ts > 0 && (oldest == 0L || ts < oldest)) oldest = ts
        }
        return mapOf(
            "count" to arr.length(),
            "max" to MAX_EVENTS,
            "oldestTimestampMs" to oldest,
            "retentionDays" to RETENTION_DAYS.toInt(),
        )
    }

    /**
     * "Refresh storage": drops every event older than the ~1-month retention
     * window, keeping only the last month. Returns how many were removed.
     */
    fun clearExceptLastMonth(context: Context): Int {
        val cutoff = System.currentTimeMillis() - RETENTION_MS
        synchronized(lock) {
            val prefs = prefs(context)
            val arr = readArray(prefs)
            val kept = JSONArray()
            var removed = 0
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                if (o.optLong("timestampMs") >= cutoff) kept.put(o) else removed++
            }
            prefs.edit().putString(KEY_EVENTS, kept.toString()).apply()
            Log.i(TAG, "Cleared $removed event(s) older than $RETENTION_DAYS days.")
            return removed
        }
    }

    private fun containsDedupeKey(arr: JSONArray, key: String): Boolean {
        for (i in 0 until arr.length()) {
            if (arr.optJSONObject(i)?.optString("dedupeKey") == key) return true
        }
        return false
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
