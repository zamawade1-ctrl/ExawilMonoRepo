import 'package:dio/dio.dart';

import '../domain/app_user.dart';

/// The parsed result of a sign-up / sign-in: the token, the user, and the raw
/// `plan` object (trial/plan snapshot) the backend returns alongside them.
typedef AuthResult = (String accessToken, AppUser user, Map<String, dynamic>? planJson);

/// Talks to MoneyExchange.Api's /api/auth endpoints. Knows the wire format
/// (the `ServiceResponse<T>` envelope every endpoint returns), nothing else.
class AuthApi {
  AuthApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Signs up with full name + phone number + password. Returns the access token,
  /// the newly-registered [AppUser], and the initial plan snapshot.
  Future<AuthResult> register({
    required String fullName,
    required String phoneNumber,
    required String password,
    String? deviceId,
    String? deviceLabel,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'password': password,
        'deviceId': ?deviceId,
        'deviceLabel': ?deviceLabel,
      },
    );
    return _parseAuth(response);
  }

  /// Signs in with a phone number + password. Returns the access token, the
  /// signed-in [AppUser], and the current plan snapshot. The device id binds the
  /// account to this phone (a mismatch is rejected by the backend).
  Future<AuthResult> login({
    required String phoneNumber,
    required String password,
    String? deviceId,
    String? deviceLabel,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {
        'phoneNumber': phoneNumber,
        'password': password,
        'deviceId': ?deviceId,
        'deviceLabel': ?deviceLabel,
      },
    );
    return _parseAuth(response);
  }

  AuthResult _parseAuth(Response<Map<String, dynamic>> response) {
    final data = response.data!['data'] as Map<String, dynamic>;
    return (
      data['accessToken'] as String,
      AppUser.fromAuthResponse(data),
      data['plan'] as Map<String, dynamic>?,
    );
  }

  /// Changes the signed-in user's own password (current + new). Throws on failure.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/auth/password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  /// Turns the app-lock PIN on/off. Returns a fresh session (token + updated user + plan).
  Future<AuthResult> setPinEnabled(bool enabled) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/pin-enabled',
      data: {'enabled': enabled},
    );
    return _parseAuth(response);
  }

  /// Permanently deletes the signed-in customer's account and all associated
  /// data. The JWT is attached automatically by [ApiClient]'s interceptor.
  Future<void> deleteAccount() async {
    await _dio.delete<Map<String, dynamic>>('/api/auth/me');
  }
}
