import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_info.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../forwarding/data/forwarding_channel.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/delete_account.dart';
import '../../customer/presentation/customer_providers.dart';
import '../../forwarding/presentation/forwarding_destination_card.dart';
import '../../forwarding/presentation/forwarding_mode_card.dart';
import '../../forwarding/presentation/forwarding_providers.dart';
import '../../forwarding/presentation/forwarding_sim_card.dart';
import '../../subscription/presentation/plan_badge.dart';
import '../../subscription/presentation/plan_countdown_ring.dart';
import '../../transactions/presentation/transactions_screen.dart';
import 'widgets/promo_slideshow.dart';

/// The signed-in app's frame: an app bar with a left navigation drawer (menu)
/// and a "run sweep now" action, plus a bottom nav switching between Home and
/// Transactions. (The old Accessibility tab is gone — its manual-sweep button
/// moved to the app bar and its permission asks are handled by the guide dialog.)
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  /// One scroll controller per tab so re-tapping the current tab can scroll it
  /// back to the top (the Facebook-style "tap the active nav icon" gesture).
  final _scrollControllers = List.generate(3, (_) => ScrollController());

  @override
  void dispose() {
    for (final c in _scrollControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Bottom-nav / drawer tab switch. Re-selecting the tab you're already on
  /// scrolls it to the top AND refreshes it — like tapping Home in Facebook.
  void _selectTab(int index) {
    if (index == _selectedIndex) {
      _scrollToTop(index);
      _refreshTab(index);
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _scrollToTop(int index) {
    final controller = _scrollControllers[index];
    if (controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _refreshTab(int index) {
    switch (index) {
      case 0:
      case 2:
        // Dashboard and Transactions both read the on-device ledger.
        ref.read(deviceLedgerProvider.notifier).refresh();
      case 1:
        ref.read(customerProfileControllerProvider.notifier).refresh();
        if (Platform.isAndroid) {
          ref.read(nativeForwardingProvider.notifier).refresh();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: 0,
        // Top-left: the drawer menu button plus the plan badge (a green "PRO" pill
        // on a paid plan, or a live "Trial m:ss" countdown during the free trial).
        leadingWidth: 160,
        leading: Builder(
          builder: (ctx) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
              const Flexible(child: PlanBadge()),
            ],
          ),
        ),
        title: const _AppBarTitle(title: AppInfo.appName),
        // Top-right: a circular countdown ring draining as the trial/Pro window elapses.
        actions: const [PlanCountdownRing()],
      ),
      drawer: _AppDrawer(
        selectedIndex: _selectedIndex,
        onSelectTab: _selectTab,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardScreen(controller: _scrollControllers[0]),
          _ForwardingTab(controller: _scrollControllers[1]),
          TransactionsScreen(controller: _scrollControllers[2]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz),
            label: 'Forwarding',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
        ],
      ),
    );
  }
}

/// Branded app-bar title: the app icon in a rounded tile next to the current
/// tab's name, so the product identity is always visible at the top.
class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The app icon glyph, tinted to the brand icon green (#26A65B). Uses the
        // adaptive-icon foreground (transparent background) so the srcIn tint
        // colours the mark cleanly rather than flattening a whole tile.
        Image.asset(
          'assets/branding/app_icon_foreground.png',
          width: 34,
          height: 34,
          color: AppTheme.brandIconGreen,
          colorBlendMode: BlendMode.srcIn,
          // Never let a missing asset take down the whole app bar.
          errorBuilder: (_, _, _) => const Icon(
            Icons.bolt,
            color: AppTheme.brandIconGreen,
            size: 26,
          ),
        ),
        const SizedBox(width: 8),
        // App name, brand name green (#2E8B57) and bold.
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppTheme.brandNameGreen,
          ),
        ),
      ],
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
                    icon: Icons.dashboard_outlined,
                    label: 'Home',
                    selected: selectedIndex == 0,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectTab(0);
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.swap_horiz_outlined,
                    label: 'Forwarding',
                    selected: selectedIndex == 1,
                    onTap: () {
                      Navigator.pop(context);
                      onSelectTab(1);
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Transactions',
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
          if (user?.email case final email? when email.isNotEmpty)
            Text(
              email,
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

/// The forwarding-setup tab: mode, destination, and SIM cards. This is where the
/// user configures what the on-device forwarder does; the dashboard (Home) shows
/// the results.
class _ForwardingTab extends ConsumerWidget {
  const _ForwardingTab({this.controller});

  final ScrollController? controller;

  Future<void> _refresh(WidgetRef ref) async {
    // Pull-to-refresh re-pulls both the backend profile and the on-device
    // forwarder status, so the cards reflect the latest saved state.
    final futures = <Future<void>>[
      ref.read(customerProfileControllerProvider.notifier).refresh(),
      ref.read(nativeForwardingProvider.notifier).refresh(),
    ];
    // A pull-to-refresh also dials the *800# USSD, by mode:
    //  - auto-forward: a full balance SWEEP (read + forward if ≥ $1), the manual
    //    equivalent of the timer tick.
    //  - check-messages: a balance-only CHECK (no forward) to refresh the leftover
    //    readout. This is now the ONLY way to refresh the leftover balance — the
    //    little refresh icon that used to sit on the leftover card was removed in
    //    favour of this swipe-down gesture. (A forward is still offered explicitly
    //    via the "Run sweep" button.)
    // Guarded on a stored PIN so we never pop a *800# dialog we can't drive.
    if (Platform.isAndroid) {
      final status = ref.read(nativeForwardingProvider).value?.status;
      if (status?.mode == ForwardingMode.autoForward) {
        futures.add(const ForwardingChannel().sweepNow());
      } else if (status?.hasPin ?? false) {
        // Flag the balance check as in flight so the "Run sweep" button disables
        // itself while *800# is being dialed. It re-enables when the balance comes
        // back on the leftover stream (see ForwardingModeCard), or on a timeout.
        ref.read(balanceRefreshInProgressProvider.notifier).begin();
        futures.add(const ForwardingChannel().checkBalance());
      }
    }
    await Future.wait(futures);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: SingleChildScrollView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PromoSlideshow(),
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
