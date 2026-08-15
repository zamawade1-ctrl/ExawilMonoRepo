import 'package:dio/dio.dart';

import '../domain/admin_models.dart';

/// An admin operation failure carrying a user-facing message (the backend's
/// `ServiceResponse.message`, e.g. "No account with that phone number.").
class AdminException implements Exception {
  const AdminException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to MoneyExchange.Api's /api/admin endpoints. The admin JWT is attached automatically by the
/// shared [ApiClient] interceptor; a non-admin token gets 403 from the backend (role-gated).
class AdminApi {
  AdminApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// All accounts with their live plan snapshot (the admin dashboard feed).
  Future<List<AdminUser>> listUsers() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/admin/users');
      final list = (response.data!['data'] as List).cast<Map<String, dynamic>>();
      return list.map(AdminUser.fromJson).toList();
    } on DioException catch (e) {
      throw AdminException(_messageFor(e));
    }
  }

  /// Mints [count] activation code(s) bound to [phone], granting [durationMinutes]
  /// (or a forever plan when [forever]), expiring in [expiresInMinutes] (0 = never).
  /// Returns all generated codes.
  Future<List<GeneratedCode>> generateCodes({
    required String phone,
    required int durationMinutes,
    required int expiresInMinutes,
    bool forever = false,
    int count = 1,
    int? priceUsd,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/admin/activation-codes',
        data: {
          'phone': phone,
          'durationMinutes': durationMinutes,
          'expiresInMinutes': expiresInMinutes,
          'forever': forever,
          'count': count,
          // Admin billing amount for this plan; omitted (null) = unpriced.
          'priceUsd': ?priceUsd,
        },
      );
      final list = (response.data!['data'] as List).cast<Map<String, dynamic>>();
      return list.map(GeneratedCode.fromJson).toList();
    } on DioException catch (e) {
      throw AdminException(_messageFor(e));
    }
  }

  /// Forces a user's plan to lapse [inSeconds] from now (0 = immediately).
  Future<void> expirePlan({required String phone, int inSeconds = 0}) =>
      _post('/api/admin/expire-plan', {'phone': phone, 'inSeconds': inSeconds});

  /// Clears a user's device binding so they can sign in on a new phone.
  Future<void> resetDevice({required String phone}) =>
      _post('/api/admin/reset-device', {'phone': phone});

  /// Sets a new password for a user who forgot theirs.
  Future<void> resetPassword({required String phone, required String newPassword}) =>
      _post('/api/admin/reset-password', {'phone': phone, 'newPassword': newPassword});

  /// Corrects a user's mistyped phone number.
  Future<void> updatePhone({required String phone, required String newPhone}) =>
      _post('/api/admin/update-phone', {'phone': phone, 'newPhone': newPhone});

  Future<void> _post(String path, Map<String, dynamic> body) async {
    try {
      await _dio.post<Map<String, dynamic>>(path, data: body);
    } on DioException catch (e) {
      throw AdminException(_messageFor(e));
    }
  }

  String _messageFor(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String && (data['message'] as String).isNotEmpty) {
      return data['message'] as String;
    }
    if (e.response?.statusCode == 403) return 'Admin access required.';
    if (e.response != null) return 'Something went wrong. Please try again.';
    return 'Could not reach the server. Check your connection and try again.';
  }
}
