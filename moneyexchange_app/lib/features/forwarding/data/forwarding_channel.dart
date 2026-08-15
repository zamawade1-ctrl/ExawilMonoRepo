import 'dart:io';

import 'package:flutter/services.dart';

/// How the on-device sweep decides when to run. Mirrors the native
/// `ForwardingMode` enum (android/.../forwarding/ForwardingSettings.kt) -
/// serialized as its ordinal, not a string.
enum ForwardingMode {
  /// Dials `*800#` on a timer (`intervalMinutes`), regardless of whether
  /// money has actually arrived.
  autoForward,

  /// Never runs on a timer - only sweeps when a Zaad money-in SMS arrives.
  messageCheck;

  static ForwardingMode fromWire(int value) => ForwardingMode.values[value];
}

/// One active SIM, as reported by the native side for the dual-SIM picker.
class SimCard {
  const SimCard({
    required this.subscriptionId,
    required this.slotIndex,
    required this.displayName,
    required this.carrierName,
    this.number,
  });

  final int subscriptionId;
  final int slotIndex;
  final String displayName;
  final String carrierName;
  final String? number;

  /// A human label like "SIM 1 · Somtel" for the dropdown. The carrier is only
  /// appended when it adds information — if the SIM's display name is already the
  /// carrier (common: both read "Telesom"), it's shown once, not "Telesom · Telesom".
  String get label {
    final name = displayName.trim();
    final carrier = carrierName.trim();
    if (carrier.isEmpty || carrier.toLowerCase() == name.toLowerCase()) {
      return name.isNotEmpty ? name : carrier;
    }
    return name.isNotEmpty ? '$name · $carrier' : carrier;
  }

  static SimCard fromMap(Map<Object?, Object?> map) => SimCard(
    subscriptionId: (map['subscriptionId'] as num?)?.toInt() ?? -1,
    slotIndex: (map['slotIndex'] as num?)?.toInt() ?? 0,
    displayName: map['displayName'] as String? ?? 'SIM',
    carrierName: map['carrierName'] as String? ?? '',
    number: (map['number'] as String?)?.isNotEmpty == true
        ? map['number'] as String?
        : null,
  );
}

/// Snapshot of the native side's readiness, mirrored from `MainActivity.status`.
class ForwardingStatus {
  const ForwardingStatus({
    required this.hasSmsPermission,
    required this.hasCallPermission,
    required this.hasPhoneStatePermission,
    required this.accessibilityEnabled,
    required this.overlayEnabled,
    required this.ignoringBatteryOptimizations,
    required this.enabled,
    required this.destination,
    required this.hasPin,
    required this.hasSecondaryPin,
    required this.hasBankPin,
    required this.pin,
    required this.secondaryPin,
    required this.bankPin,
    required this.forwardingMethod,
    required this.intervalMinutes,
    required this.simSubscriptionId,
    required this.mode,
    required this.lastAccountPhone,
    required this.lastLeftoverBalance,
    required this.lastLeftoverAtMs,
  });

  final bool hasSmsPermission;
  final bool hasCallPermission;
  final bool hasPhoneStatePermission;
  final bool accessibilityEnabled;
  final bool overlayEnabled;

  /// Whether the app is exempt from battery optimization (Doze). Required for the
  /// auto-forward timer to keep its exact 1-minute cadence with the screen off /
  /// phone locked overnight — without it, Android defers the wake-ups.
  final bool ignoringBatteryOptimizations;

  final bool enabled;
  final String? destination;
  final bool hasPin;
  final bool hasSecondaryPin;

  /// Whether the customer's bank PIN is stored (bank-account method only).
  final bool hasBankPin;

  /// The saved primary / secondary / bank PIN values, so the edit form can
  /// pre-fill them (masked) on a return visit without a backend round-trip.
  /// On-device only — never sent to the server.
  final String? pin;
  final String? secondaryPin;
  final String? bankPin;

  /// 0 = mobile number (`*806#`), 1 = bank account (`*800#` deposit walk).
  /// Mirrors the backend/native `ForwardingMethod` ordinal.
  final int forwardingMethod;

  final int intervalMinutes;
  final int simSubscriptionId;
  final ForwardingMode mode;

  /// The account's own number, as last read from the *800# balance screen.
  final String? lastAccountPhone;

  /// The balance left on the account after the most recent forward, read off the
  /// "…Your Balance is $X." result dialog. Null until the first forward completes.
  final double? lastLeftoverBalance;

  /// Wall-clock millis when [lastLeftoverBalance] was captured; 0 if never.
  final int lastLeftoverAtMs;

  /// Whether the destination is a bank account (vs a mobile number).
  bool get isBankMethod => forwardingMethod == 1;

  /// Whether every device permission the forwarder needs is granted: SMS/phone/
  /// SIM runtime permissions, the accessibility (auto-type PIN) service, and the
  /// display-over-other-apps overlay. Device permissions only — not whether a
  /// destination/PIN is configured (that's [fullyReady]). The permissions are
  /// requested on first run via system prompts + the accessibility guide dialog;
  /// there's no longer a full-screen onboarding gate or an Accessibility tab.
  bool get permissionsReady =>
      hasSmsPermission &&
      hasCallPermission &&
      hasPhoneStatePermission &&
      accessibilityEnabled &&
      overlayEnabled;

  /// Whether the forwarding destination + PINs are configured (the non-permission
  /// half of [fullyReady]): mobile needs a destination number + both PINs, bank
  /// needs the account PIN + the bank PIN. Used to word the "not yet active"
  /// banner accurately — so it doesn't tell the user to "finish the destination"
  /// when the real blocker is a missing permission.
  bool get hasForwardingCredentials {
    if (!hasPin) return false;
    return isBankMethod
        ? hasBankPin
        : (destination?.isNotEmpty ?? false) && hasSecondaryPin;
  }

  /// Everything the native forwarder needs before the balance sweep can run.
  /// The credential requirements differ by method: mobile needs a destination
  /// number + both PINs, bank needs only the account PIN + the bank PIN.
  bool get fullyReady {
    if (!(hasSmsPermission &&
        hasCallPermission &&
        accessibilityEnabled &&
        overlayEnabled &&
        enabled &&
        hasPin)) {
      return false;
    }
    return isBankMethod
        ? hasBankPin
        : (destination?.isNotEmpty ?? false) && hasSecondaryPin;
  }

  static ForwardingStatus fromMap(Map<Object?, Object?> map) =>
      ForwardingStatus(
        hasSmsPermission: map['hasSmsPermission'] as bool? ?? false,
        hasCallPermission: map['hasCallPermission'] as bool? ?? false,
        hasPhoneStatePermission:
            map['hasPhoneStatePermission'] as bool? ?? false,
        accessibilityEnabled: map['accessibilityEnabled'] as bool? ?? false,
        overlayEnabled: map['overlayEnabled'] as bool? ?? false,
        ignoringBatteryOptimizations:
            map['ignoringBatteryOptimizations'] as bool? ?? false,
        enabled: map['enabled'] as bool? ?? false,
        destination: map['destination'] as String?,
        hasPin: map['hasPin'] as bool? ?? false,
        hasSecondaryPin: map['hasSecondaryPin'] as bool? ?? false,
        hasBankPin: map['hasBankPin'] as bool? ?? false,
        pin: map['pin'] as String?,
        secondaryPin: map['secondaryPin'] as String?,
        bankPin: map['bankPin'] as String?,
        forwardingMethod: (map['forwardingMethod'] as num?)?.toInt() ?? 0,
        intervalMinutes: (map['intervalMinutes'] as num?)?.toInt() ?? 1,
        simSubscriptionId: (map['simSubscriptionId'] as num?)?.toInt() ?? -1,
        mode: ForwardingMode.fromWire(
          (map['mode'] as num?)?.toInt() ?? ForwardingMode.messageCheck.index,
        ),
        lastAccountPhone: map['lastAccountPhone'] as String?,
        lastLeftoverBalance: (map['lastLeftoverBalance'] as num?)?.toDouble(),
        lastLeftoverAtMs: (map['lastLeftoverAtMs'] as num?)?.toInt() ?? 0,
      );
}

/// Thin Dart wrapper over the native `xawil/forwarding` method channel. All
/// methods are Android-only; on other platforms they throw
/// [MissingPluginException], so callers should guard with `Platform.isAndroid`.
class ForwardingChannel {
  const ForwardingChannel();

  static const _channel = MethodChannel('xawil/forwarding');
  static const _balanceEvents = EventChannel('xawil/forwarding/balance');

  /// Streams the account's leftover balance the instant the native side reads it
  /// off a completed forward's result dialog, so the UI updates without a refresh.
  /// Empty on non-Android platforms (no on-device forwarder).
  Stream<double> leftoverBalanceEvents() {
    if (!Platform.isAndroid) return const Stream.empty();
    return _balanceEvents
        .receiveBroadcastStream()
        .where((e) => e is num)
        .map((e) => (e as num).toDouble());
  }

  Future<ForwardingStatus> getStatus() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getStatus');
    return ForwardingStatus.fromMap(raw ?? const {});
  }

  /// Lists the phone's active SIMs for the dual-SIM picker. Empty when the
  /// phone-state permission is missing or the device is single-SIM.
  Future<List<SimCard>> listSims() async {
    final raw = await _channel.invokeMethod<List<Object?>>('listSims');
    return (raw ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(SimCard.fromMap)
        .toList();
  }

  /// Persists the balance-sweep settings as a **partial update**: only the
  /// fields passed here are written on the native side, so the "forwarding
  /// mode" card and the "forwarding profile" card can each save just their own
  /// fields without clobbering the other's. Omitting a field leaves the stored
  /// value untouched.
  ///
  /// The PINs are additionally ignored when empty (so re-saving without
  /// retyping keeps the stored ones); they go straight to the Android Keystore
  /// and are never sent anywhere else. Setting [enabled] true with everything
  /// configured starts the sweep; setting it false stops it.
  Future<void> saveSettings({
    String? destination,
    String? pin,
    String? secondaryPin,
    String? bankPin,
    int? forwardingMethod,
    int? intervalMinutes,
    int? simSubscriptionId,
    ForwardingMode? mode,
    bool? enabled,
  }) {
    return _channel.invokeMethod('saveSettings', {
      'destination': ?destination,
      if (pin != null && pin.isNotEmpty) 'pin': pin,
      if (secondaryPin != null && secondaryPin.isNotEmpty)
        'secondaryPin': secondaryPin,
      // The bank PIN goes to the Android Keystore like the other PINs; it's typed
      // on the *800# deposit walk's "enter bank pin" prompt.
      if (bankPin != null && bankPin.isNotEmpty) 'bankPin': bankPin,
      'forwardingMethod': ?forwardingMethod,
      'intervalMinutes': ?intervalMinutes,
      'simSubscriptionId': ?simSubscriptionId,
      'mode': ?mode?.index,
      'enabled': ?enabled,
    });
  }

  Future<void> requestPermissions() =>
      _channel.invokeMethod('requestPermissions');

  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod('openAccessibilitySettings');

  Future<void> openOverlaySettings() =>
      _channel.invokeMethod('openOverlaySettings');

  /// Opens the system prompt to exempt the app from battery optimization (Doze),
  /// so the auto-forward timer keeps its exact cadence overnight. No-op if the
  /// app is already exempt.
  Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod('requestIgnoreBatteryOptimizations');

  /// Runs one balance-sweep cycle now (dial *800#, read balance, forward if
  /// ≥ $1), without waiting for the next tick. When [fresh] is true (the
  /// auto-forward pull-to-refresh) it forces a live *800# balance read rather
  /// than depositing the cached leftover.
  Future<void> sweepNow({bool fresh = false}) =>
      _channel.invokeMethod('sweepNow', {'fresh': fresh});

  /// Reads the account balance via *800# and publishes it to the leftover-balance
  /// stream WITHOUT forwarding — the check-messages "pull to refresh my balance"
  /// action. No-op off Android.
  Future<void> checkBalance() => _channel.invokeMethod('checkBalance');

  /// Tells the native side which signed-in user owns the on-device data (settings,
  /// PINs, ledger), so each user gets their own persistent, isolated data. Pass the
  /// backend User id on login / session-restore, or null on logout. No-op off
  /// Android (nothing on-device to scope).
  Future<void> setActiveUser(int? userId) =>
      _channel.invokeMethod('setActiveUser', {'userId': userId});

  /// Tells the native side whether the user's plan (trial or paid) is currently
  /// active and, if so, the epoch-millis instant it stays valid through. The native
  /// forwarder refuses to dial `*800#` or act on a Zaad SMS once the plan has
  /// expired, so an expired account does nothing — even with the app closed. Pass
  /// [active] false (and any [activeUntilEpochMs]) to hard-stop it. No-op off Android.
  Future<void> setPlanActive({
    required bool active,
    required int activeUntilEpochMs,
  }) => _channel.invokeMethod('setPlanActive', {
    'active': active,
    'activeUntilEpochMs': activeUntilEpochMs,
  });

  /// Stops the on-device forwarder so no USSD runs once the user is signed out —
  /// in either mode. Disables the enabled flag (standing down the SMS-driven
  /// message-check path and the boot receiver) and tears the poller + its alarm
  /// down. Pass [clear] true on account deletion to also wipe all stored config
  /// and encrypted PINs. No-op on non-Android platforms.
  Future<void> stopForwarding({bool clear = false}) =>
      _channel.invokeMethod('stopForwarding', {'clear': clear});
}
