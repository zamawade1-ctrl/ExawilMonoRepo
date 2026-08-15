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
  static const _planKey = 'plan_snapshot';

  /// Whether the first-run permission guides (accessibility + "display over
  /// other apps") have been presented once on this install. Device-level
  /// permissions persist across users, so this is intentionally **install-wide**
  /// and NOT cleared on sign-out/[clear] — the guided dialogs should appear only
  /// the first time someone signs up and starts using the app, never re-popping
  /// on later launches. The ongoing nudge for a still-missing permission lives in
  /// the Forwarding mode card's (tappable) banner instead.
  static const _firstRunGuidesKey = 'first_run_guides_shown';

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

  /// Rewrites only the cached profile, leaving the stored token untouched (used
  /// when a profile field changes mid-session, e.g. the user sets their app PIN).
  Future<void> updateUserProfile(Map<String, dynamic> userProfileJson) =>
      _storage.write(key: _userProfileKey, value: jsonEncode(userProfileJson));

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<Map<String, dynamic>?> readUserProfile() async {
    final raw = await _storage.read(key: _userProfileKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Caches the latest plan snapshot (trial/plan timestamps) so the trial
  /// countdown + expiry gate survive a cold start and keep working offline.
  Future<void> savePlan(Map<String, dynamic> planJson) =>
      _storage.write(key: _planKey, value: jsonEncode(planJson));

  Future<Map<String, dynamic>?> readPlan() async {
    final raw = await _storage.read(key: _planKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// True once the first-run permission guides have been shown on this install.
  /// See [_firstRunGuidesKey]: install-wide, survives sign-out.
  Future<bool> hasShownFirstRunGuides() async =>
      (await _storage.read(key: _firstRunGuidesKey)) == 'true';

  /// Records that the first-run permission guides have been presented, so they
  /// never auto-re-pop on later launches.
  Future<void> markFirstRunGuidesShown() =>
      _storage.write(key: _firstRunGuidesKey, value: 'true');

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _userProfileKey);
    await _storage.delete(key: _planKey);
    // NB: _firstRunGuidesKey is deliberately NOT cleared here — the guided
    // permission prompts are once-per-install, not once-per-session.
  }
}
