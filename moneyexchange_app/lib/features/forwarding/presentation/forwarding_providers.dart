import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_number/mobile_number.dart' as mn;

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

/// SIM MSISDNs read via the `mobile_number` package, keyed by SIM **slot index**.
/// The package reads the number through `TelephonyManager.getLine1Number()` (per
/// subscription) — a different source than our native `SubscriptionInfo.getNumber`
/// — so it can surface a number that path returned blank. Android-only; a slot
/// whose number the carrier never provisioned is simply absent from the map (the
/// SIM picker then falls back to the account phone). Errors degrade to an empty map.
final simNumbersProvider = FutureProvider<Map<int, String>>((ref) async {
  if (!Platform.isAndroid) return const {};
  try {
    final cards = await mn.MobileNumber.getSimCards ?? const <mn.SimCard>[];
    final out = <int, String>{};
    for (final c in cards) {
      final slot = c.slotIndex;
      final number = c.number?.trim();
      if (slot == null || number == null || number.isEmpty) continue;
      // getLine1Number sometimes omits the country prefix; prepend it when the
      // package parsed one and the number isn't already in international form.
      final prefix = c.countryPhonePrefix?.trim();
      out[slot] = (prefix != null && prefix.isNotEmpty && !number.startsWith('+') && !number.startsWith(prefix))
          ? '$prefix$number'
          : number;
    }
    return out;
  } catch (_) {
    return const {};
  }
});

/// Live stream of the account's leftover balance, pushed by the native side the
/// instant it reads it off a completed forward's result dialog. The sweep card
/// prefers this over the (refresh-time) [ForwardingStatus.lastLeftoverBalance] so
/// the readout is real-time. Empty until the first forward completes this session.
final leftoverBalanceStreamProvider = StreamProvider<double>((ref) {
  return const ForwardingChannel().leftoverBalanceEvents();
});

/// Whether a pull-to-refresh balance check (`*800#`, balance-only) is currently
/// being dialed. The "Run sweep" button watches this and disables itself while a
/// refresh is in flight, so a sweep can't be started on top of an in-progress
/// balance read. Set the moment a pull-to-refresh fires the check; cleared when the
/// balance comes back on [leftoverBalanceStreamProvider], or a safety timeout fires
/// (in case the read never reports back) so the button can never stay stuck.
final balanceRefreshInProgressProvider =
    NotifierProvider<BalanceRefreshNotifier, bool>(BalanceRefreshNotifier.new);

class BalanceRefreshNotifier extends Notifier<bool> {
  Timer? _timeout;

  @override
  bool build() {
    ref.onDispose(() => _timeout?.cancel());
    return false;
  }

  /// A pull-to-refresh started dialing the `*800#` balance check: disable Run
  /// sweep. Auto-clears after [maxWait] as a backstop, so a read that never
  /// reports a balance can't leave the button disabled forever.
  void begin({Duration maxWait = const Duration(seconds: 20)}) {
    _timeout?.cancel();
    state = true;
    _timeout = Timer(maxWait, () => state = false);
  }

  /// The balance came back (or the wait elapsed): re-enable Run sweep.
  void complete() {
    _timeout?.cancel();
    _timeout = null;
    if (state) state = false;
  }
}

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
  /// Returns whether the save parked a NEW/CHANGED mobile number into the
  /// pending-confirmation state (true only for a changed mobile number), so the
  /// caller can redirect to the confirmation screen.
  Future<bool> saveDestination({
    required int forwardingMethod,
    String? destination,
    String? pin,
    String? secondaryPin,
    String? bankPin,
    required int intervalSeconds,
  }) async {
    final pendingCreated = await _channel.saveSettings(
      forwardingMethod: forwardingMethod,
      destination: destination,
      pin: pin,
      secondaryPin: secondaryPin,
      bankPin: bankPin,
      intervalSeconds: intervalSeconds,
    );
    await refresh();
    return pendingCreated;
  }

  /// Confirms the pending mobile destination change (new number goes live), then
  /// refreshes so the card/status reflect the now-active destination.
  Future<void> confirmDestinationChange() async {
    await _channel.confirmDestinationChange();
    await refresh();
  }

  /// Rejects the pending mobile destination change (old number stays active).
  Future<void> rejectDestinationChange() async {
    await _channel.rejectDestinationChange();
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
