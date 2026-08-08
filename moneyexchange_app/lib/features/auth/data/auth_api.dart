import 'package:dio/dio.dart';

import '../domain/app_user.dart';

/// Talks to MoneyExchange.Api's /api/auth endpoints. Knows the wire format
/// (the `ServiceResponse<T>` envelope every endpoint returns), nothing else.
class AuthApi {
  AuthApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Exchanges a Google ID token for our own JWT + user profile.
  /// Returns the access token and the signed-in [AppUser].
  Future<(String accessToken, AppUser user)> signInWithGoogle(
    String idToken,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/google',
      data: {'idToken': idToken},
    );

    final body = response.data!;
    final data = body['data'] as Map<String, dynamic>;
    return (data['accessToken'] as String, AppUser.fromJson(data));
  }

  /// Permanently deletes the signed-in user's account and all associated data.
  /// The JWT is attached automatically by [ApiClient]'s interceptor.
  Future<void> deleteAccount() async {
    await _dio.delete<Map<String, dynamic>>('/api/auth/me');
  }
}
