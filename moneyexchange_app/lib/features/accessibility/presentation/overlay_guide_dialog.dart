import 'package:flutter/material.dart';

/// Step-by-step guide shown before opening the system "Display over other apps"
/// settings. The on-device forwarder draws the USSD auto-fill overlay on top of
/// the dialer, so it needs the display-over-other-apps ("appear on top")
/// permission — which, like accessibility, Android only exposes through Settings
/// and never through a runtime "Allow / Don't allow" dialog. "Open settings" pops
/// with `true` to launch the settings page; "Not now" pops with `false`.
///
/// Shared by the first-run setup ([HomeGate]) and anywhere the "turn on
/// appear-on-top" ask is surfaced, so it reads identically everywhere.
class OverlayGuideDialog extends StatelessWidget {
  const OverlayGuideDialog({super.key});

  /// The app name as it appears in the system "Display over other apps" list.
  static const _appName = 'e-Xawil';

  static const _steps = <String>[
    'On the next screen, find "$_appName" in the list of apps.',
    'Tap it to open its permission page.',
    'Turn "Allow display over other apps" (also called "Appear on top") On.',
    'Press Back to return here — this step ticks off automatically.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.layers, color: theme.colorScheme.primary),
      title: const Text('Turn on display over other apps'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This lets e-Xawil run the transfer on the USSD screens for you while '
            'you use other apps or the screen is off. Follow these steps in '
            'Settings:',
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

/// Shows [OverlayGuideDialog] and resolves to whether the user chose to open the
/// system "Display over other apps" settings.
Future<bool> showOverlayGuide(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (_) => const OverlayGuideDialog(),
  );
  return open ?? false;
}
