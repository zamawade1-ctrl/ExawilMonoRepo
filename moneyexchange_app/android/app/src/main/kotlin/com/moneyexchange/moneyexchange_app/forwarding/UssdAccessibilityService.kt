package com.moneyexchange.moneyexchange_app.forwarding

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

    /** Throttle for the leftover-dialog janitor (see [dismissLeftoverResultDialog]). */
    private var lastJanitorCloseMs = 0L

    /** Janitor dismiss attempts on the current dialog; reset once it's gone. Gates BACK. */
    private var janitorAttempts = 0

    /**
     * Guards the janitor's leftover-balance read so a completed forward's result
     * dialog is captured once, not on every frame it lingers. Reset (with
     * [janitorAttempts]) whenever the dialog is gone, so the next forward's result
     * dialog is captured afresh.
     */
    private var janitorLeftoverCaptured = false

    /** Guards [closeResultDialog] so the leftover balance is captured once per step. */
    private var leftoverCaptured = false

    /** Posts the proactive pre-dial cleanup onto the a11y main thread. */
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Only ever read/act on the system telephony USSD dialog. If we read whatever
        // window is merely "active", an SMS/notification that arrives mid-sweep steals
        // focus (the notification shade or the Messages app becomes active) and its
        // text gets parsed as the USSD screen — e.g. a Telesom "hadhaagaagu waa 0.00
        // dollar" SMS parsed as a $0 balance, making the sweep skip a real forward even
        // though the true *800# balance was ≥ $1. resolveUssdRoot returns ONLY the
        // telephony dialog (and finds it even under a heads-up notification), or null.
        val root = resolveUssdRoot() ?: return

        // No cycle in flight: sweep away any leftover terminal forwarding result
        // dialog (a "you sent…" / "successfully transferred…" screen) that lingered
        // after a finished cycle, arrived late, or is stacking up across cycles.
        // Left on screen it both looks stuck AND blocks/confuses the next *800# / *806#
        // dial — the reported "stacked success dialog → forwarding failures" bug.
        // Tightly scoped: only a no-input screen whose text we recognise as ours.
        if (!UssdSession.isActive()) {
            dismissLeftoverResultDialog(root)
            return
        }

        // Reset the dialog-close retry counters the moment we enter a new step, so
        // each terminal screen gets a fresh retry budget.
        if (UssdSession.step != closeStepAnchor) {
            closeStepAnchor = UssdSession.step
            closeAttempts = 0
            lastCloseAtMs = 0L
            leftoverCaptured = false
        }

        // The dial was rejected: the system shows "Connection problem or invalid MMI
        // code." No input field, so no step handler can act — dismiss it and flag the
        // session so [UssdDialer] re-dials rather than letting the forward silently
        // fail. Checked before the step handlers because it can appear at ANY dial.
        if (isMmiErrorDialog(collectText(root))) {
            // Tap OK only (no BACK) — the error dialog is a standard AlertDialog whose
            // OK reliably dismisses it, and BACK here could close our app behind it.
            dismissDialog(root)
            UssdSession.signalMmiError()
            Log.w(TAG, "MMI-error dialog dismissed; flagged for re-dial (step=${UssdSession.step}).")
            return
        }

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
                    closeResultDialog(root, captureLeftover = true) { UssdSession.onSendResultClosed() }

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
                    closeResultDialog(root, captureLeftover = true) { UssdSession.onBankResultClosed() }

                else -> {}
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error driving USSD dialog at step ${UssdSession.step}", e)
        }
    }

    /**
     * The root node of the system telephony USSD dialog, or null if it isn't on
     * screen. This is the single guard that keeps us reading the *800# dialog and
     * nothing else.
     *
     * Why not just [rootInActiveWindow]: when an SMS or notification lands during a
     * sweep, the notification shade (`com.android.systemui`) or the Messages app
     * becomes the active window, so `rootInActiveWindow` returns THAT — and its text
     * (an SMS body, a "hadhaagaagu waa 0.00" promo) gets parsed as the USSD screen,
     * misreading the balance and skipping a real forward. So we locate the telephony
     * window explicitly from the interactive windows list (which still contains the
     * dialog even when a heads-up notification is drawn over it, so we can keep
     * driving it), and only fall back to the active window when it too is telephony.
     * Never returns our own app window, so the balance parser can't read our card.
     */
    private fun resolveUssdRoot(): AccessibilityNodeInfo? {
        try {
            for (w in windows) {
                val r = w.root ?: continue
                if (r.packageName?.toString() in USSD_DIALOG_PACKAGES) return r
            }
        } catch (e: Exception) {
            Log.w(TAG, "Interactive-windows lookup failed; falling back to active window.", e)
        }
        val active = rootInActiveWindow ?: return null
        return if (active.packageName?.toString() in USSD_DIALOG_PACKAGES) active else null
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
     * the balance option; otherwise it MAY be the balance shown directly (some
     * accounts skip the menu). We only treat a no-input screen as a direct
     * balance once an amount actually parses off it — a menu that hasn't finished
     * rendering its input field also momentarily has no editable, and mistaking
     * that for "balance shown directly" would skip typing the menu option and
     * hang the cycle. When a balance IS present, advance MENU → BALANCE_RESULT
     * (so the capture, guarded on that step, takes effect) and read it; otherwise
     * wait for the next frame (the input field, or the balance, to render).
     */
    private fun handleMenuOrBalance(root: AccessibilityNodeInfo) {
        val input = findEditable(root)
        if (input != null && input.text.isNullOrEmpty()) {
            typeAndSend(root, UssdSession.menuOption) { UssdSession.onMenuOptionTyped() }
            return
        }
        if (input != null) return // input present but already filled: wait it out
        if (BalanceParser.parse(collectText(root)).balanceUsd == null) return
        // No input AND a balance is parseable → this account skipped the menu.
        UssdSession.onMenuBypassedToBalance()
        readBalance(root)
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
        // True only on the frame that actually captures (onBalanceRead advances the
        // step), so the leftover persist/emit below runs exactly once per read.
        val wasResult = UssdSession.step == UssdSession.Step.BALANCE_RESULT
        val balance = result.balanceUsd
        UssdSession.onBalanceRead(balance, result.phoneNumber)
        result.phoneNumber?.let { ForwardingSettings(this).lastAccountPhone = it }
        // The *800# balance IS the account's current (leftover) balance. Persist +
        // push it live so a Run sweep updates the leftover readout the same way a
        // completed forward does — including when the balance is below the forward
        // threshold and no send (hence no result dialog) follows. If the sweep does
        // go on to forward, the post-forward result dialog re-captures the true
        // remaining balance afterwards (see closeResultDialog).
        if (wasResult && balance != null) {
            ForwardingSettings(this).apply {
                lastLeftoverBalance = balance
                lastLeftoverAtMs = System.currentTimeMillis()
            }
            BalanceEvents.emit(balance)
        }
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
     *  - It dismisses only while a dismiss button (OK/close) is actually present,
     *    proving this is a finished result screen — never a transient "USSD code
     *    running…" frame — so an in-flight send can't be cancelled.
     *  - It taps the OK button first and only falls back to BACK on a retry, once an
     *    OK tap has provably left the dialog up ([dismissDialog]). A speculative BACK
     *    alongside a successful OK tap would fall through to the app behind the dialog
     *    and could close our own app — so BACK is never pressed on the first attempt.
     */
    private fun closeResultDialog(
        root: AccessibilityNodeInfo,
        captureLeftover: Boolean = false,
        onClosed: () -> Unit,
    ) {
        // Interactive screen (PIN / menu / confirmation): never touch it.
        if (findEditable(root) != null) return

        val hasDismiss = findLabeled(root, DISMISS_LABELS) != null

        // Terminal result screen for a completed forward: read the LEFTOVER balance
        // off "…Your Balance is $X." before we dismiss it, for the sweep card's
        // readout. Once per step; never gates the close.
        if (hasDismiss && captureLeftover && !leftoverCaptured) {
            BalanceParser.lastBalanceUsd(collectText(root))?.let { leftover ->
                leftoverCaptured = true
                ForwardingSettings(this).apply {
                    lastLeftoverBalance = leftover
                    lastLeftoverAtMs = System.currentTimeMillis()
                }
                // Push it live to the UI so the sweep card updates without a refresh.
                BalanceEvents.emit(leftover)
                Log.i(TAG, "Captured leftover balance \$$leftover from the result dialog.")
            }
        }

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

        // Terminal result screen is still showing. Tap its OK, throttled so we don't
        // spam faster than the system can animate the dialog away, and keep re-tapping
        // OK on later frames until the dismiss button disappears above. Never BACK on
        // top of a tap (see [dismissDialog]) so the app can't be closed.
        val now = SystemClock.elapsedRealtime()
        if (now - lastCloseAtMs < CLOSE_RETRY_GAP_MS) return
        dismissDialog(root)
        lastCloseAtMs = now
        closeAttempts++
        Log.i(TAG, "Dismissed the result dialog (attempt $closeAttempts).")

        // Backstop: if repeated presses never clear it, stop trying and let the
        // poller wrap up rather than looping forever on a stuck screen.
        if (closeAttempts >= MAX_CLOSE_ATTEMPTS) {
            Log.w(TAG, "Result dialog still up after $MAX_CLOSE_ATTEMPTS attempts; giving up the close.")
            onClosed()
        }
    }

    /**
     * Janitor for when NO cycle is active: dismisses a leftover terminal
     * forwarding-result dialog that lingered after a finished cycle, arrived late
     * (the USSD round-trip finished after we'd already stood the cycle down), or is
     * stacking up because an earlier close was ignored by the ROM. This is the fix
     * for the "successful-forward dialog stays stacked and causes forwarding
     * failures" bug: a lingering system dialog blocks/garbles the next *800# / *806#
     * dial, so we proactively clear it whenever it's on screen and unowned.
     *
     * Safety — this runs outside our own state machine, so it is deliberately narrow:
     *  - NEVER acts on a screen with an input field (an editable = a pending
     *    interactive PIN/transfer/menu — could be the user's own USSD session).
     *  - Only ever a screen whose text we recognise as a Zaad/bank money RESULT
     *    ([isForwardingResultDialog]) AND that carries a dismiss (OK) button, so an
     *    unrelated app dialog is never touched.
     */
    private fun dismissLeftoverResultDialog(root: AccessibilityNodeInfo) {
        // Not one of our dialogs (or it's gone): reset the retry budget so the next
        // real dialog starts fresh with an OK-only tap (no speculative BACK).
        if (findEditable(root) != null) { janitorAttempts = 0; janitorLeftoverCaptured = false; return }
        if (findLabeled(root, DISMISS_LABELS) == null) { janitorAttempts = 0; janitorLeftoverCaptured = false; return }
        val text = collectText(root)
        // Also clear a lingering "Connection problem or invalid MMI code" error dialog:
        // like a result dialog, a stuck error dialog blocks the next dial.
        if (!isForwardingResultDialog(text) && !isMmiErrorDialog(text)) {
            janitorAttempts = 0
            janitorLeftoverCaptured = false
            return
        }

        // A completed forward's result dialog ("…successfully transferred… Your
        // Balance is $X.") is now handled here rather than inside the (already
        // finished) sweep cycle — the forward no longer blocks on this close. So
        // read the leftover balance off it before dismissing, once per dialog, and
        // push it live to the sweep card exactly as the in-cycle close used to.
        if (!janitorLeftoverCaptured && isForwardingResultDialog(text)) {
            BalanceParser.lastBalanceUsd(text)?.let { leftover ->
                janitorLeftoverCaptured = true
                ForwardingSettings(this).apply {
                    lastLeftoverBalance = leftover
                    lastLeftoverAtMs = System.currentTimeMillis()
                }
                BalanceEvents.emit(leftover)
                Log.i(TAG, "Janitor captured leftover balance \$$leftover from a result dialog.")
            }
        }

        val now = SystemClock.elapsedRealtime()
        if (now - lastJanitorCloseMs < CLOSE_RETRY_GAP_MS) return
        lastJanitorCloseMs = now
        // Tap OK; never BACK on top of a tap (see [dismissDialog]) so clearing the
        // leftover dialog can't fall through and close the app the user is viewing.
        dismissDialog(root)
        janitorAttempts++
        Log.i(TAG, "Janitor dismissed a leftover forwarding/error dialog.")
    }

    /** True if [text] reads like a completed Zaad/bank money result (not an app or user screen). */
    private fun isForwardingResultDialog(text: String): Boolean {
        if (text.isBlank()) return false
        val t = text.lowercase()
        return RESULT_MARKERS.any { t.contains(it) }
    }

    /** True if [text] is the system "Connection problem or invalid MMI code." dialog. */
    private fun isMmiErrorDialog(text: String): Boolean {
        if (text.isBlank()) return false
        val t = text.lowercase()
        return ERROR_MARKERS.any { t.contains(it) }
    }

    /**
     * Dismisses a terminal result dialog by tapping its OK/close button (climbing to
     * a clickable ancestor when the label node itself isn't clickable). A button tap
     * only ever affects the dialog, so it is always safe.
     *
     * We DELIBERATELY never issue the global BACK action alongside an OK tap. BACK is
     * dangerous: the instant the OK tap removes the dialog, a BACK falls through to
     * whatever is behind it — our own app — and closes/backgrounds it (the "app
     * closes when a forward finishes" bug; the app must stay visible until the user
     * themselves leaves it). So BACK is used ONLY as a last resort when there is no
     * clickable OK to tap at all — and the caller only invokes this while a dismiss
     * button is present, so at that point the dialog is provably still up and BACK
     * targets the dialog, not our app. When an OK tap doesn't clear it, we simply
     * re-tap OK on the next frame (the caller's throttled retry loop) rather than
     * ever pressing BACK on top of a tap.
     */
    private fun dismissDialog(root: AccessibilityNodeInfo) {
        val okButton = clickableSelfOrAncestor(findLabeled(root, DISMISS_LABELS))
        if (okButton != null) {
            okButton.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        } else {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
    }

    /** Walks up from [node] to the nearest clickable node (itself included), or null. */
    private fun clickableSelfOrAncestor(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        var n = node
        var hops = 0
        while (n != null && hops < 6) {
            if (n.isClickable) return n
            n = n.parent
            hops++
        }
        return null
    }

    /**
     * Finds a node whose text/description matches one of [labels] — unlike
     * [findButton] it does NOT require the node itself to be clickable, so it also
     * catches an OK label whose click target is a parent (climbed via
     * [clickableSelfOrAncestor]).
     */
    private fun findLabeled(node: AccessibilityNodeInfo?, labels: List<String>): AccessibilityNodeInfo? {
        if (node == null) return null
        val label = (node.text ?: node.contentDescription)?.toString()?.lowercase()?.trim()
        if (label != null && labels.any { label == it || label.contains(it) }) return node
        for (i in 0 until node.childCount) {
            findLabeled(node.getChild(i), labels)?.let { return it }
        }
        return null
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

        /**
         * Packages that host the system USSD/MMI dialog. We read/act on a window ONLY
         * when it belongs to one of these, so an SMS/notification that grabs focus
         * mid-sweep (the notification shade `com.android.systemui`, or a Messages app)
         * can never be parsed as the USSD screen. Confirmed on the target device
         * (Samsung a06): the *800# dialog is hosted by `com.android.phone`. The rest
         * cover the common hosts on other OEMs so the sweep doesn't silently stall
         * where the dialog lives elsewhere.
         */
        private val USSD_DIALOG_PACKAGES = setOf(
            "com.android.phone",
            "com.android.server.telecom",
            "com.samsung.android.app.telephonyui",
            "com.sec.phone",
            "com.samsung.telephony",
            "com.mediatek.telephony",
            "com.android.incallui",
        )
        // Positive-button labels: EN "send"/"ok" and Somali "dir"/"haa"/"diri".
        private val SEND_LABELS = listOf("send", "ok", "dir", "diri", "haa", "sii dir")
        // Dismiss/close labels for the terminal balance screen.
        private val DISMISS_LABELS = listOf("ok", "close", "cancel", "dismiss", "xir", "daboo", "ka noqo")

        /**
         * Text markers that identify a *finished* Zaad/eDahab/bank money result
         * dialog, so the janitor ([dismissLeftoverResultDialog]) only ever clears a
         * screen that is genuinely one of ours and never an unrelated app/user dialog.
         * Covers both the mobile "you sent…" and bank "successfully transferred…"
         * result screens, EN + Somali, plus the leftover balance screen.
         */
        private val RESULT_MARKERS = listOf(
            "successfully transferred", "transferred to your bank", "you have successfully",
            "adeega sarifka", "transfer-id", "transferid", "you sent", "u dirtay",
            "waxaad", "sariftay", "u sariftay", "your balance is", "balance is",
        )

        /**
         * Text markers for the system telephony error dialog shown when a USSD dial
         * is rejected — "Connection problem or invalid MMI code." Recognised so it's
         * dismissed (never left blocking the next dial) and the dial is retried.
         */
        private val ERROR_MARKERS = listOf(
            "invalid mmi", "mmi code", "connection problem",
        )

        /** Min gap between dismiss attempts in [closeResultDialog], to let the dialog animate away. */
        private const val CLOSE_RETRY_GAP_MS = 400L

        /** Give up closing after this many dismiss attempts (poller timeout is the final backstop). */
        private const val MAX_CLOSE_ATTEMPTS = 12

        /**
         * The connected accessibility service instance, so the poller can ask it to
         * clear a leftover result dialog right before dialing. Null when the user
         * hasn't enabled the service (or it's been torn down).
         */
        @Volatile
        private var instance: UssdAccessibilityService? = null

        /**
         * Best-effort: if a leftover terminal forwarding result dialog is still on
         * screen, dismiss it NOW so it can't block the USSD dial that's about to
         * happen. Called by the dialer at the START of each phase — before that
         * phase's own dialog exists — so the only thing it can find is a stale result
         * screen from a prior phase/cycle. Safe to call from any thread (e.g. the
         * poller's background sweep thread): it hops to the a11y main thread and
         * reuses [dismissLeftoverResultDialog], whose guards (no input field +
         * recognised result text + a dismiss button) mean it can never touch an
         * interactive PIN/menu/confirm screen even while a cycle is armed. No-op if
         * the service isn't enabled.
         */
        fun clearLeftoverResultDialog() {
            val service = instance ?: return
            service.mainHandler.post {
                // Same telephony-only guard as the event path: never touch a non-USSD
                // window (the notification shade / Messages app that may be foreground).
                val root = service.resolveUssdRoot() ?: return@post
                service.dismissLeftoverResultDialog(root)
            }
        }
    }
}
