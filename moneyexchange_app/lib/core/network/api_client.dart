import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/session_storage.dart';

/// Thin wrapper around a configured [Dio] instance: base URL set once, and
/// the stored JWT (if any) attached to every request automatically.
class ApiClient {
  ApiClient({required SessionStorage sessionStorage})
    : _sessionStorage = sessionStorage,
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
      ),
    );
  }

  final Dio _dio;
  final SessionStorage _sessionStorage;

  Dio get dio => _dio;
}
