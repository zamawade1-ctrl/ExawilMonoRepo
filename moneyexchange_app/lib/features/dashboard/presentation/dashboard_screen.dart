import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/dashboard_data.dart';
import 'dashboard_providers.dart';
import 'widgets/dashboard_charts.dart';

/// The signed-in home: an at-a-glance view of money received vs forwarded, the
/// destinations it went to, a weekly summary, and a live "today's forwarded"
/// counter that ticks up the instant a forward completes. All data is the
/// on-device ledger — the real record of what the forwarder actually did.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, this.controller});

  /// Owned by the home shell so tapping the Home tab again scrolls to the top.
  final ScrollController? controller;

  Future<void> _refresh(WidgetRef ref) =>
      ref.read(deviceLedgerProvider.notifier).refresh();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(deviceLedgerProvider);
    final data = ref.watch(dashboardDataProvider);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _RangeSelector(),
          const SizedBox(height: 16),
          _TodayForwardedHero(amount: data.todayForwarded),
          const SizedBox(height: 16),
          _StatRow(data: data),
          const SizedBox(height: 20),
          _SectionTitle('Received vs Forwarded', subtitle: data.label),
          const SizedBox(height: 12),
          if (ledger.isLoading && ledger.value == null)
            const _ChartPlaceholder()
          else if (data.isEmpty)
            const _EmptyChart()
          else
            ReceivedForwardedChart(points: data.daily),
          if (data.forwardedCount > 0) ...[
            const SizedBox(height: 16),
            _InsightsStrip(data: data),
          ],
          const SizedBox(height: 24),
          _SectionTitle(
            'Forwarded destinations',
            subtitle: data.destinations.isEmpty ? null : data.label,
          ),
          const SizedBox(height: 12),
          if (data.destinations.isEmpty)
            const _EmptyChart(message: 'No forwards in this range yet.')
          else ...[
            ForwardDestinationSplit(
              mobile: data.mobileForward,
              bank: data.bankForward,
            ),
            const SizedBox(height: 16),
            DestinationsBreakdown(destinations: data.destinations),
          ],
          if (data.providers.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle('Where money came from', subtitle: data.label),
            const SizedBox(height: 12),
            ProviderBreakdown(
              providers: data.providers,
              total: data.rangeReceived,
            ),
          ],
          if (data.forwardedCount + data.failedCount > 0) ...[
            const SizedBox(height: 24),
            _SectionTitle('Forwarding reliability', subtitle: data.label),
            const SizedBox(height: 12),
            ReliabilityCard(
              successRate: data.successRate,
              delivered: data.forwardedCount,
              failed: data.failedCount,
            ),
          ],
          if (data.forwardedCount > 0) ...[
            const SizedBox(height: 24),
            _SectionTitle('When money moves', subtitle: data.label),
            const SizedBox(height: 12),
            TimeOfDayChart(buckets: data.timeOfDay),
          ],
          const SizedBox(height: 24),
          _SectionTitle('This week', subtitle: 'Last 7 days'),
          const SizedBox(height: 12),
          WeeklySummaryCard(data: data),
        ],
      ),
    );
  }
}

/// The date/day picker: quick presets plus a calendar button for any specific day.
class _RangeSelector extends ConsumerWidget {
  const _RangeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(dashboardSelectionProvider);
    final controller = ref.read(dashboardSelectionProvider.notifier);

    Widget chip(String label, DashboardMode mode) {
      final selected = selection.mode == mode;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => controller.select(DashboardSelection(mode)),
      );
    }

    final pickedLabel = selection.mode == DashboardMode.day && selection.day != null
        ? DateFormat.MMMd().format(selection.day!)
        : 'Pick a day';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip('Today', DashboardMode.today),
        chip('Yesterday', DashboardMode.yesterday),
        chip('Week', DashboardMode.week),
        chip('Month', DashboardMode.month),
        ActionChip(
          avatar: const Icon(Icons.calendar_today, size: 16),
          label: Text(pickedLabel),
          backgroundColor: selection.mode == DashboardMode.day
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: selection.day ?? now,
              firstDate: DateTime(now.year - 2),
              lastDate: now,
            );
            if (picked != null) {
              controller.select(DashboardSelection(DashboardMode.day, picked));
            }
          },
        ),
      ],
    );
  }
}

/// The live counter: today's forwarded total, updated the instant a forward is
/// recorded natively (via the ledger's event stream). The most prominent tile.
class _TodayForwardedHero extends StatelessWidget {
  const _TodayForwardedHero({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.north_east, color: theme.colorScheme.onPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Forwarded today',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // AnimatedSwitcher so the live increment reads as a change, not a jump.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(sizeFactor: anim, axis: Axis.horizontal, child: child),
            ),
            child: Text(
              _money.format(amount),
              key: ValueKey(amount),
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Received',
            value: _money.format(data.rangeReceived),
            icon: Icons.south_west,
            color: theme.colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Forwarded',
            value: _money.format(data.rangeForwarded),
            icon: Icons.north_east,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: data.failedCount > 0 ? '${data.failedCount} failed' : 'Forwards',
            value: '${data.forwardedCount}',
            icon: Icons.swap_horiz,
            color: data.failedCount > 0 ? theme.colorScheme.error : theme.colorScheme.secondary,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact three-tile strip of derived forwarding stats: the average forward
/// size, the single largest forward, and the busiest day — quick context the
/// totals alone don't convey.
class _InsightsStrip extends StatelessWidget {
  const _InsightsStrip({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busiest = data.busiestDay;
    // For a single-day range "busiest day" is trivially that day, so show the
    // count of forwards instead; otherwise show the weekday that moved the most.
    final singleDay = data.end.difference(data.start).inDays <= 1;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Avg forward',
            value: _money.format(data.averageForward),
            icon: Icons.calculate_outlined,
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Largest',
            value: _money.format(data.largestForward),
            icon: Icons.trending_up,
            color: theme.colorScheme.tertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: singleDay ? 'Forwards' : 'Busiest day',
            value: singleDay
                ? '${data.forwardedCount}'
                : (busiest != null ? DateFormat.E().format(busiest) : '—'),
            icon: singleDay ? Icons.swap_horiz : Icons.event_available_outlined,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 200,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insights_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            message ?? 'No activity in this range yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared USD formatter for the dashboard.
final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
