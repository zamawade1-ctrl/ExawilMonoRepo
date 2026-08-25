package com.moneyexchange.moneyexchange_app.forwarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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

    // --- Real 898 / 222 outgoing confirmations (observed on-device): the
    //     check-messages 898 flow hard-blocks these via isOutgoingOrIgnorable so
    //     our own send confirmation is never re-forwarded (which would loop). ---

    @Test
    fun sms898_englishSentConfirmation_isBlocked() {
        val sms = "[-ADEEGA SARIFKA-] Ref:15474116643 \$10 sent to SUHAYB CABDIKARIIM AXMED"
        assertTrue(SmsMoneyParser.isOutgoingOrIgnorable(sms))
        assertFalse(SmsMoneyParser.parse(sms).isIncoming)
    }

    @Test
    fun zaad222_uSariftayConfirmation_isBlocked() {
        val sms = "[-[-ADEEGA SARIFKA-]-] Tixraac: 15474105681, Waxaad \$10 u sariftay SUHAYB"
        assertTrue(SmsMoneyParser.isOutgoingOrIgnorable(sms))
        assertFalse(SmsMoneyParser.parse(sms).isIncoming)
    }

    @Test
    fun edahabDollarSent_isIgnored() {
        val sms = "130 Dollar Ayaad u Dirtay SUHAYB CABDIKARIIM AXMED. Lambarka:654480003"
        assertTrue(SmsMoneyParser.isOutgoingOrIgnorable(sms))
        assertFalse(SmsMoneyParser.parse(sms).isIncoming)
    }

    // The English "successfully transferred" outgoing confirmation (real 898
    // message) — this one slipped past the old markers and nearly re-forwarded
    // against our own send (caught only by the cooldown). It MUST be blocked.
    @Test
    fun sms898_englishTransferConfirmation_isBlocked() {
        val sms = "[-ADEEGA SARIFKA-] Transfer-Id: 15477606041, You have successfully " +
            "transferred \$1 to SUHAYB, Your Balance is \$0.67"
        assertTrue(SmsMoneyParser.isOutgoingOrIgnorable(sms))
        assertFalse(SmsMoneyParser.parse(sms).isIncoming)
    }

    // Real 898 cash-out / exchange confirmation ("ayaad ka Sarifatay"): outgoing,
    // must be blocked so it's never forwarded against.
    @Test
    fun sms898_kaSarifatayExchange_isBlocked() {
        val sms = "[-ADEEGA SARIFKA-] Tix: 14653183525 \$5 ayaad ka Sarifatay GUDAAL MONEY " +
            "EXCHANGE (313933), Hadhaagaagu:\$0.Ka xidho lacagta kaa qaldanta *151#"
        assertTrue(SmsMoneyParser.isOutgoingOrIgnorable(sms))
        assertFalse(SmsMoneyParser.parse(sms).isIncoming)
    }

    // The "ADEEGA SARIFKA" header only ever tags an outgoing send/exchange
    // (received money is tagged "ZAAD SERVICES"), so it's a safe catch-all block
    // for send-confirmation wordings we haven't enumerated.
    @Test
    fun adeegaSarifkaHeader_isBlocked() {
        val sms = "[-ADEEGA SARIFKA-] Tix:14814703106, \$1 ayaad u dirtay SUHAYB (252634192816)"
        assertTrue(SmsMoneyParser.isOutgoingOrIgnorable(sms))
    }

    // A real "ZAAD SERVICES" money-in message must NOT be blocked (the header
    // catch-all above must not over-match the received case).
    @Test
    fun zaadServicesReceived_isNotBlocked() {
        val sms = "[-[--ZAAD SERVICES--]-] Tix: 14491966276, Waxaad \$1 ka heshay  XALWO  " +
            "CALI AXMED CALI (252634187585) Tar: 06/04/26 21:30:22, Hadhaagaagu waa \$1"
        assertFalse(SmsMoneyParser.isOutgoingOrIgnorable(sms))
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

    // --- isCheckMessageTrigger + exchangedUsd: check-messages forwards the DOLLAR
    //     amount from a Zaad 898 EXCHANGE ("$X u sariftay"). ONLY the 898 copy fires
    //     (the identical 222 copy is ignored). All strings + senders are REAL, pulled
    //     off the device (R9ZY500BRVD) — the body carries a newline after the header. ---

    // Real 898 exchange (the message the user showed): sender 898 → MUST fire, amount $1.
    @Test
    fun trigger_zaad898Exchange_fires_readsDollarAmount() {
        val sms = "[-[-ADEEGA SARIFKA-]-] \n Tixraac: 15480615237, Waxaad  \$1 u sariftay " +
            "SLSH11,000SUHAYB CABDIKARIIN AXMED GUDAAL(252634480003)."
        assertTrue(SmsMoneyParser.isCheckMessageTrigger("898", sms))
        assertEquals(1.0, SmsMoneyParser.exchangedUsd(sms)!!, 0.0001)
        assertEquals("15480615237", SmsMoneyParser.exchangeRef(sms))
    }

    // The second image's message: "$2 u sariftay" → amount $2. And a decimal one.
    @Test
    fun exchange_readsAmount_wholeAndDecimal() {
        val two = "[-[-ADEEGA SARIFKA-]-] Tixraac: 15288317776, Waxaad  \$2 u sariftay " +
            "SLSH22,000MAXAMUUD  CABDI MAXAMUUD CIGE(252634080684)."
        assertEquals(2.0, SmsMoneyParser.exchangedUsd(two)!!, 0.0001)
        val half = "[-[-ADEEGA SARIFKA-]-]  Tixraac: 15480358899, Waxaad  \$0.5 u sariftay " +
            "SLSH5,500CABDILAAHI  ISMAACII CABDILAAHI AADAM(252634691251)."
        assertEquals(0.5, SmsMoneyParser.exchangedUsd(half)!!, 0.0001)
        val ten = "Tixraac: 15480282872, Waxaad  \$10 u sariftay SLSH110,000MUSTAFE CABDI(252634188654)."
        assertEquals(10.0, SmsMoneyParser.exchangedUsd(ten)!!, 0.0001)
    }

    // CRITICAL: the SAME exchange is ALSO delivered from 222 — that copy MUST NOT fire,
    // so we forward each exchange once (the 222 copy is the user's "only 898" rule).
    @Test
    fun trigger_exchange222Copy_ignored_wrongSender() {
        val sms = "[-[-ADEEGA SARIFKA-]-] \n Tixraac: 15480615237, Waxaad  \$1 u sariftay " +
            "SLSH11,000SUHAYB CABDIKARIIN AXMED GUDAAL(252634480003)."
        assertFalse(SmsMoneyParser.isCheckMessageTrigger("222", sms))
    }

    // A real eDahab dollar receipt — wrong sender → ignored (never triggers).
    @Test
    fun trigger_edahab_ignored_wrongSender() {
        val sms = "100 Dollar Ayaad Ka Heshay MAXAMUUD. Lambarka 654590204. " +
            "Hadhaagaaga Cusubi Waa 100.9 Dollar.[-eDahab-Service-Dollar]"
        assertFalse(SmsMoneyParser.isCheckMessageTrigger("eDahab-USD", sms))
    }

    // Cash-out "ka Sarifatay" (dollars OUT) — even from 898, MUST NOT fire (not "u sariftay").
    @Test
    fun trigger_cashOutKaSarifatay_ignored() {
        val sms = "[-ADEEGA SARIFKA-] Tix: 14653183525 \$5 ayaad ka Sarifatay GUDAAL MONEY " +
            "EXCHANGE (313933), Hadhaagaagu:\$0."
        assertFalse(SmsMoneyParser.isCheckMessageTrigger("898", sms))
        assertNull(SmsMoneyParser.exchangedUsd(sms))
    }

    // Our OWN bank forward confirmation (real, 898) — not an exchange → ignored (no loop).
    @Test
    fun trigger_ownBankForwardConfirmation_ignored() {
        val sms = "[-ADEEGA SARIFKA-] Transfer-Id: 15480151408, You have successfully " +
            "transferred \$12 to your bank account No: 630XXX23, Your Balance is \$0.01."
        assertFalse(SmsMoneyParser.isCheckMessageTrigger("898", sms))
        assertNull(SmsMoneyParser.exchangedUsd(sms))
    }

    // Our OWN mobile "sent to" confirmation (real, 898) — not an exchange → ignored.
    @Test
    fun trigger_ownSentConfirmation_ignored() {
        val sms = "[-ADEEGA SARIFKA-] Ref:15478100832 \$1 sent to SUHAYB GUDAAL(252634192816), Your Balance is \$0.17."
        assertFalse(SmsMoneyParser.isCheckMessageTrigger("898", sms))
    }

    // A real ZAAD SERVICES OTP (898) — not an exchange → ignored.
    @Test
    fun trigger_otp_ignored() {
        val sms = "-ZAAD SERVICES- Access code is 137940. Fadlan Code-kan cidna hala wadaagin"
        assertFalse(SmsMoneyParser.isCheckMessageTrigger("898", sms))
    }

    // A direct dollar receipt ("Received from") is NOT an exchange, so it does not
    // trigger under the exchange-only rule (documents the intended scope).
    @Test
    fun trigger_directReceive_notAnExchange_ignored() {
        val sms = "[-ZAAD SERVICES-] Ref:15470335393 confirmed. \$50 Received from SUHAYB " +
            "(634192816), Your New A/C Balance is \$50"
        assertFalse(SmsMoneyParser.isCheckMessageTrigger("898", sms))
    }

    // Dedup key: the SAME exchange double-delivered (byte-identical) yields the SAME key
    // (its Tixraac ref), so the second delivery is skipped and never double-counts received.
    @Test
    fun dedupKey_identicalReDelivery_sameKey_usesRef() {
        val sms = "[-[-ADEEGA SARIFKA-]-] \n Tixraac: 14814754003, Waxaad  \$3 u sariftay " +
            "SLSH30,000SUHAYB CABDIKARIIN AXMED GUDAAL(252634480003)."
        assertEquals("14814754003", SmsMoneyParser.dedupKey(sms))
        assertEquals(SmsMoneyParser.dedupKey(sms), SmsMoneyParser.dedupKey(sms))
    }

    // Two DIFFERENT exchanges of the same $ amount have different refs → different keys,
    // so a genuine second $3 exchange is NOT wrongly deduped (money still forwarded).
    @Test
    fun dedupKey_differentTransactions_differentKeys() {
        val a = "Tixraac: 14814754003, Waxaad  \$3 u sariftay SLSH30,000A(252634480003)."
        val b = "Tixraac: 14814754999, Waxaad  \$3 u sariftay SLSH30,000B(252634480003)."
        assertTrue(SmsMoneyParser.dedupKey(a) != SmsMoneyParser.dedupKey(b))
    }

    // No parseable ref → a body-hash key (never null), so dedup is never silently skipped;
    // an identical re-delivery of that body still shares the key.
    @Test
    fun dedupKey_noRef_fallsBackToBodyHash_neverNull() {
        val noRef = "Waxaad  \$3 u sariftay SLSH30,000SOMEONE(252634480003)."
        val key = SmsMoneyParser.dedupKey(noRef)
        assertTrue(key.startsWith("b:"))
        assertEquals(key, SmsMoneyParser.dedupKey(noRef))
    }

    // --- exchangeSignature: content-based dedup that survives a DIFFERENT ref. This is
    //     the fix for the real bug — Zaad re-delivered the same exchange minutes apart
    //     with a new "Tixraac" ref, so ref-only dedup let a second (failing) forward
    //     through and double-counted the received total. ---

    // THE KEY CASE: same exchange (same $, same SLSH, same counterparty) delivered twice
    // with DIFFERENT refs → SAME signature, so the windowed dedup collapses the duplicate.
    @Test
    fun exchangeSignature_sameExchange_differentRef_sameSignature() {
        val first = "[-[-ADEEGA SARIFKA-]-] \n Tixraac: 15480615237, Waxaad  \$1 u sariftay " +
            "SLSH11,000SUHAYB CABDIKARIIN AXMED GUDAAL(252634480003)."
        val reDelivered = "[-[-ADEEGA SARIFKA-]-] \n Tixraac: 15480699999, Waxaad  \$1 u sariftay " +
            "SLSH11,000SUHAYB CABDIKARIIN AXMED GUDAAL(252634480003)."
        assertEquals(SmsMoneyParser.exchangeSignature(first), SmsMoneyParser.exchangeSignature(reDelivered))
    }

    // Different dollar amount → different signature (a genuine other exchange still forwards).
    @Test
    fun exchangeSignature_differentAmount_differentSignature() {
        val one = "Tixraac: 1, Waxaad  \$1 u sariftay SLSH11,000NAME(252634480003)."
        val two = "Tixraac: 2, Waxaad  \$2 u sariftay SLSH22,000NAME(252634480003)."
        assertTrue(SmsMoneyParser.exchangeSignature(one) != SmsMoneyParser.exchangeSignature(two))
    }

    // Different counterparty phone → different signature (two people, same $ → both forward).
    @Test
    fun exchangeSignature_differentCounterparty_differentSignature() {
        val a = "Tixraac: 1, Waxaad  \$3 u sariftay SLSH30,000NAME(252634480003)."
        val b = "Tixraac: 2, Waxaad  \$3 u sariftay SLSH30,000NAME(252634111111)."
        assertTrue(SmsMoneyParser.exchangeSignature(a) != SmsMoneyParser.exchangeSignature(b))
    }

    // A non-exchange message has no signature (nothing to dedup as a forward).
    @Test
    fun exchangeSignature_nonExchange_isNull() {
        val otp = "-ZAAD SERVICES- Access code is 137940. Fadlan Code-kan cidna hala wadaagin"
        assertNull(SmsMoneyParser.exchangeSignature(otp))
    }

    // Sender gate in isolation: only 898 counts as the Zaad dollar service.
    @Test
    fun zaad898Sender_matchesOnly898() {
        assertTrue(SmsMoneyParser.isZaad898Sender("898"))
        assertFalse(SmsMoneyParser.isZaad898Sender("eDahab-USD"))
        assertFalse(SmsMoneyParser.isZaad898Sender("222"))
    }

    // --- bankTransferUsd / bankTransferRef: the FORWARDED total is recorded off the
    //     real Zaad "…successfully transferred $X to your bank account…" confirmation
    //     (the exact amount that landed), deduped by its Transfer-Id. All strings are
    //     the real on-device confirmation shape (the one the user screenshotted). ---

    // The screenshotted confirmation: amount is the "$10" transferred, NOT the "630XXX23"
    // account digits and NOT the trailing "$0.29" balance.
    @Test
    fun bankTransferUsd_readsTransferredAmount_notBalanceOrAccount() {
        val sms = "[-ADEEGA SARIFKA-] Transfer-Id: 15602795163, You have successfully " +
            "transferred \$10 to your bank account No: 630XXX23, Your Balance is \$0.29."
        assertEquals(10.0, SmsMoneyParser.bankTransferUsd(sms)!!, 0.0001)
        assertEquals("15602795163", SmsMoneyParser.bankTransferRef(sms))
        assertTrue(SmsMoneyParser.isBankTransferConfirmation(sms))
    }

    // A decimal / larger confirmation still reads exactly the transferred figure.
    @Test
    fun bankTransferUsd_wholeAndLarger() {
        val twelve = "[-ADEEGA SARIFKA-] Transfer-Id: 15480151408, You have successfully " +
            "transferred \$12 to your bank account No: 630XXX23, Your Balance is \$0.01."
        assertEquals(12.0, SmsMoneyParser.bankTransferUsd(twelve)!!, 0.0001)
    }

    // The MOBILE "sent to" confirmation and the "$X to <name>" (no "bank account")
    // transfer are NOT bank confirmations — they must not be recorded as bank forwards.
    @Test
    fun bankTransferUsd_notABankConfirmation_isNull() {
        val sentTo = "[-ADEEGA SARIFKA-] Ref:15478100832 \$1 sent to SUHAYB(252634192816), Your Balance is \$0.17."
        assertNull(SmsMoneyParser.bankTransferUsd(sentTo))
        assertFalse(SmsMoneyParser.isBankTransferConfirmation(sentTo))
        val toName = "[-ADEEGA SARIFKA-] Transfer-Id: 15477606041, You have successfully " +
            "transferred \$1 to SUHAYB, Your Balance is \$0.67"
        assertNull(SmsMoneyParser.bankTransferUsd(toName))
    }

    // The exchange TRIGGER ("$X u sariftay") is not a bank confirmation, so recording the
    // forward off the confirmation never collides with the trigger's received bookkeeping.
    @Test
    fun bankTransferUsd_exchangeTrigger_isNull() {
        val exchange = "[-[-ADEEGA SARIFKA-]-] Tixraac: 15480615237, Waxaad  \$1 u sariftay " +
            "SLSH11,000SUHAYB(252634480003)."
        assertNull(SmsMoneyParser.bankTransferUsd(exchange))
    }
}
