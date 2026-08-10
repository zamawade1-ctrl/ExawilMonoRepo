package com.moneyexchange.moneyexchange_app.forwarding

import android.content.Context

/**
 * How the balance sweep decides *when* to run.
 *
 * [AUTO_FORWARD] runs on a timer ([ForwardingSettings.intervalMinutes]), dialing
 * `*800#` periodically to read + forward the balance regardless of whether money
 * has arrived. [MESSAGE_CHECK] never runs on a timer and never dials the `*800#`
 * balance check — it forwards the exact dollar amount read from a **Zaad 898**
 * exchange SMS ("$X u sariftay"); eDahab and the duplicate 222 copy are ignored.
 */
enum class ForwardingMode {
    AUTO_FORWARD,
    MESSAGE_CHECK,
    ;

    companion object {
        fun fromOrdinal(value: Int?): ForwardingMode =
            values().getOrElse(value ?: 0) { AUTO_FORWARD }
    }
}

/**
 * Where swept USD is sent. Ordinals mirror the backend/Dart `ForwardingMethod`
 * (MobileNumber = 0, BankAccount = 1).
 *
 * [MOBILE_NUMBER] forwards via the `*806*dest*amount*secondaryPin#` one-shot.
 * [BANK_ACCOUNT] forwards via an interactive `*800#` menu walk that ends by
 * typing the customer's [ForwardingSettings.bankPin] (see [UssdSession.beginBankSend]).
 */
enum class ForwardingMethod {
    MOBILE_NUMBER,
    BANK_ACCOUNT,
    ;

    companion object {
        fun fromOrdinal(value: Int?): ForwardingMethod =
            values().getOrElse(value ?: 0) { MOBILE_NUMBER }
    }
}

/**
 * The on-device source of truth for the balance-sweep auto-forwarder.
 *
 * Every [intervalMinutes] the poller dials the balance-check USSD (`*800#`),
 * auto-types the [pin] (primary), reads the balance, and — if it's at least
 * $1 — forwards it to [destination] via `*806*destination*amount*secondaryPin#`,
 * auto-typing the primary [pin] again on the confirmation popup. Both PINs are
 * encrypted at rest (Android Keystore) and never leave the device.
 *
 * [simSubscriptionId] selects which SIM the USSD is dialed on (dual-SIM phones);
 * -1 means the system default. [lastAccountPhone] is the account's own number as
 * read from the balance screen, recorded for reference.
 */
class ForwardingSettings(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences("xawil_forwarding", Context.MODE_PRIVATE)

    var destination: String?
        get() = prefs.getString(KEY_DESTINATION, null)
        set(value) = prefs.edit().putString(KEY_DESTINATION, value).apply()

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    /** How often the balance sweep runs. Clamped to a sane 1..60 range. */
    var intervalMinutes: Int
        get() = prefs.getInt(KEY_INTERVAL, DEFAULT_INTERVAL)
        set(value) = prefs.edit().putInt(KEY_INTERVAL, value.coerceIn(1, 60)).apply()

    /** Subscription id of the SIM to dial on; -1 = system default. */
    var simSubscriptionId: Int
        get() = prefs.getInt(KEY_SIM_SUB_ID, -1)
        set(value) = prefs.edit().putInt(KEY_SIM_SUB_ID, value).apply()

    /**
     * Whether the sweep runs on a timer or only reacts to a money-in SMS.
     * Defaults to [ForwardingMode.MESSAGE_CHECK] - the app leads with checking
     * only when money actually arrives rather than dialing on a fixed timer.
     */
    var mode: ForwardingMode
        get() = ForwardingMode.fromOrdinal(prefs.getInt(KEY_MODE, ForwardingMode.MESSAGE_CHECK.ordinal))
        set(value) = prefs.edit().putInt(KEY_MODE, value.ordinal).apply()

    /** Primary PIN — typed into the interactive USSD popups. Encrypted at rest. */
    var pin: String?
        get() = CryptoStore.decrypt(prefs.getString(KEY_PIN_ENC, null))
        set(value) {
            val enc = value?.takeIf { it.isNotEmpty() }?.let { CryptoStore.encrypt(it) }
            prefs.edit().putString(KEY_PIN_ENC, enc).apply()
        }

    /** Secondary PIN — embedded inline in the *806 send command. Encrypted at rest. */
    var secondaryPin: String?
        get() = CryptoStore.decrypt(prefs.getString(KEY_SECONDARY_PIN_ENC, null))
        set(value) {
            val enc = value?.takeIf { it.isNotEmpty() }?.let { CryptoStore.encrypt(it) }
            prefs.edit().putString(KEY_SECONDARY_PIN_ENC, enc).apply()
        }

    /** Whether swept USD forwards to a mobile number (`*806#`) or a bank account (`*800#` walk). */
    var forwardingMethod: ForwardingMethod
        get() = ForwardingMethod.fromOrdinal(prefs.getInt(KEY_METHOD, ForwardingMethod.MOBILE_NUMBER.ordinal))
        set(value) = prefs.edit().putInt(KEY_METHOD, value.ordinal).apply()

    /**
     * Bank PIN — typed on the bank-forwarding "enter bank pin" prompt (bank method
     * only). Distinct from the account [pin] that unlocks `*800#`. Encrypted at rest.
     */
    var bankPin: String?
        get() = CryptoStore.decrypt(prefs.getString(KEY_BANK_PIN_ENC, null))
        set(value) {
            val enc = value?.takeIf { it.isNotEmpty() }?.let { CryptoStore.encrypt(it) }
            prefs.edit().putString(KEY_BANK_PIN_ENC, enc).apply()
        }

    /** The account's own phone number, as last read from the balance screen. */
    var lastAccountPhone: String?
        get() = prefs.getString(KEY_LAST_PHONE, null)
        set(value) = prefs.edit().putString(KEY_LAST_PHONE, value).apply()

    /**
     * True only when we have everything needed to run a full sweep + forward.
     * Requirements differ by method: mobile needs a destination + both PINs
     * (the secondary PIN rides inside `*806#`); bank needs only the account [pin]
     * (to unlock `*800#`) and the [bankPin], with no destination or secondary PIN.
     */
    fun isReady(): Boolean =
        enabled && when (forwardingMethod) {
            ForwardingMethod.MOBILE_NUMBER ->
                !destination.isNullOrBlank() && !pin.isNullOrBlank() && !secondaryPin.isNullOrBlank()
            ForwardingMethod.BANK_ACCOUNT ->
                !pin.isNullOrBlank() && !bankPin.isNullOrBlank()
        }

    /**
     * Dedup guard for check-messages: the same Zaad exchange SMS is delivered more
     * than once (an 898 copy and a 222 copy, and sometimes twice each), so we key
     * off the message's "Tixraac" reference and forward each ref at most once.
     * [markRefForwardedIfNew] atomically checks-and-marks so two near-simultaneous
     * deliveries can't both pass. Keeps only the most recent [MAX_REFS] refs.
     */
    @Synchronized
    fun markRefForwardedIfNew(ref: String): Boolean {
        val existing = prefs.getString(KEY_FORWARDED_REFS, "").orEmpty()
        val refs = existing.split(',').filter { it.isNotBlank() }
        if (refs.contains(ref)) return false
        val updated = (refs + ref).takeLast(MAX_REFS).joinToString(",")
        prefs.edit().putString(KEY_FORWARDED_REFS, updated).apply()
        return true
    }

    /**
     * Wipes every stored forwarding setting — destination, all PINs, mode, method,
     * interval, SIM, and the enabled flag. Used on account deletion so no config
     * (or encrypted PIN) survives the account it belonged to. Logout, by contrast,
     * only flips [enabled] off so the same user's config is still there on re-login.
     */
    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_DESTINATION = "destination"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_INTERVAL = "interval_minutes"
        private const val KEY_SIM_SUB_ID = "sim_subscription_id"
        private const val KEY_MODE = "mode"
        private const val KEY_METHOD = "forwarding_method"
        private const val KEY_PIN_ENC = "pin_enc"
        private const val KEY_SECONDARY_PIN_ENC = "secondary_pin_enc"
        private const val KEY_BANK_PIN_ENC = "bank_pin_enc"
        private const val KEY_LAST_PHONE = "last_account_phone"
        private const val KEY_FORWARDED_REFS = "forwarded_refs"
        private const val DEFAULT_INTERVAL = 1

        /** How many recent exchange refs to remember for dedup. */
        private const val MAX_REFS = 50
    }
}
