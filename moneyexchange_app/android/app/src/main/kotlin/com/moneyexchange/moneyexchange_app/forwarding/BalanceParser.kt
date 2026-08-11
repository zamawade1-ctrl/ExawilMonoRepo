package com.moneyexchange.moneyexchange_app.forwarding

/**
 * Extracts the account **balance** from the `*800#` USSD balance screen ("…
 * Available Balance: $2.6697" / "Hadhaageedu waa $10.00"). Used by the AUTO_FORWARD
 * sweep (and the manual "sweep now" action), which dial `*800#` and forward the
 * balance. MESSAGE_CHECK does NOT use this — it forwards the exact exchanged amount
 * parsed from the 898 SMS by [SmsMoneyParser.exchangedUsd] and never dials `*800#`.
 *
 * [receivedUsd] is a legacy amount matcher kept only for tests.
 *
 * ## Why we key off the balance *phrase*, not the first "$…"
 * A received-money SMS contains TWO dollar amounts — the incoming transaction
 * amount first, then the resulting balance:
 *
 *   "…$100 Received from MUNA … , Your New A/C Balance is $150.0045"  → balance 150.0045
 *   "…$50 Received from SUHAYB … , Your New A/C Balance is $50"        → balance 50
 *   "…Waxaad $5 ka heshay … , hadhaagaadu waa: $5"                     → balance 5
 *   "Hadhaageedu waa $10.00"   (the *800# balance screen)             → balance 10.00
 *
 * Grabbing the first "$…" would forward the *transaction* amount, not the
 * balance — the "check-messages isn't reading the balance" bug. So we match the
 * amount that immediately follows a balance phrase ("… Balance is",
 * "hadhaag… waa", "haraag…", "lacagta"), which is always the balance.
 *
 * SAFETY: the outgoing forward confirmation ("$X sent to …, Your Balance is
 * $0.07") also carries a "Balance is" phrase, so it MUST be hard-blocked before
 * it ever reaches here — [SmsMoneyParser.isOutgoingOrIgnorable] does that off the
 * "sent to" / "u sariftay" markers, so we never forward against our own send.
 */
object BalanceParser {

    data class Result(
        /** Parsed USD balance, or null if none could be read. */
        val balanceUsd: Double?,
        /** Account phone number if present in the text, else null. */
        val phoneNumber: String?,
        /** Human-readable explanation, for logging. */
        val reason: String,
    )

    /**
     * The balance is the amount that follows a balance phrase. Handles the
     * English "… Balance is $150.0045" / "Balance: $10" and the Somali
     * "hadhaagaadu waa: $5" / "Hadhaageedu waa $10.00" shapes. The "$"/currency
     * marker and the "waa"/":" connector are optional so wording variants still
     * match; the captured group is always the numeric balance.
     */
    private val BALANCE_PHRASE = Regex(
        """(?:balance\s+is|balance|hadhaag\w*|haraag\w*|lacagta)\s*(?:waa)?\s*[:=]?\s*(?:\$|usd)?\s*([0-9][0-9,]*(?:\.[0-9]+)?)""",
        RegexOption.IGNORE_CASE,
    )

    /**
     * The USD amount RECEIVED, used as a FALLBACK for the check-messages (898)
     * flow when a money-in SMS carries no balance clause. Real ZAAD money-in
     * messages usually include "… Hadhaagaagu waa $X" (a balance, preferred), but
     * some just say "Waxaad $X ka heshay <name>" with no balance — without this
     * fallback those arrive and forward nothing. Matches the "$X" that sits right
     * before a received marker ("$1 ka heshay", "$125 Received from …").
     *
     * The leading "$" is REQUIRED so a bare number elsewhere (a ref id, a date, an
     * account number) can never be mistaken for an amount. SAFETY: callers MUST
     * have already excluded outgoing/ignorable messages via
     * [SmsMoneyParser.isOutgoingOrIgnorable] before using this — an outgoing
     * "$X sent to …" also has a "$X" and would otherwise be read as received.
     */
    private val RECEIVED_USD = Regex(
        """\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*(?:ka\s+heshay|kaa\s+heshay|received\s+from)""",
        RegexOption.IGNORE_CASE,
    )

    // Phone number: an international or local Somali-style number (7–15 digits,
    // optional +, spaces/dashes allowed between).
    private val PHONE = Regex("""(\+?\d[\d\s-]{6,14}\d)""")

    fun parse(text: String): Result {
        val balance = extractBalance(text)
        val phone = extractPhone(text)

        return when {
            balance == null -> Result(null, phone, "no balance phrase found in text")
            else -> Result(balance, phone, "balance=$balance phone=${phone ?: "?"}")
        }
    }

    /**
     * Reads the balance that sits right after a balance phrase. We deliberately
     * do NOT fall back to "any $ amount": a stray amount elsewhere (the incoming
     * transaction amount, an exchange rate, a menu label) must never be treated
     * as the balance and forwarded against. No balance phrase → null → skip.
     */
    private fun extractBalance(text: String): Double? {
        val raw = BALANCE_PHRASE.find(text)?.groupValues?.get(1) ?: return null
        return raw.replace(",", "").toDoubleOrNull()
    }

    /**
     * The **last** balance amount in [text] — used to read the *leftover* balance
     * off the "…Your Balance is $X." result dialog shown after a forward completes.
     * Takes the last match (not the first) so that if a couple of confirmations
     * briefly stack in one dialog, we report the most recent remaining balance.
     */
    fun lastBalanceUsd(text: String): Double? =
        BALANCE_PHRASE.findAll(text).lastOrNull()?.groupValues?.get(1)
            ?.replace(",", "")?.toDoubleOrNull()

    /**
     * The USD amount received, or null if the text isn't a "$X received" message.
     * Used only as a fallback when [extractBalance] finds no balance clause. See
     * [RECEIVED_USD] for the safety contract (callers must exclude outgoing first).
     */
    fun receivedUsd(text: String): Double? =
        RECEIVED_USD.find(text)?.groupValues?.get(1)?.replace(",", "")?.toDoubleOrNull()

    private fun extractPhone(text: String): String? {
        val match = PHONE.find(text)?.groupValues?.get(1) ?: return null
        val digits = match.filter { it.isDigit() || it == '+' }
        // Guard against matching the balance amount itself (too short to be a phone).
        return if (digits.count { it.isDigit() } in 7..15) digits else null
    }
}
