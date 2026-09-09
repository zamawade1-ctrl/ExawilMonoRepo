import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/destination_change.dart';
import 'destination_change_confirm_screen.dart';
import 'notifications_providers.dart';

/// The Notifications tab: a durable on-device audit trail of forwarding
/// destination changes (timestamp, old → new numbers, status). Pending entries
/// are tappable and open the confirmation screen. This is a security log, not the
/// money ledger — it never affects the dashboard's Received/Forwarded totals.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key, this.controller});

  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final logAsync = ref.watch(destinationChangeLogProvider);

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(destinationChangeLogProvider.notifier).refresh(),
      child: logAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _EmptyState(
          controller: controller,
          icon: Icons.error_outline,
          title: 'Could not load notifications',
          message: 'Pull down to try again.',
        ),
        data: (changes) {
          if (changes.isEmpty) {
            return _EmptyState(
              controller: controller,
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              message: Platform.isAndroid
                  ? 'When you change your mobile forwarding number, the change '
                        'appears here to confirm.'
                  : 'Destination-change alerts appear here on Android.',
            );
          }
          return ListView.separated(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: changes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) =>
                _ChangeCard(change: changes[i], theme: theme),
          );
        },
      ),
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change, required this.theme});

  final DestinationChange change;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd().add_jm();
    final pending = change.status == DestinationChangeStatus.pending;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Only a still-pending change opens the confirmation screen.
        onTap: pending
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DestinationChangeConfirmScreen(),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.swap_horiz,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Forwarding number changed',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusBadge(status: change.status, theme: theme),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${change.oldNumberLabel}  →  ${change.newNumber}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                dateFormat.format(change.at),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (pending) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tap to review and confirm',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.theme});

  final DestinationChangeStatus status;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      DestinationChangeStatus.pending => (
        theme.colorScheme.tertiaryContainer,
        theme.colorScheme.onTertiaryContainer,
      ),
      DestinationChangeStatus.confirmed => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
      DestinationChangeStatus.rejected => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.controller,
    required this.icon,
    required this.title,
    required this.message,
  });

  final ScrollController? controller;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A scrollable so pull-to-refresh works even when empty.
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Icon(icon, size: 64, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
