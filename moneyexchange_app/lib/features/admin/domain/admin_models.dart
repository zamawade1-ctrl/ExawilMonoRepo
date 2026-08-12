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
    required this.plan,
  });

  final int userId;
  final String fullName;
  final String? phone;
  final String role;
  final String? deviceLabel;
  final bool hasDevice;
  final DateTime createdAtUtc;
  final DateTime lastLoginAtUtc;
  final PlanSnapshot plan;

  bool get isAdmin => role.toLowerCase() == 'admin';

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    userId: json['userId'] as int,
    fullName: json['fullName'] as String? ?? '',
    phone: json['phone'] as String?,
    role: json['role'] as String? ?? 'User',
    deviceLabel: json['deviceLabel'] as String?,
    hasDevice: json['hasDevice'] as bool? ?? false,
    createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
    lastLoginAtUtc: DateTime.parse(json['lastLoginAtUtc'] as String).toUtc(),
    plan: PlanSnapshot.fromJson(json['plan'] as Map<String, dynamic>),
  );
}

/// A freshly-minted activation code returned to the admin.
class GeneratedCode {
  const GeneratedCode({
    required this.code,
    required this.durationMinutes,
    this.assignedToPhone,
    this.expiresAtUtc,
  });

  final String code;
  final int durationMinutes;
  final String? assignedToPhone;
  final DateTime? expiresAtUtc;

  factory GeneratedCode.fromJson(Map<String, dynamic> json) => GeneratedCode(
    code: json['code'] as String,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    assignedToPhone: json['assignedToPhone'] as String?,
    expiresAtUtc: json['expiresAtUtc'] == null
        ? null
        : DateTime.parse(json['expiresAtUtc'] as String).toUtc(),
  );
}
