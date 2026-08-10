package com.moneyexchange.moneyexchange_app.forwarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * All strings here are REAL 898 (ZAAD SERVICES / ADEEGA SARIFKA) messages pulled
 * off the device. The critical property: for the check-messages flow we forward
 * the ACCOUNT BALANCE, so [BalanceParser] must read the amount after the balance
 * phrase — NOT the (earlier) incoming transaction amount on the same line.
 */
class BalanceParserTest {

    // --- Received money: forward the New A/C Balance, not the received amount ---

    @Test
    fun received_readsNewAcBalance_notTheReceivedAmount() {
        val sms = "[-[--ZAAD SERVICES--]-] Ref:15470359126 confirmed. \$100 Received from " +
            "MUNA  ISMAACIIL CABDILAAHI AADAM (633514928),Date: 08/08/26 15:07:01, " +
            "Your New A/C Balance is \$150.0045"
        val r = BalanceParser.parse(sms)
        // Must be the balance 150.0045 — NOT the $100 that was received.
        assertEquals(150.0045, r.balanceUsd!!, 0.0001)
    }

    @Test
    fun received_equalAmountAndBalance() {
        val sms = "[-ZAAD SERVICES-] Ref:15470335393 confirmed. \$50 Received from SUHAYB  " +
            "CABDIKARIIM AXMED GUDAAL (634192816),Date: 08/08/26 14:59:03, Your New A/C Balance is \$50"
        assertEquals(50.0, BalanceParser.parse(sms).balanceUsd!!, 0.0001)
    }

    @Test
    fun received_somaliKaHeshay_readsHadhaag() {
        val sms = "[---ZAAD SERVICES---] Tixraac: 14652320972, Waxaad \$5 ka heshay " +
            "200407-MUSTAFE C/SALAAN-SALES ISHA BORAMA(252634220791), hadhaagaadu waa: \$5"
        assertEquals(5.0, BalanceParser.parse(sms).balanceUsd!!, 0.0001)
    }

    @Test
    fun ussdBalanceScreen_somali() {
        // The *800# balance screen shape (auto-forward mode).
        assertEquals(10.0, BalanceParser.parse("Hadhaageedu waa \$10.00").balanceUsd!!, 0.0001)
    }

    // --- Messages with no balance phrase: nothing to forward ---

    @Test
    fun noBalancePhrase_isNull() {
        val sms = "<---ZAAD SERVICES--- > Tix: 15229414740, Waxaad  202 ka heshay " +
            "RIDWAAN CABDULLAAHI CABDI (252619295048)"
        assertNull(BalanceParser.parse(sms).balanceUsd)
    }

    // --- Our own outgoing forward confirmation: parseable balance BUT must be
    //     hard-blocked upstream so we never re-forward against it (loop guard). ---

    @Test
    fun outgoingForwardConfirmation_isHardBlocked() {
        val sms = "[-ADEEGA SARIFKA-] Ref:15474493051 \$1 sent to SUHAYB  CABDIKARIIM AXMED " +
            "GUDAAL(252634192816) at 08/08/26 22:24:10, Your Balance is \$0.07."
        // It DOES carry a balance phrase…
        assertNotNull(BalanceParser.parse(sms).balanceUsd)
        // …so the safety net is the outgoing hard-block, which must catch it.
        assertTrue(SmsMoneyParser.isOutgoingOrIgnorable(sms))
    }

    @Test
    fun outgoingExchange_uSariftay_isHardBlocked() {
        val sms = "[-[-ADEEGA SARIFKA-]-] Tixraac: 15474478247, Waxaad  \$1 u sariftay " +
            "SLSH11,000SUHAYB CABDIKARIIN AXMED GUDAAL(252634480003)."
        assertTrue(SmsMoneyParser.isOutgoingOrIgnorable(sms))
    }

    // --- End-to-end check-messages decision: received forwards its balance,
    //     outgoing does not. ---

    // --- REAL on-device 898 money-in message (Somali form): the balance sits on
    //     the "Hadhaagaagu waa $X" continuation line. It must parse. ---

    @Test
    fun realDevice_zaadServicesSomaliReceived_parsesBalance() {
        val sms = "[-[--ZAAD SERVICES--]-] Tix: 14491966276, Waxaad \$1 ka heshay  XALWO  " +
            "CALI AXMED CALI (252634187585) Tar: 06/04/26 21:30:22, Hadhaagaagu waa \$1"
        assertFalse(SmsMoneyParser.isOutgoingOrIgnorable(sms))
        assertEquals(1.0, BalanceParser.parse(sms).balanceUsd!!, 0.0001)
    }

    @Test
    fun realDevice_zaadServices197Received_parsesBalance() {
        val sms = "[-ZAAD SERVICES-] Tix: 14595124400, Waxaad \$197 ka heshay  SUHAYB  " +
            "CABDIKARIIM AXMED GUDAAL (252634192816) Tar: 20/04/26 11:16:47, Hadhaagaagu waa \$197"
        assertEquals(197.0, BalanceParser.parse(sms).balanceUsd!!, 0.0001)
    }

    // --- receivedUsd fallback: for a money-in SMS with NO balance clause, we
    //     forward the received amount instead of nothing. ---

    @Test
    fun receivedUsd_fallback_readsReceivedAmount() {
        // No "Hadhaagaagu waa …" balance clause on this one.
        val sms = "[-[--ZAAD SERVICES--]-] Tix: 14491966276, Waxaad \$1 ka heshay  XALWO CALI"
        assertNull(BalanceParser.parse(sms).balanceUsd)
        assertEquals(1.0, BalanceParser.receivedUsd(sms)!!, 0.0001)
    }

    @Test
    fun receivedUsd_ignoresBareNumbersWithoutDollar() {
        // "Waxaad  2 ka heshay" (no $) is too ambiguous — the fallback requires
        // the "$" so a ref id / date is never mistaken for an amount.
        val sms = " <---ZAAD SERVICES--- > Tix: 14492692674, Waxaad  2 ka heshay MAXAMED CUMAR"
        assertNull(BalanceParser.receivedUsd(sms))
    }

    @Test
    fun checkMessagesDecision_receivedForwardsBalance() {
        val sms = "[-ZAAD SERVICES-] Ref:15469142867 confirmed. \$54 Received from SUHAYB  " +
            "CABDIKARIIM AXMED GUDAAL (634192816),Date: 08/08/26 11:36:27, Your New A/C Balance is \$100"
        assertFalse(SmsMoneyParser.isOutgoingOrIgnorable(sms))
        assertEquals(100.0, BalanceParser.parse(sms).balanceUsd!!, 0.0001)
    }
}
