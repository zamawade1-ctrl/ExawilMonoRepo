/// Build-time configuration, passed via `--dart-define` so no secrets or
/// per-environment values are hardcoded in source.
///
/// Example:
/// ```
/// flutter run \
///   --dart-define=API_BASE_URL=http://10.0.2.2:5219 \
///   --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
/// ```
///
/// See CLAUDE.md for where these values come from.
class AppConfig {
  const AppConfig._();

  /// Base URL of MoneyExchange.Api. Defaults to the LIVE production backend so
  /// a release build is always pointed at the hosted API even if no
  /// `--dart-define=API_BASE_URL` is passed — there is no dev/localhost fallback
  /// baked into a shipped app. For local development, override it explicitly,
  /// e.g. `--dart-define=API_BASE_URL=http://10.0.2.2:5219` (Android emulator)
  /// or `http://localhost:5219` (iOS simulator / adb reverse).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://moneyexchaneautoussd.onrender.com',
  );

  /// The Web OAuth client ID from Google Cloud Console. This - not the
  /// Android/iOS client ID - is what must be passed as `serverClientId` to
  /// google_sign_in so the returned ID token's audience matches what the
  /// backend validates against (GoogleAuth:Audiences in appsettings.json).
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );
}
