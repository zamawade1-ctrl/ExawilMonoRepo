import 'package:dio/dio.dart';

/// A PIN operation failure carrying a message safe to show the user (the
/// backend's `ServiceResponse.message`, e.g. "Your current PIN is incorrect.").
class PinException implements Exception {
  const PinException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to MoneyExchange.Api's /api/pin endpoints — the server-side store of the
/// custom 6-digit app-lock PIN (kept as a PBKDF2 hash on the User).
class PinApi {
  PinApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Sets the PIN for the first time. Throws [PinException] on failure.
  Future<void> setPin(String pin) => _run(
    () => _dio.post<Map<String, dynamic>>('/api/pin/set', data: {'pin': pin}),
  );

  /// Verifies a PIN server-side. Returns whether it matched.
  Future<bool> verify(String pin) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/pin/verify',
      data: {'pin': pin},
    );
    return response.data?['data'] == true;
  }

  /// Changes the PIN after verifying the current one. Throws [PinException].
  Future<void> updatePin({
    required String currentPin,
    required String newPin,
  }) => _run(
    () => _dio.post<Map<String, dynamic>>(
      '/api/pin/update',
      data: {'currentPin': currentPin, 'newPin': newPin},
    ),
  );

  Future<void> _run(Future<Response<Map<String, dynamic>>> Function() call) async {
    try {
      await call();
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String &&
          (data['message'] as String).isNotEmpty) {
        throw PinException(data['message'] as String);
      }
      if (e.response != null) {
        throw const PinException('Something went wrong. Please try again.');
      }
      throw const PinException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }
}
