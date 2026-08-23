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

    // Per-user: each signed-in user has their own forwarding config + encrypted
    // PINs, keyed by the active user's namespace (see [SessionStore]). Switching
    // users switches which file this reads/writes; signed out uses "anon".
    private val prefs = context.applicationContext
        .getSharedPreferences("xawil_forwarding_${SessionStore.namespace(context)}", Context.MODE_PRIVATE)

    var destination: String?
        get() = prefs.getString(KEY_DESTINATION, null)
        set(value) = prefs.edit().putString(KEY_DESTINATION, value).apply()

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    /** How often the balance sweep runs, in whole minutes. Legacy unit — kept for the older
     *  minutes-based clients; [intervalSeconds] is the real scheduling unit now. Clamped 1..60. */
    var intervalMinutes: Int
        get() = prefs.getInt(KEY_INTERVAL, DEFAULT_INTERVAL)
        set(value) = prefs.edit().putInt(KEY_INTERVAL, value.coerceIn(1, 60)).apply()

    /**
     * How often the auto-forward balance sweep runs, in SECONDS — the source of truth the poller
     * schedules on (see [ForwardingForegroundService.scheduleNextTick]). Supersedes
     * [intervalMinutes] so the sweep can run as often as every [MIN_INTERVAL_SEC] seconds (30s).
     * When no seconds value has been saved yet it falls back to any legacy minutes value, else the
     * [DEFAULT_INTERVAL_SEC] default. Always returned clamped to [MIN_INTERVAL_SEC]..[MAX_INTERVAL_SEC].
     */
    var intervalSeconds: Int
        get() {
            val storedSec = prefs.getInt(KEY_INTERVAL_SECONDS, 0)
            if (storedSec > 0) return storedSec.coerceIn(MIN_INTERVAL_SEC, MAX_INTERVAL_SEC)
            // No seconds value yet: honour a previously-saved minutes value, else default to 30s.
            val effective =
                if (prefs.contains(KEY_INTERVAL)) prefs.getInt(KEY_INTERVAL, DEFAULT_INTERVAL) * 60
                else DEFAULT_INTERVAL_SEC
            return effective.coerceIn(MIN_INTERVAL_SEC, MAX_INTERVAL_SEC)
        }
        set(value) = prefs.edit()
            .putInt(KEY_INTERVAL_SECONDS, value.coerceIn(MIN_INTERVAL_SEC, MAX_INTERVAL_SEC))
            .apply()

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
     * Whether the user's trial/paid plan is currently active, as last pushed from
     * Flutter (`setPlanActive`). Defaults true so behaviour is unchanged until the
     * app first reports a plan — a missing plan never silently blocks forwarding.
     */
    var planActive: Boolean
        get() = prefs.getBoolean(KEY_PLAN_ACTIVE, true)
        set(value) = prefs.edit().putBoolean(KEY_PLAN_ACTIVE, value).apply()

    /**
     * Epoch-millis the plan stays valid through (trial end or paid-until), or 0 for
     * "no known expiry". Lets the forwarder self-expire even if the app never reopens.
     */
    var planActiveUntilMs: Long
        get() = prefs.getLong(KEY_PLAN_UNTIL, 0L)
        set(value) = prefs.edit().putLong(KEY_PLAN_UNTIL, value).apply()

    /**
     * Whether the plan permits any USSD work right now: the flag must be on AND, if a
     * validity instant is known, [now] must be before it. An expired plan makes the
     * forwarder completely inert (no sweep, balance check, SMS forward, or tick).
     */
    fun isPlanActive(now: Long = System.currentTimeMillis()): Boolean =
        planActive && (planActiveUntilMs == 0L || now < planActiveUntilMs)

    /**
     * The **leftover balance** remaining on the account after the most recent
     * forward — read off the "…Your Balance is $X." result dialog by the
     * accessibility service. Stored as a string to keep full precision; the UI
     * shows it in the sweep card. Null until the first forward completes.
     */
    var lastLeftoverBalance: Double?
        get() = prefs.getString(KEY_LAST_BALANCE, null)?.toDoubleOrNull()
        set(value) = prefs.edit().putString(KEY_LAST_BALANCE, value?.toString()).apply()

    /** Wall-clock millis when [lastLeftoverBalance] was captured; 0 if never. */
    var lastLeftoverAtMs: Long
        get() = prefs.getLong(KEY_LAST_BALANCE_AT, 0L)
        set(value) = prefs.edit().putLong(KEY_LAST_BALANCE_AT, value).apply()

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
     * Dedup guard for check-messages, keyed by a content SIGNATURE
     * ([SmsMoneyParser.exchangeSignature]) within a time window. The same Zaad exchange
     * is delivered more than once (an 898 copy and a 222 copy, sometimes twice each,
     * occasionally minutes apart with a DIFFERENT "Tixraac" ref on the copy — the case
     * that let duplicates through the old ref-only guard, attempting a second forward
     * and double-counting the received total). The signature is identical across every
     * copy of one exchange regardless of its ref, so this forwards each exchange once.
     *
     * Returns true (forward it) only if [signature] hasn't been seen within [windowMs];
     * a match inside the window is a duplicate and returns false. Entries older than the
     * window are pruned on each call, so an identical exchange repeated legitimately far
     * apart in time is still forwarded. Keeps only the most recent [MAX_SIGS] entries.
     *
     * commit(), not apply(): the write must be durable BEFORE we go on to forward, so a
     * duplicate SMS that arrives after the process is recycled (Doze/low-memory kill
     * between the two deliveries) still sees this signature on disk and is skipped.
     */
    @Synchronized
    fun markExchangeIfNew(signature: String, windowMs: Long): Boolean {
        val now = System.currentTimeMillis()
        val existing = prefs.getString(KEY_EXCHANGE_SIGS, "").orEmpty()
        // Each entry is "signature<SIG_SEP>timestampMs"; drop any now outside the window.
        val kept = existing.split('\n').filter { it.isNotBlank() }.mapNotNull { entry ->
            val sep = entry.lastIndexOf(SIG_SEP)
            if (sep <= 0) return@mapNotNull null
            val sig = entry.substring(0, sep)
            val ts = entry.substring(sep + SIG_SEP.length).toLongOrNull() ?: return@mapNotNull null
            if (now - ts in 0..windowMs) sig to ts else null
        }
        if (kept.any { it.first == signature }) return false
        val updated = (kept + (signature to now)).takeLast(MAX_SIGS)
            .joinToString("\n") { "${it.first}$SIG_SEP${it.second}" }
        prefs.edit().putString(KEY_EXCHANGE_SIGS, updated).commit()
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
        private const val KEY_INTERVAL_SECONDS = "interval_seconds"
        private const val KEY_SIM_SUB_ID = "sim_subscription_id"
        private const val KEY_MODE = "mode"
        private const val KEY_METHOD = "forwarding_method"
        private const val KEY_PIN_ENC = "pin_enc"
        private const val KEY_SECONDARY_PIN_ENC = "secondary_pin_enc"
        private const val KEY_BANK_PIN_ENC = "bank_pin_enc"
        private const val KEY_LAST_PHONE = "last_account_phone"
        private const val KEY_PLAN_ACTIVE = "plan_active"
        private const val KEY_PLAN_UNTIL = "plan_active_until_ms"
        private const val KEY_LAST_BALANCE = "last_leftover_balance"
        private const val KEY_LAST_BALANCE_AT = "last_leftover_balance_at"
        private const val KEY_EXCHANGE_SIGS = "forwarded_exchange_sigs"
        private const val DEFAULT_INTERVAL = 1

        /** Default auto-forward sweep cadence when nothing has been saved yet: every 30 seconds. */
        private const val DEFAULT_INTERVAL_SEC = 30

        /** Fastest allowed sweep cadence — every 30 seconds. */
        private const val MIN_INTERVAL_SEC = 30

        /** Slowest allowed sweep cadence — once an hour. */
        private const val MAX_INTERVAL_SEC = 3600

        /** How many recent exchange signatures to remember for dedup. */
        private const val MAX_SIGS = 50

        /**
         * In-record separator between a stored exchange signature and its timestamp.
         * A control char that can't occur inside a signature (which is only dollars,
         * shilling digits, and phone digits), so splitting is unambiguous.
         */
        private const val SIG_SEP = "\u0001"
    }
}
