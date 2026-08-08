import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_info.dart';

/// "Contact us" page: tappable support channels (email, phone, website).
/// Part of the publishing-readiness set (About / Contact / Privacy).
class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  Future<void> _launch(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open ${uri.scheme}. Try again later.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Contact us')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Have a question or need help with a forward? Reach us through any of '
            'the channels below — we usually reply within one business day.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _ContactCard(
            icon: Icons.email_outlined,
            title: 'Email',
            value: AppInfo.supportEmail,
            onTap: () => _launch(context, Uri(scheme: 'mailto', path: AppInfo.supportEmail)),
          ),
          _ContactCard(
            icon: Icons.phone_outlined,
            title: 'Phone',
            value: AppInfo.supportPhone,
            onTap: () => _launch(
              context,
              Uri(scheme: 'tel', path: AppInfo.supportPhone.replaceAll(' ', '')),
            ),
          ),
          _ContactCard(
            icon: Icons.language_outlined,
            title: 'Website',
            value: AppInfo.websiteUrl,
            onTap: () => _launch(context, Uri.parse(AppInfo.websiteUrl)),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: Text(value),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: onTap,
      ),
    );
  }
}
