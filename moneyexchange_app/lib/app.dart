import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_info.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'features/app_update/application/app_update_controller.dart';
import 'features/app_update/presentation/mandatory_update_screen.dart';

class MoneyExchangeApp extends ConsumerStatefulWidget {
  const MoneyExchangeApp({super.key});

  @override
  ConsumerState<MoneyExchangeApp> createState() => _MoneyExchangeAppState();
}

class _MoneyExchangeAppState extends ConsumerState<MoneyExchangeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Re-check for a mandatory update every time the app comes back to the
    // foreground (in addition to the launch check the controller runs when it's
    // first read below). This is what makes the block re-appear after resume and
    // what unblocks the app once the newer build is installed.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appUpdateControllerProvider.notifier).check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).value ?? ThemeMode.system;

    // Watching here (and instantiating the controller) triggers the launch-time
    // update check. When an update is enforced the whole app is covered by the
    // non-dismissible update screen via MaterialApp.builder, so no route — signed
    // in or out — can be reached until the newer build is installed.
    final mustUpdate = ref.watch(
      appUpdateControllerProvider.select((s) => s.isBlocking),
    );

    return MaterialApp.router(
      title: AppInfo.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => mustUpdate
          ? const MandatoryUpdateScreen()
          : (child ?? const SizedBox.shrink()),
    );
  }
}
