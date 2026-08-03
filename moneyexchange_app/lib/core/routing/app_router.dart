import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/home/presentation/home_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static const signIn = '/sign-in';
  static const home = '/home';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: AppRoutes.signIn,
    refreshListenable: _AuthStateListenable(ref),
    redirect: (context, state) {
      // While restoring/attempting a session, keep the current screen - the
      // sign-in screen has its own loading indicator for this.
      if (authState.isLoading) return null;

      final isSignedIn = authState.value != null;
      final isOnSignIn = state.matchedLocation == AppRoutes.signIn;

      if (!isSignedIn && !isOnSignIn) return AppRoutes.signIn;
      if (isSignedIn && isOnSignIn) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod's [authControllerProvider] to go_router's
/// [Listenable]-based `refreshListenable`, so navigation re-evaluates
/// `redirect` whenever sign-in state changes.
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}
