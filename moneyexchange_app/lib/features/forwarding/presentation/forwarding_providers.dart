import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/forwarding_channel.dart';

/// The on-device forwarder's native state: the saved [ForwardingStatus] (mode,
/// enabled, whether PINs are stored, permissions, etc.) plus the phone's active
/// [SimCard]s for the dual-SIM picker. Bundled so a single provider is the one
/// source of truth both the "forwarding mode" card and the "forwarding profile"
/// card read from — and the one thing pull-to-refresh re-fetches.
class NativeForwardingState {
  const NativeForwardingState({this.status, this.sims = const []});

  final ForwardingStatus? status;
  final List<SimCard> sims;
}

final nativeForwardingProvider =
    AsyncNotifierProvider<NativeForwardingController, NativeForwardingState>(
      NativeForwardingController.new,
    );

/// Live stream of the account's leftover balance, pushed by the native side the
/// instant it reads it off a completed forward's result dialog. The sweep card
/// prefers this over the (refresh-time) [ForwardingStatus.lastLeftoverBalance] so
/// the readout is real-time. Empty until the first forward completes this session.
final leftoverBalanceStreamProvider = StreamProvider<double>((ref) {
  return const ForwardingChannel().leftoverBalanceEvents();
});

class NativeForwardingController extends AsyncNotifier<NativeForwardingState> {
  static const _channel = ForwardingChannel();

  @override
  Future<NativeForwardingState> build() => _load();

  /// Reads the native status + SIM list. On non-Android platforms the native
  /// channel isn't wired, so this returns an empty state instead of throwing.
  Future<NativeForwardingState> _load() async {
    if (!Platform.isAndroid) return const NativeForwardingState();
    try {
      final status = await _channel.getStatus();
      final sims = await _channel.listSims();
      return NativeForwardingState(status: status, sims: sims);
    } on PlatformException {
      return const NativeForwardingState();
    }
  }

  /// Re-reads native state (pull-to-refresh, or after returning from a system
  /// settings screen).
  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  /// Saves just the mode + on/off (the forwarding-mode card), then refreshes.
  /// Leaves destination/PINs/SIM/interval untouched (native partial update).
  Future<void> saveMode({
    required ForwardingMode mode,
    required bool enabled,
  }) async {
    await _channel.saveSettings(mode: mode, enabled: enabled);
    await refresh();
  }

  /// Saves the destination + credentials + sweep interval (the forwarding-
  /// destination card), then refreshes. Leaves mode/enabled/SIM untouched.
  /// Empty PINs keep the stored ones (see [ForwardingChannel.saveSettings]).
  ///
  /// [forwardingMethod] (0 = mobile, 1 = bank) selects which forward path the
  /// on-device sweep uses; [bankPin] is the customer's bank PIN, needed only for
  /// the bank-account method (typed on the *800# deposit walk).
  Future<void> saveDestination({
    required int forwardingMethod,
    String? destination,
    String? pin,
    String? secondaryPin,
    String? bankPin,
    required int intervalMinutes,
  }) async {
    await _channel.saveSettings(
      forwardingMethod: forwardingMethod,
      destination: destination,
      pin: pin,
      secondaryPin: secondaryPin,
      bankPin: bankPin,
      intervalMinutes: intervalMinutes,
    );
    await refresh();
  }

  /// Saves just the SIM selection (the SIM-card section), then refreshes.
  /// Leaves every other field untouched.
  Future<void> saveSim({required int simSubscriptionId}) async {
    await _channel.saveSettings(simSubscriptionId: simSubscriptionId);
    await refresh();
  }

  /// Opens the system "ignore battery optimization" prompt, then refreshes so the
  /// banner clears once the user grants it. Needed for the auto-forward timer to
  /// fire on time with the screen off / phone locked overnight.
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    await _channel.requestIgnoreBatteryOptimizations();
    await refresh();
  }
}
