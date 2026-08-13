import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../subscription/domain/plan_snapshot.dart';
import '../data/admin_api.dart';
import '../domain/admin_models.dart';
import 'admin_providers.dart';
import 'generate_code_screen.dart';

/// A subtly-distinct admin accent — a slightly cooler emerald than the customer
/// app's Leon green, so the admin console reads as its own surface while staying
/// in the same family.
const Color _adminAccent = Color(0xFF127C63);
const Color _adminAccentDark = Color(0xFF0E6853);

/// Which admin tab is showing.
enum _AdminTab { overview, users, billing }

/// USD price a plan-kind label maps to (1 month $10, 1 year $60, Forever $200).
int? _planPrice(String? planKind) {
  switch ((planKind ?? '').toLowerCase()) {
    case '1 month':
      return 10;
    case '1 year':
      return 60;
    case 'forever':
      return 200;
    default:
      return null;
  }
}

/// The admin console: a two-tab shell (Overview + Users) with a bottom nav, an
/// app-bar menu (settings / dark mode / log out), and full user management —
/// search (phone or device label), plan filter, sort, pagination, per-user
/// actions (generate code, expire, reset password/device, edit phone), and the
/// plan kind each customer paid for. Only reachable by an Admin account.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  _AdminTab _tab = _AdminTab.users;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    // Re-tint just the admin console with the distinct accent.
    final theme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: _adminAccent,
        secondary: _adminAccent,
        tertiary: _adminAccentDark,
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_tab) {
            _AdminTab.overview => 'Admin overview',
            _AdminTab.users => 'Users',
            _AdminTab.billing => 'Billing',
          }),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(adminUsersProvider),
            ),
            _AdminMenu(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _adminAccent,
          foregroundColor: Colors.white,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const GenerateCodeScreen()),
          ),
          icon: const Icon(Icons.vpn_key),
          label: const Text('Generate code'),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab.index,
          onDestinationSelected: (i) => setState(() => _tab = _AdminTab.values[i]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Overview',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Users',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Billing',
            ),
          ],
        ),
        body: switch (_tab) {
          _AdminTab.overview => const _OverviewTab(),
          _AdminTab.users => const _UsersTab(),
          _AdminTab.billing => const _BillingTab(),
        },
      ),
    );
  }
}

/// The app-bar overflow menu: settings, dark-mode toggle, log out.
class _AdminMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu),
      onSelected: (v) {
        switch (v) {
          case 'settings':
            context.push(AppRoutes.settings);
          case 'theme':
            ref.read(themeModeControllerProvider.notifier).setDarkMode(!isDark);
          case 'logout':
            ref.read(authControllerProvider.notifier).signOut();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings & app PIN'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            leading: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            title: Text(isDark ? 'Light mode' : 'Dark mode'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Log out'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Overview tab: headline stats + quick actions.
class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminUsersProvider),
      child: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorList(message: '$e'),
        data: (users) {
          final customers = users.where((u) => !u.isAdmin).toList();
          var pro = 0, trial = 0, expired = 0, devices = 0;
          for (final u in customers) {
            switch (u.plan.status) {
              case PlanStatus.pro:
                pro++;
              case PlanStatus.trial:
                trial++;
              case PlanStatus.expired:
                expired++;
            }
            if (u.hasDevice) devices++;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatGrid(
                total: customers.length,
                pro: pro,
                trial: trial,
                expired: expired,
                devices: devices,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: _adminAccent,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const GenerateCodeScreen()),
                ),
                icon: const Icon(Icons.vpn_key),
                label: const Text('Generate activation code'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({
    required this.total,
    required this.pro,
    required this.trial,
    required this.expired,
    required this.devices,
  });
  final int total, pro, trial, expired, devices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = <(String, int, Color)>[
      ('Total customers', total, _adminAccent),
      ('On Pro', pro, _adminAccent),
      ('On trial', trial, theme.colorScheme.tertiary),
      ('Expired', expired, theme.colorScheme.error),
      ('Devices bound', devices, _adminAccent),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        for (final (label, value, color) in tiles)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: color, width: 4)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$value',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }
}

enum _Filter { all, pro, trial, expired }

enum _Sort { recent, name, remaining }

/// Users tab: search + filter + sort + pagination over the customer list.
class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  static const _pageSize = 8;

  final _searchController = TextEditingController();
  String _query = '';
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.recent;
  int _page = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);
    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorList(message: '$e'),
      data: (users) {
        final customers = users.where((u) => !u.isAdmin).toList();

        // Search by phone number or device label (also name, for convenience).
        final q = _query.trim().toLowerCase();
        var rows = customers.where((u) {
          if (_filter != _Filter.all && _statusOf(u) != _filter) return false;
          if (q.isEmpty) return true;
          return (u.phone ?? '').toLowerCase().contains(q) ||
              (u.deviceLabel ?? '').toLowerCase().contains(q) ||
              u.fullName.toLowerCase().contains(q);
        }).toList();

        // Sort.
        rows.sort((a, b) => switch (_sort) {
              _Sort.recent => b.lastModifiedAtUtc.compareTo(a.lastModifiedAtUtc),
              _Sort.name => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
              _Sort.remaining => a.plan.remaining.compareTo(b.plan.remaining),
            });

        final pageCount = (rows.length / _pageSize).ceil().clamp(1, 9999);
        final page = _page.clamp(0, pageCount - 1);
        final start = page * _pageSize;
        final pageRows = rows.skip(start).take(_pageSize).toList();

        return Column(
          children: [
            _Toolbar(
              controller: _searchController,
              onQuery: (v) => setState(() {
                _query = v;
                _page = 0;
              }),
              filter: _filter,
              onFilter: (f) => setState(() {
                _filter = f;
                _page = 0;
              }),
              sort: _sort,
              onSort: (s) => setState(() => _sort = s),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No matching customers.'))
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(adminUsersProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: pageRows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _UserCard(user: pageRows[i]),
                      ),
                    ),
            ),
            if (rows.isNotEmpty)
              _Pagination(
                page: page,
                pageCount: pageCount,
                total: rows.length,
                onPrev: page > 0 ? () => setState(() => _page = page - 1) : null,
                onNext:
                    page < pageCount - 1 ? () => setState(() => _page = page + 1) : null,
              ),
          ],
        );
      },
    );
  }

  static _Filter _statusOf(AdminUser u) => switch (u.plan.status) {
        PlanStatus.pro => _Filter.pro,
        PlanStatus.trial => _Filter.trial,
        PlanStatus.expired => _Filter.expired,
      };
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.onQuery,
    required this.filter,
    required this.onFilter,
    required this.sort,
    required this.onSort,
  });

  final TextEditingController controller;
  final ValueChanged<String> onQuery;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final _Sort sort;
  final ValueChanged<_Sort> onSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onQuery,
                  decoration: InputDecoration(
                    hintText: 'Search phone or device',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_Sort>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort',
                initialValue: sort,
                onSelected: onSort,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _Sort.recent, child: Text('Recently edited')),
                  PopupMenuItem(value: _Sort.name, child: Text('Name (A–Z)')),
                  PopupMenuItem(value: _Sort.remaining, child: Text('Time remaining')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_filterLabel(f)),
                      selected: filter == f,
                      onSelected: (_) => onFilter(f),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _filterLabel(_Filter f) => switch (f) {
        _Filter.all => 'All',
        _Filter.pro => 'Pro',
        _Filter.trial => 'Trial',
        _Filter.expired => 'Expired',
      };
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int page, pageCount, total;
  final VoidCallback? onPrev, onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Text('$total total', style: theme.textTheme.bodySmall),
          const Spacer(),
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Text('${page + 1} / $pageCount', style: theme.textTheme.bodyMedium),
          IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
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
      PlanStatus.pro => (_adminAccent, 'PRO'),
      PlanStatus.trial => (theme.colorScheme.tertiary, 'TRIAL'),
      PlanStatus.expired => (theme.colorScheme.error, 'EXPIRED'),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openActions(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
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
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  if (user.planKind != null)
                    _MetaChip(icon: Icons.workspace_premium_outlined, text: user.planKind!),
                  if (user.hasDevice)
                    _MetaChip(
                      icon: Icons.smartphone,
                      text: user.deviceLabel ?? 'Device registered',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _ActionsSheet(user: user),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(text,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}

/// Bottom sheet of per-user actions.
class _ActionsSheet extends ConsumerWidget {
  const _ActionsSheet({required this.user});
  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = user.phone ?? '';
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            title: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(user.phone ?? '—'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.vpn_key),
            title: const Text('Generate code'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => GenerateCodeScreen(initialPhone: phone),
              ));
              ref.invalidate(adminUsersProvider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Edit phone number'),
            onTap: () async {
              Navigator.pop(context);
              await _editPhone(context, ref, user);
            },
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Reset password'),
            onTap: () async {
              Navigator.pop(context);
              await _resetPassword(context, ref, user);
            },
          ),
          ListTile(
            leading: const Icon(Icons.smartphone),
            title: const Text('Reset device'),
            onTap: () async {
              Navigator.pop(context);
              await _confirmDo(context, ref, 'Reset device?',
                  'Clear ${user.fullName}\'s device binding?',
                  () => ref.read(adminApiProvider).resetDevice(phone: phone),
                  'Device binding cleared.');
            },
          ),
          ListTile(
            leading: Icon(Icons.timer_off_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Expire plan now',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () async {
              Navigator.pop(context);
              await _confirmDo(context, ref, 'Expire plan?',
                  'Force ${user.fullName}\'s plan to expire now?',
                  () => ref.read(adminApiProvider).expirePlan(phone: phone),
                  'Plan expired.');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// --- Action helpers (shared by the sheet) -----------------------------------

Future<void> _confirmDo(
  BuildContext context,
  WidgetRef ref,
  String title,
  String body,
  Future<void> Function() op,
  String okMsg,
) async {
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
  if (ok != true) return;
  await _run(context, ref, op, okMsg);
}

Future<void> _editPhone(BuildContext context, WidgetRef ref, AdminUser user) async {
  final controller = TextEditingController(text: user.phone ?? '');
  final newPhone = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Edit ${user.fullName}\'s phone'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'New phone number',
          hintText: '+2526XXXXXXX',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Update'),
        ),
      ],
    ),
  );
  if (newPhone == null || newPhone.isEmpty || !context.mounted) return;
  await _run(context, ref,
      () => ref.read(adminApiProvider).updatePhone(phone: user.phone ?? '', newPhone: newPhone),
      'Phone number updated.');
}

Future<void> _resetPassword(BuildContext context, WidgetRef ref, AdminUser user) async {
  final controller = TextEditingController();
  final pw = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Reset ${user.fullName}\'s password'),
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
  if (pw == null || pw.isEmpty || !context.mounted) return;
  await _run(
      context,
      ref,
      () => ref.read(adminApiProvider).resetPassword(phone: user.phone ?? '', newPassword: pw),
      'Password reset.');
}

Future<void> _run(
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

/// Billing tab: customers who have paid, most recent first, with the amount their
/// plan kind maps to and the total collected.
class _BillingTab extends ConsumerWidget {
  const _BillingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usersAsync = ref.watch(adminUsersProvider);
    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorList(message: '$e'),
      data: (users) {
        final paid = users.where((u) => !u.isAdmin && u.planKind != null).toList()
          ..sort((a, b) => (b.plan.periodStartUtc ?? b.lastModifiedAtUtc)
              .compareTo(a.plan.periodStartUtc ?? a.lastModifiedAtUtc));
        final total = paid.fold<int>(0, (sum, u) => sum + (_planPrice(u.planKind) ?? 0));

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminUsersProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _BillingStat(label: 'Paying customers', value: '${paid.length}')),
                  const SizedBox(width: 12),
                  Expanded(child: _BillingStat(label: 'Total collected', value: '\$$total')),
                ],
              ),
              const SizedBox(height: 16),
              if (paid.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('No payments recorded yet.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                )
              else
                for (final u in paid) ...[
                  _BillingRow(user: u, price: _planPrice(u.planKind)),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _BillingStat extends StatelessWidget {
  const _BillingStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: _adminAccent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _BillingRow extends StatelessWidget {
  const _BillingRow({required this.user, required this.price});
  final AdminUser user;
  final int? price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paidAt = user.plan.periodStartUtc ?? user.lastModifiedAtUtc;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(user.phone ?? '—', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text('${user.planKind} · ${_fmtDate(paidAt)}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text(price != null ? '\$$price' : '—',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _adminAccent,
                )),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 12),
        Center(child: Text(message, textAlign: TextAlign.center)),
      ],
    );
  }
}
