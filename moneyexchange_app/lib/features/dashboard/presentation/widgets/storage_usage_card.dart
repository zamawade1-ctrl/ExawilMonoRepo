import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/device_ledger_channel.dart';
import '../dashboard_providers.dart';

/// Shows how full the on-device transaction ledger is as a progress bar
/// (received + forwarded events out of the native cap), with an optional
/// "Refresh storage" action that keeps only the last month.
///
/// Used both on the dashboard (read-only) and in Settings (with the clear
/// action, [showClear] = true).
class StorageUsageCard extends ConsumerWidget {
  const StorageUsageCard({super.key, this.showClear = false});

  /// When true, renders the "Refresh storage" button + last-month note.
  final bool showClear;

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Refresh storage?'),
        content: const Text(
          'This clears older transactions and keeps only the last month. '
          'Your recent history stays; older records are permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final removed =
        await ref.read(deviceLedgerChannelProvider).clearOldTransactions();
    ref.invalidate(storageInfoProvider);
    await ref.read(deviceLedgerProvider.notifier).refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed == 0
                ? 'Storage is already within the last month.'
                : 'Cleared $removed older transaction${removed == 1 ? '' : 's'}.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final infoAsync = ref.watch(storageInfoProvider);
    final info = infoAsync.value ?? StorageInfo.empty;
    final pct = (info.usedFraction * 100).round();

    // Green normally, amber past 80% so the user knows to refresh soon.
    final barColor = info.usedFraction >= 0.8
        ? const Color(0xFFC98A00)
        : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sd_storage_outlined,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('On-device storage',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('$pct%',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: barColor, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: info.usedFraction,
              minHeight: 9,
              backgroundColor: barColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${info.count} of ${info.max} records stored'
            '${info.oldest != null ? ' · oldest ${_ago(info.oldest!)}' : ''}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (showClear) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _clear(context, ref),
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: const Text('Refresh storage'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Keeps only the last month of transactions; older records are removed.',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays >= 1) return '${d.inDays}d ago';
    if (d.inHours >= 1) return '${d.inHours}h ago';
    return '${d.inMinutes}m ago';
  }
}
