import 'package:dio/dio.dart';

import '../domain/app_user.dart';

/// Talks to MoneyExchange.Api's /api/auth endpoints. Knows the wire format
/// (the `ServiceResponse<T>` envelope every endpoint returns), nothing else.
class AuthApi {
  AuthApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Signs up with full name + email + username + password. Returns the access
  /// token and the newly-registered [AppUser].
  Future<(String accessToken, AppUser user)> register({
    required String fullName,
    required String email,
    required String username,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {
        'fullName': fullName,
        'email': email,
        'username': username,
        'password': password,
      },
    );
    return _parseAuth(response);
  }

  /// Signs in with a username-or-email + password. Returns the access token and
  /// the signed-in [AppUser].
  Future<(String accessToken, AppUser user)> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'usernameOrEmail': usernameOrEmail, 'password': password},
    );
    return _parseAuth(response);
  }

  (String, AppUser) _parseAuth(Response<Map<String, dynamic>> response) {
    final data = response.data!['data'] as Map<String, dynamic>;
    return (data['accessToken'] as String, AppUser.fromAuthResponse(data));
  }

  /// Permanently deletes the signed-in customer's account and all associated
  /// data. The JWT is attached automatically by [ApiClient]'s interceptor.
  Future<void> deleteAccount() async {
    await _dio.delete<Map<String, dynamic>>('/api/auth/me');
  }
}
