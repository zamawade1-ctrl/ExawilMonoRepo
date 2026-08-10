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

/// Forwarded total for one delivery method (mobile number or bank account) over
/// the range, for the side-by-side destination cards.
class ForwardMethodTotal {
  const ForwardMethodTotal({required this.total, required this.count});

  final double total;
  final int count;

  bool get isEmpty => count == 0;
}

/// Received total for one money provider (Zaad / eDahab) over the range, for the
/// "where money came from" donut.
class ProviderTotal {
  const ProviderTotal({required this.name, required this.total, required this.count});

  final String name;
  final double total;
  final int count;
}

/// Forwarded amount in one part of the day (Night/Morning/Afternoon/Evening),
/// for the time-of-day activity bars. [label] is the bucket name; [range] is a
/// short "6a–12p" style hour label.
class TimeBucket {
  const TimeBucket({
    required this.label,
    required this.range,
    required this.total,
    required this.count,
  });

  final String label;
  final String range;
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
    required this.mobileForward,
    required this.bankForward,
    required this.providers,
    required this.timeOfDay,
    required this.rangeReceived,
    required this.rangeForwarded,
    required this.forwardedCount,
    required this.failedCount,
    required this.largestForward,
    required this.busiestDay,
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

  /// Forwards delivered to a mobile number (`*806#`) over the range.
  final ForwardMethodTotal mobileForward;

  /// Forwards deposited to a bank account (`*800#`) over the range.
  final ForwardMethodTotal bankForward;

  /// Received totals split by money provider (Zaad / eDahab), largest first.
  final List<ProviderTotal> providers;

  /// Forwarded amount bucketed into the four parts of the day.
  final List<TimeBucket> timeOfDay;
  final double rangeReceived;
  final double rangeForwarded;
  final int forwardedCount;
  final int failedCount;

  /// The single largest successful forward in the range (0 if none).
  final double largestForward;

  /// The day in the range with the most forwarded money (null if none).
  final DateTime? busiestDay;
  final double todayForwarded;
  final List<DailyPoint> weekly;
  final double weeklyForwarded;
  final double weeklyReceived;

  bool get isEmpty => rangeReceived == 0 && rangeForwarded == 0 && daily.every((d) => d.max == 0);

  /// Fraction of forward attempts that succeeded (1.0 when none were attempted).
  double get successRate {
    final attempts = forwardedCount + failedCount;
    return attempts == 0 ? 1 : forwardedCount / attempts;
  }

  /// Average value of a successful forward in the range (0 if none).
  double get averageForward =>
      forwardedCount == 0 ? 0 : rangeForwarded / forwardedCount;
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Maps an hour-of-day (0–23) to a part-of-day bucket:
/// 0 Night (0–5), 1 Morning (6–11), 2 Afternoon (12–17), 3 Evening (18–23).
int _timeBucketIndex(int hour) => (hour ~/ 6).clamp(0, 3);

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
  var mobileTotal = 0.0;
  var mobileCount = 0;
  var bankTotal = 0.0;
  var bankCount = 0;
  var largestForward = 0.0;
  final providerTotals = <String, double>{};
  final providerCounts = <String, int>{};
  // Forwarded money bucketed into the four parts of the day (indexes 0..3).
  final tod = <double>[0, 0, 0, 0];
  final todCounts = <int>[0, 0, 0, 0];

  for (final t in txns) {
    final local = t.timestamp.toLocal();
    if (!inRange(local)) continue;
    final key = _startOfDay(local);
    if (t.isReceived) {
      received[key] = (received[key] ?? 0) + t.amountUsd;
      rangeReceived += t.amountUsd;
      final p = (t.provider == null || t.provider!.isEmpty) ? 'Other' : t.provider!;
      providerTotals[p] = (providerTotals[p] ?? 0) + t.amountUsd;
      providerCounts[p] = (providerCounts[p] ?? 0) + 1;
    } else if (t.isForwarded) {
      if (t.status == DeviceTxStatus.failed) {
        failedCount++;
        continue;
      }
      forwarded[key] = (forwarded[key] ?? 0) + t.amountUsd;
      rangeForwarded += t.amountUsd;
      forwardedCount++;
      if (t.amountUsd > largestForward) largestForward = t.amountUsd;
      final bucket = _timeBucketIndex(local.hour);
      tod[bucket] += t.amountUsd;
      todCounts[bucket]++;
      if (t.isBankMethod) {
        bankTotal += t.amountUsd;
        bankCount++;
      } else {
        mobileTotal += t.amountUsd;
        mobileCount++;
      }
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

  final providers =
      (providerTotals.entries.map(
            (e) => ProviderTotal(
              name: e.key,
              total: e.value,
              count: providerCounts[e.key] ?? 0,
            ),
          ).toList()
        ..sort((a, b) => b.total.compareTo(a.total)));

  final timeOfDay = <TimeBucket>[
    TimeBucket(label: 'Night', range: '12–6a', total: tod[0], count: todCounts[0]),
    TimeBucket(label: 'Morning', range: '6a–12p', total: tod[1], count: todCounts[1]),
    TimeBucket(label: 'Afternoon', range: '12–6p', total: tod[2], count: todCounts[2]),
    TimeBucket(label: 'Evening', range: '6p–12a', total: tod[3], count: todCounts[3]),
  ];

  // The day in the range that forwarded the most (null when nothing forwarded).
  DateTime? busiestDay;
  var busiestTotal = 0.0;
  forwarded.forEach((day, total) {
    if (total > busiestTotal) {
      busiestTotal = total;
      busiestDay = day;
    }
  });

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
    mobileForward: ForwardMethodTotal(total: mobileTotal, count: mobileCount),
    bankForward: ForwardMethodTotal(total: bankTotal, count: bankCount),
    providers: providers,
    timeOfDay: timeOfDay,
    rangeReceived: rangeReceived,
    rangeForwarded: rangeForwarded,
    forwardedCount: forwardedCount,
    failedCount: failedCount,
    largestForward: largestForward,
    busiestDay: busiestDay,
    todayForwarded: todayForwarded,
    weekly: weekly,
    weeklyForwarded: weeklyForwarded,
    weeklyReceived: weeklyReceived,
  );
}
