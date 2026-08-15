import 'package:dio/dio.dart';

import '../domain/app_update_info.dart';

/// Talks to the PUBLIC (no-auth) `GET /api/app-updates/android` endpoint, which
/// always returns the currently-active Android release (or nothing if none is
/// configured). Uses the shared [Dio], so it inherits the base-URL and the
/// local→production fallback; it sends no Authorization header (the endpoint is
/// anonymous), so it works before sign-in and never triggers a session teardown.
class AppUpdateApi {
  AppUpdateApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// The active Android release, or null when the backend reports none. Throws
  /// on a network/connection failure (the caller treats that as "unknown" and
  /// does NOT force an update — fail-safe).
  Future<AppUpdateInfo?> fetchAndroid() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/app-updates/android',
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) return null;
    return AppUpdateInfo.fromJson(data);
  }
}
