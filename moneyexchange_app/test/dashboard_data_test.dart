import 'package:flutter_test/flutter_test.dart';
import 'package:moneyexchange_app/features/dashboard/domain/dashboard_data.dart';
import 'package:moneyexchange_app/features/dashboard/domain/device_transaction.dart';

void main() {
  // A fixed "now" so relative ranges (today/yesterday/week) are deterministic.
  final now = DateTime(2026, 8, 9, 15, 0); // Sun 9 Aug 2026, 3pm

  DeviceTransaction rx(double amount, DateTime at, {String? provider = 'Zaad'}) =>
      DeviceTransaction(
        id: at.millisecondsSinceEpoch,
        type: DeviceTxType.received,
        amountUsd: amount,
        timestamp: at,
        provider: provider,
      );

  DeviceTransaction fwd(
    double amount,
    DateTime at, {
    String? destination,
    int method = 0,
    DeviceTxStatus status = DeviceTxStatus.success,
  }) =>
      DeviceTransaction(
        id: at.millisecondsSinceEpoch + 1,
        type: DeviceTxType.forwarded,
        amountUsd: amount,
        timestamp: at,
        destination: destination,
        method: method,
        status: status,
      );

  test('today totals received and forwarded, excludes yesterday', () {
    final txns = [
      rx(10, DateTime(2026, 8, 9, 9)),
      fwd(10, DateTime(2026, 8, 9, 9, 1), destination: '634480003'),
      rx(5, DateTime(2026, 8, 8, 9)), // yesterday — excluded
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.today), now);

    expect(data.rangeReceived, 10);
    expect(data.rangeForwarded, 10);
    expect(data.forwardedCount, 1);
    expect(data.todayForwarded, 10);
    expect(data.daily.length, 1);
    expect(data.destinations.single.destination, '634480003');
    expect(data.destinations.single.count, 1);
  });

  test('yesterday selection shows only yesterday', () {
    final txns = [
      rx(7, DateTime(2026, 8, 8, 12)),
      fwd(7, DateTime(2026, 8, 8, 12, 1)),
      fwd(3, DateTime(2026, 8, 9, 12)), // today — excluded from yesterday range
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.yesterday), now);

    expect(data.rangeReceived, 7);
    expect(data.rangeForwarded, 7);
    // todayForwarded is always today regardless of selection.
    expect(data.todayForwarded, 3);
  });

  test('failed forwards are counted but excluded from money totals', () {
    final txns = [
      fwd(20, DateTime(2026, 8, 9, 10), status: DeviceTxStatus.failed),
      fwd(5, DateTime(2026, 8, 9, 11), status: DeviceTxStatus.success),
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.today), now);

    expect(data.rangeForwarded, 5);
    expect(data.forwardedCount, 1);
    expect(data.failedCount, 1);
    expect(data.todayForwarded, 5);
  });

  test('week has 7 daily buckets and aggregates destinations', () {
    final txns = [
      fwd(4, DateTime(2026, 8, 4), destination: 'Bank account', method: 1),
      fwd(6, DateTime(2026, 8, 9), destination: 'Bank account', method: 1),
      fwd(2, DateTime(2026, 8, 9), destination: '634480003'),
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.week), now);

    expect(data.daily.length, 7);
    expect(data.weekly.length, 7);
    expect(data.rangeForwarded, 12);
    // Destinations sorted by total desc: bank (10) before mobile (2).
    expect(data.destinations.first.destination, 'Bank account');
    expect(data.destinations.first.total, 10);
    expect(data.destinations.last.destination, '634480003');
  });

  test('picked day selection isolates that calendar day', () {
    final txns = [
      fwd(9, DateTime(2026, 8, 3, 14)),
      fwd(1, DateTime(2026, 8, 4, 14)),
    ];
    final data = computeDashboard(
      txns,
      DashboardSelection(DashboardMode.day, DateTime(2026, 8, 3)),
      now,
    );

    expect(data.rangeForwarded, 9);
    expect(data.daily.length, 1);
  });
}
