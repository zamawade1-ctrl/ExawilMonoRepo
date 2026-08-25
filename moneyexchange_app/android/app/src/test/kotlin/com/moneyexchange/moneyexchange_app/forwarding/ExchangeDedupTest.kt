package com.moneyexchange.moneyexchange_app.forwarding

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Dedup decision for check-messages 898 forwards ([ForwardingSettings.isDuplicateExchange]).
 * The real device bug these lock in: the user made genuine repeat $X exchanges to the
 * same person seconds/minutes apart (each a NEW Tixraac ref) and the money was dropped as
 * a "leftover". The Tixraac ref is now the SOLE identity when present — distinct refs are
 * distinct exchanges and always forward, even for the identical amount + counterparty
 * moments apart; only a re-delivered SAME ref is a duplicate. The content signature is a
 * fallback used ONLY when no ref could be parsed.
 */
class ExchangeDedupTest {

    private val refWin = 30 * 60_000L // EXCHANGE_REF_DEDUP_WINDOW_MS
    private val sigWin = 90_000L      // EXCHANGE_SIG_DEDUP_WINDOW_MS
    private val sig = "u:1.0|s:11000|p:252634480003"

    /** Real case: genuine repeat, same amount+person, a NEW ref, 2 min later → FORWARD. */
    @Test
    fun genuineRepeat_newRef_afterSigWindow_isNotDuplicate() {
        val now = 1_000_000L
        val kept = listOf(Triple("15603724048", sig, now - 2 * 60_000L)) // 2 min ago
        assertFalse(
            ForwardingSettings.isDuplicateExchange(kept, "15603785238", sig, now, refWin, sigWin),
        )
    }

    /** Three real repeats 19:02/19:04/19:09-style (new refs, >90s apart) all forward. */
    @Test
    fun threeRepeats_differentRefs_minutesApart_allForward() {
        var now = 0L
        val kept = mutableListOf<Triple<String, String, Long>>()
        for ((i, ref) in listOf("A1", "A2", "A3", "A4").withIndex()) {
            now = i * 130_000L // 130s apart, like the device timeline
            assertFalse(
                "repeat #$i should forward",
                ForwardingSettings.isDuplicateExchange(kept, ref, sig, now, refWin, sigWin),
            )
            kept.add(Triple(ref, sig, now))
        }
    }

    /** Byte-identical re-delivery (SAME ref) minutes later → DUPLICATE (skip). */
    @Test
    fun sameRef_reDelivery_withinRefWindow_isDuplicate() {
        val now = 1_000_000L
        val kept = listOf(Triple("15603724048", sig, now - 5 * 60_000L)) // 5 min ago
        assertTrue(
            ForwardingSettings.isDuplicateExchange(kept, "15603724048", sig, now, refWin, sigWin),
        )
    }

    /**
     * Different ref, same amount+person, seconds apart → FORWARD (NOT a duplicate). This is
     * the "second 898 became a leftover" fix: two distinct Zaad transactions (distinct refs)
     * are two real exchanges, so the second one's money must still be forwarded even though
     * the old short signature window used to swallow it.
     */
    @Test
    fun differentRef_sameSignature_secondsApart_isNotDuplicate() {
        val now = 1_000_000L
        val kept = listOf(Triple("15603724048", sig, now - 20_000L)) // 20s ago
        assertFalse(
            ForwardingSettings.isDuplicateExchange(kept, "15603785238", sig, now, refWin, sigWin),
        )
    }

    /** Same ref but beyond the ref window → not a duplicate (a real later repeat). */
    @Test
    fun sameRef_beyondRefWindow_isNotDuplicate() {
        val now = 1_000_000L
        val kept = listOf(Triple("R", sig, now - 31 * 60_000L)) // 31 min ago
        assertFalse(ForwardingSettings.isDuplicateExchange(kept, "R", sig, now, refWin, sigWin))
    }

    /** A different exchange (different signature, new ref) is never a duplicate. */
    @Test
    fun differentExchange_isNotDuplicate() {
        val now = 1_000_000L
        val kept = listOf(Triple("R1", sig, now - 10_000L))
        assertFalse(
            ForwardingSettings.isDuplicateExchange(
                kept, "R2", "u:2.0|s:22000|p:252634080684", now, refWin, sigWin,
            ),
        )
    }

    /** Null/blank ref falls back to signature-only dedup (still guards rapid copies). */
    @Test
    fun nullRef_usesSignatureWindowOnly() {
        val now = 1_000_000L
        val recent = listOf(Triple("", sig, now - 10_000L))
        assertTrue(ForwardingSettings.isDuplicateExchange(recent, null, sig, now, refWin, sigWin))
        val old = listOf(Triple("", sig, now - 100_000L)) // >90s
        assertFalse(ForwardingSettings.isDuplicateExchange(old, null, sig, now, refWin, sigWin))
    }
}
