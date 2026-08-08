package com.moneyexchange.moneyexchange_app.forwarding

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Drives the interactive USSD dialogs of one balance-sweep cycle so the whole
 * thing runs hands-free. It acts purely off the shared [UssdSession] step, and
 * only while a cycle is active, so it never touches a USSD session the user
 * opened themselves nor any other dialog:
 *
 *   - [UssdSession.Step.BALANCE_PIN] : type the primary PIN, tap Send.
 *   - [UssdSession.Step.MENU]        : type the balance menu option ("1"), tap Send.
 *   - [UssdSession.Step.BALANCE_RESULT] : read the balance + account number off the
 *     result screen (via [BalanceParser]) and hand them back to the session.
 *   - [UssdSession.Step.SEND_PIN]    : type the primary PIN on the send-confirmation
 *     popup, tap Send.
 *
 * Accessibility events are delivered one-at-a-time on the main thread, and each
 * step transitions the session as soon as it acts, so a step never fires twice.
 *
 * NOTE: exact button labels / dialog layouts vary by device, ROM, and language,
 * so the matchers are broad and may need a small tweak once tested against the
 * real Zaad *800# / *806# prompts on the user's phone — the raw screen text is
 * logged to help with that.
 */
class UssdAccessibilityService : AccessibilityService() {

    /** De-dupes the verbose screen log so we don't spam identical frames. */
    private var lastLoggedScreen: String? = null

    /** Retry bookkeeping for [closeResultDialog], reset whenever the step changes. */
    private var closeStepAnchor: UssdSession.Step? = null
    private var closeAttempts = 0
    private var lastCloseAtMs = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!UssdSession.isActive()) return
        val root = rootInActiveWindow ?: return

        // Reset the dialog-close retry counters the moment we enter a new step, so
        // each terminal screen gets a fresh retry budget.
        if (UssdSession.step != closeStepAnchor) {
            closeStepAnchor = UssdSession.step
            closeAttempts = 0
            lastCloseAtMs = 0L
        }

        // Only ever read/act on the system USSD dialog — never our own app UI.
        // Our card text contains "$1 or more", which the balance parser would
        // otherwise misread as a $1 balance and forward against.
        if (root.packageName == packageName) return

        logScreen(root)

        try {
            when (UssdSession.step) {
                UssdSession.Step.BALANCE_PIN ->
                    typeAndSend(root, UssdSession.primaryPin) { UssdSession.onBalancePinTyped() }

                // After the PIN, the account may show a numbered menu (pick the
                // balance option) OR jump straight to the balance screen — handle
                // both, since it varies by account/provider.
                UssdSession.Step.MENU -> handleMenuOrBalance(root)

                UssdSession.Step.BALANCE_RESULT -> readBalance(root)

                // Balance captured — close the leftover balance/menu dialog before
                // the poller dials *806#. Retried across frames until it's gone.
                UssdSession.Step.BALANCE_CLOSING ->
                    closeResultDialog(root) { UssdSession.onBalanceDialogClosed() }

                UssdSession.Step.SEND_PIN ->
                    typeAndSend(root, UssdSession.primaryPin) { UssdSession.onSendPinTyped() }

                // Send submitted — wait for and close the "you sent…" result dialog.
                // closeResultDialog only touches a terminal (no-input) screen, so it
                // can never cancel the still-open confirmation, and it keeps retrying
                // BACK across frames until the dialog is actually gone before marking
                // the cycle complete so the poller can wrap up.
                UssdSession.Step.SEND_PIN_DONE ->
                    closeResultDialog(root) { UssdSession.onSendResultClosed() }

                // Bank-account forwarding: one typed dialog per step. Each types its
                // value, taps Send, and advances the session; typeAndSend's empty-input
                // guard stops a lingering event for the just-filled dialog from
                // mis-typing the next step's value into it.
                UssdSession.Step.BANK_PIN ->
                    typeAndSend(root, UssdSession.primaryPin) {
                        UssdSession.advanceBank(UssdSession.Step.BANK_PIN, UssdSession.Step.BANK_MENU)
                    }
                UssdSession.Step.BANK_MENU ->
                    typeAndSend(root, UssdSession.BANK_MENU_OPTION) {
                        UssdSession.advanceBank(UssdSession.Step.BANK_MENU, UssdSession.Step.BANK_SUBMENU)
                    }
                UssdSession.Step.BANK_SUBMENU ->
                    typeAndSend(root, UssdSession.BANK_SUBMENU_OPTION) {
                        UssdSession.advanceBank(UssdSession.Step.BANK_SUBMENU, UssdSession.Step.BANK_AMOUNT)
                    }
                UssdSession.Step.BANK_AMOUNT ->
                    typeAndSend(root, UssdSession.forwardAmount) {
                        UssdSession.advanceBank(UssdSession.Step.BANK_AMOUNT, UssdSession.Step.BANK_COMMENT)
                    }
                UssdSession.Step.BANK_COMMENT ->
                    typeAndSend(root, UssdSession.BANK_COMMENT_TEXT) {
                        UssdSession.advanceBank(UssdSession.Step.BANK_COMMENT, UssdSession.Step.BANK_BANK_PIN)
                    }
                UssdSession.Step.BANK_BANK_PIN ->
                    typeAndSend(root, UssdSession.bankPin) {
                        UssdSession.advanceBank(UssdSession.Step.BANK_BANK_PIN, UssdSession.Step.BANK_CONFIRM)
                    }
                UssdSession.Step.BANK_CONFIRM ->
                    typeAndSend(root, UssdSession.BANK_CONFIRM_OPTION) {
                        UssdSession.advanceBank(UssdSession.Step.BANK_CONFIRM, UssdSession.Step.BANK_CONFIRM_DONE)
                    }
                UssdSession.Step.BANK_CONFIRM_DONE ->
                    closeResultDialog(root) { UssdSession.onBankResultClosed() }

                else -> {}
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error driving USSD dialog at step ${UssdSession.step}", e)
        }
    }

    /** Logs the raw text of each distinct USSD screen, for matcher tuning. */
    private fun logScreen(root: AccessibilityNodeInfo) {
        val text = collectText(root)
        if (text.isNotBlank() && text != lastLoggedScreen) {
            lastLoggedScreen = text
            Log.i(TAG, "USSD screen [step=${UssdSession.step}]: ${text.replace('\n', '|')}")
        }
    }

    /**
     * Post-PIN screen: if it has an input field it's the balance menu, so type
     * the balance option; otherwise it's the balance shown directly, so read it.
     */
    private fun handleMenuOrBalance(root: AccessibilityNodeInfo) {
        val input = findEditable(root)
        if (input != null && input.text.isNullOrEmpty()) {
            typeAndSend(root, UssdSession.menuOption) { UssdSession.onMenuOptionTyped() }
        } else {
            readBalance(root)
        }
    }

    override fun onInterrupt() {}

    /**
     * Types [value] into the dialog's input and taps the positive button, then
     * runs [onDone]. Only acts when the input is still empty, so repeated
     * content-changed events on the same dialog don't double-type.
     */
    private fun typeAndSend(root: AccessibilityNodeInfo, value: String?, onDone: () -> Unit) {
        if (value.isNullOrEmpty()) return
        val input = findEditable(root) ?: return
        if (!input.text.isNullOrEmpty()) return
        val sendButton = findButton(root, SEND_LABELS) ?: return

        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value)
        }
        input.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        sendButton.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        onDone()
        Log.i(TAG, "Filled a USSD field and tapped send (step was ${UssdSession.step}).")
    }

    /**
     * Reads the balance-result screen, extracts the USD balance + account number,
     * records the account number for reference, and dismisses the dialog.
     */
    private fun readBalance(root: AccessibilityNodeInfo) {
        val text = collectText(root)
        if (text.isBlank()) return

        val result = BalanceParser.parse(text)
        // Ignore early, half-rendered screens: wait until an amount is actually
        // present before capturing, so we never mistake a not-yet-loaded screen
        // for a zero balance. If it never parses, the poller times out and skips.
        if (result.balanceUsd == null) return

        Log.i(TAG, "Balance screen parsed: ${result.reason}")
        UssdSession.onBalanceRead(result.balanceUsd, result.phoneNumber)
        result.phoneNumber?.let { ForwardingSettings(this).lastAccountPhone = it }
        // The session is now BALANCE_CLOSING; the leftover balance/menu dialog is
        // closed (with retries) by the BALANCE_CLOSING handler, before the poller
        // dials *806#, so a lingering dialog can't block the fresh send call.
    }

    /**
     * Closes a *terminal* USSD result dialog (the balance screen, or the "you
     * sent…" screen after a send) and calls [onClosed] once it's actually gone.
     *
     * Unlike a single BACK press, this RETRIES across accessibility frames: a lone
     * press can race the dialog's render/animation or hit a frame whose OK button
     * label we don't recognise, leaving the dialog stuck on screen with no second
     * attempt — the "dialog sometimes doesn't close" bug. Here we keep pressing on
     * each frame that still shows the terminal dialog, and only report closed once
     * a later frame no longer shows it.
     *
     * Safety rules, because this runs on money screens:
     *  - It only ever acts when the screen has NO input field. An interactive
     *    screen (PIN prompt, menu, send confirmation) is left completely untouched,
     *    so it can never tap "Cancel"/BACK on a pending transfer.
     *  - It presses BACK only while a dismiss button (OK/close) is actually
     *    present, proving this is a finished result screen — never a transient
     *    "USSD code running…" frame — so an in-flight send can't be cancelled.
     *  - BACK is used rather than ACTION_CLICK on the OK button because Samsung's
     *    system USSD dialog ignores an accessibility click on it (reports success
     *    yet the dialog stays), whereas BACK reliably dismisses the system dialog.
     */
    private fun closeResultDialog(root: AccessibilityNodeInfo, onClosed: () -> Unit) {
        // Interactive screen (PIN / menu / confirmation): never touch it.
        if (findEditable(root) != null) return

        val hasDismiss = findButton(root, DISMISS_LABELS) != null
        if (!hasDismiss) {
            // No dismiss button on a non-input screen. If we've already pressed BACK
            // at least once, the terminal dialog is gone — the cycle is done. If we
            // haven't pressed yet, this is a transient "USSD running…" frame, so wait.
            if (closeAttempts > 0) {
                Log.i(TAG, "Result dialog is gone after $closeAttempts close attempt(s).")
                onClosed()
            }
            return
        }

        // Terminal result screen is still showing. Press BACK, throttled so we don't
        // spam it faster than the system can animate the dialog away, and keep
        // retrying on later frames until the dismiss button disappears above.
        val now = SystemClock.elapsedRealtime()
        if (now - lastCloseAtMs < CLOSE_RETRY_GAP_MS) return
        performGlobalAction(GLOBAL_ACTION_BACK)
        lastCloseAtMs = now
        closeAttempts++
        Log.i(TAG, "Pressed BACK to close the result dialog (attempt $closeAttempts).")

        // Backstop: if repeated presses never clear it, stop trying and let the
        // poller wrap up rather than looping forever on a stuck screen.
        if (closeAttempts >= MAX_CLOSE_ATTEMPTS) {
            Log.w(TAG, "Result dialog still up after $MAX_CLOSE_ATTEMPTS attempts; giving up the close.")
            onClosed()
        }
    }

    private fun findEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable) return node
        for (i in 0 until node.childCount) {
            findEditable(node.getChild(i))?.let { return it }
        }
        return null
    }

    private fun findButton(node: AccessibilityNodeInfo?, labels: List<String>): AccessibilityNodeInfo? {
        if (node == null) return null
        val label = (node.text ?: node.contentDescription)?.toString()?.lowercase()?.trim()
        if (node.isClickable && label != null && labels.any { label == it || label.contains(it) }) {
            return node
        }
        for (i in 0 until node.childCount) {
            findButton(node.getChild(i), labels)?.let { return it }
        }
        return null
    }

    /** Concatenates all visible text under [node], newline-separated, for parsing. */
    private fun collectText(node: AccessibilityNodeInfo?, sb: StringBuilder = StringBuilder()): String {
        if (node == null) return sb.toString()
        (node.text ?: node.contentDescription)?.toString()?.takeIf { it.isNotBlank() }?.let {
            if (sb.isNotEmpty()) sb.append('\n')
            sb.append(it)
        }
        for (i in 0 until node.childCount) collectText(node.getChild(i), sb)
        return sb.toString()
    }

    companion object {
        private const val TAG = "Xawil/UssdA11y"
        // Positive-button labels: EN "send"/"ok" and Somali "dir"/"haa"/"diri".
        private val SEND_LABELS = listOf("send", "ok", "dir", "diri", "haa", "sii dir")
        // Dismiss/close labels for the terminal balance screen.
        private val DISMISS_LABELS = listOf("ok", "close", "cancel", "dismiss", "xir", "daboo", "ka noqo")

        /** Min gap between BACK presses in [closeResultDialog], to let the dialog animate away. */
        private const val CLOSE_RETRY_GAP_MS = 700L

        /** Give up closing after this many BACK presses (poller timeout is the final backstop). */
        private const val MAX_CLOSE_ATTEMPTS = 12
    }
}
