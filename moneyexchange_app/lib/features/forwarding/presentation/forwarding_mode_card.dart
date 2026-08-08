import 'package:flutter/material.dart';
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
    return (
      icon: Icons.info_outline,
      text:
          '${_modeName(s.mode)} mode selected — finish the destination below to activate it.',
      tone: SectionBannerTone.pending,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ref.watch(nativeForwardingProvider).value?.status;

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
        const SizedBox(height: 8),
        Text(
          _selectedMode == ForwardingMode.autoForward
              ? 'Checks your balance on a timer, whether or not money has arrived. '
                    'Set how often under the destination below.'
              : 'Only checks your balance when a Zaad message says money arrived — '
                    'no periodic dialing.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
      ],
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
