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
  (ref) => ApiClient(sessionStorage: ref.watch(sessionStorageProvider)),
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
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);

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
}
