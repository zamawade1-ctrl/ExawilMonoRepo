package com.moneyexchange.moneyexchange_app.forwarding

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Dual-SIM support for USSD dialing. Lists the active SIMs so the user can pick
 * one in the app, and resolves the chosen subscription id to the
 * [PhoneAccountHandle] the dialer needs to place the call on that specific SIM.
 *
 * Requires READ_PHONE_STATE (and, for the number, READ_PHONE_NUMBERS). If the
 * permission is missing we degrade gracefully to an empty list / system default.
 */
object SimCards {

    private const val TAG = "Xawil/SimCards"

    /** One row per active SIM, as a channel-friendly map. */
    fun list(context: Context): List<Map<String, Any?>> {
        if (!hasPhoneStatePermission(context)) return emptyList()

        val sm = ContextCompat.getSystemService(context, SubscriptionManager::class.java)
            ?: return emptyList()

        return try {
            @Suppress("MissingPermission")
            val infos = sm.activeSubscriptionInfoList ?: emptyList()
            infos.map { info ->
                mapOf(
                    "subscriptionId" to info.subscriptionId,
                    "slotIndex" to info.simSlotIndex,
                    "displayName" to (info.displayName?.toString() ?: "SIM ${info.simSlotIndex + 1}"),
                    "carrierName" to (info.carrierName?.toString() ?: ""),
                    "number" to (info.number?.takeIf { it.isNotBlank() }),
                )
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "No permission to read SIM list", e)
            emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read SIM list", e)
            emptyList()
        }
    }

    /**
     * Resolves [subscriptionId] to the matching call-capable [PhoneAccountHandle],
     * so the dialer can route the USSD onto that SIM. Returns null for -1 (use the
     * system default) or when no match is found.
     */
    fun phoneAccountHandle(context: Context, subscriptionId: Int): PhoneAccountHandle? {
        if (subscriptionId < 0) return null
        if (!hasPhoneStatePermission(context)) return null

        val telecom = ContextCompat.getSystemService(context, TelecomManager::class.java)
            ?: return null

        return try {
            @Suppress("MissingPermission")
            val handles = telecom.callCapablePhoneAccounts ?: return null
            // The PhoneAccountHandle id is the subscription id string on most devices.
            handles.firstOrNull { it.id == subscriptionId.toString() }
                ?: handles.getOrNull(slotForSubscription(context, subscriptionId))
        } catch (e: SecurityException) {
            Log.w(TAG, "No permission to read phone accounts", e)
            null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resolve phone account handle", e)
            null
        }
    }

    private fun slotForSubscription(context: Context, subscriptionId: Int): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            SubscriptionManager.getSlotIndex(subscriptionId).coerceAtLeast(0)
        } else {
            0
        }
    }

    private fun hasPhoneStatePermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED
}
