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
import com.moneyexchange.moneyexchange_app.forwarding.DestinationChangeNotifications
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

    /** Emits deep-link route strings (e.g. from a tapped destination-change notification). */
    private val navChannelName = "xawil/forwarding/navigation"

    /**
     * Live sink for the deep-link navigation channel, and a one-slot buffer for a
     * route that arrived (via the launch intent / onNewIntent) before Flutter had
     * subscribed. When [onListen] attaches the sink we flush the buffered route, so a
     * notification tapped while the app was closed still reaches the Dart router.
     */
    private var navSink: EventChannel.EventSink? = null
    private var pendingNavRoute: String? = null

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
                        //
                        // Apply the method FIRST so the destination-change logic below
                        // knows whether this is a mobile save (only mobile uses the
                        // pending-confirmation security flow).
                        call.argument<Int>("forwardingMethod")?.let {
                            settings.forwardingMethod = ForwardingMethod.fromOrdinal(it)
                        }
                        call.argument<String>("pin")?.let { settings.pin = it }
                        call.argument<String>("secondaryPin")?.let { settings.secondaryPin = it }
                        call.argument<String>("bankPin")?.let { settings.bankPin = it }
                        call.argument<Int>("intervalMinutes")?.let { settings.intervalMinutes = it }
                        // Seconds is the real scheduling unit (auto-forward can run every 30s).
                        call.argument<Int>("intervalSeconds")?.let { settings.intervalSeconds = it }
                        call.argument<Int>("simSubscriptionId")?.let { settings.simSubscriptionId = it }
                        call.argument<Int>("mode")?.let { settings.mode = ForwardingMode.fromOrdinal(it) }
                        call.argument<Boolean>("enabled")?.let { settings.enabled = it }

                        // Destination handling. For the MOBILE method a NEW or CHANGED
                        // number does NOT go live immediately — it enters the pending
                        // state (see ForwardingSettings.requestDestinationChange) and the
                        // forwarder refuses to forward until the user confirms. The BANK
                        // path (destination arg omitted) and an UNCHANGED mobile re-save
                        // are completely unaffected.
                        var pendingCreated = false
                        if (call.hasArgument("destination")) {
                            val newDest = call.argument<String>("destination")
                            if (settings.forwardingMethod == ForwardingMethod.MOBILE_NUMBER &&
                                !newDest.isNullOrBlank()
                            ) {
                                val current = settings.destination
                                if (newDest != current) {
                                    settings.requestDestinationChange(current, newDest)
                                    DestinationChangeNotifications.post(this, newDest)
                                    pendingCreated = true
                                }
                                // else: unchanged re-save → leave the active number as-is.
                            } else {
                                // Bank (destination omitted → not here) / blank: as before.
                                settings.destination = newDest
                            }
                        }

                        // Re-evaluate on every save: forwarding runs only when it's both
                        // switched on AND fully configured. A pending mobile change makes
                        // isReady() false, so this also stands the forwarder down until
                        // the user confirms the new number.
                        if (settings.enabled && settings.isReady()) {
                            ForwardingForegroundService.start(this)
                        } else {
                            ForwardingForegroundService.stop(this)
                        }
                        result.success(mapOf("pendingDestinationChange" to pendingCreated))
                    }
                    "getDestinationChangeLog" -> result.success(settings.destinationChangeLog())
                    "getPendingDestinationChange" -> result.success(
                        mapOf(
                            "hasPending" to settings.hasPendingDestinationChange(),
                            "oldNumber" to settings.pendingOldDestination,
                            "newNumber" to settings.pendingDestination,
                            "atMs" to settings.pendingChangeAtMs,
                        ),
                    )
                    "confirmDestinationChange" -> {
                        settings.confirmDestinationChange()
                        // Now that the new number is the active destination, resume the
                        // forwarder if everything's configured + enabled.
                        if (settings.enabled && settings.isReady()) {
                            ForwardingForegroundService.start(this)
                        } else {
                            ForwardingForegroundService.stop(this)
                        }
                        result.success(null)
                    }
                    "rejectDestinationChange" -> {
                        settings.rejectDestinationChange()
                        // The old number stays active; resume the forwarder for it.
                        if (settings.enabled && settings.isReady()) {
                            ForwardingForegroundService.start(this)
                        } else {
                            ForwardingForegroundService.stop(this)
                        }
                        result.success(null)
                    }
                    "getDeviceId" -> {
                        // Settings.Secure.ANDROID_ID: a per-device (per app-signing-key)
                        // identifier that is genuinely UNIQUE across physical devices —
                        // unlike device_info_plus's `id` (Build.ID, the firmware build
                        // string, which is IDENTICAL on every phone of the same model +
                        // build and so made two distinct "samsung SM-A075F" phones collide
                        // under the one-account-per-device check). The real hardware serial
                        // (Build.getSerial) is unreadable without privileged/carrier access
                        // on Android 10+, so ANDROID_ID is the correct stable unique id.
                        // It also survives app reinstalls, so a reinstall doesn't lock the
                        // real owner out. Raw value is hashed on the Dart side before it
                        // leaves the device.
                        val androidId = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID,
                        )
                        result.success(androidId)
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
                                // Reads each SIM's own number for the SIM picker.
                                Manifest.permission.READ_PHONE_NUMBERS,
                                // Lets the destination-change alert (and the ongoing
                                // forwarding notification) show on Android 13+. Requested
                                // as a string so it compiles below API 33, where it's a
                                // harmless no-op.
                                "android.permission.POST_NOTIFICATIONS",
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

        // Deep-link navigation: a tapped notification re-launches this activity with a
        // route extra; we forward it to Flutter here. A route that arrived before Dart
        // subscribed is buffered and flushed on first listen (see [pendingNavRoute]).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, navChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    navSink = events
                    pendingNavRoute?.let { route ->
                        events?.success(route)
                        pendingNavRoute = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    navSink = null
                }
            })

        // Capture a deep-link route from the intent that launched the app (cold start).
        // Buffered until the Dart side subscribes on the nav channel above.
        readNavRoute(intent)?.let { pendingNavRoute = it }
    }

    /** Pulls the deep-link route out of an intent's extras, if present. */
    private fun readNavRoute(intent: Intent?): String? =
        intent?.getStringExtra(DestinationChangeNotifications.EXTRA_ROUTE)

    /**
     * Delivers a deep-link route to Flutter now if it's listening, else buffers it
     * for [onListen] to flush.
     */
    private fun emitNavRoute(route: String) {
        val sink = navSink
        if (sink != null) sink.success(route) else pendingNavRoute = route
    }

    /**
     * The app is singleTop, so a notification tap while it's already running delivers
     * the deep-link here instead of a fresh launch. Forward the route to Flutter.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readNavRoute(intent)?.let { emitNavRoute(it) }
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
        "intervalSeconds" to settings.intervalSeconds,
        "simSubscriptionId" to settings.simSubscriptionId,
        "mode" to settings.mode.ordinal,
        "lastAccountPhone" to settings.lastAccountPhone,
        // Leftover balance read off the last forward's result dialog, for the sweep card.
        "lastLeftoverBalance" to settings.lastLeftoverBalance,
        "lastLeftoverAtMs" to settings.lastLeftoverAtMs,
        // Mobile destination-change security flow: whether a new number is awaiting
        // confirmation, and what it is, so the UI can surface the pending state.
        "hasPendingDestinationChange" to settings.hasPendingDestinationChange(),
        "pendingDestination" to settings.pendingDestination,
        "pendingOldDestination" to settings.pendingOldDestination,
        "pendingChangeAtMs" to settings.pendingChangeAtMs,
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
