import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../forwarding/data/forwarding_channel.dart';

/// The Accessibility tab: the one-time on-device permission checklist
/// (SMS/phone/SIM, accessibility service, overlay) the balance-sweep
/// forwarder needs, plus a manual "run a sweep now" trigger. Split out of the
/// Home tab's forwarding profile card so the Home tab only holds forwarding
/// *configuration* and this tab only holds device *permissions*. Android-only,
/// like the rest of the on-device forwarder.
class AccessibilityScreen extends StatefulWidget {
  const AccessibilityScreen({super.key});

  @override
  State<AccessibilityScreen> createState() => _AccessibilityScreenState();
}

class _AccessibilityScreenState extends State<AccessibilityScreen> with WidgetsBindingObserver {
  static const _channel = ForwardingChannel();

  ForwardingStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from a system settings screen should refresh the checklist.
    if (state == AppLifecycleState.resumed && Platform.isAndroid) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await _channel.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } on PlatformException {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!Platform.isAndroid) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Automatic USSD forwarding runs on Android only — iOS can\'t '
                'dial the balance USSD or auto-fill the PIN. Use this screen on '
                'your Android phone with the Zaad SIM.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final status = _status;
    if (status == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Could not read the on-device forwarder status.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Setup', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'One-time permissions the balance sweep needs before it can run.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _SetupRow(
            label: 'SMS, phone & SIM permissions',
            done: status.hasSmsPermission &&
                status.hasCallPermission &&
                status.hasPhoneStatePermission,
            actionLabel: 'Grant',
            onAction: () => _channel.requestPermissions(),
          ),
          _SetupRow(
            label: 'Accessibility (auto-type PIN)',
            done: status.accessibilityEnabled,
            actionLabel: 'Enable',
            onAction: () => _channel.openAccessibilitySettings(),
          ),
          _SetupRow(
            label: 'Display over other apps',
            done: status.overlayEnabled,
            actionLabel: 'Allow',
            onAction: () => _channel.openOverlaySettings(),
          ),
          const SizedBox(height: 12),
          if (status.fullyReady)
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ready — your Zaad balance is checked and forwarded automatically.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            )
          else
            Text(
              'Finish the steps above to activate auto-forwarding.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _channel.sweepNow(),
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('Run a sweep now'),
          ),
        ],
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.label,
    required this.done,
    required this.actionLabel,
    required this.onAction,
  });

  final String label;
  final bool done;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: done ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (!done) TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
