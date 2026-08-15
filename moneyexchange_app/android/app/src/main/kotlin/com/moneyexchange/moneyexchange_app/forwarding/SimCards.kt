package com.moneyexchange.moneyexchange_app.forwarding

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionInfo
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
                    "displayName" to (info.displayName?.toString()?.takeIf { it.isNotBlank() }
                        ?: "SIM ${info.simSlotIndex + 1}"),
                    "carrierName" to (info.carrierName?.toString() ?: ""),
                    "number" to numberFor(context, sm, info),
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
     * The SIM's own MSISDN, best-effort. On Android 13+ [SubscriptionManager.getPhoneNumber]
     * pulls it from several sources (SIM, carrier config, IMS) and is far more likely to
     * return a value than the long-deprecated [SubscriptionInfo.getNumber] — but it needs
     * READ_PHONE_NUMBERS, so we only try it when that's granted, then fall back to the legacy
     * field. Returns null when no source has the number (many carriers never provision it).
     */
    private fun numberFor(
        context: Context,
        sm: SubscriptionManager,
        info: SubscriptionInfo,
    ): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            hasPhoneNumbersPermission(context)
        ) {
            try {
                val n = sm.getPhoneNumber(info.subscriptionId)
                if (n.isNotBlank()) return n.trim()
            } catch (e: SecurityException) {
                Log.w(TAG, "No permission to read SIM phone number", e)
            } catch (e: Exception) {
                Log.w(TAG, "getPhoneNumber failed", e)
            }
        }
        @Suppress("DEPRECATION", "MissingPermission")
        return info.number?.trim()?.takeIf { it.isNotBlank() }
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

    private fun hasPhoneNumbersPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_NUMBERS) ==
            PackageManager.PERMISSION_GRANTED
}
