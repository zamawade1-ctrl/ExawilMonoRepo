import 'package:flutter_test/flutter_test.dart';
import 'package:moneyexchange_app/features/subscription/domain/plan_snapshot.dart';

/// The router gates an expired user to the activation screen by reading [PlanSnapshot.status] live.
/// These tests lock that boundary math (and [reanchored], which the expiry timer emits to fire the
/// redirect) so a Pro/trial window flips to `expired` the moment it lapses — no refetch/logout.
void main() {
  PlanSnapshot proExpiringAt(DateTime paidUntil, {required DateTime serverNow}) => PlanSnapshot(
        // Trial already long gone, so only the paid window matters here.
        trialEndsAtUtc: serverNow.subtract(const Duration(days: 30)),
        planPaidUntilUtc: paidUntil,
        serverNowUtc: serverNow,
        fetchedAtLocal: DateTime.now(),
        planDays: 30,
      );

  test('Pro while the paid window is still in the future', () {
    final now = DateTime.now().toUtc();
    final snap = proExpiringAt(now.add(const Duration(minutes: 5)), serverNow: now);
    expect(snap.status, PlanStatus.pro);
    expect(snap.remaining.inMinutes, greaterThanOrEqualTo(4));
  });

  test('expired once the paid window is in the past', () {
    final now = DateTime.now().toUtc();
    final snap = proExpiringAt(now.subtract(const Duration(seconds: 1)), serverNow: now);
    expect(snap.status, PlanStatus.expired);
    expect(snap.remaining, Duration.zero);
  });

  test('reanchored keeps the same window but re-anchors to now (flips to expired at the boundary)', () {
    // Fetched when the plan had 40ms left, anchored to a serverNow that is now ~in the past.
    final anchor = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
    final snap = PlanSnapshot(
      trialEndsAtUtc: anchor.subtract(const Duration(days: 30)),
      planPaidUntilUtc: anchor.add(const Duration(seconds: 1)), // ended ~1s ago in real time
      serverNowUtc: anchor,
      fetchedAtLocal: DateTime.now().subtract(const Duration(seconds: 2)),
      planDays: 30,
    );

    final re = snap.reanchored();
    // Same absolute window preserved…
    expect(re.planPaidUntilUtc, snap.planPaidUntilUtc);
    // …but re-anchored to the present, where the window has already elapsed → expired.
    expect(re.status, PlanStatus.expired);
  });
}
