import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/delete_account.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/theme_mode_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    final theme = Theme.of(context);
    // Reflects the effective (resolved) brightness, whether it came from an
    // explicit choice or the system default.
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: user?.profilePictureUrl != null
                ? CircleAvatar(backgroundImage: NetworkImage(user!.profilePictureUrl!))
                : const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user?.fullName ?? ''),
            subtitle: Text(user?.email ?? ''),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark mode'),
            value: isDark,
            onChanged: (value) => ref.read(themeModeControllerProvider.notifier).setDarkMode(value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.about),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Contact us'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.contact),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacy),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Log out', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text('Delete account', style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text('Permanently remove your account and all data'),
            onTap: () => confirmAndDeleteAccount(context, ref),
          ),
        ],
      ),
    );
  }
}
