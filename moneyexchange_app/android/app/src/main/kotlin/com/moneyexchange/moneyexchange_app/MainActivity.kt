package com.moneyexchange.moneyexchange_app

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.moneyexchange.moneyexchange_app.forwarding.ForwardingForegroundService
import com.moneyexchange.moneyexchange_app.forwarding.ForwardingMethod
import com.moneyexchange.moneyexchange_app.forwarding.ForwardingMode
import com.moneyexchange.moneyexchange_app.forwarding.ForwardingSettings
import com.moneyexchange.moneyexchange_app.forwarding.SimCards
import com.moneyexchange.moneyexchange_app.forwarding.UssdAccessibilityService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Flutter forwarding UI to the native on-device balance-sweep
 * forwarder: stores settings (destination, primary + secondary PIN, interval,
 * SIM, mode, enabled), lists SIMs, reports permission + accessibility status,
 * requests runtime permissions, and can trigger a manual sweep. Saving with
 * forwarding enabled starts the service, which then decides for itself (based
 * on [ForwardingMode]) whether that means a periodic poller or an idle,
 * SMS-triggered-only listener — see [ForwardingForegroundService]. PINs only
 * ever cross this channel on their way to the Android Keystore — never to the
 * server.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "xawil/forwarding"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val settings = ForwardingSettings(this)
                when (call.method) {
                    "saveSettings" -> {
                        // Partial update: only fields actually present in the call are
                        // written, so the "forwarding mode" card (mode/interval/enabled)
                        // and the "forwarding profile" card (destination/pins/sim) can
                        // each save independently without clobbering the other's fields.
                        if (call.hasArgument("destination")) {
                            settings.destination = call.argument<String>("destination")
                        }
                        call.argument<String>("pin")?.let { settings.pin = it }
                        call.argument<String>("secondaryPin")?.let { settings.secondaryPin = it }
                        call.argument<String>("bankPin")?.let { settings.bankPin = it }
                        call.argument<Int>("forwardingMethod")?.let {
                            settings.forwardingMethod = ForwardingMethod.fromOrdinal(it)
                        }
                        call.argument<Int>("intervalMinutes")?.let { settings.intervalMinutes = it }
                        call.argument<Int>("simSubscriptionId")?.let { settings.simSubscriptionId = it }
                        call.argument<Int>("mode")?.let { settings.mode = ForwardingMode.fromOrdinal(it) }
                        call.argument<Boolean>("enabled")?.let { settings.enabled = it }

                        // Re-evaluate on every save: forwarding runs only when it's both
                        // switched on AND fully configured. Enabling before the profile
                        // is complete is fine — this flips it on as soon as it's ready.
                        if (settings.enabled && settings.isReady()) {
                            ForwardingForegroundService.start(this)
                        } else {
                            ForwardingForegroundService.stop(this)
                        }
                        result.success(null)
                    }
                    "getStatus" -> result.success(status(settings))
                    "listSims" -> result.success(SimCards.list(this))
                    "requestPermissions" -> {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                Manifest.permission.RECEIVE_SMS,
                                Manifest.permission.CALL_PHONE,
                                Manifest.permission.READ_PHONE_STATE,
                            ),
                            REQ_PERMISSIONS,
                        )
                        result.success(null)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "openOverlaySettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        // Critical for auto-forward to keep its exact 1-minute cadence
                        // through Doze (screen off / phone locked at night). Only opens
                        // the system prompt if we're not already exempt.
                        if (!isIgnoringBatteryOptimizations()) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                        }
                        result.success(null)
                    }
                    "sweepNow" -> {
                        ForwardingForegroundService.sweepNow(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun status(settings: ForwardingSettings): Map<String, Any?> = mapOf(
        "hasSmsPermission" to granted(Manifest.permission.RECEIVE_SMS),
        "hasCallPermission" to granted(Manifest.permission.CALL_PHONE),
        "hasPhoneStatePermission" to granted(Manifest.permission.READ_PHONE_STATE),
        "accessibilityEnabled" to isAccessibilityEnabled(),
        "overlayEnabled" to Settings.canDrawOverlays(this),
        "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(),
        "enabled" to settings.enabled,
        "destination" to settings.destination,
        "hasPin" to !settings.pin.isNullOrBlank(),
        "hasSecondaryPin" to !settings.secondaryPin.isNullOrBlank(),
        "hasBankPin" to !settings.bankPin.isNullOrBlank(),
        // The decrypted PIN values, so the edit form can pre-fill them (masked) on
        // a return visit — just like the backend-stored bank PIN. These cross the
        // in-process method channel to the app's own UI only; they are still never
        // sent to the server (the profile PUT carries no mobile PINs).
        "pin" to settings.pin,
        "secondaryPin" to settings.secondaryPin,
        // The bank PIN, decrypted, so the bank form pre-fills it on a return visit
        // without depending on the backend. Same in-process-only path as the mobile
        // PINs above — never sent to the server.
        "bankPin" to settings.bankPin,
        "forwardingMethod" to settings.forwardingMethod.ordinal,
        "intervalMinutes" to settings.intervalMinutes,
        "simSubscriptionId" to settings.simSubscriptionId,
        "mode" to settings.mode.ordinal,
        "lastAccountPhone" to settings.lastAccountPhone,
    )

    private fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    /** Whether the app is exempt from Doze/battery optimization (needed for exact night ticks). */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(PowerManager::class.java) ?: return false
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(this, UssdAccessibilityService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expected, ignoreCase = true)) return true
        }
        return false
    }

    companion object {
        private const val REQ_PERMISSIONS = 9001
    }
}
