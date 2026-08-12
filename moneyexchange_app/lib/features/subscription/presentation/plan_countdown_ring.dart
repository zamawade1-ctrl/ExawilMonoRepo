import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plan_snapshot.dart';
import 'plan_providers.dart';

/// App-bar (top-right) circular countdown: a ring that drains as the current window elapses, with the
/// compact time-left in the middle. Green while on Pro, amber during the trial; hidden when there's no
/// plan or it's expired (an expired user is gated to the activation screen anyway). Ticks every second.
class PlanCountdownRing extends ConsumerStatefulWidget {
  const PlanCountdownRing({super.key});

  @override
  ConsumerState<PlanCountdownRing> createState() => _PlanCountdownRingState();
}

class _PlanCountdownRingState extends ConsumerState<PlanCountdownRing> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
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
    final snapshot = ref.watch(planControllerProvider).value;
    if (snapshot == null || snapshot.status == PlanStatus.expired) {
      return const SizedBox.shrink();
    }

    final isPro = snapshot.status == PlanStatus.pro;
    final ringColor = isPro ? theme.colorScheme.primary : theme.colorScheme.tertiary;
    final progress = snapshot.progressRemaining;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Tooltip(
        message: isPro
            ? 'Pro — ${_long(snapshot.remaining)} left'
            : 'Trial — ${_long(snapshot.remaining)} left',
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  value: progress == 0 ? null : progress,
                  strokeWidth: 3,
                  backgroundColor: ringColor.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation(ringColor),
                ),
              ),
              Text(
                _short(snapshot.remaining),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                  color: ringColor,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Very compact label for inside the ring: "29d", "3h", "2m", or "45s".
  static String _short(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  /// Fuller label for the tooltip: "29d 4h", "3h 12m", or "1:45".
  static String _long(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
