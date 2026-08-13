import 'package:dio/dio.dart';

import '../domain/plan_snapshot.dart';

/// A subscription/activation failure carrying a user-facing message (the
/// backend's `ServiceResponse.message`, e.g. "This activation code has already
/// been used.").
class SubscriptionException implements Exception {
  const SubscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to MoneyExchange.Api's /api/subscription endpoints: the trial/plan status
/// and activation-code redemption.
class SubscriptionApi {
  SubscriptionApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// The signed-in user's current plan snapshot.
  Future<PlanSnapshot> status() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/subscription/status',
    );
    return PlanSnapshot.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  /// The session's live validity + plan, for the fast session poll. [valid] is
  /// false once this [deviceId] no longer matches the account's bound device
  /// (e.g. after an admin device-reset), signalling the app to sign out.
  Future<({bool valid, PlanSnapshot plan})> session(String? deviceId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/subscription/session',
      queryParameters: deviceId == null ? null : {'deviceId': deviceId},
    );
    final data = response.data!['data'] as Map<String, dynamic>;
    return (
      valid: data['valid'] as bool? ?? true,
      plan: PlanSnapshot.fromJson(data['plan'] as Map<String, dynamic>),
    );
  }

  /// Redeems an activation code, returning the new plan snapshot. Throws
  /// [SubscriptionException] with the backend message on failure.
  Future<PlanSnapshot> redeem(String code) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/subscription/redeem',
        data: {'code': code},
      );
      return PlanSnapshot.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw SubscriptionException(_messageFor(e));
    }
  }

  String _messageFor(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String &&
        (data['message'] as String).isNotEmpty) {
      return data['message'] as String;
    }
    if (e.response != null) return 'Something went wrong. Please try again.';
    return 'Could not reach the server. Check your connection and try again.';
  }
}
