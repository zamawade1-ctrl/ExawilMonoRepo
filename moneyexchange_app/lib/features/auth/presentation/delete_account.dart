import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

/// Shows the destructive "delete account" confirmation, and on confirm calls the
/// backend to permanently delete the account. On success the auth state drops to
/// signed-out and the router redirects to sign-in automatically, so callers don't
/// need to navigate. Shared by the home drawer and the settings screen.
///
/// The root navigator + messenger are captured synchronously up front so this
/// keeps working when invoked from the drawer (whose own context unmounts as the
/// drawer closes).
Future<void> confirmAndDeleteAccount(BuildContext context, WidgetRef ref) async {
  final theme = Theme.of(context);
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: rootNavigator.context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 32),
      title: const Text('Delete account?'),
      // Buttons live in the content as a single Row of two equal-width buttons so
      // Cancel and Delete always sit SIDE BY SIDE (the default `actions:` OverflowBar
      // stacked them vertically because the error-filled Delete button is wide).
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This permanently deletes your account, forwarding profile and transaction '
            'history. This cannot be undone.',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (confirmed != true || !rootNavigator.mounted) return;

  // Block interaction with a spinner while the deletion round-trips.
  showDialog<void>(
    context: rootNavigator.context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await ref.read(authControllerProvider.notifier).deleteAccount();
    // Dismiss the spinner. The router redirect handles leaving the screen.
    if (rootNavigator.canPop()) rootNavigator.pop();
  } catch (_) {
    if (rootNavigator.canPop()) rootNavigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not delete your account. Please try again.')),
    );
  }
}
