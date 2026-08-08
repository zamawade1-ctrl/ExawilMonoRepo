import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/transactions_api.dart';
import '../domain/incoming_transaction.dart';

final transactionsApiProvider = Provider(
  (ref) => TransactionsApi(dio: ref.watch(apiClientProvider).dio),
);

final transactionsControllerProvider =
    AsyncNotifierProvider<TransactionsController, List<IncomingTransaction>>(
      TransactionsController.new,
    );

class TransactionsController extends AsyncNotifier<List<IncomingTransaction>> {
  @override
  Future<List<IncomingTransaction>> build() {
    return ref.read(transactionsApiProvider).getMyTransactions();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(transactionsApiProvider).getMyTransactions());
  }
}
