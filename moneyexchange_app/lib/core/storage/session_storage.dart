import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the signed-in session (JWT + a lightweight cached profile) in the
/// platform keystore/keychain - never in SharedPreferences or plain files.
///
/// The profile is cached alongside the token purely so the app can restore
/// "who's signed in" on cold start without an extra network round trip;
/// there's no `/api/me` endpoint yet.
class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const _userProfileKey = 'user_profile';

  final FlutterSecureStorage _storage;

  /// Persists the session. [accessToken] is optional: a local, on-device session
  /// (created when the backend is unreachable at sign-in) stores just the cached
  /// profile and no token. Passing a null token clears any previously stored one
  /// so a stale token can't linger under a token-less session.
  Future<void> save({
    String? accessToken,
    required Map<String, dynamic> userProfileJson,
  }) async {
    if (accessToken != null) {
      await _storage.write(key: _accessTokenKey, value: accessToken);
    } else {
      await _storage.delete(key: _accessTokenKey);
    }
    await _storage.write(
      key: _userProfileKey,
      value: jsonEncode(userProfileJson),
    );
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<Map<String, dynamic>?> readUserProfile() async {
    final raw = await _storage.read(key: _userProfileKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _userProfileKey);
  }
}
