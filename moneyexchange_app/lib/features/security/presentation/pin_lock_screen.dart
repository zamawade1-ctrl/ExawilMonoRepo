import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import 'pin_providers.dart';
import 'widgets/pin_entry_view.dart';

/// The unlock gate shown on every app open once a PIN is set: enter the 6-digit
/// PIN to continue. A correct PIN flips the lock controller and the router
/// redirects on to the app. A "Log out" escape hatch is offered for a user who's
/// forgotten their PIN (they can sign back in with their password).
class PinLockScreen extends ConsumerWidget {
  const PinLockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<String?> onSubmit(String pin) async {
      final ok = await ref.read(appPinControllerProvider).verify(pin);
      if (ok) {
        ref.read(pinLockControllerProvider.notifier).markUnlocked();
        return null;
      }
      return 'Incorrect PIN. Try again.';
    }

    return Scaffold(
      body: PinEntryView(
        icon: Icons.lock_outline,
        title: 'Enter your PIN',
        subtitle: 'Enter your 6-digit PIN to unlock the app.',
        onSubmit: onSubmit,
        footer: TextButton(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          child: const Text('Log out'),
        ),
      ),
    );
  }
}
