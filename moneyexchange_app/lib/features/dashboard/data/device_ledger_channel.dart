import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/device_transaction.dart';

/// A snapshot of on-device ledger storage usage, for the storage progress bar.
class StorageInfo {
  const StorageInfo({
    required this.count,
    required this.max,
    required this.oldestTimestampMs,
    required this.retentionDays,
  });

  final int count;
  final int max;
  final int oldestTimestampMs;
  final int retentionDays;

  static const StorageInfo empty =
      StorageInfo(count: 0, max: 1000, oldestTimestampMs: 0, retentionDays: 31);

  /// Fraction 0..1 of capacity used, for the progress bar.
  double get usedFraction => max <= 0 ? 0 : (count / max).clamp(0.0, 1.0);

  DateTime? get oldest => oldestTimestampMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(oldestTimestampMs)
      : null;

  factory StorageInfo.fromMap(Map<Object?, Object?> map) => StorageInfo(
        count: (map['count'] as num?)?.toInt() ?? 0,
        max: (map['max'] as num?)?.toInt() ?? 1000,
        oldestTimestampMs: (map['oldestTimestampMs'] as num?)?.toInt() ?? 0,
        retentionDays: (map['retentionDays'] as num?)?.toInt() ?? 31,
      );
}

/// Thin Dart wrapper over the native on-device transaction ledger. Reads the
/// full history via the `xawil/forwarding` method channel and streams newly
/// recorded events over the `xawil/forwarding/events` EventChannel so the
/// dashboard can update live (e.g. today's forwarded total ticking up the moment
/// a forward completes). Android-only; on other platforms there's no on-device
/// forwarder, so [getTransactions] returns empty and [events] is an empty stream.
class DeviceLedgerChannel {
  const DeviceLedgerChannel();

  static const _method = MethodChannel('xawil/forwarding');
  static const _events = EventChannel('xawil/forwarding/events');

  Future<List<DeviceTransaction>> getTransactions() async {
    if (!Platform.isAndroid) return const [];
    final raw = await _method.invokeMethod<List<Object?>>('getTransactions');
    return (raw ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(DeviceTransaction.fromMap)
        .toList(growable: false);
  }

  /// How full the on-device ledger is (count / max) + the retention window, for
  /// the storage progress bar. Returns an empty snapshot off Android.
  Future<StorageInfo> getStorageInfo() async {
    if (!Platform.isAndroid) return StorageInfo.empty;
    final raw = await _method.invokeMethod<Map<Object?, Object?>>('getStorageInfo');
    return StorageInfo.fromMap(raw ?? const {});
  }

  /// "Refresh storage": drops events older than the retention window (keeps the
  /// last month). Returns how many were removed.
  Future<int> clearOldTransactions() async {
    if (!Platform.isAndroid) return 0;
    final removed = await _method.invokeMethod<int>('clearOldTransactions');
    return removed ?? 0;
  }

  /// Emits each transaction the native side records while the app is alive.
  Stream<DeviceTransaction> events() {
    if (!Platform.isAndroid) return const Stream.empty();
    return _events
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => DeviceTransaction.fromMap(e as Map<Object?, Object?>));
  }
}
