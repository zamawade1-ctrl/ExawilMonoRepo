import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/session_storage.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../data/google_auth_service.dart';
import '../domain/app_user.dart';

export '../data/google_auth_service.dart' show GoogleSignInCanceled;

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

final googleAuthServiceProvider = Provider((_) => GoogleAuthService());

final authApiProvider = Provider(
  (ref) => AuthApi(dio: ref.watch(apiClientProvider).dio),
);

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(
    googleAuthService: ref.watch(googleAuthServiceProvider),
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
  Future<AppUser?> build() {
    return ref.read(authRepositoryProvider).restoreSession();
  }

  Future<void> signInWithGoogle() async {
    final previousState = state;
    state = const AsyncLoading();

    try {
      final user = await ref.read(authRepositoryProvider).signInWithGoogle();
      state = AsyncData(user);
    } on GoogleSignInCanceled {
      // User backed out of the account picker - not an error worth showing.
      state = previousState;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
  }

  /// Called when a backend call returns 401: the stored token is expired or
  /// invalid, so clear just the local session (not the Google account, so
  /// re-signing in is a single tap) and drop to signed-out. The router then
  /// redirects to the sign-in screen. Idempotent - concurrent 401s that all
  /// fire this are harmless once the state is already null.
  Future<void> handleSessionExpired() async {
    if (state.value == null) return;
    await ref.read(sessionStorageProvider).clear();
    state = const AsyncData(null);
  }

  /// Permanently deletes the account, then drops to the signed-out state. Throws
  /// on failure so the caller can surface an error and keep the user signed in.
  Future<void> deleteAccount() async {
    await ref.read(authRepositoryProvider).deleteAccount();
    state = const AsyncData(null);
  }
}
