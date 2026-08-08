import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/storage/session_storage.dart';
import '../domain/app_user.dart';
import 'auth_api.dart';
import 'google_auth_service.dart';

/// Orchestrates a full sign-in: Google account picker -> ID token -> backend
/// exchange -> persisted session. This is the one place that knows all three
/// pieces (Google, the backend, secure storage) have to happen together.
class AuthRepository {
  AuthRepository({
    required GoogleAuthService googleAuthService,
    required AuthApi authApi,
    required SessionStorage sessionStorage,
  }) : _googleAuthService = googleAuthService,
       _authApi = authApi,
       _sessionStorage = sessionStorage;

  final GoogleAuthService _googleAuthService;
  final AuthApi _authApi;
  final SessionStorage _sessionStorage;

  /// Signs in with Google, then tries to exchange the Google token for a backend
  /// session. The backend only provides a server identity; the app's forwarding
  /// runs entirely on-device, so a backend that's down or unreachable must NOT
  /// block sign-in. When the exchange can't complete, we fall back to a **local
  /// session** built from the Google account — the user gets straight into the
  /// app and everything on-device keeps working.
  ///
  /// The only way this throws is a genuine Google-side failure (the user backs
  /// out → [GoogleSignInCanceled], or a [GoogleSignInException] for a config /
  /// no-account problem) — those are surfaced to the UI with a specific message.
  Future<AppUser> signInWithGoogle() async {
    // Google errors propagate (canceled / real failure) — handled by the caller.
    final account = await _googleAuthService.signIn();
    final idToken = account.authentication.idToken;

    if (idToken != null) {
      try {
        final (accessToken, user) = await _authApi.signInWithGoogle(idToken);
        await _sessionStorage.save(
          accessToken: accessToken,
          userProfileJson: user.toJson(),
        );
        return user;
      } catch (error) {
        // Backend unreachable / erroring — not a sign-in failure for an on-device
        // app. Fall through to a local session so the user still gets in.
        debugPrint(
          'Backend sign-in exchange failed ($error); '
          'continuing with an on-device local session.',
        );
      }
    } else {
      debugPrint(
        'Google returned no ID token (check GOOGLE_SERVER_CLIENT_ID is a Web '
        'OAuth client ID); continuing with an on-device local session.',
      );
    }

    final localUser = _localUserFromGoogle(account);
    // Local session: profile only, no backend token.
    await _sessionStorage.save(userProfileJson: localUser.toJson());
    return localUser;
  }

  /// Builds an [AppUser] from the Google account for a local (backend-less)
  /// session. Uses id 0 as a sentinel — there's no backend user id — and the
  /// Google display name (falling back to the email) as the full name.
  AppUser _localUserFromGoogle(GoogleSignInAccount account) {
    final name = account.displayName?.trim();
    return AppUser(
      id: 0,
      email: account.email,
      fullName: (name != null && name.isNotEmpty) ? name : account.email,
      profilePictureUrl: account.photoUrl,
    );
  }

  /// Restores the cached profile from a previous sign-in. The cached profile is
  /// the source of "who's signed in"; the backend token is optional (a local
  /// on-device session has none). An expired backend token is simply dropped —
  /// NOT treated as a sign-out — so the user isn't surprise-kicked back to the
  /// sign-in screen just because a server token lapsed; forwarding is on-device
  /// and doesn't need it. A live 401 mid-session is still handled by the
  /// interceptor when a token is actually attached.
  Future<AppUser?> restoreSession() async {
    final profile = await _sessionStorage.readUserProfile();
    if (profile == null) return null;

    final token = await _sessionStorage.readAccessToken();
    if (token != null && _isJwtExpired(token)) {
      // Drop the dead token but keep the user in via a local session.
      await _sessionStorage.save(userProfileJson: profile);
    }

    return AppUser.fromJson(profile);
  }

  /// Best-effort local check of a JWT's `exp` claim. Returns true only when the
  /// token is confidently past expiry; anything unparseable returns false and
  /// lets the server be the authority (the 401 interceptor still covers it).
  static bool _isJwtExpired(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final exp =
          (jsonDecode(_decodeBase64Url(parts[1]))
              as Map<String, dynamic>)['exp'];
      if (exp is! int) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      );
      // Small skew so a token about to expire is treated as already expired.
      return DateTime.now().toUtc().isAfter(
        expiry.subtract(const Duration(seconds: 30)),
      );
    } catch (_) {
      return false;
    }
  }

  static String _decodeBase64Url(String segment) {
    var s = segment.replaceAll('-', '+').replaceAll('_', '/');
    switch (s.length % 4) {
      case 2:
        s += '==';
      case 3:
        s += '=';
    }
    return utf8.decode(base64.decode(s));
  }

  Future<void> signOut() async {
    await _googleAuthService.signOut();
    await _sessionStorage.clear();
  }

  /// Deletes the account server-side, then tears down the local session exactly
  /// like a sign-out so the app returns to the signed-out state.
  Future<void> deleteAccount() async {
    await _authApi.deleteAccount();
    await _googleAuthService.signOut();
    await _sessionStorage.clear();
  }
}
