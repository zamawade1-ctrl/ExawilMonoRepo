package com.moneyexchange.moneyexchange_app.forwarding

import android.content.Context

/**
 * Remembers which signed-in user the on-device stores belong to, so every user
 * gets their OWN persistent forwarding config + PINs ([ForwardingSettings]) and
 * transaction ledger ([TransactionStore]) instead of one shared global blob.
 *
 * The Flutter app sets the active user on login / session-restore
 * (`setActiveUser`) and clears it on logout. Both native stores derive their
 * SharedPreferences file name from [namespace], so switching users switches which
 * data they read/write — and the background SMS-triggered forwarder (which runs
 * with the app closed) reads the LAST active user's namespace, persisted here.
 *
 * The id itself is tiny and non-sensitive (the backend User id), so a plain
 * global pref is fine; the sensitive PINs live encrypted inside each user's
 * namespaced [ForwardingSettings].
 */
object SessionStore {

    private const val PREFS = "xawil_session"
    private const val KEY_ACTIVE_USER = "active_user_id"

    /**
     * One-time guard so orphaned pre-namespacing data is adopted only once.
     * Bumped to v2 to also sweep in the "anon" namespace (data recorded while
     * signed in but before the active user was being set on login).
     */
    private const val KEY_LEGACY_MIGRATED = "legacy_global_migrated_v2"

    /** The backend User id of the signed-in user, or null when signed out. */
    fun activeUserId(context: Context): String? =
        prefs(context).getString(KEY_ACTIVE_USER, null)

    fun setActiveUserId(context: Context, userId: String?) {
        prefs(context).edit().putString(KEY_ACTIVE_USER, userId).apply()
        // First real user to sign in after the per-user namespacing update adopts
        // any pre-namespacing data (config + ledger) so it isn't stranded — this
        // is why an existing user's dashboard could show nothing after the update.
        if (userId != null) migrateLegacyGlobalInto(context, userId)
    }

    /**
     * Before per-user namespacing, both stores lived in single **global** files
     * (`xawil_forwarding`, `xawil_transactions`); and in the brief window after
     * namespacing but before the active user was set on login, data landed in the
     * **`anon`** namespace (`..._anon`). Either way it became orphaned once the
     * dashboard/forwarder started reading `..._<userId>`. This adopts whichever of
     * those sources still holds data into the first signing-in user's namespace,
     * exactly once (a global flag), and only when the user's own file is still
     * empty (so a real user's data is never clobbered).
     */
    private fun migrateLegacyGlobalInto(context: Context, userId: String) {
        val session = prefs(context)
        if (session.getBoolean(KEY_LEGACY_MIGRATED, false)) return

        // Prefer the global (oldest) source; fall back to the "anon" namespace.
        val movedFwd = copyPrefsIfTargetEmpty(
            context,
            listOf("xawil_forwarding", "xawil_forwarding_anon"),
            "xawil_forwarding_$userId",
        )
        val movedTx = copyPrefsIfTargetEmpty(
            context,
            listOf("xawil_transactions", "xawil_transactions_anon"),
            "xawil_transactions_$userId",
        )

        // Mark done regardless: the orphaned blob belongs to a single pre-update
        // user, so it's adopted once and never re-copied to a second account.
        session.edit().putBoolean(KEY_LEGACY_MIGRATED, true).apply()
        android.util.Log.i(
            "Xawil/Session",
            "Legacy migration into user=$userId: forwarding=$movedFwd, transactions=$movedTx.",
        )
    }

    /**
     * Copies every entry from the first non-empty source in [legacyNames] into
     * [targetName], but ONLY when the target is still empty (so a user's real
     * namespaced data is never overwritten). Returns whether a copy happened.
     * Encrypted PIN strings copy verbatim (the Keystore key is process-global, not
     * per-file, so they still decrypt).
     */
    private fun copyPrefsIfTargetEmpty(context: Context, legacyNames: List<String>, targetName: String): Boolean {
        val ctx = context.applicationContext
        val target = ctx.getSharedPreferences(targetName, Context.MODE_PRIVATE)
        if (target.all.isNotEmpty()) return false
        val legacy = legacyNames
            .map { ctx.getSharedPreferences(it, Context.MODE_PRIVATE) }
            .firstOrNull { it.all.isNotEmpty() } ?: return false

        val editor = target.edit()
        for ((key, value) in legacy.all) {
            when (value) {
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
                is Boolean -> editor.putBoolean(key, value)
                is Float -> editor.putFloat(key, value)
                is Set<*> -> {
                    @Suppress("UNCHECKED_CAST")
                    editor.putStringSet(key, value as Set<String>)
                }
            }
        }
        editor.apply()
        return true
    }

    /**
     * Per-user suffix for the namespaced stores. Falls back to "anon" when no user
     * is active (signed out), so a logged-out background forwarder reads an empty
     * config and does nothing.
     */
    fun namespace(context: Context): String = activeUserId(context) ?: "anon"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
