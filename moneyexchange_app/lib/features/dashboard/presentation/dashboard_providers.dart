import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_ledger_channel.dart';
import '../domain/dashboard_data.dart';
import '../domain/device_transaction.dart';
import '../domain/sample_ledger.dart';

final deviceLedgerChannelProvider = Provider(
  (ref) => const DeviceLedgerChannel(),
);

/// On-device ledger storage usage (count / max), for the storage progress bar in
/// the dashboard and settings. Recomputed whenever the ledger changes.
final storageInfoProvider = FutureProvider<StorageInfo>((ref) async {
  // Re-read whenever the ledger changes so the bar reflects the latest count.
  ref.watch(deviceLedgerProvider);
  final channel = ref.watch(deviceLedgerChannelProvider);
  return channel.getStorageInfo();
});

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
    // Demo/preview only (--dart-define=SEED_SAMPLE_LEDGER=true): stand in for the
    // native ledger so the dashboard can be exercised without a forwarding device.
    if (kSeedSampleLedger) {
      return sampleLedger()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
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
/// date/day changes. Mobile-number forwards are filtered out (bank-only app now)
/// so no mobile-forwarding data appears in any chart or total.
final dashboardDataProvider = Provider<DashboardData>((ref) {
  final all = ref.watch(deviceLedgerProvider).value ?? const <DeviceTransaction>[];
  final txns = all.where(isDisplayedTransaction).toList();
  final selection = ref.watch(dashboardSelectionProvider);
  return computeDashboard(txns, selection, DateTime.now());
});
