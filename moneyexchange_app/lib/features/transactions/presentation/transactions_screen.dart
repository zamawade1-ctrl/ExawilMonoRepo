import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../dashboard/domain/dashboard_data.dart';
import '../../dashboard/domain/device_transaction.dart';
import '../../dashboard/presentation/dashboard_providers.dart';

// Built once, not per row per rebuild — DateFormat/NumberFormat construction parses
// locale patterns, which added up across a long transactions list.
final _dateFormat = DateFormat.yMMMd().add_jm();
final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

/// The Transactions tab: the full on-device ledger — every money-in that arrived
/// and every forward the device made — newest first. This is the real record of
/// what the on-device forwarder did (the backend only ever sees the server-side
/// polling fallback, which the USSD/SMS path never uses).
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key, this.controller});

  /// Owned by the home shell so re-tapping the tab can scroll to the top.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deviceLedgerProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(deviceLedgerProvider.notifier).refresh(),
      child: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          onRetry: () => ref.read(deviceLedgerProvider.notifier).refresh(),
        ),
        data: (all) {
          // Bank-only app now: hide mobile-number forwards (a removed feature).
          // Received money-in and bank forwards remain.
          final transactions = all.where(isDisplayedTransaction).toList();
          return transactions.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: transactions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _TransactionTile(transaction: transactions[index]),
                );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('No transactions yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Money received on Zaad and every auto-forward will show up '
                    'here, newest first.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load transactions."),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final DeviceTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReceived = transaction.isReceived;

    final (icon, iconBg, iconFg) = isReceived
        ? (
          Icons.south_west,
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        )
        : (
          Icons.north_east,
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        );

    final title = isReceived
        ? 'Received ${_money.format(transaction.amountUsd)}'
        : 'Forwarded ${_money.format(transaction.amountUsd)}';
    final subtitle = isReceived
        ? (transaction.provider ?? 'Zaad')
        : 'to ${transaction.destinationLabel}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: iconBg,
              child: Icon(icon, color: iconFg, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dateFormat.format(transaction.timestamp.toLocal()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (transaction.isForwarded) _StatusChip(status: transaction.status),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DeviceTxStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (label, background, foreground) = switch (status) {
      DeviceTxStatus.success || DeviceTxStatus.none => (
        'Forwarded',
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
      DeviceTxStatus.failed => (
        'Failed',
        theme.colorScheme.errorContainer,
        theme.colorScheme.onErrorContainer,
      ),
    };

    return Chip(
      label: Text(label),
      backgroundColor: background,
      labelStyle: TextStyle(color: foreground),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
