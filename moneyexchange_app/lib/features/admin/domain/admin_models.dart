import '../../subscription/domain/plan_snapshot.dart';

/// One row of the admin "all users" view: identity + their live plan snapshot.
class AdminUser {
  const AdminUser({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.deviceLabel,
    required this.hasDevice,
    required this.createdAtUtc,
    required this.lastLoginAtUtc,
    required this.lastModifiedAtUtc,
    required this.planKind,
    required this.plan,
    this.latestCodeGeneratedAtUtc,
    this.latestCodeRedeemed = false,
    this.latestCodeRedeemedAtUtc,
  });

  final int userId;
  final String fullName;
  final String? phone;
  final String role;
  final String? deviceLabel;
  final bool hasDevice;
  final DateTime createdAtUtc;
  final DateTime lastLoginAtUtc;
  final DateTime lastModifiedAtUtc;
  final String? planKind;
  final PlanSnapshot plan;

  /// When the most recent activation code was generated for this account (null if none ever was).
  final DateTime? latestCodeGeneratedAtUtc;

  /// Whether that most recent code has been used. False + a non-null generated-at = "issued, not
  /// used yet" — the plan hasn't started counting because redemption is what starts it.
  final bool latestCodeRedeemed;

  /// When the most recent code was redeemed (the instant the plan duration started), or null.
  final DateTime? latestCodeRedeemedAtUtc;

  bool get isAdmin => role.toLowerCase() == 'admin';

  static DateTime? _parseUtc(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toUtc();

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    userId: json['userId'] as int,
    fullName: json['fullName'] as String? ?? '',
    phone: json['phone'] as String?,
    role: json['role'] as String? ?? 'User',
    deviceLabel: json['deviceLabel'] as String?,
    hasDevice: json['hasDevice'] as bool? ?? false,
    createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
    lastLoginAtUtc: DateTime.parse(json['lastLoginAtUtc'] as String).toUtc(),
    lastModifiedAtUtc: json['lastModifiedAtUtc'] == null
        ? DateTime.parse(json['createdAtUtc'] as String).toUtc()
        : DateTime.parse(json['lastModifiedAtUtc'] as String).toUtc(),
    planKind: json['planKind'] as String?,
    plan: PlanSnapshot.fromJson(json['plan'] as Map<String, dynamic>),
    latestCodeGeneratedAtUtc: _parseUtc(json['latestCodeGeneratedAtUtc']),
    latestCodeRedeemed: json['latestCodeRedeemed'] as bool? ?? false,
    latestCodeRedeemedAtUtc: _parseUtc(json['latestCodeRedeemedAtUtc']),
  );
}

/// A freshly-minted activation code returned to the admin.
class GeneratedCode {
  const GeneratedCode({
    required this.code,
    required this.durationMinutes,
    this.assignedToPhone,
    this.planKind,
    this.expiresAtUtc,
  });

  final String code;
  final int durationMinutes;
  final String? assignedToPhone;
  final String? planKind;
  final DateTime? expiresAtUtc;

  factory GeneratedCode.fromJson(Map<String, dynamic> json) => GeneratedCode(
    code: json['code'] as String,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    assignedToPhone: json['assignedToPhone'] as String?,
    planKind: json['planKind'] as String?,
    expiresAtUtc: json['expiresAtUtc'] == null
        ? null
        : DateTime.parse(json['expiresAtUtc'] as String).toUtc(),
  );
}
