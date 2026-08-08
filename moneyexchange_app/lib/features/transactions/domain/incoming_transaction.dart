/// Mirrors MoneyProvider in Models/Entities/IncomingMoneyTransaction.cs.
enum MoneyProvider {
  zaad,
  eDahab;

  static MoneyProvider fromWire(int value) => MoneyProvider.values[value];

  String get label => switch (this) {
    MoneyProvider.zaad => 'Zaad',
    MoneyProvider.eDahab => 'eDahab',
  };
}

/// Mirrors ForwardStatus in Models/Entities/IncomingMoneyTransaction.cs.
enum ForwardStatus {
  pending,
  forwarded,
  failed,
  unmatched;

  static ForwardStatus fromWire(int value) => ForwardStatus.values[value];
}

/// A USD receipt from Zaad/eDahab and what happened when we tried to forward it.
class IncomingTransaction {
  const IncomingTransaction({
    required this.id,
    required this.provider,
    required this.senderPhoneNumber,
    required this.amountUsd,
    required this.forwardStatus,
    required this.receivedAt,
    this.forwardNote,
    this.forwardedAt,
  });

  factory IncomingTransaction.fromJson(Map<String, dynamic> json) => IncomingTransaction(
    id: json['id'] as int,
    provider: MoneyProvider.fromWire(json['provider'] as int),
    senderPhoneNumber: json['senderPhoneNumber'] as String,
    amountUsd: (json['amountUsd'] as num).toDouble(),
    forwardStatus: ForwardStatus.fromWire(json['forwardStatus'] as int),
    receivedAt: DateTime.parse(json['receivedAt'] as String),
    forwardNote: json['forwardNote'] as String?,
    forwardedAt: json['forwardedAt'] == null ? null : DateTime.parse(json['forwardedAt'] as String),
  );

  final int id;
  final MoneyProvider provider;
  final String senderPhoneNumber;
  final double amountUsd;
  final ForwardStatus forwardStatus;
  final DateTime receivedAt;
  final String? forwardNote;
  final DateTime? forwardedAt;
}
