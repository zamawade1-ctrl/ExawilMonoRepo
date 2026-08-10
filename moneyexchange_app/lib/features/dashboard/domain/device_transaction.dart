/// A money event recorded by the on-device forwarder — the real source of truth
/// for the dashboard and Transactions tab (the backend only ever sees the
/// server-side polling fallback, which the on-device USSD/SMS path never uses).
///
/// Mirrors the map recorded by the native `TransactionStore`
/// (android/.../forwarding/TransactionStore.kt).
enum DeviceTxType {
  received,
  forwarded,
  unknown;

  static DeviceTxType fromWire(String? value) => switch (value) {
    'received' => DeviceTxType.received,
    'forwarded' => DeviceTxType.forwarded,
    _ => DeviceTxType.unknown,
  };
}

/// Outcome of a forward. Received events carry no status.
enum DeviceTxStatus {
  success,
  failed,
  none;

  static DeviceTxStatus fromWire(String? value) => switch (value) {
    'success' => DeviceTxStatus.success,
    'failed' => DeviceTxStatus.failed,
    _ => DeviceTxStatus.none,
  };
}

class DeviceTransaction {
  const DeviceTransaction({
    required this.id,
    required this.type,
    required this.amountUsd,
    required this.timestamp,
    this.destination,
    this.method,
    this.status = DeviceTxStatus.none,
    this.provider,
    this.note,
  });

  factory DeviceTransaction.fromMap(Map<Object?, Object?> map) {
    final ms = (map['timestampMs'] as num?)?.toInt() ?? (map['id'] as num?)?.toInt() ?? 0;
    return DeviceTransaction(
      id: (map['id'] as num?)?.toInt() ?? ms,
      type: DeviceTxType.fromWire(map['type'] as String?),
      amountUsd: (map['amountUsd'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ms),
      destination: map['destination'] as String?,
      method: (map['method'] as num?)?.toInt(),
      status: DeviceTxStatus.fromWire(map['status'] as String?),
      provider: map['provider'] as String?,
      note: map['note'] as String?,
    );
  }

  final int id;
  final DeviceTxType type;
  final double amountUsd;
  final DateTime timestamp;
  final String? destination;

  /// 0 = mobile number (`*806#`), 1 = bank account (`*800#` deposit walk).
  final int? method;
  final DeviceTxStatus status;
  final String? provider;
  final String? note;

  bool get isReceived => type == DeviceTxType.received;
  bool get isForwarded => type == DeviceTxType.forwarded;
  bool get isBankMethod => method == 1;

  /// A human label for the destination shown in the Transactions list.
  String get destinationLabel {
    if (destination != null && destination!.isNotEmpty) return destination!;
    return isBankMethod ? 'Bank account' : 'Mobile number';
  }
}
