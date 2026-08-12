import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/app_pin_store.dart';
import '../data/pin_api.dart';

final appPinStoreProvider = Provider((_) => AppPinStore());

final pinApiProvider = Provider(
  (ref) => PinApi(dio: ref.watch(apiClientProvider).dio),
);

enum AppLockStatus { locked, unlocked }

/// Whether the app is currently locked behind the 6-digit PIN gate. Starts
/// [AppLockStatus.locked] so a restored session never flashes home before the
/// PIN is entered; [_resolveColdStart] settles it to unlocked when nobody's
/// signed in or the user hasn't set a PIN yet (they go to the set-PIN screen).
/// Relocks whenever the app leaves the foreground, so every reopen asks again.
final pinLockControllerProvider =
    NotifierProvider<PinLockController, AppLockStatus>(PinLockController.new);

class PinLockController extends Notifier<AppLockStatus> {
  @override
  AppLockStatus build() {
    final listener = AppLifecycleListener(onStateChange: _onLifecycle);
    ref.onDispose(listener.dispose);
    _resolveColdStart();
    return AppLockStatus.locked;
  }

  Future<void> _resolveColdStart() async {
    final user = await ref.read(authControllerProvider.future);
    // Only gate a signed-in user who has actually set a PIN.
    if (!(user != null && user.hasAppPin)) {
      state = AppLockStatus.unlocked;
    }
  }

  void _onLifecycle(AppLifecycleState lifecycle) {
    // Relock on the way to the background so the lock screen is already in place
    // when the app is reopened.
    if (lifecycle == AppLifecycleState.paused) {
      final user = ref.read(authControllerProvider).value;
      if (user != null && user.hasAppPin) state = AppLockStatus.locked;
    }
  }

  void markUnlocked() => state = AppLockStatus.unlocked;

  void lock() => state = AppLockStatus.locked;
}

/// Actions on the custom app-lock PIN: set it (first run), verify it (unlock), and
/// change it (settings). Writes to both the backend (authoritative hash, the DB
/// store) and a local secure-storage copy (for instant/offline unlock).
final appPinControllerProvider = Provider((ref) => AppPinController(ref));

class AppPinController {
  AppPinController(this._ref);
  final Ref _ref;

  /// Sets the PIN for the first time: stores it server-side + locally, flips the
  /// cached user's `hasAppPin`, and unlocks. Throws [PinException] on failure.
  Future<void> setPin(String pin) async {
    await _ref.read(pinApiProvider).setPin(pin);
    final user = _ref.read(authControllerProvider).value;
    if (user != null) {
      await _ref.read(appPinStoreProvider).write(user.id, pin);
      await _ref.read(authControllerProvider.notifier).markPinSet();
    }
    _ref.read(pinLockControllerProvider.notifier).markUnlocked();
  }

  /// Verifies an entered PIN for unlocking. Prefers the instant local check;
  /// falls back to the backend (and caches the PIN on success) when there's no
  /// local copy yet — e.g. a fresh install where the session was restored but the
  /// PIN was set on another device.
  Future<bool> verify(String pin) async {
    final user = _ref.read(authControllerProvider).value;
    if (user == null) return false;
    final store = _ref.read(appPinStoreProvider);
    final local = await store.read(user.id);
    if (local != null) return local == pin;
    try {
      final ok = await _ref.read(pinApiProvider).verify(pin);
      if (ok) await store.write(user.id, pin);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Changes the PIN after verifying the current one server-side. Updates the
  /// local copy too. Throws [PinException] with a user-facing message on failure.
  Future<void> updatePin({
    required String currentPin,
    required String newPin,
  }) async {
    await _ref.read(pinApiProvider).updatePin(
      currentPin: currentPin,
      newPin: newPin,
    );
    final user = _ref.read(authControllerProvider).value;
    if (user != null) {
      await _ref.read(appPinStoreProvider).write(user.id, newPin);
    }
  }
}
