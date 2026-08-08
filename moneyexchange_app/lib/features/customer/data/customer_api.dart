import 'package:dio/dio.dart';

import '../domain/customer_profile.dart';

/// Talks to MoneyExchange.Api's /api/customers/me endpoints.
class CustomerApi {
  CustomerApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Returns null if the signed-in user hasn't set up a forwarding profile yet.
  Future<CustomerProfile?> getMyProfile() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/api/customers/me');
      final data = response.data!['data'] as Map<String, dynamic>;
      return CustomerProfile.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<CustomerProfile> saveMyProfile(ForwardingProfileInput input) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/customers/me',
      data: input.toJson(),
    );
    final data = response.data!['data'] as Map<String, dynamic>;
    return CustomerProfile.fromJson(data);
  }
}
