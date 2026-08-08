package com.moneyexchange.moneyexchange_app.forwarding

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Places the two USSD calls of one balance-sweep cycle:
 *
 *   - [dialBalanceCheck] dials `*800#` — the interactive balance menu. The
 *     [UssdAccessibilityService] then types the primary PIN, picks menu option 1,
 *     and reads the balance + account number off the result screen.
 *   - [dialSend] dials `*806*<destination>*<amount>*<secondaryPin>#` — the send
 *     command, whose confirmation popup the accessibility service completes by
 *     typing the primary PIN.
 *
 * We dial via ACTION_CALL (not TelephonyManager.sendUssdRequest) because both
 * flows are interactive multi-step dialogs that sendUssdRequest can't answer.
 * Session state (which step we're on, which PINs to type) lives in [UssdSession];
 * the dialer itself only places calls and never holds a PIN.
 *
 * On dual-SIM phones the call is routed onto the SIM chosen in the app via the
 * resolved [android.telecom.PhoneAccountHandle] (see [SimCards]); -1 uses the
 * system default.
 */
object UssdDialer {

    private const val TAG = "Xawil/UssdDialer"

    /** Balance-check short code: `*800#`. */
    private const val BALANCE_PREFIX = "800"

    /** Send-money short code: `*806*dest*amount*secondaryPin#`. */
    private const val SEND_PREFIX = "806"

    fun buildBalanceCheck(): String = "*$BALANCE_PREFIX#"

    fun buildSend(destination: String, amount: String, secondaryPin: String): String =
        "*$SEND_PREFIX*$destination*$amount*$secondaryPin#"

    /** Dials `*800#` to open the balance menu. */
    fun dialBalanceCheck(context: Context, subscriptionId: Int): Boolean =
        dial(context, buildBalanceCheck(), subscriptionId)

    /** Dials `*806*destination*amount*secondaryPin#` to send the swept balance. */
    fun dialSend(
        context: Context,
        destination: String,
        amount: String,
        secondaryPin: String,
        subscriptionId: Int,
    ): Boolean = dial(context, buildSend(destination, amount, secondaryPin), subscriptionId)

    /**
     * Places the USSD call. Must be called from a context that currently has
     * background-activity-start privilege (the foreground service) or from the
     * foreground.
     */
    private fun dial(context: Context, ussd: String, subscriptionId: Int): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "CALL_PHONE not granted; cannot dial USSD.")
            return false
        }

        // '#' must be percent-encoded (%23) or the dialer truncates the code.
        val uri = Uri.parse("tel:" + Uri.encode(ussd))
        val intent = Intent(Intent.ACTION_CALL, uri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            SimCards.phoneAccountHandle(context, subscriptionId)?.let { handle ->
                putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
            }
        }

        return try {
            context.startActivity(intent)
            Log.i(TAG, "Dialed USSD ${redact(ussd)} on sub=$subscriptionId")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to dial USSD", e)
            false
        }
    }

    /** The send command embeds the secondary PIN inline; keep it out of logs. */
    private fun redact(ussd: String): String =
        if (ussd.startsWith("*$SEND_PREFIX")) "*$SEND_PREFIX*…#" else ussd
}
