import 'device_transaction.dart';

/// Which slice of history the dashboard charts show. `day` carries a specific
/// picked calendar date; the rest are relative presets.
enum DashboardMode { today, yesterday, week, month, day }

/// The user's dashboard date/day choice — a preset, or a specific [day].
class DashboardSelection {
  const DashboardSelection(this.mode, [this.day]);

  final DashboardMode mode;
  final DateTime? day;

  @override
  bool operator ==(Object other) =>
      other is DashboardSelection &&
      other.mode == mode &&
      other.day?.year == day?.year &&
      other.day?.month == day?.month &&
      other.day?.day == day?.day;

  @override
  int get hashCode => Object.hash(mode, day?.year, day?.month, day?.day);
}

/// One day's received + forwarded totals, for the grouped bar chart.
class DailyPoint {
  const DailyPoint({required this.day, required this.received, required this.forwarded});

  final DateTime day;
  final double received;
  final double forwarded;

  double get max => received > forwarded ? received : forwarded;
}

/// Total forwarded to one destination over the range, for the breakdown chart.
class DestinationTotal {
  const DestinationTotal({required this.destination, required this.total, required this.count});

  final String destination;
  final double total;
  final int count;
}

/// Everything the dashboard renders, computed from the raw on-device ledger.
class DashboardData {
  const DashboardData({
    required this.start,
    required this.end,
    required this.label,
    required this.daily,
    required this.destinations,
    required this.rangeReceived,
    required this.rangeForwarded,
    required this.forwardedCount,
    required this.failedCount,
    required this.todayForwarded,
    required this.weekly,
    required this.weeklyForwarded,
    required this.weeklyReceived,
  });

  final DateTime start; // inclusive
  final DateTime end; // exclusive
  final String label;
  final List<DailyPoint> daily;
  final List<DestinationTotal> destinations;
  final double rangeReceived;
  final double rangeForwarded;
  final int forwardedCount;
  final int failedCount;
  final double todayForwarded;
  final List<DailyPoint> weekly;
  final double weeklyForwarded;
  final double weeklyReceived;

  bool get isEmpty => rangeReceived == 0 && rangeForwarded == 0 && daily.every((d) => d.max == 0);
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// A forward counts toward money totals when it wasn't an outright failure
/// (legacy events with no status are treated as successful).
bool _countsAsForwarded(DeviceTransaction t) =>
    t.isForwarded && t.status != DeviceTxStatus.failed;

/// Pure aggregation of the raw ledger into the dashboard view model. Buckets by
/// local calendar day; the selected range drives the grouped bar chart while the
/// weekly summary always covers the last 7 days. `now` is injected for testability.
DashboardData computeDashboard(
  List<DeviceTransaction> txns,
  DashboardSelection selection,
  DateTime now,
) {
  final today = _startOfDay(now);

  final (start, end, label) = switch (selection.mode) {
    DashboardMode.today => (today, today.add(const Duration(days: 1)), 'Today'),
    DashboardMode.yesterday => (
      today.subtract(const Duration(days: 1)),
      today,
      'Yesterday',
    ),
    DashboardMode.week => (
      today.subtract(const Duration(days: 6)),
      today.add(const Duration(days: 1)),
      'Last 7 days',
    ),
    DashboardMode.month => (
      today.subtract(const Duration(days: 29)),
      today.add(const Duration(days: 1)),
      'Last 30 days',
    ),
    DashboardMode.day => () {
      final d = _startOfDay(selection.day ?? now);
      return (d, d.add(const Duration(days: 1)), 'Selected day');
    }(),
  };

  bool inRange(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  // Bucket per day across the range.
  final dayCount = end.difference(start).inDays.clamp(1, 366);
  final received = <DateTime, double>{};
  final forwarded = <DateTime, double>{};
  final destTotals = <String, double>{};
  final destCounts = <String, int>{};
  var rangeReceived = 0.0;
  var rangeForwarded = 0.0;
  var forwardedCount = 0;
  var failedCount = 0;

  for (final t in txns) {
    final local = t.timestamp.toLocal();
    if (!inRange(local)) continue;
    final key = _startOfDay(local);
    if (t.isReceived) {
      received[key] = (received[key] ?? 0) + t.amountUsd;
      rangeReceived += t.amountUsd;
    } else if (t.isForwarded) {
      if (t.status == DeviceTxStatus.failed) {
        failedCount++;
        continue;
      }
      forwarded[key] = (forwarded[key] ?? 0) + t.amountUsd;
      rangeForwarded += t.amountUsd;
      forwardedCount++;
      final d = t.destinationLabel;
      destTotals[d] = (destTotals[d] ?? 0) + t.amountUsd;
      destCounts[d] = (destCounts[d] ?? 0) + 1;
    }
  }

  final daily = <DailyPoint>[
    for (var i = 0; i < dayCount; i++)
      () {
        final day = start.add(Duration(days: i));
        return DailyPoint(
          day: day,
          received: received[day] ?? 0,
          forwarded: forwarded[day] ?? 0,
        );
      }(),
  ];

  final destinations =
      (destTotals.entries.map(
            (e) => DestinationTotal(
              destination: e.key,
              total: e.value,
              count: destCounts[e.key] ?? 0,
            ),
          ).toList()
        ..sort((a, b) => b.total.compareTo(a.total)));

  // Weekly summary — always the last 7 days, independent of the selection.
  final weekStart = today.subtract(const Duration(days: 6));
  final weekReceived = <DateTime, double>{};
  final weekForwarded = <DateTime, double>{};
  var weeklyForwarded = 0.0;
  var weeklyReceived = 0.0;
  for (final t in txns) {
    final local = t.timestamp.toLocal();
    if (local.isBefore(weekStart) || !local.isBefore(today.add(const Duration(days: 1)))) {
      continue;
    }
    final key = _startOfDay(local);
    if (t.isReceived) {
      weekReceived[key] = (weekReceived[key] ?? 0) + t.amountUsd;
      weeklyReceived += t.amountUsd;
    } else if (_countsAsForwarded(t)) {
      weekForwarded[key] = (weekForwarded[key] ?? 0) + t.amountUsd;
      weeklyForwarded += t.amountUsd;
    }
  }
  final weekly = <DailyPoint>[
    for (var i = 0; i < 7; i++)
      () {
        final day = weekStart.add(Duration(days: i));
        return DailyPoint(
          day: day,
          received: weekReceived[day] ?? 0,
          forwarded: weekForwarded[day] ?? 0,
        );
      }(),
  ];

  // Today's forwarded — always today, drives the live counter tile.
  final todayForwarded = weekForwarded[today] ?? 0;

  return DashboardData(
    start: start,
    end: end,
    label: label,
    daily: daily,
    destinations: destinations,
    rangeReceived: rangeReceived,
    rangeForwarded: rangeForwarded,
    forwardedCount: forwardedCount,
    failedCount: failedCount,
    todayForwarded: todayForwarded,
    weekly: weekly,
    weeklyForwarded: weeklyForwarded,
    weeklyReceived: weeklyReceived,
  );
}
