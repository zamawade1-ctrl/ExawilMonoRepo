import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/delete_account.dart';
import '../../subscription/presentation/plan_badge.dart';

/// The Profile tab: the signed-in user's identity + plan, with quick links into
/// settings, support, and account actions. A calm, read-first page reached from
/// the bottom navigation.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.controller});

  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).value;
    final initials = (user?.fullName ?? 'U')
        .trim()
        .split(RegExp(r'\s+'))
        .map((p) => p.isEmpty ? '' : p[0])
        .take(2)
        .join()
        .toUpperCase();

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: user?.profilePictureUrl != null
                ? NetworkImage(user!.profilePictureUrl!)
                : null,
            child: user?.profilePictureUrl == null
                ? Text(
                    initials.isEmpty ? 'U' : initials,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            user?.fullName ?? 'Your account',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            user?.phoneNumber ?? '—',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Center(child: PlanBadge()),
        const SizedBox(height: 24),
        _Section(
          children: [
            _Tile(
              icon: Icons.workspace_premium_outlined,
              title: 'Plans & billing',
              subtitle: 'Pricing and how to pay',
              onTap: () => context.push(AppRoutes.billing),
            ),
            _Tile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Theme, app PIN, password',
              onTap: () => context.push(AppRoutes.settings),
            ),
            _Tile(
              icon: Icons.info_outline,
              title: 'About',
              onTap: () => context.push(AppRoutes.about),
            ),
            _Tile(
              icon: Icons.mail_outline,
              title: 'Contact us',
              onTap: () => context.push(AppRoutes.contact),
            ),
            _Tile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () => context.push(AppRoutes.privacy),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          children: [
            _Tile(
              icon: Icons.logout,
              title: 'Log out',
              danger: true,
              onTap: () => ref.read(authControllerProvider.notifier).signOut(),
            ),
            _Tile(
              icon: Icons.delete_outline,
              title: 'Delete account',
              danger: true,
              onTap: () => confirmAndDeleteAccount(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: danger ? theme.colorScheme.error : null),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: danger ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
