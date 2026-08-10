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

  /// A human label like "SIM 1 · Somtel" for the dropdown.
  String get label {
    final carrier = carrierName.isNotEmpty ? ' · $carrierName' : '';
    return '$displayName$carrier';
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
      );
}

/// Thin Dart wrapper over the native `xawil/forwarding` method channel. All
/// methods are Android-only; on other platforms they throw
/// [MissingPluginException], so callers should guard with `Platform.isAndroid`.
class ForwardingChannel {
  const ForwardingChannel();

  static const _channel = MethodChannel('xawil/forwarding');

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
  /// ≥ $1), for testing on a real device without waiting for the next tick.
  Future<void> sweepNow() => _channel.invokeMethod('sweepNow');

  /// Stops the on-device forwarder so no USSD runs once the user is signed out —
  /// in either mode. Disables the enabled flag (standing down the SMS-driven
  /// message-check path and the boot receiver) and tears the poller + its alarm
  /// down. Pass [clear] true on account deletion to also wipe all stored config
  /// and encrypted PINs. No-op on non-Android platforms.
  Future<void> stopForwarding({bool clear = false}) =>
      _channel.invokeMethod('stopForwarding', {'clear': clear});
}
