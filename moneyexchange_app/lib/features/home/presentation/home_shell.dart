import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_info.dart';
import '../../../core/routing/app_router.dart';
import '../../accessibility/presentation/accessibility_screen.dart';
import '../../forwarding/data/forwarding_channel.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/delete_account.dart';
import '../../customer/presentation/customer_providers.dart';
import '../../forwarding/presentation/forwarding_destination_card.dart';
import '../../forwarding/presentation/forwarding_mode_card.dart';
import '../../forwarding/presentation/forwarding_providers.dart';
import '../../forwarding/presentation/forwarding_sim_card.dart';
import '../../transactions/presentation/transactions_screen.dart';

/// The signed-in app's frame: an app bar with a left navigation drawer (menu),
/// and a bottom nav switching between Home, Transactions, and Accessibility.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  static const _titles = [AppInfo.appName, 'Transactions', 'Accessibility'];

  void _selectTab(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_selectedIndex])),
      drawer: _AppDrawer(
        selectedIndex: _selectedIndex,
        onSelectTab: _selectTab,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _HomeTab(),
          TransactionsScreen(),
          AccessibilityScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.accessibility_new_outlined),
            selectedIcon: Icon(Icons.accessibility_new),
            label: 'Accessibility',
          ),
        ],
      ),
    );
  }
}

/// The left navigation menu: profile header, the two tabs, the info/legal pages,
/// settings, and the destructive account actions.
class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.selectedIndex, required this.onSelectTab});

  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).value;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(user: user),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerTile(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    selected: selectedIndex == 0,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectTab(0);
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Transactions',
                    selected: selectedIndex == 1,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectTab(1);
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.accessibility_new_outlined,
                    label: 'Accessibility',
                    selected: selectedIndex == 2,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectTab(2);
                    },
                  ),
                  const Divider(),
                  _DrawerTile(
                    icon: Icons.info_outline,
                    label: 'About',
                    onTap: () => _go(context, AppRoutes.about),
                  ),
                  _DrawerTile(
                    icon: Icons.mail_outline,
                    label: 'Contact us',
                    onTap: () => _go(context, AppRoutes.contact),
                  ),
                  _DrawerTile(
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap: () => _go(context, AppRoutes.privacy),
                  ),
                  _DrawerTile(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => _go(context, AppRoutes.settings),
                  ),
                  const Divider(),
                  _DrawerTile(
                    icon: Icons.logout,
                    label: 'Log out',
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(authControllerProvider.notifier).signOut();
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.delete_outline,
                    label: 'Delete account',
                    color: theme.colorScheme.error,
                    onTap: () {
                      Navigator.pop(context);
                      confirmAndDeleteAccount(context, ref);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, String route) {
    Navigator.pop(context);
    context.push(route);
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.onPrimary,
            backgroundImage: user?.profilePictureUrl != null
                ? NetworkImage(user!.profilePictureUrl!)
                : null,
            child: user?.profilePictureUrl == null
                ? Icon(Icons.person, color: theme.colorScheme.primary)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            user?.fullName ?? AppInfo.appName,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (user?.email != null)
            Text(
              user!.email,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? (selected ? theme.colorScheme.primary : null);
    return ListTile(
      leading: Icon(icon, color: tint),
      title: Text(label, style: TextStyle(color: tint)),
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.35,
      ),
      onTap: onTap,
    );
  }
}

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  Future<void> _refresh(WidgetRef ref) async {
    // Pull-to-refresh re-pulls both the backend profile and the on-device
    // forwarder status, so the cards reflect the latest saved state.
    final futures = <Future<void>>[
      ref.read(customerProfileControllerProvider.notifier).refresh(),
      ref.read(nativeForwardingProvider.notifier).refresh(),
    ];
    // A pull-to-refresh also acts as a manual "check now": kick off an immediate
    // on-device USSD balance sweep. It runs in the background service and returns
    // right away; the native side no-ops if forwarding isn't fully configured, so
    // an unconfigured pull never dials anything.
    if (Platform.isAndroid) {
      futures.add(const ForwardingChannel().sweepNow());
    }
    await Future.wait(futures);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WelcomeCard(user: user),
            const SizedBox(height: 20),
            // The forwarding-mode and SIM sections are on-device (USSD) concerns,
            // so they're Android-only. The destination is a cross-platform
            // preference and shows everywhere (it explains the iOS limits itself).
            if (Platform.isAndroid) ...[
              const ForwardingModeCard(),
              const SizedBox(height: 20),
            ],
            const ForwardingDestinationCard(),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 20),
              const ForwardingSimCard(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Gradient hero card greeting the signed-in user.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameParts = user?.fullName.split(' ') ?? const [];
    final firstName = nameParts.isEmpty ? '' : nameParts.first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome${firstName.isEmpty ? '' : ', $firstName'}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your Zaad & eDahab USD is forwarded automatically.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.onPrimary,
            backgroundImage: user?.profilePictureUrl != null
                ? NetworkImage(user!.profilePictureUrl!)
                : null,
            child: user?.profilePictureUrl == null
                ? Icon(Icons.bolt, color: theme.colorScheme.primary)
                : null,
          ),
        ],
      ),
    );
  }
}
