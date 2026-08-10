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
