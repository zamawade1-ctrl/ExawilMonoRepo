import 'device_transaction.dart';

/// Whether to replace the (empty) native ledger with demo transactions. Off by
/// default; enable for a screenshot/preview build with:
///   flutter run --dart-define=SEED_SAMPLE_LEDGER=true
/// This never ships in a normal build — it exists only to exercise the dashboard
/// (destination split, provider mix, reliability, time-of-day, insights) without
/// a live forwarding device.
const bool kSeedSampleLedger = bool.fromEnvironment('SEED_SAMPLE_LEDGER');

/// A handful of demo transactions spanning today and the past few days. Exercises
/// every dashboard view: both delivery methods (mobile + bank), both providers
/// (Zaad + eDahab), a failed forward (so reliability isn't a flat 100%), and
/// forwards spread across the day (so the time-of-day chart has shape).
List<DeviceTransaction> sampleLedger([DateTime? now]) {
  final base = now ?? DateTime.now();
  DateTime at(int daysAgo, int hour) =>
      DateTime(base.year, base.month, base.day, hour).subtract(Duration(days: daysAgo));

  var id = 1000;
  DeviceTransaction received(double amount, DateTime ts, {String provider = 'Zaad'}) =>
      DeviceTransaction(
        id: id++,
        type: DeviceTxType.received,
        amountUsd: amount,
        timestamp: ts,
        provider: provider,
      );
  DeviceTransaction toMobile(double amount, DateTime ts, String number) =>
      DeviceTransaction(
        id: id++,
        type: DeviceTxType.forwarded,
        amountUsd: amount,
        timestamp: ts,
        destination: number,
        method: 0,
        status: DeviceTxStatus.success,
      );
  DeviceTransaction toBank(double amount, DateTime ts) => DeviceTransaction(
    id: id++,
    type: DeviceTxType.forwarded,
    amountUsd: amount,
    timestamp: ts,
    method: 1,
    status: DeviceTxStatus.success,
  );
  DeviceTransaction failedForward(double amount, DateTime ts, String number) =>
      DeviceTransaction(
        id: id++,
        type: DeviceTxType.forwarded,
        amountUsd: amount,
        timestamp: ts,
        destination: number,
        method: 0,
        status: DeviceTxStatus.failed,
      );

  return [
    // Today — both methods, both providers, times across the day, one failure.
    received(50, at(0, 8), provider: 'Zaad'), // morning
    toMobile(50, at(0, 8), '063 4567890'),
    received(120, at(0, 11), provider: 'eDahab'), // morning
    toBank(120, at(0, 11)),
    received(35, at(0, 14), provider: 'Zaad'), // afternoon
    toMobile(35, at(0, 14), '065 1122334'),
    received(80, at(0, 19), provider: 'eDahab'), // evening
    toBank(80, at(0, 19)),
    received(25, at(0, 21), provider: 'Zaad'), // evening — this forward fails
    failedForward(25, at(0, 21), '063 4567890'),
    // Earlier this week.
    received(60, at(1, 10), provider: 'Zaad'),
    toMobile(60, at(1, 10), '063 4567890'),
    received(200, at(2, 13), provider: 'eDahab'),
    toBank(200, at(2, 13)),
    received(45, at(3, 16), provider: 'Zaad'),
    toMobile(45, at(3, 16), '065 1122334'),
  ];
}
