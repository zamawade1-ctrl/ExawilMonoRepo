package com.moneyexchange.moneyexchange_app.forwarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * All strings here are REAL messages the user shared (digits/names unchanged
 * except where noted). The most important assertions are the "sent" ones:
 * those must never be treated as incoming, or we'd loop and drain the account.
 */
class SmsMoneyParserTest {

    // --- Money OUT: must be ignored (these are what Zaad sends us after WE forward) ---

    @Test
    fun zaadSent_welcomeForm_isIgnored() {
        val sms = "[-[--ZAAD SHILLING--]-] Kusoo dhawaaw  NACFI CAFATERIA Tix: 15433103972, " +
            "SLSH2,000  ayaad u dirtay   (517144). Hadhaagaagu waa SLSH6,262.33."
        val r = SmsMoneyParser.parse(sms)
        assertFalse(r.reason, r.isIncoming)
    }

    @Test
    fun zaadSent_namedRecipient_isIgnored() {
        val sms = "[-[--ZAAD SHILLING--]-] Tix:15433187519, SLSH 2,000 ayaad u dirtay MAXAMUUD " +
            "CUMAR WAYRAX GUURE(0634779796) Tar:03/08/26 20:42:26, Hadhaagaaga:SLSH 4,262.33"
        val r = SmsMoneyParser.parse(sms)
        assertFalse(r.reason, r.isIncoming)
    }

    @Test
    fun edahabSent_isIgnored() {
        val sms = "4,000 Shilling ayaad u dirtay CHIEF FAST FOOD(657499670).Code:732136 Txn " +
            "id :MP260804.1031.D64643.Hadhaagaagu waa: 141.7 Shilling.Tar :04-08-2026[-eDahab-Service-Shilling]"
        val r = SmsMoneyParser.parse(sms)
        assertFalse(r.reason, r.isIncoming)
    }

    // --- Airtime top-up that happens to contain "waxaad heshay": must be ignored ---

    @Test
    fun edahabAirtimeTopUp_isIgnored() {
        val sms = "Macmiil,Waxaad heshay:\nKu Hadal \$0.12\nU furtay lambarka: 653468466\n" +
            "eDahab Ref: CO260803.0908.D02632\nHadhaagaagu waa: 19141.7\n" +
            "Waad ku mahadsantahay isticmaalka adeegyada SOMTEL."
        val r = SmsMoneyParser.parse(sms)
        assertFalse(r.reason, r.isIncoming)
    }

    // --- Money IN: must be forwarded, with the correct amount (not the balance) ---

    @Test
    fun edahabReceived_parsesAmountNotBalance() {
        val sms = "4,000 Shilling Ayaad Ka Heshay MAXAMED WARSAME CUMAR.Code-ka:NA. Lambarka " +
            ":654461828,Tixraaca : PP260804.0947.D61224, Hadhaagaaga Cusubi Waa: 4,141.7 " +
            "Shilling..Tariikh :04-08-2026[-eDahab-Service-Shilling]"
        val r = SmsMoneyParser.parse(sms)
        assertTrue(r.reason, r.isIncoming)
        assertEquals("4000", r.amount)
    }

    // --- Representative Zaad "received" shape (PLACEHOLDER wording; confirm with
    //     a real Zaad received SMS, then tighten if needed). Verifies the amount
    //     comes from the receive line and not the SLSH balance. ---

    @Test
    fun zaadReceived_placeholder_parsesAmountNotBalance() {
        val sms = "[-[--ZAAD SHILLING--]-] Tix:15436379999, SLSH 3,500 ayaad ka heshay YAXYE " +
            "CABDI(0633984169) Tar:04/08/26 10:15:08, Hadhaagaaga:SLSH 5,762.33"
        val r = SmsMoneyParser.parse(sms)
        assertTrue(r.reason, r.isIncoming)
        assertEquals("3500", r.amount)
    }
}
