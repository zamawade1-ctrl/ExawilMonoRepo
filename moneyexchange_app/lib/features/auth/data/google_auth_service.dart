import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';

/// Thrown when the user closes the Google sign-in sheet without picking an
/// account. Distinct from a real failure so the UI can stay quiet about it.
class GoogleSignInCanceled implements Exception {}

/// Wraps the google_sign_in package: one place that knows how to obtain a
/// Google ID token, and nothing about our backend or app state.
class GoogleAuthService {
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: AppConfig.googleServerClientId.isEmpty
          ? null
          : AppConfig.googleServerClientId,
    );
    _initialized = true;
  }

  /// Triggers the interactive Google sign-in flow and returns the signed-in
  /// account. The account carries both the ID token (for the backend exchange)
  /// and the profile (email/name/photo, used to build an on-device local session
  /// when the backend is unreachable). Throws [GoogleSignInCanceled] if the user
  /// backs out, or [GoogleSignInException] for any other Google-side failure.
  Future<GoogleSignInAccount> signIn() async {
    await _ensureInitialized();
    try {
      return await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw GoogleSignInCanceled();
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }
}
