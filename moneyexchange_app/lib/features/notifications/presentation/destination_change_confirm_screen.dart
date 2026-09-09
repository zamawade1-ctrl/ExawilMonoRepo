import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../forwarding/presentation/forwarding_providers.dart';
import '../../security/presentation/require_app_pin.dart';
import 'notifications_providers.dart';

/// The confirmation screen for a pending mobile forwarding-destination change.
/// Shows the old → new numbers with **Confirm** and **Reject** actions. Money is
/// only forwarded to the new number once the user taps Confirm; Reject keeps the
/// old number active. Reached three ways: right after saving a changed number, by
/// tapping the destination-change notification (deep link), and from a Pending
/// row on the Notifications page.
class DestinationChangeConfirmScreen extends ConsumerStatefulWidget {
  const DestinationChangeConfirmScreen({super.key});

  @override
  ConsumerState<DestinationChangeConfirmScreen> createState() =>
      _DestinationChangeConfirmScreenState();
}

class _DestinationChangeConfirmScreenState
    extends ConsumerState<DestinationChangeConfirmScreen> {
  bool _busy = false;

  /// Confirming a destination change ALWAYS requires the app PIN first — this is
  /// the money-redirecting step, so it's gated every time the user taps Confirm.
  /// The prompt is independent of the app-lock toggle in settings and is never
  /// cached/timed: [requireAppPin] re-asks on every confirm (it only skips when no
  /// PIN was ever set). Backing out of the PIN screen leaves the change pending.
  Future<void> _confirm() async {
    final ok = await requireAppPin(
      context,
      ref,
      subtitle: 'Confirm your PIN to change your forwarding number.',
    );
    if (!ok || !mounted) return;
    await _act(confirm: true);
  }

  Future<void> _reject() => _act(confirm: false);

  Future<void> _act({required bool confirm}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(nativeForwardingProvider.notifier);
    try {
      if (confirm) {
        await notifier.confirmDestinationChange();
      } else {
        await notifier.rejectDestinationChange();
      }
      // Refresh the audit trail so the Notifications page reflects the new status.
      await ref.read(destinationChangeLogProvider.notifier).refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            confirm
                ? 'Destination confirmed. Forwarding to the new number is now active.'
                : 'Change rejected. Your previous number stays active.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Something went wrong. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(nativeForwardingProvider).value?.status;
    final hasPending = status?.hasPendingDestinationChange ?? false;
    final oldNumber = status?.pendingOldDestination;
    final newNumber = status?.pendingDestination;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm destination change')),
      body: SafeArea(
        child: hasPending && newNumber != null
            ? _buildPending(theme, oldNumber, newNumber)
            : _buildResolved(theme),
      ),
    );
  }

  Widget _buildResolved(ThemeData theme) {
    // No change is pending (already confirmed/rejected, or resolved elsewhere).
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No change to confirm',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This destination change has already been resolved.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPending(ThemeData theme, String? oldNumber, String newNumber) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'For your security, money will NOT be forwarded to the new number '
                  'until you confirm this change.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Your forwarding number is changing', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        _NumberRow(
          label: 'Current number',
          value: (oldNumber == null || oldNumber.isEmpty) ? 'Not set' : oldNumber,
          icon: Icons.phone_outlined,
          muted: true,
          theme: theme,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Icon(
            Icons.arrow_downward,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        _NumberRow(
          label: 'New number',
          value: newNumber,
          icon: Icons.phone_android,
          muted: false,
          theme: theme,
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _reject,
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.muted,
    required this.theme,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool muted;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final border = muted
        ? theme.colorScheme.outlineVariant
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: muted ? 1 : 1.6),
      ),
      child: Row(
        children: [
          Icon(icon, color: muted ? theme.colorScheme.onSurfaceVariant : border),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
