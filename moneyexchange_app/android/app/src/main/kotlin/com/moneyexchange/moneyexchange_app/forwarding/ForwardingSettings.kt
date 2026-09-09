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

    // --- Mobile destination-change security flow -------------------------------
    //
    // When the user saves a NEW or CHANGED mobile forwarding number it does NOT go
    // live immediately: the new number is parked in [pendingDestination] while the
    // ACTIVE [destination] deliberately stays the previously-confirmed (old) number.
    // While a pending change exists the mobile branch of [isReady] returns false, so
    // the forwarder refuses to forward at all until the user explicitly confirms —
    // and, defensively, even a stray forward would go to the trusted OLD number, not
    // the unconfirmed new one. Confirm promotes [pendingDestination] to [destination];
    // reject discards it and leaves the old number active. Bank forwarding never sets
    // any of this, so that path is completely unaffected.

    /** The new mobile number awaiting the user's confirmation, or null when none is pending. */
    var pendingDestination: String?
        get() = prefs.getString(KEY_PENDING_DEST, null)
        private set(value) = prefs.edit().putString(KEY_PENDING_DEST, value).apply()

    /** The number that was active when the pending change was requested (for display / reject). */
    var pendingOldDestination: String?
        get() = prefs.getString(KEY_PENDING_OLD_DEST, null)
        private set(value) = prefs.edit().putString(KEY_PENDING_OLD_DEST, value).apply()

    /** Epoch-millis the pending change was requested; 0 when none is pending. */
    var pendingChangeAtMs: Long
        get() = prefs.getLong(KEY_PENDING_AT, 0L)
        private set(value) = prefs.edit().putLong(KEY_PENDING_AT, value).apply()

    /** True while a mobile destination change is awaiting confirmation. */
    fun hasPendingDestinationChange(): Boolean = !pendingDestination.isNullOrBlank()

    /**
     * Parks a NEW mobile [new] number as pending (old = [old]) and appends a PENDING
     * entry to the durable audit log. Any prior still-PENDING entry is marked REJECTED
     * (superseded) so only the newest change is ever pending. Returns the new entry's
     * id (its request timestamp). commit() so the pending state is durable before we go
     * on to (not) forward. Does NOT touch [destination] — that only moves on confirm.
     */
    @Synchronized
    fun requestDestinationChange(old: String?, new: String): Long {
        val now = System.currentTimeMillis()
        val superseded = readChangeLog().map { e ->
            if (e.status == STATUS_PENDING) e.copy(status = STATUS_REJECTED) else e
        }
        val entry = ChangeLogEntry(now, now, old.orEmpty(), new, STATUS_PENDING)
        writeChangeLog((superseded + entry).takeLast(MAX_CHANGE_LOG))
        prefs.edit()
            .putString(KEY_PENDING_DEST, new)
            .putString(KEY_PENDING_OLD_DEST, old)
            .putLong(KEY_PENDING_AT, now)
            .commit()
        return now
    }

    /**
     * Confirms the pending change: promotes [pendingDestination] to the active
     * [destination], marks the latest PENDING log entry CONFIRMED, and clears the
     * pending fields. No-op when nothing is pending.
     */
    @Synchronized
    fun confirmDestinationChange() {
        val newDest = pendingDestination ?: return
        markLatestPending(STATUS_CONFIRMED)
        prefs.edit()
            .putString(KEY_DESTINATION, newDest)
            .remove(KEY_PENDING_DEST)
            .remove(KEY_PENDING_OLD_DEST)
            .remove(KEY_PENDING_AT)
            .commit()
    }

    /**
     * Rejects the pending change: leaves the active [destination] as the old number,
     * marks the latest PENDING log entry REJECTED, and clears the pending fields.
     */
    @Synchronized
    fun rejectDestinationChange() {
        if (!hasPendingDestinationChange()) return
        markLatestPending(STATUS_REJECTED)
        prefs.edit()
            .remove(KEY_PENDING_DEST)
            .remove(KEY_PENDING_OLD_DEST)
            .remove(KEY_PENDING_AT)
            .commit()
    }

    private fun markLatestPending(status: String) {
        val log = readChangeLog().toMutableList()
        val idx = log.indexOfLast { it.status == STATUS_PENDING }
        if (idx >= 0) {
            log[idx] = log[idx].copy(status = status, updatedAtMs = System.currentTimeMillis())
            writeChangeLog(log)
        }
    }

    /**
     * The durable on-device audit trail of destination-change events, oldest first,
     * as channel-friendly maps: {id, atMs, updatedAtMs, oldNumber, newNumber, status}.
     * A separate record from the money ledger — it never affects dashboard totals.
     */
    fun destinationChangeLog(): List<Map<String, Any?>> =
        readChangeLog().map {
            mapOf(
                "id" to it.id,
                "atMs" to it.id,
                "updatedAtMs" to it.updatedAtMs,
                "oldNumber" to it.oldNumber,
                "newNumber" to it.newNumber,
                "status" to it.status,
            )
        }

    private data class ChangeLogEntry(
        val id: Long,
        val updatedAtMs: Long,
        val oldNumber: String,
        val newNumber: String,
        val status: String,
    )

    private fun readChangeLog(): List<ChangeLogEntry> =
        prefs.getString(KEY_CHANGE_LOG, "").orEmpty()
            .split('\n')
            .filter { it.isNotBlank() }
            .mapNotNull { line ->
                val p = line.split(LOG_SEP)
                if (p.size != 5) return@mapNotNull null
                val id = p[0].toLongOrNull() ?: return@mapNotNull null
                val updated = p[1].toLongOrNull() ?: id
                ChangeLogEntry(id, updated, p[2], p[3], p[4])
            }

    private fun writeChangeLog(entries: List<ChangeLogEntry>) {
        val joined = entries.joinToString("\n") {
            "${it.id}$LOG_SEP${it.updatedAtMs}$LOG_SEP${it.oldNumber}$LOG_SEP${it.newNumber}$LOG_SEP${it.status}"
        }
        prefs.edit().putString(KEY_CHANGE_LOG, joined).commit()
    }

    /**
     * True only when we have everything needed to run a full sweep + forward.
     * Requirements differ by method: mobile needs a destination + both PINs
     * (the secondary PIN rides inside `*806#`); bank needs only the account [pin]
     * (to unlock `*800#`) and the [bankPin], with no destination or secondary PIN.
     */
    fun isReady(): Boolean =
        enabled && when (forwardingMethod) {
            ForwardingMethod.MOBILE_NUMBER ->
                // A pending (unconfirmed) destination change hard-blocks mobile
                // forwarding until the user confirms — see the security flow above.
                !destination.isNullOrBlank() && !pin.isNullOrBlank() &&
                    !secondaryPin.isNullOrBlank() && !hasPendingDestinationChange()
            ForwardingMethod.BANK_ACCOUNT ->
                !pin.isNullOrBlank() && !bankPin.isNullOrBlank()
        }

    /**
     * Dedup guard for check-messages, so each Zaad 898 exchange is forwarded exactly
     * once. Two independent checks, because a duplicate and a genuine repeat look
     * almost identical:
     *
     *  - **[ref] (the "Tixraac" transaction id) within [refWindowMs]** — the primary,
     *    exact identity. Zaad byte-identically re-delivers the same 898 SMS (same ref),
     *    sometimes minutes apart; that copy carries the SAME ref, so a generous ref
     *    window collapses it. A GENUINE repeat exchange (the user really did $1 to the
     *    same person again) always gets a NEW ref, so ref-dedup never blocks it — this
     *    is the fix for "the 898 message arrived but nothing was forwarded", where the
     *    old signature-only window swallowed real repeats of the same amount for 10 min.
     *
     *  - **[signature] within [sigWindowMs]** — a SHORT content-only guard (dollars +
     *    shilling + counterparty, ref excluded — [SmsMoneyParser.exchangeSignature]) for
     *    the rarer case where Zaad re-delivers the same exchange with a DIFFERENT ref.
     *    Kept deliberately short so it only catches a near-simultaneous re-delivery and
     *    does NOT swallow a genuine repeat made a couple of minutes later.
     *
     * Returns true (forward it) only if neither check finds a recent match; a match in
     * either window is a duplicate → false. Entries older than BOTH windows are pruned.
     * Keeps only the most recent [MAX_SIGS] entries.
     *
     * commit(), not apply(): the write must be durable BEFORE we go on to forward, so a
     * duplicate SMS that arrives after the process is recycled (Doze/low-memory kill
     * between the two deliveries) still sees this entry on disk and is skipped.
     */
    @Synchronized
    fun markExchangeIfNew(
        ref: String?,
        signature: String,
        refWindowMs: Long,
        sigWindowMs: Long,
    ): Boolean {
        val now = System.currentTimeMillis()
        val existing = prefs.getString(KEY_EXCHANGE_SIGS, "").orEmpty()
        // Each entry is "ref<SIG_SEP>signature<SIG_SEP>timestampMs" (ref may be empty).
        // Keep an entry while it's still inside the LONGER of the two windows.
        val maxWindow = maxOf(refWindowMs, sigWindowMs)
        val kept = existing.split('\n').filter { it.isNotBlank() }.mapNotNull { entry ->
            val parts = entry.split(SIG_SEP)
            if (parts.size != 3) return@mapNotNull null
            val ts = parts[2].toLongOrNull() ?: return@mapNotNull null
            if (now - ts in 0..maxWindow) Triple(parts[0], parts[1], ts) else null
        }
        if (isDuplicateExchange(kept, ref, signature, now, refWindowMs, sigWindowMs)) return false
        val updated = (kept + Triple(ref.orEmpty(), signature, now)).takeLast(MAX_SIGS)
            .joinToString("\n") { "${it.first}$SIG_SEP${it.second}$SIG_SEP${it.third}" }
        prefs.edit().putString(KEY_EXCHANGE_SIGS, updated).commit()
        return true
    }

    // --- Pending mobile forwards (dashboard "forwarded" is confirmation-driven) --------
    //
    // A mobile `*806#` forward's dashboard FORWARDED total is recorded off Zaad's
    // "…$X sent to…" / "…$X ayaad u dirtay…" confirmation SMS — the amount that
    // actually left — NOT the send-time estimate, so an unconfirmed/failed transfer
    // never inflates the total (the same confirmation-driven rule the bank path uses).
    // But a "sent to" SMS is ALSO what Zaad sends for the user's own manual sends, so
    // we park each forward WE drive here and only count a confirmation that matches one
    // (by amount, within the window). Bank forwarding never touches any of this.

    /**
     * Parks a mobile forward of [amount] whole dollars, just driven and now awaiting
     * its "sent to" confirmation SMS (see [SmsReceiver.recordMobileConfirmation]). Each
     * entry is "amountCents<sep>atMs"; stale entries past the window are pruned and the
     * list is capped. commit() so it's durable before the confirmation can arrive.
     */
    @Synchronized
    fun addPendingMobileForward(amount: String) {
        val cents = amount.toBigDecimalOrNull()?.movePointRight(2)?.toLong() ?: return
        val now = System.currentTimeMillis()
        val kept = pendingMobileForwards(now)
        val updated = (kept + Pair(cents, now)).takeLast(MAX_PENDING_FWD)
            .joinToString("\n") { "${it.first}$PENDING_SEP${it.second}" }
        prefs.edit().putString(KEY_PENDING_MOBILE_FWD, updated).commit()
    }

    /**
     * Consumes ONE pending mobile forward matching [amountUsd] (within the window),
     * returning true when found — meaning this confirmation SMS is one of OUR forwards
     * and should be recorded as FORWARDED — or false when nothing matches, meaning the
     * "sent to" SMS is not a forward we drove (e.g. a manual send) and must be ignored.
     * The oldest matching entry is removed so two same-amount forwards each consume
     * exactly one confirmation.
     */
    @Synchronized
    fun consumePendingMobileForward(amountUsd: Double): Boolean {
        val cents = Math.round(amountUsd * 100)
        val now = System.currentTimeMillis()
        val kept = pendingMobileForwards(now).toMutableList()
        val idx = kept.indexOfFirst { it.first == cents }
        if (idx < 0) {
            // Persist the pruned list even on a miss so stale entries don't accumulate.
            prefs.edit().putString(
                KEY_PENDING_MOBILE_FWD,
                kept.joinToString("\n") { "${it.first}$PENDING_SEP${it.second}" },
            ).commit()
            return false
        }
        kept.removeAt(idx)
        prefs.edit().putString(
            KEY_PENDING_MOBILE_FWD,
            kept.joinToString("\n") { "${it.first}$PENDING_SEP${it.second}" },
        ).commit()
        return true
    }

    /** Still-in-window pending mobile forwards as (amountCents, atMs), oldest first. */
    private fun pendingMobileForwards(now: Long): List<Pair<Long, Long>> =
        prefs.getString(KEY_PENDING_MOBILE_FWD, "").orEmpty()
            .split('\n').filter { it.isNotBlank() }.mapNotNull { entry ->
                val p = entry.split(PENDING_SEP)
                if (p.size != 2) return@mapNotNull null
                val cents = p[0].toLongOrNull() ?: return@mapNotNull null
                val ts = p[1].toLongOrNull() ?: return@mapNotNull null
                if (now - ts in 0..PENDING_MOBILE_FWD_WINDOW_MS) Pair(cents, ts) else null
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
        /**
         * Pure dedup decision for [markExchangeIfNew], extracted so it can be unit-tested
         * without SharedPreferences. [kept] is the still-in-window history as
         * (ref, signature, timestampMs).
         *
         * The Tixraac [ref] is the SOLE identity when it's present (which it always is on a
         * real 898 SMS): an exchange is a duplicate only when the SAME ref recurs within
         * [refWindowMs] — Zaad's byte-identical re-delivery of one transaction, which always
         * carries the same ref. A GENUINE repeat (the user really did another $X to the same
         * person) always gets a NEW ref, so it is NEVER a duplicate and always forwards —
         * even seconds later, even for the identical amount + counterparty. This is the fix
         * for the "second 898 became a leftover" bug: the old content-signature window
         * collapsed two distinct same-amount exchanges into one and dropped the money.
         *
         * The content [signature] is used ONLY as a fallback when a ref couldn't be parsed
         * ([ref] null/blank), so a ref-less copy still can't double-send within [sigWindowMs].
         */
        fun isDuplicateExchange(
            kept: List<Triple<String, String, Long>>,
            ref: String?,
            signature: String,
            now: Long,
            refWindowMs: Long,
            sigWindowMs: Long,
        ): Boolean {
            if (!ref.isNullOrEmpty()) {
                // Ref present → dedup on the ref alone. Distinct refs = distinct exchanges,
                // so a genuine repeat of the same amount to the same person still forwards.
                return kept.any { it.first == ref && now - it.third in 0..refWindowMs }
            }
            // No ref to key on: fall back to the short content-signature window.
            return kept.any { it.second == signature && now - it.third in 0..sigWindowMs }
        }

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
        // Mobile destination-change security flow.
        private const val KEY_PENDING_DEST = "pending_destination"
        private const val KEY_PENDING_OLD_DEST = "pending_old_destination"
        private const val KEY_PENDING_AT = "pending_change_at_ms"
        private const val KEY_CHANGE_LOG = "destination_change_log"
        const val STATUS_PENDING = "PENDING"
        const val STATUS_CONFIRMED = "CONFIRMED"
        const val STATUS_REJECTED = "REJECTED"
        /** How many destination-change audit entries to retain. */
        private const val MAX_CHANGE_LOG = 100
        /** In-record separator for a change-log entry (a control char, never in a phone number). */
        private const val LOG_SEP = ""
        private const val DEFAULT_INTERVAL = 1

        /** Default auto-forward sweep cadence when nothing has been saved yet: every 30 seconds. */
        private const val DEFAULT_INTERVAL_SEC = 30

        /** Fastest allowed sweep cadence — every 30 seconds. */
        private const val MIN_INTERVAL_SEC = 30

        /** Slowest allowed sweep cadence — once an hour. */
        private const val MAX_INTERVAL_SEC = 3600

        /** How many recent exchange signatures to remember for dedup. */
        private const val MAX_SIGS = 50

        // Pending mobile forwards awaiting their "sent to" confirmation SMS.
        private const val KEY_PENDING_MOBILE_FWD = "pending_mobile_forwards"
        private const val PENDING_SEP = ""
        private const val MAX_PENDING_FWD = 50

        /**
         * How long a mobile forward waits for its "…$X sent to…" confirmation SMS before
         * its pending token is pruned. Generous (30 min) so a delayed confirmation still
         * records the FORWARDED event; bounded so a never-confirmed forward's stale token
         * can't be claimed much later by an unrelated same-amount manual send.
         */
        private const val PENDING_MOBILE_FWD_WINDOW_MS = 30L * 60L * 1000L

        /**
         * In-record separator between a stored exchange signature and its timestamp.
         * A control char that can't occur inside a signature (which is only dollars,
         * shilling digits, and phone digits), so splitting is unambiguous.
         */
        private const val SIG_SEP = "\u0001"
    }
}
