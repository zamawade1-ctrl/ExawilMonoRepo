import 'package:flutter/material.dart';

/// Step-by-step guide shown before opening the system Accessibility settings.
/// It names the exact service to look for ("e-Xawil USSD auto-fill") and each
/// tap the user makes there, so a screen the user has likely never opened stops
/// being a dead end. "Open settings" pops with `true` to launch the settings
/// page; "Not now" pops with `false`.
///
/// Shared by the first-run setup ([HomeGate]) and the Accessibility tab so the
/// "turn on auto-type" ask reads identically wherever it appears.
class AccessibilityGuideDialog extends StatelessWidget {
  const AccessibilityGuideDialog({super.key});

  /// The service label as it appears in the system list — must match
  /// AndroidManifest's `android:label` for `UssdAccessibilityService`.
  static const _serviceName = 'e-Xawil USSD auto-fill';

  static const _steps = <String>[
    'On the next screen, find "$_serviceName" — it may be under '
        '"Installed apps", "Downloaded apps", or "Installed services".',
    'Tap it to open the service page.',
    'Turn the switch at the top On.',
    'Tap "Allow" on the confirmation popup Android shows.',
    'Press Back to return here — this step ticks off automatically.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.accessibility_new, color: theme.colorScheme.primary),
      title: const Text('Turn on auto-type PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This lets e-Xawil type your PIN and confirm the transfer on the '
            'USSD screens for you. Follow these steps in Settings:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == _steps.length - 1 ? 0 : 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_steps[i], style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Open settings'),
        ),
      ],
    );
  }
}

/// Shows [AccessibilityGuideDialog] and resolves to whether the user chose to
/// open the system Accessibility settings.
Future<bool> showAccessibilityGuide(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (_) => const AccessibilityGuideDialog(),
  );
  return open ?? false;
}
