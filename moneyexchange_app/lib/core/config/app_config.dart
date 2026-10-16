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

  /// The LIVE production backend. Always available as a fallback target — see
  /// [apiBaseUrl] and the connection-failure fallback in `ApiClient`.
  static const String productionApiBaseUrl =
      'https://exawilmonorepo.onrender.com';

  /// Base URL of MoneyExchange.Api. Defaults to the LIVE production backend so
  /// a release build is always pointed at the hosted API even if no
  /// `--dart-define=API_BASE_URL` is passed — there is no dev/localhost fallback
  /// baked into a shipped app. For local development, override it explicitly,
  /// e.g. `--dart-define=API_BASE_URL=http://10.0.2.2:5219` (Android emulator)
  /// or `http://localhost:5219` (iOS simulator / adb reverse).
  ///
  /// Dev convenience: when this points at a local/LAN backend and that backend
  /// is unreachable (e.g. you stopped `dotnet run`), `ApiClient` automatically
  /// falls back to [productionApiBaseUrl] for the rest of the session, so you
  /// can keep using the app against the live server without rebuilding.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: productionApiBaseUrl,
  );

  /// True when [apiBaseUrl] targets a local/LAN development backend (localhost,
  /// the Android-emulator host alias, or a private-network IP) rather than the
  /// hosted production API. Only such a base URL is allowed to fall back to
  /// production on a connection failure — production never "falls back" to
  /// itself, and a real remote outage is surfaced, not masked.
  static bool get isLocalApiBase {
    final host = Uri.tryParse(apiBaseUrl)?.host ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '10.0.2.2' || // Android emulator → host machine
        host == '10.0.3.2') {
      return true;
    }
    // Private-network LAN ranges (physical device over Wi-Fi): 192.168.x.x,
    // 10.x.x.x, and 172.16–31.x.x.
    if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
    final m = RegExp(r'^172\.(\d{1,3})\.').firstMatch(host);
    if (m != null) {
      final second = int.tryParse(m.group(1)!) ?? 0;
      if (second >= 16 && second <= 31) return true;
    }
    return false;
  }

  /// The Web OAuth client ID from Google Cloud Console. This - not the
  /// Android/iOS client ID - is what must be passed as `serverClientId` to
  /// google_sign_in so the returned ID token's audience matches what the
  /// backend validates against (GoogleAuth:Audiences in appsettings.json).
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );
}
