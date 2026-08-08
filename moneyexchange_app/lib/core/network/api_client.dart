import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/session_storage.dart';

/// Thin wrapper around a configured [Dio] instance: base URL set once, the
/// stored JWT (if any) attached to every request automatically, and a 401
/// handler that reports an expired/invalid session so the app can drop to
/// signed-out and re-authenticate instead of surfacing dead-end errors.
class ApiClient {
  ApiClient({
    required SessionStorage sessionStorage,
    void Function()? onUnauthorized,
  }) : _sessionStorage = sessionStorage,
       _onUnauthorized = onUnauthorized,
       _dio = Dio(
         BaseOptions(
           baseUrl: AppConfig.apiBaseUrl,
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 10),
         ),
       ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _sessionStorage.readAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          // A 401 on an authenticated endpoint means a stored token was rejected
          // (expired/invalid): report it once so the session is torn down and the
          // user re-authenticates. Two exclusions:
          //  - the sign-in endpoint itself (a 401 there is a sign-in failure,
          //    handled by the sign-in flow, not a stale session);
          //  - requests that carried NO token — a local, on-device session has no
          //    token, so a 401 from the backend rejecting an anonymous call is
          //    expected and must NOT sign the user out.
          final path = error.requestOptions.path;
          final isAuthEndpoint = path.contains('/api/auth/');
          final hadToken = error.requestOptions.headers.containsKey(
            'Authorization',
          );
          if (error.response?.statusCode == 401 && !isAuthEndpoint && hadToken) {
            _onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final SessionStorage _sessionStorage;
  final void Function()? _onUnauthorized;

  Dio get dio => _dio;
}
