import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// The anchor time the auto-forward countdown counts from — reset to `now` when
/// the user pulls to refresh (which also runs a sweep), so the bar restarts and
/// the user can see the interval was reset. Auto-wraps each cycle otherwise.
final autoForwardCountdownAnchorProvider =
    StateProvider<DateTime>((ref) => DateTime.now());

/// A live countdown + progress bar showing how long until the next automatic
/// forward. Runs in parallel with the native auto-forward timer: the bar fills
/// over one [intervalSeconds] cycle and, on reaching the end, wraps to the next
/// cycle. Pulling to refresh resets the anchor (see the provider), restarting it.
///
/// Shown below the forwarding-mode section only while auto-forward mode is on.
class AutoForwardCountdown extends ConsumerStatefulWidget {
  const AutoForwardCountdown({super.key, required this.intervalSeconds});

  /// The sweep cadence in seconds — as fast as every 30s.
  final int intervalSeconds;

  @override
  ConsumerState<AutoForwardCountdown> createState() => _AutoForwardCountdownState();
}

/// Formats a cadence (seconds) as "30 seconds" / "1 minute" / "2 minutes".
String _cadenceLabel(int seconds) {
  if (seconds < 60) return '$seconds seconds';
  final minutes = seconds ~/ 60;
  return '$minutes minute${minutes == 1 ? '' : 's'}';
}

class _AutoForwardCountdownState extends ConsumerState<AutoForwardCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 1 Hz repaint so the countdown + bar advance smoothly.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intervalMs = (widget.intervalSeconds.clamp(30, 3600)) * 1000;
    final anchor = ref.watch(autoForwardCountdownAnchorProvider);

    // Elapsed within the current cycle (auto-wrapping every interval).
    final sinceAnchor = DateTime.now().difference(anchor).inMilliseconds;
    final elapsed = sinceAnchor <= 0 ? 0 : sinceAnchor % intervalMs;
    final remainingMs = intervalMs - elapsed;
    final progress = (elapsed / intervalMs).clamp(0.0, 1.0);

    final remaining = Duration(milliseconds: remainingMs);
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

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
              Icon(Icons.timer_outlined,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Next auto-forward',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('$mm:$ss',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your balance is checked every ${_cadenceLabel(widget.intervalSeconds)} '
            'and forwarded automatically. Pull down to refresh — it runs a check '
            'now and resets this timer.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
