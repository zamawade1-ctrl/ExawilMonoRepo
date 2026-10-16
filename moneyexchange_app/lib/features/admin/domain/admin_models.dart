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
    this.planPriceUsd,
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

  /// USD price of the plan the user redeemed, for the admin billing view. Tells the
  /// $10 and $5 one-month plans apart, and marks a $0 free plan. Null = unpriced/legacy
  /// (the admin billing falls back to the duration-derived price).
  final int? planPriceUsd;

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
    planPriceUsd: (json['planPriceUsd'] as num?)?.toInt(),
    plan: PlanSnapshot.fromJson(json['plan'] as Map<String, dynamic>),
    latestCodeGeneratedAtUtc: _parseUtc(json['latestCodeGeneratedAtUtc']),
    latestCodeRedeemed: json['latestCodeRedeemed'] as bool? ?? false,
    latestCodeRedeemedAtUtc: _parseUtc(json['latestCodeRedeemedAtUtc']),
  );
}

/// One row of the admin billing ledger — a single sale, recorded when an activation code was
/// generated for a customer. Historical (never overwritten), so the billing view shows revenue
/// across every month rather than only each user's current plan.
class BillingRecord {
  const BillingRecord({
    required this.id,
    this.userId,
    this.customerName,
    this.phone,
    this.amountUsd,
    required this.planKind,
    required this.durationMinutes,
    required this.createdAtUtc,
    this.isRedeemed = false,
    this.redeemedAtUtc,
  });

  final int id;
  final int? userId;
  final String? customerName;
  final String? phone;

  /// USD billed. Null = unpriced/legacy (counts as 0); 0 = an explicit free plan.
  final int? amountUsd;
  final String planKind;
  final int durationMinutes;

  /// When the sale was recorded (= when the code was generated). Drives the month/day breakdown.
  final DateTime createdAtUtc;
  final bool isRedeemed;
  final DateTime? redeemedAtUtc;

  factory BillingRecord.fromJson(Map<String, dynamic> json) => BillingRecord(
    id: json['id'] as int,
    userId: (json['userId'] as num?)?.toInt(),
    customerName: json['customerName'] as String?,
    phone: json['phone'] as String?,
    amountUsd: (json['amountUsd'] as num?)?.toInt(),
    planKind: json['planKind'] as String? ?? '',
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
    isRedeemed: json['isRedeemed'] as bool? ?? false,
    redeemedAtUtc: json['redeemedAtUtc'] == null
        ? null
        : DateTime.parse(json['redeemedAtUtc'] as String).toUtc(),
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
