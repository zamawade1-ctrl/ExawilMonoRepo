import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pin_api.dart';
import 'pin_providers.dart';
import 'widgets/pin_entry_view.dart';

/// Changes the app-lock PIN in three steps: current PIN → new PIN → confirm. The
/// current PIN is verified server-side by the update call; on success the screen
/// pops with a confirmation.
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  // 0 = current PIN, 1 = new PIN, 2 = confirm new PIN.
  int _step = 0;
  String? _current;
  String? _newPin;

  Future<String?> _onSubmit(String pin) async {
    if (_step == 0) {
      setState(() {
        _current = pin;
        _step = 1;
      });
      return null;
    }
    if (_step == 1) {
      setState(() {
        _newPin = pin;
        _step = 2;
      });
      return null;
    }
    // Confirm step.
    if (pin != _newPin) {
      setState(() {
        _step = 1;
        _newPin = null;
      });
      return 'New PINs didn\'t match. Try again.';
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appPinControllerProvider).updatePin(
        currentPin: _current!,
        newPin: _newPin!,
      );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('PIN updated.')));
      return null;
    } on PinException catch (e) {
      // Most likely the current PIN was wrong — restart from step 0.
      setState(() {
        _step = 0;
        _current = null;
        _newPin = null;
      });
      return e.message;
    } catch (_) {
      setState(() {
        _step = 0;
        _current = null;
        _newPin = null;
      });
      return 'Could not update your PIN. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = switch (_step) {
      0 => ('Enter current PIN', 'Confirm it\'s you before changing your PIN.', Icons.lock_outline),
      1 => ('Enter new PIN', 'Choose a new 6-digit PIN.', Icons.pin_outlined),
      _ => ('Confirm new PIN', 'Re-enter your new 6 digits.', Icons.check_circle_outline),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: PinEntryView(
        resetKey: _step,
        icon: icon,
        title: title,
        subtitle: subtitle,
        onSubmit: _onSubmit,
      ),
    );
  }
}
