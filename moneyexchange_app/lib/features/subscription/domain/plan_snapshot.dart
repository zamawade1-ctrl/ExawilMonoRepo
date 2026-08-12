/// The three access states a user can be in, mirrored from the backend `PlanStatus` enum.
enum PlanStatus { trial, pro, expired }

/// A cached snapshot of the user's trial/plan window, from `/api/subscription/status` (or the auth
/// response). The backend timestamps are absolute; we remember [fetchedAtLocal] and [serverNowUtc]
/// so the countdown keeps ticking accurately offline — the "effective server now" advances with the
/// local clock from the moment we fetched, correcting for any device clock drift.
class PlanSnapshot {
  const PlanSnapshot({
    required this.trialEndsAtUtc,
    required this.planPaidUntilUtc,
    required this.serverNowUtc,
    required this.fetchedAtLocal,
    required this.planDays,
    this.periodStartUtc,
    this.periodEndUtc,
  });

  final DateTime trialEndsAtUtc;
  final DateTime? planPaidUntilUtc;
  final DateTime serverNowUtc;

  /// Local wall-clock time when this snapshot was fetched — the anchor the live countdown advances from.
  final DateTime fetchedAtLocal;
  final int planDays;

  /// Bounds of the currently-active window (trial or Pro), for the progress ring; null when expired.
  final DateTime? periodStartUtc;
  final DateTime? periodEndUtc;

  static DateTime? _parseUtc(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toUtc();

  /// Parses the backend `PlanStatusDto`. [fetchedAtLocal] defaults to now (call time).
  factory PlanSnapshot.fromJson(Map<String, dynamic> json, {DateTime? fetchedAtLocal}) {
    return PlanSnapshot(
      trialEndsAtUtc: DateTime.parse(json['trialEndsAtUtc'] as String).toUtc(),
      planPaidUntilUtc: _parseUtc(json['planPaidUntilUtc']),
      serverNowUtc: DateTime.parse(json['serverNowUtc'] as String).toUtc(),
      fetchedAtLocal: fetchedAtLocal ?? DateTime.now(),
      planDays: (json['planDays'] as num?)?.toInt() ?? 30,
      periodStartUtc: _parseUtc(json['currentPeriodStartUtc']),
      periodEndUtc: _parseUtc(json['currentPeriodEndUtc']),
    );
  }

  Map<String, dynamic> toJson() => {
    'trialEndsAtUtc': trialEndsAtUtc.toIso8601String(),
    'planPaidUntilUtc': planPaidUntilUtc?.toIso8601String(),
    'serverNowUtc': serverNowUtc.toIso8601String(),
    'fetchedAtLocal': fetchedAtLocal.toIso8601String(),
    'planDays': planDays,
    'currentPeriodStartUtc': periodStartUtc?.toIso8601String(),
    'currentPeriodEndUtc': periodEndUtc?.toIso8601String(),
  };

  /// Rebuilds a cached snapshot (keeps the stored [fetchedAtLocal] so the countdown stays anchored).
  factory PlanSnapshot.fromCache(Map<String, dynamic> json) => PlanSnapshot(
    trialEndsAtUtc: DateTime.parse(json['trialEndsAtUtc'] as String).toUtc(),
    planPaidUntilUtc: _parseUtc(json['planPaidUntilUtc']),
    serverNowUtc: DateTime.parse(json['serverNowUtc'] as String).toUtc(),
    fetchedAtLocal: DateTime.parse(json['fetchedAtLocal'] as String),
    planDays: (json['planDays'] as num?)?.toInt() ?? 30,
    periodStartUtc: _parseUtc(json['currentPeriodStartUtc']),
    periodEndUtc: _parseUtc(json['currentPeriodEndUtc']),
  );

  /// The current effective server time: server-now advanced by however long ago we fetched.
  DateTime _effectiveNowUtc() =>
      serverNowUtc.add(DateTime.now().difference(fetchedAtLocal));

  /// A fresh snapshot with the same absolute plan window but re-anchored to *now*, so emitting it
  /// as new state forces listeners (e.g. the router) to re-run even though nothing about the plan
  /// window changed — only that time has moved past a boundary. Used to fire the expiry redirect.
  PlanSnapshot reanchored() => PlanSnapshot(
    trialEndsAtUtc: trialEndsAtUtc,
    planPaidUntilUtc: planPaidUntilUtc,
    serverNowUtc: _effectiveNowUtc(),
    fetchedAtLocal: DateTime.now(),
    planDays: planDays,
    periodStartUtc: periodStartUtc,
    periodEndUtc: periodEndUtc,
  );

  /// Fraction of the current window still remaining (1.0 → full, 0.0 → done), for the progress ring.
  /// Falls back to a remaining-vs-planDays estimate when the server didn't send period bounds.
  double get progressRemaining {
    final start = periodStartUtc;
    final end = periodEndUtc ?? activeUntilUtc;
    if (end == null) return 0;
    final now = _effectiveNowUtc();
    if (start != null && end.isAfter(start)) {
      final total = end.difference(start).inMilliseconds;
      final left = end.difference(now).inMilliseconds;
      return (left / total).clamp(0.0, 1.0);
    }
    // No start bound: approximate against the nominal plan length.
    final total = Duration(days: planDays).inMilliseconds;
    final left = end.difference(now).inMilliseconds;
    return total <= 0 ? 0 : (left / total).clamp(0.0, 1.0);
  }

  /// The instant access is valid through for the current state, or null when already expired.
  DateTime? get activeUntilUtc {
    switch (status) {
      case PlanStatus.pro:
        return planPaidUntilUtc;
      case PlanStatus.trial:
        return trialEndsAtUtc;
      case PlanStatus.expired:
        return null;
    }
  }

  /// The live access state, derived from the timestamps + the (drift-corrected) current time.
  PlanStatus get status {
    final now = _effectiveNowUtc();
    if (planPaidUntilUtc != null && now.isBefore(planPaidUntilUtc!)) {
      return PlanStatus.pro;
    }
    if (now.isBefore(trialEndsAtUtc)) return PlanStatus.trial;
    return PlanStatus.expired;
  }

  /// Time remaining in the current state (zero once expired), for the countdown display.
  Duration get remaining {
    final until = activeUntilUtc;
    if (until == null) return Duration.zero;
    final left = until.difference(_effectiveNowUtc());
    return left.isNegative ? Duration.zero : left;
  }
}
