/// An activation code an admin minted for this exact account, delivered on the session poll so it
/// appears on the activation page in real time. Present only while the code is still redeemable
/// (unredeemed + unexpired); once the user redeems it the backend stops sending it, so the card
/// clears itself and won't reappear until the admin mints a fresh one.
class PendingActivationCode {
  const PendingActivationCode({
    required this.code,
    required this.planKind,
    required this.durationMinutes,
    required this.expiresAtUtc,
    required this.createdAtUtc,
  });

  /// The redeemable code in human (dashed) form, e.g. `MX-4KPA-9QTR-7WHX`.
  final String code;

  /// Human plan-kind label the code grants ("1 month", "Forever", ...), or null.
  final String? planKind;

  final int durationMinutes;
  final DateTime? expiresAtUtc;
  final DateTime createdAtUtc;

  static DateTime? _parseUtc(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toUtc();

  factory PendingActivationCode.fromJson(Map<String, dynamic> json) =>
      PendingActivationCode(
        code: json['code'] as String,
        planKind: json['planKind'] as String?,
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
        expiresAtUtc: _parseUtc(json['expiresAtUtc']),
        createdAtUtc:
            _parseUtc(json['createdAtUtc']) ?? DateTime.now().toUtc(),
      );

  /// Two pending codes are the "same waiting code" when the code string matches — used so the UI
  /// only reacts (auto-fills, animates) when a genuinely different code arrives.
  @override
  bool operator ==(Object other) =>
      other is PendingActivationCode && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
