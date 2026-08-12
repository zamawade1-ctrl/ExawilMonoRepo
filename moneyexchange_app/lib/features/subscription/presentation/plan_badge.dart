import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plan_snapshot.dart';
import 'plan_providers.dart';

/// The app-bar plan indicator (top-left): a solid green "PRO" pill on a paid plan,
/// or a "Trial m:ss" pill with a live countdown during the free trial. Hidden when
/// there's no plan yet or the plan has expired (an expired user is gated to the
/// activation screen anyway). Ticks once a second so the trial countdown stays live.
class PlanBadge extends ConsumerStatefulWidget {
  const PlanBadge({super.key});

  @override
  ConsumerState<PlanBadge> createState() => _PlanBadgeState();
}

class _PlanBadgeState extends ConsumerState<PlanBadge> {
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
    if (snapshot == null) return const SizedBox.shrink();

    switch (snapshot.status) {
      case PlanStatus.pro:
        return _Pill(
          icon: Icons.workspace_premium,
          label: 'PRO',
          background: theme.colorScheme.primary,
          foreground: Colors.white,
        );
      case PlanStatus.trial:
        return _Pill(
          icon: Icons.hourglass_bottom,
          label: 'Trial ${_format(snapshot.remaining)}',
          background: theme.colorScheme.tertiaryContainer,
          foreground: theme.colorScheme.onTertiaryContainer,
        );
      case PlanStatus.expired:
        return const SizedBox.shrink();
    }
  }

  /// Compact remaining-time label: days+hours far out, else h:mm, else m:ss.
  static String _format(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) {
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      return '${d.inHours}h ${m}m';
    }
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
