package com.moneyexchange.moneyexchange_app.forwarding

/**
 * Shared, thread-safe state machine coordinating one balance-sweep cycle between
 * two actors:
 *   - the poller ([ForwardingForegroundService]), which dials the USSD codes and
 *     makes the "forward or not" decision, and
 *   - the accessibility service ([UssdAccessibilityService]), which drives the
 *     interactive USSD dialogs (types PINs, picks the menu option, reads the
 *     balance screen).
 *
 * Cycle:
 *   1. poller: [beginBalanceCheck] → step = BALANCE_PIN, then dials `*800#`
 *   2. a11y:   PIN dialog     → types primary PIN → step = MENU
 *   3. a11y:   menu dialog    → types [menuOption] → step = BALANCE_RESULT
 *   4. a11y:   balance screen → reads amount+phone via [onBalanceRead] →
 *              step = BALANCE_CAPTURED
 *   5. poller: sees BALANCE_CAPTURED; if balance ≥ $1 → [beginSend] (step =
 *              SEND_PIN) and dials `*806*dest*amount*secondaryPin#`, else [finish]
 *   6. a11y:   send popup     → types primary PIN → step = SEND_PIN_DONE
 *   7. poller: [finish] → step = IDLE
 *
 * Only one cycle runs at a time.
 */
object UssdSession {

    enum class Step {
        IDLE,
        BALANCE_PIN,      // *800# dialed, waiting for PIN prompt
        MENU,             // PIN accepted, waiting for the menu to pick "show balance"
        BALANCE_RESULT,   // option chosen, waiting for the balance display
        BALANCE_CLOSING,  // balance read; closing the leftover result dialog before we dial send
        BALANCE_CAPTURED, // balance dialog closed; poller decides next
        SEND_PIN,         // *806 dialed, waiting for the confirmation PIN popup
        SEND_PIN_DONE,    // PIN typed on the send popup; forward submitted, awaiting result
        SEND_DONE,        // result dialog appeared and was auto-closed; cycle complete

        // Bank-account forwarding: an interactive menu walk on a fresh *800# dial,
        // one typed dialog per step (see [beginBankSend]).
        BANK_PIN,          // *800# dialed, waiting for PIN prompt → primary PIN
        BANK_MENU,         // main menu → BANK_MENU_OPTION ("5")
        BANK_SUBMENU,      // submenu → BANK_SUBMENU_OPTION ("2")
        BANK_AMOUNT,       // amount prompt → whole-dollar amount
        BANK_COMMENT,      // comment prompt → BANK_COMMENT_TEXT
        BANK_BANK_PIN,     // bank-PIN prompt → the customer's bank PIN
        BANK_CONFIRM,      // confirm menu → BANK_CONFIRM_OPTION ("1" = yes)
        BANK_CONFIRM_DONE, // confirmation submitted, awaiting result dialog
        BANK_DONE,         // result dialog appeared and was auto-closed; cycle complete

        FAILED,           // something timed out / couldn't be driven
    }

    /** Fixed inputs for the bank-forwarding menu walk (see [beginBankSend]). */
    const val BANK_MENU_OPTION = "5"
    const val BANK_SUBMENU_OPTION = "2"
    const val BANK_CONFIRM_OPTION = "1"

    /**
     * Deposit-note text for the "Please comment" prompt. It must be SHORT and
     * space-free: the real Dahabshiil/Zaad comment field rejects a long value
     * (e.g. "This is for saving purpose") with "Invalid input format(length)",
     * which throws the whole menu walk off by one. A 6-char value is known-good
     * (the 6-digit PIN was accepted there), so keep this at/under that.
     */
    const val BANK_COMMENT_TEXT = "Saving"

    /** How long a single interactive dialog stays "ours" before we give up. */
    private const val WINDOW_MS = 45_000L

    @Volatile var step: Step = Step.IDLE
        private set

    @Volatile private var armedUntilMs: Long = 0L

    @Volatile var primaryPin: String? = null
        private set
    @Volatile var secondaryPin: String? = null
        private set
    @Volatile var destination: String? = null
        private set

    /** The menu key that shows the balance (per the flow, "1"). */
    @Volatile var menuOption: String = "1"
        private set

    /** Filled by the accessibility service once the balance screen is read. */
    @Volatile var balanceUsd: Double? = null
        private set
    @Volatile var accountPhone: String? = null
        private set

    /** The customer's bank PIN, typed on the bank-forwarding "enter bank pin" prompt. */
    @Volatile var bankPin: String? = null
        private set

    /** Whole-dollar amount string, typed on the bank-forwarding "enter amount" prompt. */
    @Volatile var forwardAmount: String? = null
        private set

    @Synchronized
    fun beginBalanceCheck(primary: String, secondary: String, dest: String, option: String = "1") {
        primaryPin = primary
        secondaryPin = secondary
        destination = dest
        menuOption = option
        balanceUsd = null
        accountPhone = null
        step = Step.BALANCE_PIN
        arm()
    }

    /** Called by the a11y service after typing the balance-check PIN. */
    @Synchronized
    fun onBalancePinTyped() {
        if (step == Step.BALANCE_PIN) {
            step = Step.MENU
            arm()
        }
    }

    /** Called by the a11y service after selecting the balance menu option. */
    @Synchronized
    fun onMenuOptionTyped() {
        if (step == Step.MENU) {
            step = Step.BALANCE_RESULT
            arm()
        }
    }

    /**
     * Called by the a11y service when the post-PIN screen shows the balance
     * DIRECTLY, with no numbered menu to pick from (varies by account/provider).
     * Advances [Step.MENU] → [Step.BALANCE_RESULT] so [onBalanceRead] — which is
     * guarded on BALANCE_RESULT — actually captures the balance. Without this, a
     * directly-shown balance was parsed but never stored, so the cycle timed out
     * and a ≥ $1 balance silently failed to forward.
     */
    @Synchronized
    fun onMenuBypassedToBalance() {
        if (step == Step.MENU) {
            step = Step.BALANCE_RESULT
            arm()
        }
    }

    /**
     * Called by the a11y service once it has read the balance screen. Moves to
     * [Step.BALANCE_CLOSING] — NOT straight to captured — so the leftover balance
     * dialog is retried closed before the poller dials `*806#`; a lingering
     * balance dialog can otherwise block the fresh send call.
     */
    @Synchronized
    fun onBalanceRead(balance: Double?, phone: String?) {
        if (step == Step.BALANCE_RESULT) {
            balanceUsd = balance
            accountPhone = phone
            step = Step.BALANCE_CLOSING
            arm()
        }
    }

    /** Called by the a11y service once the balance result dialog is closed. */
    @Synchronized
    fun onBalanceDialogClosed() {
        if (step == Step.BALANCE_CLOSING) step = Step.BALANCE_CAPTURED
    }

    /** Poller arms the send phase right before dialing `*806…#`. */
    @Synchronized
    fun beginSend() {
        step = Step.SEND_PIN
        arm()
    }

    /**
     * Starts a cycle that goes STRAIGHT to the send step, skipping the `*800#`
     * balance check — used by the check-messages flow, where the amount to forward
     * was read straight from the 898 exchange SMS. Sets the PINs + destination and
     * jumps to [Step.SEND_PIN] so the accessibility service auto-fills the primary
     * PIN on the `*806#` confirmation popup exactly as it does mid-sweep.
     */
    @Synchronized
    fun beginDirectSend(primary: String, secondary: String, dest: String) {
        primaryPin = primary
        secondaryPin = secondary
        destination = dest
        balanceUsd = null
        accountPhone = null
        step = Step.SEND_PIN
        arm()
    }

    /**
     * Starts a bank-account forward on a fresh `*800#` dial. Unlike the mobile
     * `*806#` one-shot, this is a menu walk the accessibility service drives one
     * dialog at a time: primary PIN → main menu "5" → submenu "2" → [amount] →
     * comment → [bankPin] → confirm "1". [amount] is the whole-dollar string; the
     * account PIN reuses the already-stored [primaryPin].
     */
    @Synchronized
    fun beginBankSend(primary: String, bank: String, amount: String) {
        primaryPin = primary
        bankPin = bank
        forwardAmount = amount
        step = Step.BANK_PIN
        arm()
    }

    /**
     * Advances the bank menu walk from [from] to [to], re-arming the window.
     * Guarded on the current step so a repeated content-changed event for a
     * dialog we already handled can't skip a step.
     */
    @Synchronized
    fun advanceBank(from: Step, to: Step) {
        if (step == from) {
            step = to
            arm()
        }
    }

    /** Called by the a11y service once it has closed the bank "you sent…" dialog. */
    @Synchronized
    fun onBankResultClosed() {
        if (step == Step.BANK_CONFIRM_DONE) step = Step.BANK_DONE
    }

    /** Called by the a11y service after typing the PIN on the send popup. */
    @Synchronized
    fun onSendPinTyped() {
        if (step == Step.SEND_PIN) {
            step = Step.SEND_PIN_DONE
            arm()
        }
    }

    /** Called by the a11y service once it has closed the "you sent…" result dialog. */
    @Synchronized
    fun onSendResultClosed() {
        if (step == Step.SEND_PIN_DONE) {
            step = Step.SEND_DONE
        }
    }

    @Synchronized
    fun fail() {
        step = Step.FAILED
    }

    @Synchronized
    fun finish() {
        step = Step.IDLE
        armedUntilMs = 0L
        primaryPin = null
        secondaryPin = null
        destination = null
        balanceUsd = null
        accountPhone = null
        bankPin = null
        forwardAmount = null
    }

    /** True while a cycle is in flight and the current dialog window is still fresh. */
    fun isActive(): Boolean =
        step != Step.IDLE && step != Step.FAILED && System.currentTimeMillis() < armedUntilMs

    /** True if the current window elapsed without the expected dialog being driven. */
    fun isTimedOut(): Boolean =
        step != Step.IDLE && step != Step.FAILED && System.currentTimeMillis() >= armedUntilMs

    private fun arm() {
        armedUntilMs = System.currentTimeMillis() + WINDOW_MS
    }
}
