import 'package:dio/dio.dart';

import '../domain/incoming_transaction.dart';

/// Talks to MoneyExchange.Api's /api/incomingmoneytransactions endpoint,
/// already scoped server-side to the signed-in user's own profile.
class TransactionsApi {
  TransactionsApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<IncomingTransaction>> getMyTransactions() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/incomingmoneytransactions');
    final data = response.data!['data'] as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map(IncomingTransaction.fromJson)
        .toList();
  }
}
