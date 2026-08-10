import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/dashboard_data.dart';

/// Consistent two-colour encoding used across every dashboard chart:
/// received = tertiary, forwarded = primary. Defined once so the legend, bars,
/// and stat tiles never drift apart.
Color _receivedColor(BuildContext c) => Theme.of(c).colorScheme.tertiary;
Color _forwardedColor(BuildContext c) => Theme.of(c).colorScheme.primary;

final _compact = NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0);
final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

/// Grouped bar chart of received vs forwarded per day over the selected range.
/// A single-day selection shows one group (that day's two bars); a week/month
/// shows one group per day.
class ReceivedForwardedChart extends StatelessWidget {
  const ReceivedForwardedChart({super.key, required this.points});

  final List<DailyPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final received = _receivedColor(context);
    final forwarded = _forwardedColor(context);

    final maxVal = points.fold<double>(0, (m, p) => p.max > m ? p.max : m);
    final maxY = maxVal <= 0 ? 10.0 : (maxVal * 1.25);
    // With many days, label only every Nth to avoid a crowded axis.
    final labelEvery = (points.length / 6).ceil().clamp(1, 999);

    return Column(
      children: [
        _Legend(received: received, forwarded: forwarded),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  getTooltipItem: (group, _, rod, rodIndex) {
                    final p = points[group.x];
                    final isReceived = rodIndex == 0;
                    return BarTooltipItem(
                      '${DateFormat.MMMd().format(p.day)}\n'
                      '${isReceived ? "Received" : "Forwarded"} ${_money.format(rod.toY)}',
                      TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) {
                      if (value == 0 || value >= maxY) return const SizedBox.shrink();
                      return Text(
                        _compact.format(value),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      if (points.length > 1 && i % labelEvery != 0) {
                        return const SizedBox.shrink();
                      }
                      final label = points.length == 1
                          ? DateFormat.MMMd().format(points[i].day)
                          : DateFormat.Md().format(points[i].day);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      _rod(points[i].received, received, maxY),
                      _rod(points[i].forwarded, forwarded, maxY),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  BarChartRodData _rod(double value, Color color, double maxY) => BarChartRodData(
    toY: value,
    color: color,
    width: points.length > 12 ? 5 : 12,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.received, required this.forwarded});

  final Color received;
  final Color forwarded;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _dot(context, received, 'Received'),
        const SizedBox(width: 20),
        _dot(context, forwarded, 'Forwarded'),
      ],
    );
  }

  Widget _dot(BuildContext context, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// The two delivery methods side by side: how much was forwarded to a mobile
/// number vs deposited to a bank account over the range. Both cards always show
/// (a method with no forwards reads $0.00 · 0×) so the split is always visible.
class ForwardDestinationSplit extends StatelessWidget {
  const ForwardDestinationSplit({
    super.key,
    required this.mobile,
    required this.bank,
  });

  final ForwardMethodTotal mobile;
  final ForwardMethodTotal bank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // IntrinsicHeight so the two cards match heights without CrossAxisAlignment
    // .stretch (which would demand an infinite height inside the scrolling list).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _MethodCard(
              label: 'Mobile number',
              icon: Icons.smartphone,
              color: _forwardedColor(context),
              total: mobile,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MethodCard(
              label: 'Bank account',
              icon: Icons.account_balance,
              color: theme.colorScheme.secondary,
              total: bank,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.total,
  });

  final String label;
  final IconData icon;
  final Color color;
  final ForwardMethodTotal total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = !total.isEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.12 : 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: active ? 0.4 : 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money.format(total.total),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: active ? color : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            total.count == 1 ? '1 forward' : '${total.count} forwards',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal proportion bars: how much was forwarded to each destination over
/// the range, largest first. Clearer than a pie for a handful of destinations.
class DestinationsBreakdown extends StatelessWidget {
  const DestinationsBreakdown({super.key, required this.destinations});

  final List<DestinationTotal> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxTotal = destinations.fold<double>(0, (m, d) => d.total > m ? d.total : m);
    final palette = _destinationPalette(theme);

    return Column(
      children: [
        for (var i = 0; i < destinations.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DestinationBar(
              dest: destinations[i],
              fraction: maxTotal <= 0 ? 0 : destinations[i].total / maxTotal,
              color: palette[i % palette.length],
            ),
          ),
      ],
    );
  }

  List<Color> _destinationPalette(ThemeData theme) => [
    theme.colorScheme.primary,
    theme.colorScheme.tertiary,
    theme.colorScheme.secondary,
    theme.colorScheme.primaryContainer,
    theme.colorScheme.tertiaryContainer,
  ];
}

class _DestinationBar extends StatelessWidget {
  const _DestinationBar({required this.dest, required this.fraction, required this.color});

  final DestinationTotal dest;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                dest.destination,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_money.format(dest.total)}  ·  ${dest.count}×',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.02, 1.0),
            minHeight: 10,
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

/// The 7-day summary: a compact line chart of daily forwarded totals plus the
/// week's received/forwarded headline figures.
class WeeklySummaryCard extends StatelessWidget {
  const WeeklySummaryCard({super.key, required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final week = data.weekly;
    final maxVal = week.fold<double>(0, (m, p) => p.forwarded > m ? p.forwarded : m);
    final maxY = maxVal <= 0 ? 10.0 : maxVal * 1.3;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _WeekStat(
                  label: 'Received this week',
                  value: _money.format(data.weeklyReceived),
                  color: _receivedColor(context),
                ),
              ),
              Expanded(
                child: _WeekStat(
                  label: 'Forwarded this week',
                  value: _money.format(data.weeklyForwarded),
                  color: _forwardedColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                    getTooltipItems: (spots) => spots.map((s) {
                      final day = week[s.x.toInt()].day;
                      return LineTooltipItem(
                        '${DateFormat.E().format(day)}  ${_money.format(s.y)}',
                        TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                      );
                    }).toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= week.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat.E().format(week[i].day).substring(0, 1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < week.length; i++)
                        FlSpot(i.toDouble(), week[i].forwarded),
                    ],
                    isCurved: true,
                    color: _forwardedColor(context),
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _forwardedColor(context).withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekStat extends StatelessWidget {
  const _WeekStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Where the money came from: a donut of received totals by provider (Zaad /
/// eDahab), with the range's received total in the middle and a legend beside it.
class ProviderBreakdown extends StatelessWidget {
  const ProviderBreakdown({super.key, required this.providers, required this.total});

  final List<ProviderTotal> providers;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _providerPalette(theme);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    startDegreeOffset: -90,
                    sections: [
                      for (var i = 0; i < providers.length; i++)
                        PieChartSectionData(
                          value: providers[i].total,
                          color: palette[i % palette.length],
                          radius: 22,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _compact.format(total),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'received',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < providers.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _ProviderLegendRow(
                      provider: providers[i],
                      color: palette[i % palette.length],
                      fraction: total <= 0 ? 0 : providers[i].total / total,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _providerPalette(ThemeData theme) => [
    theme.colorScheme.primary,
    theme.colorScheme.tertiary,
    theme.colorScheme.secondary,
    theme.colorScheme.error,
  ];
}

class _ProviderLegendRow extends StatelessWidget {
  const _ProviderLegendRow({
    required this.provider,
    required this.color,
    required this.fraction,
  });

  final ProviderTotal provider;
  final Color color;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            provider.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_money.format(provider.total)}  ·  ${(fraction * 100).round()}%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Forwarding reliability: the share of forward attempts that were delivered vs
/// failed, shown as a headline success rate over a single stacked bar. For a
/// forwarding product this is the trust metric — did the money actually arrive.
class ReliabilityCard extends StatelessWidget {
  const ReliabilityCard({
    super.key,
    required this.successRate,
    required this.delivered,
    required this.failed,
  });

  final double successRate;
  final int delivered;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attempts = delivered + failed;
    final ok = _forwardedColor(context);
    final bad = theme.colorScheme.error;
    final pct = (successRate * 100);
    // Whole number unless a fraction would otherwise round away a real failure.
    final pctLabel = pct == pct.roundToDouble()
        ? '${pct.round()}%'
        : '${pct.toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pctLabel,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: failed == 0 ? ok : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'delivered',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: attempts == 0
                  ? ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    )
                  : Row(
                      children: [
                        if (delivered > 0)
                          Expanded(flex: delivered, child: ColoredBox(color: ok)),
                        if (failed > 0)
                          Expanded(flex: failed, child: ColoredBox(color: bad)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ReliabilityLegend(color: ok, label: 'Delivered', count: delivered),
              const SizedBox(width: 20),
              _ReliabilityLegend(
                color: bad,
                label: 'Failed',
                count: failed,
                muted: failed == 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReliabilityLegend extends StatelessWidget {
  const _ReliabilityLegend({
    required this.color,
    required this.label,
    required this.count,
    this.muted = false,
  });

  final Color color;
  final String label;
  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: muted ? color.withValues(alpha: 0.35) : color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count $label',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// When money actually moves: forwarded totals bucketed into the four parts of
/// the day, so the user can see whether activity peaks in the morning, evening,
/// etc. A compact four-column bar chart.
class TimeOfDayChart extends StatelessWidget {
  const TimeOfDayChart({super.key, required this.buckets});

  final List<TimeBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVal = buckets.fold<double>(0, (m, b) => b.total > m ? b.total : m);
    final peak = maxVal <= 0 ? -1 : buckets.indexWhere((b) => b.total == maxVal);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < buckets.length; i++)
              Expanded(
                child: _TimeBar(
                  bucket: buckets[i],
                  fraction: maxVal <= 0 ? 0 : buckets[i].total / maxVal,
                  highlight: i == peak,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimeBar extends StatelessWidget {
  const _TimeBar({required this.bucket, required this.fraction, required this.highlight});

  final TimeBucket bucket;
  final double fraction;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? _forwardedColor(context)
        : _forwardedColor(context).withValues(alpha: 0.35);

    return Column(
      children: [
        Text(
          bucket.total > 0 ? _compact.format(bucket.total) : '',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Give an empty bucket a hairline so the axis reads as continuous.
              final h = (constraints.maxHeight * fraction).clamp(3.0, constraints.maxHeight);
              return Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 26,
                  height: h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          bucket.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          bucket.range,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
