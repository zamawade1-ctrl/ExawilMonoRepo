import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_update_controller.dart';

/// The mandatory, NON-DISMISSIBLE update screen. Shown by the update gate
/// whenever the server reports a newer versionCode than the installed build.
///
/// By design there is NO Later / Skip / Cancel / Close / Back / dismiss action:
/// [PopScope] with `canPop: false` swallows the system back gesture/button, and
/// the only control is **Update Now**. The user cannot reach the rest of the app
/// until the newer build is installed (verified on resume by the controller).
class MandatoryUpdateScreen extends ConsumerWidget {
  const MandatoryUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final info = state.info;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final busy = state.phase == AppUpdatePhase.downloading ||
        state.phase == AppUpdatePhase.installing;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.system_update, size: 72, color: scheme.primary),
                    const SizedBox(height: 20),
                    Text(
                      'Update required',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      info == null
                          ? 'A newer version of the app is required to continue.'
                          : 'Version ${info.versionName} is required to continue. '
                              'Please update to keep using the app.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (info?.releaseNotes != null &&
                        info!.releaseNotes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'What\'s new',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              info.releaseNotes!.trim(),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        state.errorMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (busy) ...[
                      LinearProgressIndicator(
                        value: state.phase == AppUpdatePhase.downloading &&
                                state.progress > 0
                            ? state.progress
                            : null,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        state.phase == AppUpdatePhase.downloading
                            ? 'Downloading… ${(state.progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
                            : 'Opening installer…',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: controller.downloadAndInstall,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: const Icon(Icons.download),
                        label: const Text(
                          'Update Now',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
