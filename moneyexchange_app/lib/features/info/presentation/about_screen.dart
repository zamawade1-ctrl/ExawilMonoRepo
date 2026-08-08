import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_info.dart';

/// "About" page: what the app does, how forwarding works, and the app version.
/// Part of the publishing-readiness set (About / Contact / Privacy).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.bolt, size: 40, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 16),
                Text(AppInfo.appName, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  AppInfo.tagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                const _VersionLabel(),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('How it works', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const _AboutStep(
            icon: Icons.login,
            title: 'Sign in',
            body: 'Sign in securely with your Google account.',
          ),
          const _AboutStep(
            icon: Icons.tune,
            title: 'Set your payout',
            body: 'Choose where received USD should go — a mobile number or a bank account.',
          ),
          const _AboutStep(
            icon: Icons.sync,
            title: 'We auto-forward',
            body: 'When money lands on your Zaad or eDahab number, it is forwarded automatically '
                'to your chosen destination.',
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '© ${AppInfo.copyrightYear} ${AppInfo.companyName}. All rights reserved.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final label = info == null ? 'Version …' : 'Version ${info.version} (${info.buildNumber})';
        return Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      },
    );
  }
}

class _AboutStep extends StatelessWidget {
  const _AboutStep({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Icon(icon, size: 20, color: theme.colorScheme.onSecondaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
