package com.moneyexchange.moneyexchange_app.forwarding

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the dial-error recognition that closes a stuck USSD error dialog and
 * flags the session for a re-dial. The on-device regression was the Zaad
 * "Internal service error please try again" screen going unrecognised: it was
 * never dismissed (so it sat stuck) and the balance/forward never completed.
 */
class DialErrorMarkerTest {

    @Test
    fun `recognises the Zaad internal-service-error dialog`() {
        // Exactly the on-device screen text (as collected off the dialog).
        assertTrue(UssdAccessibilityService.matchesDialError("Internal service error please try again"))
        assertTrue(UssdAccessibilityService.matchesDialError("INTERNAL SERVICE ERROR PLEASE TRY AGAIN\nOK"))
    }

    @Test
    fun `still recognises the system MMI rejection`() {
        assertTrue(UssdAccessibilityService.matchesDialError("Connection problem or invalid MMI code."))
    }

    @Test
    fun `recognises other transient gateway errors`() {
        assertTrue(UssdAccessibilityService.matchesDialError("System busy, please try again later"))
        assertTrue(UssdAccessibilityService.matchesDialError("Service temporarily unavailable"))
    }

    @Test
    fun `does not flag a real balance or menu screen`() {
        assertFalse(UssdAccessibilityService.matchesDialError("Your Balance is \$12.50"))
        assertFalse(UssdAccessibilityService.matchesDialError("1 Show balance\n2 Send money"))
        assertFalse(UssdAccessibilityService.matchesDialError("Enter your PIN"))
        assertFalse(UssdAccessibilityService.matchesDialError(""))
    }
}
