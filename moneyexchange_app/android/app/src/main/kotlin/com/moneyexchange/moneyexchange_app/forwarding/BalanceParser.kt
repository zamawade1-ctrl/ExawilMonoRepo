package com.moneyexchange.moneyexchange_app.forwarding

/**
 * Parses the balance-check USSD response screen (shown after `*800#` → PIN →
 * menu option 1). Extracts:
 *   - the USD balance as a [Double], used to decide whether to forward and how
 *     much, and
 *   - the account's own phone number, recorded for reference.
 *
 * DEVICE/CARRIER-SPECIFIC: the exact wording of the balance screen varies. The
 * matchers below are broad (English + Somali) and will likely need a small tweak
 * once the real *800# response text is known — capture it from the on-device
 * logs (the accessibility service logs the raw screen text).
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

    // A "$12.50" / "USD 12.50" / "12.50 USD" style amount, optionally near a
    // balance keyword. We take the amount that sits closest to a balance marker
    // when one is present, otherwise the first currency-looking amount.
    private val DOLLAR_AMOUNT =
        Regex("""(?:\$|usd)\s*([0-9][0-9,]*(?:\.[0-9]+)?)""", RegexOption.IGNORE_CASE)
    private val AMOUNT_DOLLAR =
        Regex("""([0-9][0-9,]*(?:\.[0-9]+)?)\s*(?:\$|usd|dollars?)""", RegexOption.IGNORE_CASE)

    // Phone number: an international or local Somali-style number (7–15 digits,
    // optional +, spaces/dashes allowed between).
    private val PHONE = Regex("""(\+?\d[\d\s-]{6,14}\d)""")

    private val BALANCE_KEYWORDS = listOf("balance", "hadhaag", "haraaga", "lacagta")

    fun parse(text: String): Result {
        val balance = extractBalance(text)
        val phone = extractPhone(text)

        return when {
            balance == null -> Result(null, phone, "no balance amount found in screen text")
            else -> Result(balance, phone, "balance=$balance phone=${phone ?: "?"}")
        }
    }

    private fun extractBalance(text: String): Double? {
        // Require the amount to sit on a line that names the balance (e.g.
        // "Hadhaageedu waa $10.00"). We deliberately do NOT fall back to "any $
        // amount in the text": a stray amount elsewhere (an exchange rate, a menu
        // label, or even our own app UI) must never be treated as the balance and
        // forwarded against. No labelled balance line → null → skip the forward.
        val lines = text.split('\n', '\r')
        val keyworded = lines.firstOrNull { line ->
            BALANCE_KEYWORDS.any { line.contains(it, ignoreCase = true) } && amountIn(line) != null
        }
        val raw = keyworded?.let { amountIn(it) } ?: return null
        return raw.replace(",", "").toDoubleOrNull()
    }

    private fun amountIn(s: String): String? =
        DOLLAR_AMOUNT.find(s)?.groupValues?.get(1)
            ?: AMOUNT_DOLLAR.find(s)?.groupValues?.get(1)

    private fun extractPhone(text: String): String? {
        val match = PHONE.find(text)?.groupValues?.get(1) ?: return null
        val digits = match.filter { it.isDigit() || it == '+' }
        // Guard against matching the balance amount itself (too short to be a phone).
        return if (digits.count { it.isDigit() } in 7..15) digits else null
    }
}
