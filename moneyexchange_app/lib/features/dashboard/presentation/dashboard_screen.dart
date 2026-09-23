import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/dashboard_data.dart';
import 'dashboard_providers.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/storage_usage_card.dart';

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
          const SizedBox(height: 24),
          _SectionTitle(
            'Forwarded destinations',
            subtitle: data.destinations.isEmpty ? null : data.label,
          ),
          const SizedBox(height: 12),
          if (data.destinations.isEmpty)
            const _EmptyChart(message: 'No forwards in this range yet.')
          else
            // Both methods are supported again: this shows the forward totals per
            // destination for the range (each mobile number, plus "Bank account").
            DestinationsBreakdown(destinations: data.destinations),
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
          const SizedBox(height: 24),
          _SectionTitle('Storage', subtitle: 'On-device transaction records'),
          const SizedBox(height: 12),
          const StorageUsageCard(),
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
        ? _dMMMd.format(selection.day!)
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

/// Shared day-label formatter — built once (DateFormat construction parses locale
/// patterns) rather than on every rebuild of the range selector.
final _dMMMd = DateFormat.MMMd();
