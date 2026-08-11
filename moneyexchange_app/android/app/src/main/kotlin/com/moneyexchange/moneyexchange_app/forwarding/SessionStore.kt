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

    /** The backend User id of the signed-in user, or null when signed out. */
    fun activeUserId(context: Context): String? =
        prefs(context).getString(KEY_ACTIVE_USER, null)

    fun setActiveUserId(context: Context, userId: String?) {
        prefs(context).edit().putString(KEY_ACTIVE_USER, userId).apply()
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
