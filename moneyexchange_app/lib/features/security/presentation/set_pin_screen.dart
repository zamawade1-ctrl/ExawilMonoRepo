import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pin_api.dart';
import 'pin_providers.dart';
import 'widgets/pin_entry_view.dart';

/// First-run screen where a signed-in user chooses their custom 6-digit app-lock
/// PIN. Two steps: enter, then confirm. On success the PIN is saved (backend +
/// local), the user is marked as having a PIN, and the router moves on to the app.
class SetPinScreen extends ConsumerStatefulWidget {
  const SetPinScreen({super.key});

  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen> {
  // 0 = enter new PIN, 1 = confirm it.
  int _step = 0;
  String? _first;

  Future<String?> _onSubmit(String pin) async {
    if (_step == 0) {
      setState(() {
        _first = pin;
        _step = 1;
      });
      return null;
    }
    // Confirm step.
    if (pin != _first) {
      setState(() {
        _step = 0;
        _first = null;
      });
      return 'PINs didn\'t match. Start again.';
    }
    try {
      await ref.read(appPinControllerProvider).setPin(pin);
      // Success: markPinSet + markUnlocked fire inside setPin, so the router
      // redirects away from here. Nothing else to do.
      return null;
    } on PinException catch (e) {
      setState(() {
        _step = 0;
        _first = null;
      });
      return e.message;
    } catch (_) {
      setState(() {
        _step = 0;
        _first = null;
      });
      return 'Could not save your PIN. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final entering = _step == 0;
    return Scaffold(
      body: PinEntryView(
        resetKey: _step,
        icon: entering ? Icons.pin_outlined : Icons.check_circle_outline,
        title: entering ? 'Create your PIN' : 'Confirm your PIN',
        subtitle: entering
            ? 'Set a 6-digit PIN to secure the app. You\'ll enter it each time you open the app.'
            : 'Re-enter the same 6 digits to confirm.',
        onSubmit: _onSubmit,
      ),
    );
  }
}
