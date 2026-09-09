/// Status of a mobile forwarding-destination change in the on-device audit trail.
/// A change starts [pending] (forwarding is blocked until the user acts) and ends
/// [confirmed] (new number activated) or [rejected] (old number kept).
enum DestinationChangeStatus {
  pending,
  confirmed,
  rejected;

  static DestinationChangeStatus fromWire(String? raw) => switch (raw) {
    'CONFIRMED' => DestinationChangeStatus.confirmed,
    'REJECTED' => DestinationChangeStatus.rejected,
    _ => DestinationChangeStatus.pending,
  };

  String get label => switch (this) {
    DestinationChangeStatus.pending => 'Pending',
    DestinationChangeStatus.confirmed => 'Confirmed',
    DestinationChangeStatus.rejected => 'Rejected',
  };
}

/// One entry in the destination-change audit trail — a security event, NOT a
/// money-ledger transaction (it never affects dashboard totals). Records when a
/// mobile forwarding number was changed, the old→new numbers, and the outcome.
class DestinationChange {
  const DestinationChange({
    required this.id,
    required this.atMs,
    required this.updatedAtMs,
    required this.oldNumber,
    required this.newNumber,
    required this.status,
  });

  final int id;
  final int atMs;
  final int updatedAtMs;
  final String oldNumber;
  final String newNumber;
  final DestinationChangeStatus status;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(atMs);

  /// The old number shown for display — "Not set" when this was a first-time setup.
  String get oldNumberLabel => oldNumber.isEmpty ? 'Not set' : oldNumber;

  static DestinationChange fromMap(Map<Object?, Object?> map) => DestinationChange(
    id: (map['id'] as num?)?.toInt() ?? 0,
    atMs: (map['atMs'] as num?)?.toInt() ?? 0,
    updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
    oldNumber: map['oldNumber'] as String? ?? '',
    newNumber: map['newNumber'] as String? ?? '',
    status: DestinationChangeStatus.fromWire(map['status'] as String?),
  );
}
