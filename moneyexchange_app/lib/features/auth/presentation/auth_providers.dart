import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/session_storage.dart';
import '../../customer/presentation/customer_providers.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../forwarding/data/forwarding_channel.dart';
import '../../forwarding/presentation/forwarding_providers.dart';
import '../../security/presentation/pin_providers.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';

export '../data/auth_repository.dart' show AuthException;

final sessionStorageProvider = Provider((_) => SessionStorage());

final apiClientProvider = Provider(
  (ref) => ApiClient(
    sessionStorage: ref.watch(sessionStorageProvider),
    // On a 401 (expired/invalid token), tear down the session so the router
    // redirects to sign-in. Deferred to a microtask so we never mutate the
    // auth provider from inside a request's error callback.
    onUnauthorized: () => Future.microtask(
      () => ref.read(authControllerProvider.notifier).handleSessionExpired(),
    ),
  ),
);

final authApiProvider = Provider(
  (ref) => AuthApi(dio: ref.watch(apiClientProvider).dio),
);

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(
    authApi: ref.watch(authApiProvider),
    sessionStorage: ref.watch(sessionStorageProvider),
  ),
);

/// The app's single source of truth for "who's signed in". `AsyncValue<null>`
/// means signed out; `AsyncValue<AppUser>` means signed in; loading/error
/// states drive the sign-in screen's spinner and error banner.
final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final user = await ref.read(authRepositoryProvider).restoreSession();
    // Point the native on-device stores at this user's namespace BEFORE the
    // home providers first read them, so a restored session shows its own data.
    // No invalidate needed here — those providers haven't been read yet.
    await _applyActiveUser(user?.id, invalidate: false);
    return user;
  }

  /// Tells the native side which user owns the on-device data (settings, PINs,
  /// ledger) so each user's data is separate + persistent, then (when
  /// [invalidate]) re-reads the per-user providers so the UI swaps to that user's
  /// data. Android-only + best-effort — a native hiccup must never block auth.
  Future<void> _applyActiveUser(int? userId, {bool invalidate = true}) async {
    if (Platform.isAndroid) {
      try {
        await const ForwardingChannel().setActiveUser(userId);
      } on PlatformException {
        // Ignore — auth must still proceed.
      } on MissingPluginException {
        // Ignore — channel unavailable (e.g. tests).
      }
    }
    if (invalidate) {
      ref.invalidate(nativeForwardingProvider);
      ref.invalidate(deviceLedgerProvider);
      ref.invalidate(customerProfileControllerProvider);
    }
  }

  /// Signs up with full name + phone number + password. On success the state
  /// becomes the new [AppUser]; on failure it's restored and an [AuthException] is
  /// rethrown so the form can show the message.
  Future<void> register({
    required String fullName,
    required String phoneNumber,
    required String password,
  }) {
    return _authenticate(() async {
      final device = await DeviceIdentity.resolve();
      return ref.read(authRepositoryProvider).register(
        fullName: fullName,
        phoneNumber: phoneNumber,
        password: password,
        deviceId: device.id,
        deviceLabel: device.label,
      );
    });
  }

  /// Signs in with phone number + password. Same success/failure contract as
  /// [register]; the device id binds/locks the account to this phone.
  Future<void> login({
    required String phoneNumber,
    required String password,
  }) {
    return _authenticate(() async {
      final device = await DeviceIdentity.resolve();
      return ref.read(authRepositoryProvider).login(
        phoneNumber: phoneNumber,
        password: password,
        deviceId: device.id,
        deviceLabel: device.label,
      );
    });
  }

  /// Marks the signed-in user as having set their app-lock PIN (called right after
  /// the first PIN is saved), updating both the live state and the cached profile
  /// so a cold-start restore routes straight to the PIN unlock screen, not set-PIN.
  Future<void> markPinSet() async {
    final user = state.value;
    if (user == null) return;
    final updated = user.copyWith(hasAppPin: true);
    await ref.read(authRepositoryProvider).updateCachedUser(updated);
    state = AsyncData(updated);
  }

  /// Changes the signed-in user's own password. Throws [AuthException] on failure.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      ref.read(authRepositoryProvider).changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          );

  /// Turns the app-lock PIN on or off. Turning it off clears the local PIN copy and unlocks; turning
  /// it on drops `hasAppPin` so the router routes to the set-PIN screen.
  Future<void> setPinEnabled(bool enabled) async {
    final previous = state.value;
    final updated = await ref.read(authRepositoryProvider).setPinEnabled(enabled);
    if (!enabled && previous != null) {
      // No PIN any more: wipe the local copy and make sure nothing stays locked.
      await ref.read(appPinStoreProvider).clear(previous.id);
      ref.read(pinLockControllerProvider.notifier).markUnlocked();
    }
    state = AsyncData(updated);
  }

  Future<void> _authenticate(Future<AppUser> Function() call) async {
    final previousState = state;
    state = const AsyncLoading();
    try {
      final user = await call();
      // Flip to signed-in FIRST so the router redirects to /home instantly the
      // moment credentials check out — the redirect no longer waits on the native
      // active-user re-point (a method-channel round trip). A fresh phone/password
      // sign-in already proves identity, so don't make the user re-enter their PIN
      // on top of it (the PIN gate re-engages on next reopen / cold start).
      state = AsyncData(user);
      ref.read(pinLockControllerProvider.notifier).markUnlocked();
      // Re-point the native on-device stores AND the per-user Riverpod providers at
      // THIS user, so they see their own data (forwarding config, destination,
      // ledger, dashboard) instead of whoever was signed in before. This invalidates
      // the per-user providers, so /home rebuilds fresh against the new namespace —
      // any momentary stale frame is corrected the instant this completes.
      await _applyActiveUser(user.id);
    } catch (error) {
      // Don't leave the controller in an error state (the router would keep the
      // user signed out with no clear recovery); restore the prior state and let
      // the form surface the message from the rethrown exception.
      state = previousState;
      rethrow;
    }
  }

  /// Stops the on-device USSD forwarder so nothing keeps dialing once signed out,
  /// in either mode. Best-effort and Android-only; a native hiccup must never block
  /// sign-out/deletion. [clear] wipes stored config + PINs (account deletion).
  Future<void> _stopForwarding({bool clear = false}) async {
    if (!Platform.isAndroid) return;
    try {
      await const ForwardingChannel().stopForwarding(clear: clear);
    } on PlatformException {
      // Ignore — the sign-out must still complete.
    } on MissingPluginException {
      // Ignore — channel unavailable (e.g. tests).
    }
  }

  Future<void> signOut() async {
    // Stop forwarding BEFORE clearing the session so it can never linger.
    await _stopForwarding();
    await ref.read(authRepositoryProvider).signOut();
    // Clear the native active user so a logged-out device reads the empty "anon"
    // namespace (the background forwarder then does nothing) and the NEXT user to
    // sign in starts clean rather than inheriting this user's data. No invalidate:
    // the home providers aren't visible while signed out, and the next sign-in
    // re-applies + invalidates them for that user.
    await _applyActiveUser(null, invalidate: false);
    state = const AsyncData(null);
  }

  /// Called when a backend call returns 401: the stored token is expired or
  /// invalid, so clear the local session and drop to signed-out. The router then
  /// redirects to the sign-in screen. Idempotent - concurrent 401s that all fire
  /// this are harmless once the state is already null.
  Future<void> handleSessionExpired() async {
    if (state.value == null) return;
    await ref.read(sessionStorageProvider).clear();
    // Detach the native stores from this user (see [signOut]) so the next sign-in
    // starts clean.
    await _applyActiveUser(null, invalidate: false);
    state = const AsyncData(null);
  }

  /// Permanently deletes the account, then drops to the signed-out state. Throws
  /// on failure so the caller can surface an error and keep the user signed in.
  Future<void> deleteAccount() async {
    // Wipe on-device forwarding (config + encrypted PINs) as part of deletion,
    // before the backend delete, so nothing survives the account.
    await _stopForwarding(clear: true);
    // Also wipe this user's local app-lock PIN copy.
    final userId = state.value?.id;
    if (userId != null) {
      await ref.read(appPinStoreProvider).clear(userId);
    }
    await ref.read(authRepositoryProvider).deleteAccount();
    // Detach the native stores from the (now deleted) user so the next sign-in
    // starts clean.
    await _applyActiveUser(null, invalidate: false);
    state = const AsyncData(null);
  }
}
