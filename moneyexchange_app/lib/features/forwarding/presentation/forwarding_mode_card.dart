import 'dart:async';

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

  /// True while a manual "Run sweep" is dialing/forwarding — drives the button's
  /// "Running…" label + disabled state. Cleared when the sweep reports a fresh
  /// balance on the leftover stream (its completion signal) or [_sweepTimeout] fires.
  bool _sweeping = false;
  Timer? _sweepTimeout;

  @override
  void dispose() {
    _sweepTimeout?.cancel();
    super.dispose();
  }

  static String _modeName(ForwardingMode mode) =>
      mode == ForwardingMode.autoForward ? 'Auto forward' : 'Check messages';

  /// Selecting a mode card IS the action now (there's no Save button): it turns
  /// the chosen mode on immediately and pops the success dialog. Tapping the mode
  /// that's already active just re-confirms it. Ignored while a save is in flight.
  Future<void> _selectMode(ForwardingMode mode) async {
    if (_saving) return;
    setState(() => _selectedMode = mode);
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(nativeForwardingProvider.notifier)
          .saveMode(mode: _selectedMode, enabled: true);
      if (!mounted) return;
      final isAuto = _selectedMode == ForwardingMode.autoForward;
      // Stamp the activation time into the success message so the user can see
      // exactly when this mode went live.
      final activatedAt = TimeOfDay.now().format(context);
      final detail = isAuto
          ? 'Auto forward mode is enabled. Your Zaad balance is checked on a timer and forwarded automatically.'
          : 'Check message mode is activated. Your balance is checked and forwarded whenever a Zaad money-in message arrives.';
      await showForwardingSuccessDialog(
        context,
        title: '${_modeName(_selectedMode)} enabled',
        message: '$detail\n\nActivated at $activatedAt.',
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

  /// Runs one balance-sweep cycle on demand (dial *800#, read balance, forward if
  /// ≥ $1) — a manual auto-forward. Offered in check-messages mode, where there's
  /// no timer, so the user can trigger a full sweep + forward by hand. While it
  /// runs, the button shows "Running…" and is disabled ([_sweeping]); it clears when
  /// the fresh balance lands on the leftover stream, or a safety timeout fires.
  Future<void> _runSweep() async {
    final messenger = ScaffoldMessenger.of(context);
    // Run sweep is a no-op natively unless forwarding is switched on AND fully
    // configured (the native side gates on isReady()). Silently doing nothing is
    // confusing — if it isn't ready, say why instead of firing a dead sweep.
    final status = ref.read(nativeForwardingProvider).value?.status;
    if (status != null && !status.fullyReady) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            status.enabled
                ? 'Finish forwarding setup first, then run a sweep.'
                : 'Turn forwarding on first — tap Save, then run a sweep.',
          ),
        ),
      );
      return;
    }
    // Below $1 there's nothing to forward (the native sweep floors at $1), so don't
    // enter the "Running…" state for a no-op — tell the user instead. Uses the same
    // balance the readout shows (and that the native fast sweep will act on).
    final known =
        ref.read(leftoverBalanceStreamProvider).value ??
        status?.lastLeftoverBalance;
    if (known != null && known < 1.0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Balance is below \$1.00 — nothing to sweep.'),
        ),
      );
      return;
    }

    setState(() => _sweeping = true);
    // Safety backstop: clear the running state even if no balance ever comes back
    // (a failed/again-below-$1 sweep), so the button can't stay stuck on "Running…".
    _sweepTimeout?.cancel();
    _sweepTimeout = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _sweeping = false);
    });
    try {
      await const ForwardingChannel().sweepNow();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Running the sweep…')),
      );
      // The leftover readout updates live via the balance stream the moment the
      // forward completes; this delayed status re-pull is a fallback, timed to land
      // after a single-session fast sweep (~15s) has finished.
      Future<void>.delayed(const Duration(seconds: 16), () {
        if (mounted) ref.read(nativeForwardingProvider.notifier).refresh();
      });
    } on PlatformException {
      if (mounted) {
        setState(() => _sweeping = false);
        _sweepTimeout?.cancel();
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

    // While a pull-to-refresh is dialing the *800# balance check, the Run sweep
    // button is disabled (below). A fresh balance landing on the stream is the "done"
    // signal for BOTH a pull-to-refresh and a manual sweep, so clear both busy states
    // on it: the refresh in-progress flag and the local [_sweeping] "Running…" state.
    final refreshingBalance = ref.watch(balanceRefreshInProgressProvider);
    ref.listen<AsyncValue<double>>(leftoverBalanceStreamProvider, (_, next) {
      next.whenData((_) {
        ref.read(balanceRefreshInProgressProvider.notifier).complete();
        if (_sweeping) {
          _sweepTimeout?.cancel();
          setState(() => _sweeping = false);
        }
      });
    });

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
        // Two side-by-side radio cards: the selected one fills green with white
        // text; the other stays neutral. Check messages leads (left) and is the
        // default; auto forward is the timer-based alternative on the right.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ModeRadioCard(
                  icon: Icons.sms_outlined,
                  label: 'Check messages',
                  selected: _selectedMode == ForwardingMode.messageCheck,
                  onTap: _saving
                      ? null
                      : () => _selectMode(ForwardingMode.messageCheck),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ModeRadioCard(
                  icon: Icons.autorenew,
                  label: 'Auto forward',
                  selected: _selectedMode == ForwardingMode.autoForward,
                  onTap: _saving
                      ? null
                      : () => _selectMode(ForwardingMode.autoForward),
                ),
              ),
            ],
          ),
        ),
        // The leftover balance + manual "Run sweep" live here, right below the
        // mode cards — only in check-messages mode (auto-forward sweeps on its
        // own timer, so a manual run isn't offered there). Run sweep dials *800#
        // and forwards the balance — a manual auto-forward. The leftover readout no
        // longer carries its own refresh button: pull down (swipe-to-refresh) on
        // this screen to re-read the balance via *800# (see _ForwardingTab._refresh).
        if (_selectedMode == ForwardingMode.messageCheck) ...[
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _LeftoverBalance(balance: leftover)),
                const SizedBox(width: 12),
                Expanded(
                  child: _RunSweepButton(
                    // Disabled while a sweep is running ("Running…") or a pull-to-
                    // refresh balance check is dialing *800# ("Refreshing…"), so a
                    // sweep can't start on top of an in-flight USSD operation.
                    onRun: (_saving || _sweeping || refreshingBalance)
                        ? null
                        : _runSweep,
                    busy: _sweeping || refreshingBalance,
                    label: _sweeping
                        ? 'Running…'
                        : (refreshingBalance ? 'Refreshing…' : 'Run sweep'),
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
/// recent forward / balance check. Shows just the amount ("—" until the first
/// read) with no labels. Refreshed by pulling down (swipe-to-refresh) on the
/// screen — which re-reads the balance via *800# without forwarding.
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
      alignment: Alignment.center,
      child: Text(
        text,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// One selectable "forwarding mode" card in the two-up radio row. The selected
/// card fills with the brand green and flips its icon/label/radio to white; an
/// unselected card stays on a neutral surface with an outline. Tapping it selects
/// the mode (the same effect the old SegmentedButton segment had). Passing a null
/// [onTap] disables it (while a save is in flight).
class _ModeRadioCard extends StatelessWidget {
  const _ModeRadioCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Selected: green fill, white foreground. Unselected: neutral surface with an
    // outline and normal foreground.
    final Color background = selected
        ? scheme.primary
        : scheme.surfaceContainerHighest;
    final Color foreground = selected ? Colors.white : scheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: foreground, size: 22),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? Colors.white
                        : scheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right column of the sweep row: the manual "Run sweep" button. Dials *800# and
/// forwards the balance — a manual auto-forward (check-messages mode only).
class _RunSweepButton extends StatelessWidget {
  const _RunSweepButton({
    required this.onRun,
    required this.label,
    this.busy = false,
  });

  final VoidCallback? onRun;

  /// The button caption: "Run sweep" when idle, "Running…" during a sweep,
  /// "Refreshing…" while a pull-to-refresh balance check is dialing.
  final String label;

  /// True while a USSD operation is in flight: the button is disabled and shows a
  /// spinner in place of its icon so it's clear it's busy.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onRun,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
      label: Text(label),
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
