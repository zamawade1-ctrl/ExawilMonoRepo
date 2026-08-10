import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/device_transaction.dart';

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

  /// Emits each transaction the native side records while the app is alive.
  Stream<DeviceTransaction> events() {
    if (!Platform.isAndroid) return const Stream.empty();
    return _events
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => DeviceTransaction.fromMap(e as Map<Object?, Object?>));
  }
}
