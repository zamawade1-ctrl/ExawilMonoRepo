import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/forwarding_channel.dart';
import 'forwarding_providers.dart';
import 'widgets/forwarding_section.dart';

/// Standalone "Forwarding mode" card (Android only), the first of the Home
/// tab's forwarding sections. Owns the *when do we check* concern — auto-
/// forward-on-a-timer vs check-only-when-a-message-arrives, and the on/off
/// state. A banner at the top always reflects the currently active mode; saving
/// a mode enables it and pops a success dialog; a "Turn off" action stops it.
class ForwardingModeCard extends ConsumerStatefulWidget {
  const ForwardingModeCard({super.key});

  @override
  ConsumerState<ForwardingModeCard> createState() => _ForwardingModeCardState();
}

class _ForwardingModeCardState extends ConsumerState<ForwardingModeCard> {
  // Defaults to check-messages: the app leads with checking only when money
  // actually arrives rather than dialing on a fixed timer.
  ForwardingMode _selectedMode = ForwardingMode.messageCheck;
  bool _initFromNative = false;
  bool _saving = false;

  static String _modeName(ForwardingMode mode) =>
      mode == ForwardingMode.autoForward ? 'Auto forward' : 'Check messages';

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(nativeForwardingProvider.notifier)
          .saveMode(mode: _selectedMode, enabled: true);
      if (!mounted) return;
      final isAuto = _selectedMode == ForwardingMode.autoForward;
      await showForwardingSuccessDialog(
        context,
        title: '${_modeName(_selectedMode)} enabled',
        message: isAuto
            ? 'Auto forward mode is enabled. Your Zaad balance is checked on a timer and forwarded automatically.'
            : 'Check message mode is activated. Your balance is checked and forwarded whenever a Zaad money-in message arrives.',
      );
      // Auto forward relies on an exact timer that Android suspends in Doze
      // (screen off / locked at night) unless the app is battery-exempt. Nudge
      // for it right after enabling, so the overnight cadence actually holds.
      if (isAuto && mounted) {
        final status = ref.read(nativeForwardingProvider).value?.status;
        if (status != null && !status.ignoringBatteryOptimizations) {
          await ref
              .read(nativeForwardingProvider.notifier)
              .requestIgnoreBatteryOptimizations();
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save the forwarding mode. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _turnOff() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(nativeForwardingProvider.notifier)
          .saveMode(mode: _selectedMode, enabled: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto-forwarding turned off.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Runs one balance-sweep cycle on demand (dial *800#, read balance, forward if
  /// ≥ $1). Only offered in check-messages mode, where there's no timer. The
  /// leftover-balance readout beside it updates a few seconds later once the
  /// result dialog is read, so we re-pull the native status then.
  Future<void> _runSweep() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await const ForwardingChannel().sweepNow();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Balance sweep started')),
      );
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (mounted) ref.read(nativeForwardingProvider.notifier).refresh();
      });
    } on PlatformException {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not start the sweep')),
        );
      }
    }
  }

  /// Show the Doze warning whenever auto-forward is in play (either selected in
  /// the toggle or already the saved mode) and the app isn't battery-exempt yet —
  /// the exact overnight timer silently misfires without the exemption.
  bool _needsBatteryExemption(ForwardingStatus? s) {
    if (s == null || s.ignoringBatteryOptimizations) return false;
    return _selectedMode == ForwardingMode.autoForward ||
        (s.enabled && s.mode == ForwardingMode.autoForward);
  }

  ({IconData icon, String text, SectionBannerTone tone}) _banner(
    ForwardingStatus? s,
  ) {
    if (s == null) {
      return (
        icon: Icons.hourglass_empty,
        text: 'Checking forwarding status…',
        tone: SectionBannerTone.neutral,
      );
    }
    if (!s.enabled) {
      return (
        icon: Icons.pause_circle_outline,
        text:
            'Auto-forwarding is off. Pick a mode below and save to turn it on.',
        tone: SectionBannerTone.neutral,
      );
    }
    if (s.fullyReady) {
      return (
        icon: Icons.check_circle,
        text: '${_modeName(s.mode)} mode is active.',
        tone: SectionBannerTone.active,
      );
    }
    // Enabled but not fully ready: name the piece that's ACTUALLY still missing,
    // so we never tell the user to "finish the destination" when they already did
    // and the real blocker is a permission (e.g. the accessibility service, which
    // resets on a fresh install and must be turned on in Settings).
    final String missing;
    if (!s.hasForwardingCredentials) {
      missing = 'finish the destination below';
    } else if (!s.accessibilityEnabled) {
      missing = 'turn on the e-Xawil accessibility service in Settings';
    } else if (!s.overlayEnabled) {
      missing = 'allow display over other apps';
    } else if (!s.hasSmsPermission || !s.hasCallPermission) {
      missing = 'grant the SMS & phone permissions';
    } else {
      missing = 'finish setup';
    }
    return (
      icon: Icons.info_outline,
      text: '${_modeName(s.mode)} mode selected — $missing to activate it.',
      tone: SectionBannerTone.pending,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(nativeForwardingProvider).value?.status;
    // Prefer the live-streamed leftover balance (pushed the moment a forward
    // completes); fall back to the persisted, refresh-time status value.
    final streamedLeftover = ref.watch(leftoverBalanceStreamProvider).value;
    final leftover = streamedLeftover ?? status?.lastLeftoverBalance;

    // Seed the local selection from the saved native state once it loads.
    if (status != null && !_initFromNative) {
      _selectedMode = status.mode;
      _initFromNative = true;
    }

    final banner = _banner(status);

    return ForwardingSectionCard(
      icon: Icons.tune,
      title: 'Forwarding mode',
      children: [
        SectionStatusBanner(
          icon: banner.icon,
          text: banner.text,
          tone: banner.tone,
        ),
        if (_needsBatteryExemption(status)) ...[
          const SizedBox(height: 12),
          _BatteryOptimizationWarning(
            onAllow: () => ref
                .read(nativeForwardingProvider.notifier)
                .requestIgnoreBatteryOptimizations(),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'How should we check for money?',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<ForwardingMode>(
          // Check messages leads (left) and is the default; auto forward is the
          // timer-based alternative on the right.
          segments: const [
            ButtonSegment(
              value: ForwardingMode.messageCheck,
              label: Text('Check messages'),
              icon: Icon(Icons.sms_outlined),
            ),
            ButtonSegment(
              value: ForwardingMode.autoForward,
              label: Text('Auto forward'),
              icon: Icon(Icons.autorenew),
            ),
          ],
          selected: {_selectedMode},
          onSelectionChanged: _saving
              ? null
              : (selection) => setState(() => _selectedMode = selection.first),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
            if (status?.enabled ?? false) ...[
              const SizedBox(width: 12),
              TextButton(
                onPressed: _saving ? null : _turnOff,
                child: const Text('Turn off'),
              ),
            ],
          ],
        ),
        // The leftover balance + manual "Run sweep" live here, right below the
        // action buttons — only in check-messages mode (auto-forward sweeps on its
        // own timer, so a manual run isn't offered there).
        if (_selectedMode == ForwardingMode.messageCheck) ...[
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _LeftoverBalance(balance: leftover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RunSweepButton(
                    onRun: _saving ? null : _runSweep,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Left column of the sweep row: the balance left on the account after the most
/// recent forward, read off the last result dialog. Shows "—" until the first
/// forward completes.
class _LeftoverBalance extends StatelessWidget {
  const _LeftoverBalance({required this.balance});

  final double? balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = balance == null ? '—' : '\$${balance!.toStringAsFixed(2)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Leftover balance',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Right column of the sweep row: the manual "Run sweep" button.
class _RunSweepButton extends StatelessWidget {
  const _RunSweepButton({required this.onRun});

  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onRun,
      icon: const Icon(Icons.refresh),
      label: const Text('Run sweep'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(double.infinity),
      ),
    );
  }
}

/// Warns that auto-forward's exact overnight timer needs a battery-optimization
/// exemption, with a button that opens the system prompt to grant it.
class _BatteryOptimizationWarning extends StatelessWidget {
  const _BatteryOptimizationWarning({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.battery_alert,
                color: theme.colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Allow this app to ignore battery optimization, or the timer '
                  'may pause when the screen is off or the phone is locked at '
                  'night, delaying forwards.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onAllow,
              child: const Text('Allow'),
            ),
          ),
        ],
      ),
    );
  }
}
