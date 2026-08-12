import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../subscription/domain/plan_snapshot.dart';
import '../data/admin_api.dart';
import '../domain/admin_models.dart';
import 'admin_providers.dart';
import 'generate_code_screen.dart';

/// The admin console: every account with its live plan (status + a progress bar of how much of the
/// window is left), plus per-user actions — generate a code, expire the plan, reset the password, or
/// clear the device binding. Only reachable by an Admin account (role-gated in the router + backend).
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(adminUsersProvider),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const GenerateCodeScreen()),
        ),
        icon: const Icon(Icons.vpn_key),
        label: const Text('Generate code'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminUsersProvider),
        child: usersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Center(child: Text('$e', textAlign: TextAlign.center)),
            ],
          ),
          data: (users) {
            final customers = users.where((u) => !u.isAdmin).toList();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: customers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _UserCard(user: customers[i]),
            );
          },
        ),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user});
  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = user.plan;
    final (chipColor, chipLabel) = switch (plan.status) {
      PlanStatus.pro => (theme.colorScheme.primary, 'PRO'),
      PlanStatus.trial => (theme.colorScheme.tertiary, 'TRIAL'),
      PlanStatus.expired => (theme.colorScheme.error, 'EXPIRED'),
    };
    final showBar = plan.status != PlanStatus.expired;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(user.phone ?? '—', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(chipLabel,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: chipColor, fontWeight: FontWeight.w800)),
                ),
                _ActionsMenu(user: user),
              ],
            ),
            if (showBar) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: plan.progressRemaining,
                  minHeight: 7,
                  backgroundColor: chipColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(chipColor),
                ),
              ),
              const SizedBox(height: 4),
              Text('${_fmt(plan.remaining)} left',
                  style: theme.textTheme.labelSmall?.copyWith(color: chipColor)),
            ],
            if (user.hasDevice)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.smartphone, size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(user.deviceLabel ?? 'Device registered',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

enum _UserAction { generate, expire, resetPassword, resetDevice }

class _ActionsMenu extends ConsumerWidget {
  const _ActionsMenu({required this.user});
  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_UserAction>(
      icon: const Icon(Icons.more_vert),
      onSelected: (a) => _run(context, ref, a),
      itemBuilder: (_) => const [
        PopupMenuItem(value: _UserAction.generate, child: Text('Generate code')),
        PopupMenuItem(value: _UserAction.expire, child: Text('Expire plan now')),
        PopupMenuItem(value: _UserAction.resetPassword, child: Text('Reset password')),
        PopupMenuItem(value: _UserAction.resetDevice, child: Text('Reset device')),
      ],
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, _UserAction action) async {
    final phone = user.phone ?? '';
    final api = ref.read(adminApiProvider);
    switch (action) {
      case _UserAction.generate:
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => GenerateCodeScreen(initialPhone: phone),
        ));
        ref.invalidate(adminUsersProvider);
      case _UserAction.expire:
        final okE = await _confirm(context, 'Expire plan?',
            'Force ${user.fullName}\'s plan to expire now?');
        if (okE && context.mounted) {
          await _do(context, ref, () => api.expirePlan(phone: phone), 'Plan expired.');
        }
      case _UserAction.resetDevice:
        final okD = await _confirm(context, 'Reset device?',
            'Clear ${user.fullName}\'s device binding so they can sign in on a new phone?');
        if (okD && context.mounted) {
          await _do(context, ref, () => api.resetDevice(phone: phone), 'Device binding cleared.');
        }
      case _UserAction.resetPassword:
        final pw = await _promptPassword(context, user.fullName);
        if (pw != null && pw.isNotEmpty && context.mounted) {
          await _do(context, ref, () => api.resetPassword(phone: phone, newPassword: pw),
              'Password reset.');
        }
    }
  }

  Future<void> _do(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() op,
    String okMsg,
  ) async {
    try {
      await op();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
      }
      ref.invalidate(adminUsersProvider);
    } on AdminException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<String?> _promptPassword(BuildContext context, String name) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reset $name\'s password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            hintText: 'At least 6 characters',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Set password'),
          ),
        ],
      ),
    );
  }
}
