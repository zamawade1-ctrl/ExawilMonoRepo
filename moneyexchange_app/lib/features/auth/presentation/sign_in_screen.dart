import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_info.dart';
import 'auth_providers.dart';

/// The app's first page. A signed-out user lands here and has exactly one
/// thing to do: sign in with Google.
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  'assets/branding/app_icon.png',
                  width: 96,
                  height: 96,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppInfo.appName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Sign in to set up automatic USSD forwarding from your '
                'Zaad or eDahab account.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (authState.hasError) ...[
                _ErrorBanner(error: authState.error!),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: isLoading
                    ? null
                    : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(isLoading ? 'Signing in...' : 'Sign in with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final Object error;

  /// A specific, actionable message per failure cause. Because a backend that's
  /// down no longer fails sign-in (it falls back to an on-device local session),
  /// the only failures that reach here are Google-side — so the messages speak to
  /// the Google account / device config rather than a generic retry.
  String _message() {
    final e = error;
    if (e is GoogleSignInException) {
      return switch (e.code) {
        GoogleSignInExceptionCode.interrupted ||
        GoogleSignInExceptionCode.uiUnavailable =>
          'Google sign-in was interrupted. Please try again.',
        GoogleSignInExceptionCode.providerConfigurationError =>
          "Google sign-in isn't configured for this app on this device. "
              "Check that a Google account is added in Settings and try again.",
        _ =>
          'Google sign-in couldn\'t complete (${e.code.name}). '
              'Make sure a Google account is signed in on this phone, then try again.',
      };
    }
    return 'Sign-in couldn\'t complete. Please make sure a Google account is '
        'added on this phone and try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _message(),
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        textAlign: TextAlign.center,
      ),
    );
  }
}
