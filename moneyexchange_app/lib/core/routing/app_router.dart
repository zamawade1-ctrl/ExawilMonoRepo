import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/onboarding/presentation/onboarding_gate.dart';
import '../../features/info/presentation/about_screen.dart';
import '../../features/info/presentation/contact_screen.dart';
import '../../features/info/presentation/privacy_policy_screen.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/security/presentation/pin_providers.dart';
import '../../features/security/presentation/pin_lock_screen.dart';
import '../../features/security/presentation/set_pin_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/subscription/domain/plan_snapshot.dart';
import '../../features/subscription/presentation/activation_screen.dart';
import '../../features/subscription/presentation/plan_providers.dart';

class AppRoutes {
  const AppRoutes._();

  static const signIn = '/sign-in';
  static const setPin = '/set-pin';
  static const lock = '/lock';
  static const activation = '/activation';
  static const home = '/home';
  static const admin = '/admin';
  static const settings = '/settings';
  static const about = '/about';
  static const contact = '/contact';
  static const privacy = '/privacy';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.signIn,
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      // While restoring/attempting a session, keep the current screen.
      if (authState.isLoading) return null;

      final user = authState.value;
      final loc = state.matchedLocation;

      // 1. Signed out → only the sign-in screen is reachable.
      if (user == null) {
        return loc == AppRoutes.signIn ? null : AppRoutes.signIn;
      }

      // 1a. Admins skip the customer PIN/plan gates entirely and live in the admin console
      //     (plus the shared info/settings pages). Everything else bounces to /admin.
      if (user.isAdmin) {
        const adminAllowed = {
          AppRoutes.admin,
          AppRoutes.settings,
          AppRoutes.about,
          AppRoutes.contact,
          AppRoutes.privacy,
        };
        return adminAllowed.contains(loc) ? null : AppRoutes.admin;
      }

      // 2. Signed in but the PIN is enabled and not set yet → force setting one first.
      if (user.pinEnabled && !user.hasAppPin) {
        return loc == AppRoutes.setPin ? null : AppRoutes.setPin;
      }

      // 3. PIN enabled + set but currently locked → the unlock screen only.
      final locked =
          user.pinEnabled && ref.read(pinLockControllerProvider) == AppLockStatus.locked;
      if (locked) {
        return loc == AppRoutes.lock ? null : AppRoutes.lock;
      }

      // 4. Unlocked but the trial/plan has expired → the activation screen only.
      //    (A null plan means "not resolved yet" — don't gate on it, to avoid a
      //    flash of activation before the status loads.)
      final plan = ref.read(planControllerProvider).value;
      final expired = plan != null && plan.status == PlanStatus.expired;
      if (expired) {
        return loc == AppRoutes.activation ? null : AppRoutes.activation;
      }

      // 5. Fully in: keep the user out of the gate screens (and the admin-only console).
      if (loc == AppRoutes.signIn ||
          loc == AppRoutes.setPin ||
          loc == AppRoutes.lock ||
          loc == AppRoutes.activation ||
          loc == AppRoutes.admin) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.setPin,
        builder: (context, state) => const SetPinScreen(),
      ),
      GoRoute(
        path: AppRoutes.lock,
        builder: (context, state) => const PinLockScreen(),
      ),
      GoRoute(
        path: AppRoutes.activation,
        builder: (context, state) => const ActivationScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeGate(),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.contact,
        builder: (context, state) => const ContactScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
    ],
  );
});

/// Drives go_router's `redirect` re-evaluation. Notifies whenever sign-in state,
/// the PIN lock, or the plan changes — plus a slow periodic tick so a trial that
/// lapses while the app is idle is caught and the user is moved to activation.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(pinLockControllerProvider, (_, _) => notifyListeners());
    ref.listen(planControllerProvider, (_, _) => notifyListeners());
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => notifyListeners(),
    );
  }

  late final Timer _timer;

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
