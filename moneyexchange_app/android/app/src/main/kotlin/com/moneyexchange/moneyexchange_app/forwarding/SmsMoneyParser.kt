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

    // Outgoing "you sent / you exchanged" markers — hard-blocked so our own
    // post-forward confirmation can never be re-forwarded (a drain loop). All
    // confirmed against real 898/222 messages pulled off the device:
    //   - Somali send:      "$X ayaad u dirtay <name>"                → "u dirtay"
    //   - Somali exchange:  "$X ayaad ka Sarifatay GUDAAL MONEY…"     → "sarifatay"
    //   - Zaad exchange:    "Waxaad $X u sariftay SLSH…"              → "u sariftay"
    //   - English send:     "$X sent to <name>"                       → "sent to"
    //   - English transfer: "You have successfully transferred $X…"   → "transferred"
    // Plus the "ADEEGA SARIFKA" header, which ONLY ever tags an outgoing send /
    // exchange (received money is always tagged "ZAAD SERVICES"), so it's a safe
    // catch-all for send-confirmation wordings we haven't enumerated. This is the
    // loop guard the check-messages (898) flow relies on, since it forwards off a
    // balance the outgoing confirmation ALSO carries — see [isOutgoingOrIgnorable].
    private val SENT_MARKERS =
        listOf(
            "u dirtay", "aad dirtay", "waad dirtay", "sent to",
            "u sariftay", "sariftay", "sarifatay", "transferred", "adeega sarifka",
        )
    // Genuine money-IN markers. "received from" is the English ZAAD SERVICES form
    // ("$50 Received from NAME … Your New A/C Balance is $50"); the "…heshay"
    // variants are the Somali form ("Waxaad $5 ka heshay …"). None of these appear
    // in our own forward output, a "sent to" confirmation, or an OTP, so a received
    // marker cleanly identifies a check-messages trigger.
    private val RECEIVED_MARKERS =
        listOf("ka heshay", "kaa heshay", "waxaad heshay", "ayaad ka heshay", "received from")
    private val IGNORE_MARKERS = listOf("ku hadal", "shubashada", "sarifo", "digtoonoow")

    /** Amount right after an "SLSH" / "$" token, or a "<number> Shilling" phrase. */
    private val SLSH_AMOUNT = Regex("""slsh\s*([0-9][0-9,]*(?:\.[0-9]+)?)""", RegexOption.IGNORE_CASE)
    private val NUMBER_SHILLING = Regex("""([0-9][0-9,]*(?:\.[0-9]+)?)\s*shilling""", RegexOption.IGNORE_CASE)
    /** Balance clause we must never read the amount from ("Hadhaagaagu waa ..."). */
    private val BALANCE_CLAUSE = Regex("""hadhaag\w*.*$""", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))

    /**
     * The check-messages TRIGGER: a Zaad 898 dollar **exchange** ("u sariftay").
     * Real on-device shape (body carries a newline after the header):
     *   "[-[-ADEEGA SARIFKA-]-]\n Tixraac: 15480615237, Waxaad  $1 u sariftay
     *    SLSH11,000NAME(252634480003)."
     * We forward the DOLLAR amount stated right before "u sariftay" ($1 here). The
     * leading "$" is required so the shilling figure (SLSH11,000) or a ref id can
     * never be mistaken for the amount. "u sariftay" (exchanged INTO dollars) is
     * distinct from "ka sarifatay" (exchanged OUT / cash-out), which must NOT match.
     */
    private val EXCHANGE_USD =
        Regex("""\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*u\s+sariftay""", RegexOption.IGNORE_CASE)

    /** The "Tixraac: <id>" transaction reference, used to dedup double-delivered SMS. */
    private val EXCHANGE_REF = Regex("""tixraac:?\s*([0-9]+)""", RegexOption.IGNORE_CASE)

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

    /**
     * True when the SMS is a genuine money-IN notification (carries a
     * [RECEIVED_MARKERS] marker). Requiring a received marker keeps OTPs, our own
     * forward output, and "sent to" confirmations from qualifying as money-in.
     */
    fun hasReceivedMarker(body: String): Boolean {
        val text = body.lowercase()
        return RECEIVED_MARKERS.any { text.contains(it) }
    }

    /**
     * The dollar amount the account holder EXCHANGED, read from a Zaad 898
     * "…$X u sariftay…" message, or null if this isn't an exchange message. This is
     * the amount the check-messages flow forwards. Never matches "ka sarifatay"
     * (cash-out), "$X sent to", "…transferred…", or an OTP — so it cleanly picks
     * out exactly the exchange trigger.
     */
    fun exchangedUsd(body: String): Double? =
        EXCHANGE_USD.find(body)?.groupValues?.get(1)?.replace(",", "")?.toDoubleOrNull()

    /** The transaction reference ("Tixraac: <id>") used to dedup double-delivered SMS. */
    fun exchangeRef(body: String): String? =
        EXCHANGE_REF.find(body)?.groupValues?.get(1)

    /**
     * The FULL check-messages trigger decision: true only when [sender] is the Zaad
     * **dollar** short code 898 AND [body] is a dollar exchange ("$X u sariftay").
     * eDahab, Zaad shilling 222 (which also copies the exchange SMS — we take only
     * the 898 copy), our own forward output, sends, cash-outs, and OTPs all fail
     * this. Single source of truth for "does this SMS fire a forward", unit-tested
     * against real device messages.
     */
    fun isCheckMessageTrigger(sender: String, body: String): Boolean =
        isZaad898Sender(sender) && exchangedUsd(body) != null

    /**
     * Whether [sender] is the Zaad dollar short code 898. eDahab messages arrive
     * from "eDahab-USD" / "eDahab-SHL" and Zaad shilling from 222, none of which
     * contain "898", so only the Zaad dollar service matches.
     */
    fun isZaad898Sender(sender: String): Boolean {
        val s = sender.trim()
        return s == "898" || s.contains("898")
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
