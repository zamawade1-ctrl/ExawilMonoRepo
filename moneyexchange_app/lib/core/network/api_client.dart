import 'dart:io';

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
        onError: (error, handler) async {
          // Dev convenience: if the base URL points at a local/LAN backend and
          // that backend is unreachable (e.g. `dotnet run` was stopped), switch
          // to the live production API and retry the request once — so a local
          // session keeps working against the live server without a rebuild.
          // Only a *connection* failure triggers this (a real HTTP error means
          // the server IS reachable), and only from a local base (production is
          // never masked by a fallback to itself).
          if (_shouldFallBackToProduction(error)) {
            _switchedToProduction = true;
            _dio.options.baseUrl = AppConfig.productionApiBaseUrl;
            try {
              final retry = await _dio.fetch<dynamic>(
                error.requestOptions..baseUrl = AppConfig.productionApiBaseUrl,
              );
              return handler.resolve(retry);
            } catch (_) {
              // Production is also unreachable — fall through to normal handling.
            }
          }
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

  /// Set once we've switched the base URL to production after a local backend
  /// was found unreachable, so we neither retry-loop nor keep re-probing local.
  bool _switchedToProduction = false;

  Dio get dio => _dio;

  /// True when [error] is a *connection* failure (not an HTTP status error)
  /// against a still-local base URL — the only case we transparently retry on
  /// production. A response with any status code means the server was reached.
  bool _shouldFallBackToProduction(DioException error) {
    if (!AppConfig.isLocalApiBase || _switchedToProduction) return false;
    if (error.response != null) return false;
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.unknown:
        return error.error is SocketException;
      default:
        return false;
    }
  }
}
