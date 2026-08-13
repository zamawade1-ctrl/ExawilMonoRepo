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
import com.moneyexchange.moneyexchange_app.forwarding.BalanceEvents
import com.moneyexchange.moneyexchange_app.forwarding.ForwardingForegroundService
import com.moneyexchange.moneyexchange_app.forwarding.ForwardingMethod
import com.moneyexchange.moneyexchange_app.forwarding.ForwardingMode
import com.moneyexchange.moneyexchange_app.forwarding.ForwardingSettings
import com.moneyexchange.moneyexchange_app.forwarding.SessionStore
import com.moneyexchange.moneyexchange_app.forwarding.SimCards
import com.moneyexchange.moneyexchange_app.forwarding.TransactionEvents
import com.moneyexchange.moneyexchange_app.forwarding.TransactionStore
import com.moneyexchange.moneyexchange_app.forwarding.UssdAccessibilityService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
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
// Extends FlutterFragmentActivity (not FlutterActivity) because the local_auth
// plugin's BiometricPrompt-based device-auth flow requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {

    private val channelName = "xawil/forwarding"
    private val eventsChannelName = "xawil/forwarding/events"
    private val balanceChannelName = "xawil/forwarding/balance"

    /**
     * Live sink for the transactions EventChannel: while the dashboard is in the
     * foreground it's fed every newly recorded [TransactionStore] event so the
     * "today's forwarded" counter ticks up the instant a forward completes. Held
     * so the [TransactionEvents] listener can be detached in onCancel.
     */
    private var txListener: ((Map<String, Any?>) -> Unit)? = null

    /**
     * Live sink for the leftover-balance EventChannel: fed the account's remaining
     * balance the instant the accessibility service reads it off a completed
     * forward's result dialog, so the forwarding-mode card's readout updates without
     * a refresh. Held so the [BalanceEvents] listener can be detached in onCancel.
     */
    private var balanceListener: ((Double) -> Unit)? = null

    /**
     * The Flutter result for an in-flight `requestPermissions` call, completed in
     * [onRequestPermissionsResult] once the user has responded to the native
     * runtime dialogs. Lets the Dart side await the prompts and then move on to
     * the accessibility ask.
     */
    private var pendingPermissionResult: MethodChannel.Result? = null

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
                    "getTransactions" -> result.success(TransactionStore.all(this))
                    "getStorageInfo" -> result.success(TransactionStore.storageInfo(this))
                    "clearOldTransactions" -> {
                        // "Refresh storage": drop everything older than ~1 month, keep the
                        // last month. Returns how many events were removed.
                        val removed = TransactionStore.clearExceptLastMonth(this)
                        result.success(removed)
                    }
                    "listSims" -> result.success(SimCards.list(this))
                    "requestPermissions" -> {
                        // Hold the Flutter result until the user has actually
                        // responded to the native "Allow / Don't allow" dialogs
                        // (delivered in onRequestPermissionsResult), so the Dart
                        // side can chain the next step (the accessibility ask)
                        // AFTER these prompts instead of racing them.
                        pendingPermissionResult?.success(null) // free any stale one
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                Manifest.permission.RECEIVE_SMS,
                                Manifest.permission.CALL_PHONE,
                                Manifest.permission.READ_PHONE_STATE,
                            ),
                            REQ_PERMISSIONS,
                        )
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
                        // fresh=true (the pull-to-refresh) forces a live *800# balance read
                        // instead of depositing the cached leftover.
                        val fresh = call.argument<Boolean>("fresh") ?: false
                        ForwardingForegroundService.sweepNow(this, fresh)
                        result.success(null)
                    }
                    "checkBalance" -> {
                        // Check-messages refresh: read the balance via *800# (updates
                        // the leftover readout live) WITHOUT forwarding.
                        ForwardingForegroundService.checkBalance(this)
                        result.success(null)
                    }
                    "setActiveUser" -> {
                        // Switch which user's namespaced on-device data (settings,
                        // PINs, ledger) is active. Called by the app on login /
                        // session-restore (userId set) and logout (userId null), so
                        // each user gets their own persistent data. Then re-evaluate
                        // the forwarder for the now-active user.
                        val userId = call.argument<Int>("userId")
                        SessionStore.setActiveUserId(this, userId?.toString())
                        val userSettings = ForwardingSettings(this) // reads new namespace
                        if (userSettings.enabled && userSettings.isReady()) {
                            ForwardingForegroundService.start(this)
                        } else {
                            ForwardingForegroundService.stop(this)
                        }
                        result.success(null)
                    }
                    "stopForwarding" -> {
                        // Called on logout / account deletion. Forwarding must NOT keep
                        // running once the user is signed out, in either mode: flip the
                        // enabled flag off (so the SMS-driven message-check path and the
                        // boot receiver both stand down) and tear the poller + its alarm
                        // down now. On deletion (clear=true) also wipe all stored config
                        // + encrypted PINs so nothing outlives the account.
                        val clear = call.argument<Boolean>("clear") ?: false
                        if (clear) {
                            settings.clear()
                            // Account deletion: wipe the on-device ledger too so no
                            // transaction history outlives the account it belonged to.
                            TransactionStore.clear(this)
                        } else {
                            settings.enabled = false
                        }
                        ForwardingForegroundService.stop(this)
                        result.success(null)
                    }
                    "setPlanActive" -> {
                        // Push the plan window from Flutter: whether the trial/paid plan
                        // is active and the epoch-millis it stays valid through. The
                        // forwarder refuses ALL USSD once expired (see the plan gate in
                        // ForwardingForegroundService.onStartCommand), even app-closed.
                        // When it flips inactive, tear the running poller down now.
                        val active = call.argument<Boolean>("active") ?: true
                        val until = call.argument<Number>("activeUntilEpochMs")?.toLong() ?: 0L
                        settings.planActive = active
                        settings.planActiveUntilMs = until
                        if (!settings.isPlanActive()) {
                            ForwardingForegroundService.stop(this)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Streams every newly recorded transaction to Dart while the app is alive,
        // so the dashboard updates live (e.g. today's forwarded total increments
        // the moment a forward completes) without polling.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventsChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val sink = events ?: return
                    val listener: (Map<String, Any?>) -> Unit = { event -> sink.success(event) }
                    txListener = listener
                    TransactionEvents.addListener(listener)
                }

                override fun onCancel(arguments: Any?) {
                    txListener?.let { TransactionEvents.removeListener(it) }
                    txListener = null
                }
            })

        // Streams the leftover balance to Dart the instant a forward's result dialog
        // is read, so the forwarding-mode card's readout is real-time (no refresh).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, balanceChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val sink = events ?: return
                    val listener: (Double) -> Unit = { balance -> sink.success(balance) }
                    balanceListener = listener
                    BalanceEvents.addListener(listener)
                }

                override fun onCancel(arguments: Any?) {
                    balanceListener?.let { BalanceEvents.removeListener(it) }
                    balanceListener = null
                }
            })
    }

    /**
     * Completes the awaiting `requestPermissions` call once the user has answered
     * the native runtime-permission dialogs. Always calls super first so Flutter
     * plugins still receive their permission callbacks.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_PERMISSIONS) {
            pendingPermissionResult?.success(null)
            pendingPermissionResult = null
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
        // Leftover balance read off the last forward's result dialog, for the sweep card.
        "lastLeftoverBalance" to settings.lastLeftoverBalance,
        "lastLeftoverAtMs" to settings.lastLeftoverAtMs,
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
