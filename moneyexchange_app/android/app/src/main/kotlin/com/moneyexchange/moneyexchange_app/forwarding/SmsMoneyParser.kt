package com.moneyexchange.moneyexchange_app.forwarding

/**
 * SAFETY-CRITICAL. Decides whether an incoming SMS represents money *received*
 * (which we forward) versus money *sent*, airtime, or anything else (which we
 * must ignore).
 *
 * Why this matters: the moment we forward money, Zaad sends us a "you sent X"
 * confirmation SMS. If that confirmation were mistaken for newly-received money
 * we would forward it again, and again — an infinite loop draining the account.
 * So the rule is a strict allowlist:
 *
 *   incoming  ==  (a RECEIVED marker is present)
 *             AND (no SENT marker is present)
 *             AND (an amount can be extracted)
 *
 * Somali markers, confirmed from real Zaad/eDahab messages:
 *   - RECEIVED: "ka heshay" (received from), "waxaad heshay" (you have received)
 *   - SENT:     "u dirtay"  (you sent to)      <-- hard block
 *   - airtime:  "ku hadal" / "shubashada"      <-- ignore (Somtel top-up)
 *
 * v1 targets Zaad Shilling (sender 222, amounts prefixed "SLSH"). The Zaad
 * *received* wording is pending a real sample from the user; the RECEIVED
 * markers below are the ones shared across Zaad/eDahab, and are unit-tested
 * against the real SENT samples to guarantee we never treat a send as a receive.
 */
object SmsMoneyParser {

    data class Result(
        /** True only when this SMS is money we should forward. */
        val isIncoming: Boolean,
        /** Normalized amount to type into the USSD, e.g. "4000". Null unless isIncoming. */
        val amount: String?,
        /** Human-readable explanation, for logging/debugging. */
        val reason: String,
    )

    private val SENT_MARKERS = listOf("u dirtay", "aad dirtay", "waad dirtay")
    private val RECEIVED_MARKERS = listOf("ka heshay", "kaa heshay", "waxaad heshay", "ayaad ka heshay")
    private val IGNORE_MARKERS = listOf("ku hadal", "shubashada", "sarifo", "digtoonoow")

    /** Amount right after an "SLSH" / "$" token, or a "<number> Shilling" phrase. */
    private val SLSH_AMOUNT = Regex("""slsh\s*([0-9][0-9,]*(?:\.[0-9]+)?)""", RegexOption.IGNORE_CASE)
    private val NUMBER_SHILLING = Regex("""([0-9][0-9,]*(?:\.[0-9]+)?)\s*shilling""", RegexOption.IGNORE_CASE)
    /** Balance clause we must never read the amount from ("Hadhaagaagu waa ..."). */
    private val BALANCE_CLAUSE = Regex("""hadhaag\w*.*$""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))

    /**
     * SAFETY guard for the check-messages (898) flow: true when the SMS is one
     * we must never forward against — an outgoing "you sent…" confirmation, or
     * an airtime/exchange notification. The 898 balance flow reads a balance out
     * of the message directly (it has no "received" marker to key off), so it
     * relies on this hard block to avoid re-forwarding the confirmation Zaad
     * sends right after our own send (which would loop and drain the account).
     */
    fun isOutgoingOrIgnorable(body: String): Boolean {
        val text = body.lowercase()
        return SENT_MARKERS.any { text.contains(it) } || IGNORE_MARKERS.any { text.contains(it) }
    }

    fun parse(body: String): Result {
        val text = body.lowercase()

        if (IGNORE_MARKERS.any { text.contains(it) }) {
            return Result(false, null, "ignored: airtime/exchange/other notification")
        }
        // Hard block: a "sent" confirmation must never be treated as received.
        if (SENT_MARKERS.any { text.contains(it) }) {
            return Result(false, null, "ignored: outgoing (u dirtay) confirmation")
        }
        if (RECEIVED_MARKERS.none { text.contains(it) }) {
            return Result(false, null, "ignored: no 'received' marker found")
        }

        val amount = extractAmount(body)
            ?: return Result(false, null, "received marker present but no amount could be parsed")

        return Result(true, amount, "incoming money: $amount")
    }

    /**
     * Extracts the *received* amount, deliberately excluding the balance clause
     * (which also contains an "SLSH ..." number). Returns whole-shilling digits
     * with separators stripped, e.g. "4,000" -> "4000".
     */
    private fun extractAmount(body: String): String? {
        val beforeBalance = BALANCE_CLAUSE.replace(body, "")
        val raw = SLSH_AMOUNT.find(beforeBalance)?.groupValues?.get(1)
            ?: NUMBER_SHILLING.find(beforeBalance)?.groupValues?.get(1)
            ?: return null
        return normalize(raw)
    }

    /** "4,000" -> "4000"; "4,000.00" -> "4000"; keeps a real fractional part otherwise. */
    private fun normalize(raw: String): String {
        val noSeparators = raw.replace(",", "")
        val value = noSeparators.toBigDecimalOrNull() ?: return noSeparators
        return value.stripTrailingZeros().toPlainString().let {
            if (it.endsWith(".0") || !it.contains(".")) value.toBigInteger().toString() else it
        }
    }
}
