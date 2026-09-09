import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import 'pin_providers.dart';
import 'widgets/pin_entry_view.dart';

/// Prompts for the app's 6-digit PIN and returns whether it was entered
/// correctly. Used to gate sensitive actions — e.g. editing the forwarding
/// destination, where a wrong change could send money to the wrong place.
///
/// The gate fires whenever a PIN EXISTS for the user — the backend `hasAppPin`
/// flag OR a locally-stored copy — **regardless of whether the app-lock is
/// switched on in settings**. This is intentional: the app-lock (locking on
/// open) is optional and can be toggled off, but once a PIN has been set the
/// forwarding-destination form is always protected by it. Turning the lock off
/// keeps the local PIN copy precisely so this still works (see
/// `AuthController.setPinEnabled`).
///
/// Returns `true` immediately (no prompt) only when NO PIN has ever been set, so
/// the gate never dead-ends a user who never created one. Returns `false` if the
/// user backs out without entering the correct PIN.
/// Pure gate decision for [requireAppPin], extracted so it can be unit-tested
/// without a widget tree. The PIN is required whenever one EXISTS — either the
/// backend says so ([hasAppPin]) or a local copy is present ([hasLocalPin]) —
/// **independent of whether the app-lock is enabled**. Turning the app-lock off
/// nulls the backend `hasAppPin` but deliberately keeps the local copy, so this
/// still returns true and the forwarding-destination form stays protected.
bool shouldRequireAppPin({
  required bool hasAppPin,
  required bool hasLocalPin,
}) =>
    hasAppPin || hasLocalPin;

Future<bool> requireAppPin(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Enter your PIN',
  String subtitle = 'Confirm your 6-digit PIN to continue.',
}) async {
  final user = ref.read(authControllerProvider).value;
  if (user == null) return true;
  final hasLocalPin = await ref.read(appPinControllerProvider).hasLocalPin();
  if (!shouldRequireAppPin(
    hasAppPin: user.hasAppPin,
    hasLocalPin: hasLocalPin,
  )) {
    return true;
  }
  if (!context.mounted) return false;

  final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => _AppPinGateScreen(title: title, subtitle: subtitle),
    ),
  );
  return ok ?? false;
}

/// A full-screen PIN prompt that pops `true` on the first correct PIN, and
/// `false` if the user closes it. Reuses the same [PinEntryView] keypad as the
/// unlock screen, so the entry feels identical (and fast).
class _AppPinGateScreen extends ConsumerWidget {
  const _AppPinGateScreen({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<String?> onSubmit(String pin) async {
      final valid = await ref.read(appPinControllerProvider).verify(pin);
      if (valid) {
        if (context.mounted) Navigator.of(context).pop(true);
        return null;
      }
      return 'Incorrect PIN. Try again.';
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: PinEntryView(
        icon: Icons.lock_outline,
        title: title,
        subtitle: subtitle,
        onSubmit: onSubmit,
      ),
    );
  }
}
