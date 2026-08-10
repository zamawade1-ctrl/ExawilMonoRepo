import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_ledger_channel.dart';
import '../domain/dashboard_data.dart';
import '../domain/device_transaction.dart';

final deviceLedgerChannelProvider = Provider(
  (ref) => const DeviceLedgerChannel(),
);

/// The on-device transaction ledger, newest-first. Loads the full history from
/// the native store and then listens to the live event stream, prepending each
/// newly recorded transaction so the dashboard/transactions update in real time
/// (e.g. the moment a forward completes) without a manual refresh.
final deviceLedgerProvider =
    AsyncNotifierProvider<DeviceLedgerController, List<DeviceTransaction>>(
      DeviceLedgerController.new,
    );

class DeviceLedgerController extends AsyncNotifier<List<DeviceTransaction>> {
  @override
  Future<List<DeviceTransaction>> build() async {
    final channel = ref.watch(deviceLedgerChannelProvider);

    // Live updates: prepend each native-recorded event as it arrives, deduped by
    // id so a load that races a live event can't double-count.
    final sub = channel.events().listen((tx) {
      final current = state.value ?? const <DeviceTransaction>[];
      if (current.any((t) => t.id == tx.id)) return;
      state = AsyncData([tx, ...current]);
    });
    ref.onDispose(sub.cancel);

    return _load(channel);
  }

  Future<void> refresh() async {
    final channel = ref.read(deviceLedgerChannelProvider);
    state = await AsyncValue.guard(() => _load(channel));
  }

  Future<List<DeviceTransaction>> _load(DeviceLedgerChannel channel) async {
    final all = await channel.getTransactions();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // newest first
    return all;
  }
}

/// The user's selected date/day for the dashboard charts. Defaults to Today.
final dashboardSelectionProvider =
    NotifierProvider<DashboardSelectionController, DashboardSelection>(
      DashboardSelectionController.new,
    );

class DashboardSelectionController extends Notifier<DashboardSelection> {
  @override
  DashboardSelection build() => const DashboardSelection(DashboardMode.today);

  void select(DashboardSelection selection) => state = selection;
}

/// The dashboard view model, recomputed whenever the ledger or the selected
/// date/day changes.
final dashboardDataProvider = Provider<DashboardData>((ref) {
  final txns = ref.watch(deviceLedgerProvider).value ?? const <DeviceTransaction>[];
  final selection = ref.watch(dashboardSelectionProvider);
  return computeDashboard(txns, selection, DateTime.now());
});
