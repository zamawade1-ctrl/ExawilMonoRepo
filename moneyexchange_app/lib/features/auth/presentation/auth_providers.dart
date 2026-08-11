import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/session_storage.dart';
import '../../customer/presentation/customer_providers.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../forwarding/data/forwarding_channel.dart';
import '../../forwarding/presentation/forwarding_providers.dart';
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

  /// Signs up. On success the state becomes the new [AppUser]; on failure it's
  /// restored and an [AuthException] is rethrown so the form can show the message.
  Future<void> register({
    required String fullName,
    required String email,
    required String username,
    required String password,
  }) {
    return _authenticate(
      () => ref.read(authRepositoryProvider).register(
        fullName: fullName,
        email: email,
        username: username,
        password: password,
      ),
    );
  }

  /// Signs in. Same success/failure contract as [register].
  Future<void> login({
    required String usernameOrEmail,
    required String password,
  }) {
    return _authenticate(
      () => ref.read(authRepositoryProvider).login(
        usernameOrEmail: usernameOrEmail,
        password: password,
      ),
    );
  }

  Future<void> _authenticate(Future<AppUser> Function() call) async {
    final previousState = state;
    state = const AsyncLoading();
    try {
      state = AsyncData(await call());
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
    state = const AsyncData(null);
  }

  /// Called when a backend call returns 401: the stored token is expired or
  /// invalid, so clear the local session and drop to signed-out. The router then
  /// redirects to the sign-in screen. Idempotent - concurrent 401s that all fire
  /// this are harmless once the state is already null.
  Future<void> handleSessionExpired() async {
    if (state.value == null) return;
    await ref.read(sessionStorageProvider).clear();
    state = const AsyncData(null);
  }

  /// Permanently deletes the account, then drops to the signed-out state. Throws
  /// on failure so the caller can surface an error and keep the user signed in.
  Future<void> deleteAccount() async {
    // Wipe on-device forwarding (config + encrypted PINs) as part of deletion,
    // before the backend delete, so nothing survives the account.
    await _stopForwarding(clear: true);
    await ref.read(authRepositoryProvider).deleteAccount();
    state = const AsyncData(null);
  }
}
