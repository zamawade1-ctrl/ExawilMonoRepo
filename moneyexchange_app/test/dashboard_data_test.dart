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

  test('splits forwarded totals by mobile vs bank method', () {
    final txns = [
      fwd(10, DateTime(2026, 8, 9, 9), destination: '634480003'), // mobile
      fwd(15, DateTime(2026, 8, 9, 10), destination: '065112233'), // mobile
      fwd(40, DateTime(2026, 8, 9, 11), method: 1), // bank
      fwd(20, DateTime(2026, 8, 9, 12), method: 1, status: DeviceTxStatus.failed), // bank, failed
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.today), now);

    expect(data.mobileForward.total, 25);
    expect(data.mobileForward.count, 2);
    expect(data.bankForward.total, 40); // failed bank forward excluded
    expect(data.bankForward.count, 1);
  });

  test('bank-only range leaves the mobile split empty', () {
    final txns = [fwd(30, DateTime(2026, 8, 9, 9), method: 1)];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.today), now);

    expect(data.bankForward.count, 1);
    expect(data.mobileForward.isEmpty, isTrue);
    expect(data.mobileForward.total, 0);
  });

  test('received totals split by provider, largest first', () {
    final txns = [
      rx(30, DateTime(2026, 8, 9, 9), provider: 'Zaad'),
      rx(20, DateTime(2026, 8, 9, 10), provider: 'Zaad'),
      rx(80, DateTime(2026, 8, 9, 11), provider: 'eDahab'),
      rx(5, DateTime(2026, 8, 9, 12), provider: null), // -> 'Other'
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.today), now);

    expect(data.providers.map((p) => p.name).toList(), ['eDahab', 'Zaad', 'Other']);
    expect(data.providers.first.total, 80);
    expect(data.providers[1].total, 50); // Zaad aggregated
    expect(data.providers[1].count, 2);
  });

  test('success rate and reliability counts exclude/include failures', () {
    final txns = [
      fwd(10, DateTime(2026, 8, 9, 9)),
      fwd(10, DateTime(2026, 8, 9, 10)),
      fwd(10, DateTime(2026, 8, 9, 11)),
      fwd(10, DateTime(2026, 8, 9, 12), status: DeviceTxStatus.failed),
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.today), now);

    expect(data.forwardedCount, 3);
    expect(data.failedCount, 1);
    expect(data.successRate, closeTo(0.75, 1e-9));
  });

  test('successRate is 1.0 when nothing was attempted', () {
    final data = computeDashboard(const [], const DashboardSelection(DashboardMode.today), now);
    expect(data.successRate, 1.0);
  });

  test('largest forward and average forward reflect successful forwards only', () {
    final txns = [
      fwd(10, DateTime(2026, 8, 9, 9)),
      fwd(40, DateTime(2026, 8, 9, 10)),
      fwd(100, DateTime(2026, 8, 9, 11), status: DeviceTxStatus.failed), // ignored
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.today), now);

    expect(data.largestForward, 40);
    expect(data.averageForward, 25); // (10 + 40) / 2
  });

  test('forwards bucket into parts of the day', () {
    final txns = [
      fwd(5, DateTime(2026, 8, 9, 3)), // Night
      fwd(10, DateTime(2026, 8, 9, 8)), // Morning
      fwd(20, DateTime(2026, 8, 9, 15)), // Afternoon
      fwd(40, DateTime(2026, 8, 9, 20)), // Evening
      fwd(15, DateTime(2026, 8, 9, 21)), // Evening
    ];
    final data = computeDashboard(txns, const DashboardSelection(DashboardMode.today), now);

    expect(data.timeOfDay.map((b) => b.label).toList(),
        ['Night', 'Morning', 'Afternoon', 'Evening']);
    expect(data.timeOfDay[0].total, 5);
    expect(data.timeOfDay[1].total, 10);
    expect(data.timeOfDay[2].total, 20);
    expect(data.timeOfDay[3].total, 55); // two evening forwards
    expect(data.timeOfDay[3].count, 2);
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
