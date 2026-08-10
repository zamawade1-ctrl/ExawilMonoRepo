import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/storage/session_storage.dart';
import '../domain/app_user.dart';
import 'auth_api.dart';

/// A sign-in / sign-up failure with a message safe to show the user. Carries the
/// backend's `ServiceResponse.message` when there was one (e.g. "This username is
/// already taken.", "Incorrect username/email or password."), or a network
/// message when the backend couldn't be reached.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Orchestrates username/password auth (the flow that replaced Google Sign-In):
/// call the backend, then persist the returned JWT + profile so the session
/// survives a cold start. Unlike the old Google flow, the first sign-in/sign-up
/// genuinely needs the backend (a password can only be verified server-side), so
/// there's no offline fallback here — but a *returning* user is restored from the
/// cached profile without any network call (see [restoreSession]).
class AuthRepository {
  AuthRepository({
    required AuthApi authApi,
    required SessionStorage sessionStorage,
  }) : _authApi = authApi,
       _sessionStorage = sessionStorage;

  final AuthApi _authApi;
  final SessionStorage _sessionStorage;

  /// Creates an account, then persists the session. Throws [AuthException] with a
  /// user-facing message on any failure.
  Future<AppUser> register({
    required String fullName,
    required String email,
    required String username,
    required String password,
  }) async {
    return _run(
      () => _authApi.register(
        fullName: fullName,
        email: email,
        username: username,
        password: password,
      ),
    );
  }

  /// Signs in, then persists the session. Throws [AuthException] with a
  /// user-facing message on any failure.
  Future<AppUser> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    return _run(
      () => _authApi.login(usernameOrEmail: usernameOrEmail, password: password),
    );
  }

  /// Runs an auth call and, on success, saves the token + profile. Maps
  /// transport/backend errors to a friendly [AuthException].
  Future<AppUser> _run(
    Future<(String, AppUser)> Function() call,
  ) async {
    try {
      final (accessToken, user) = await call();
      await _sessionStorage.save(
        accessToken: accessToken,
        userProfileJson: user.toJson(),
      );
      return user;
    } on DioException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  /// Extracts the backend's `ServiceResponse.message` from an error response, or
  /// falls back to a network/generic message when there's no usable body.
  String _messageFor(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String &&
        (data['message'] as String).isNotEmpty) {
      return data['message'] as String;
    }
    if (e.response != null) {
      return 'Something went wrong. Please try again.';
    }
    return 'Could not reach the server. Check your connection and try again.';
  }

  /// Restores the cached profile from a previous sign-in. The cached profile is
  /// the source of "who's signed in"; the backend token is optional here. An
  /// expired token is dropped (not treated as a sign-out) so a returning user
  /// isn't surprise-kicked to sign-in just because a server token lapsed — the
  /// on-device forwarding keeps working without it. A live 401 mid-session is
  /// still handled by the interceptor when a token is actually attached.
  Future<AppUser?> restoreSession() async {
    final profile = await _sessionStorage.readUserProfile();
    if (profile == null) return null;

    final token = await _sessionStorage.readAccessToken();
    if (token != null && _isJwtExpired(token)) {
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
    await _sessionStorage.clear();
  }

  /// Deletes the account server-side, then tears down the local session exactly
  /// like a sign-out so the app returns to the signed-out state.
  Future<void> deleteAccount() async {
    await _authApi.deleteAccount();
    await _sessionStorage.clear();
  }
}
