import 'package:flutter/material.dart';

import '../../../core/config/app_info.dart';

/// In-app privacy policy. App stores require a reachable privacy policy; this
/// mirrors the hosted one at [AppInfo.privacyPolicyUrl] so it's available offline
/// and inside the review flow. Keep the two in sync. The body is exposed as
/// [PrivacyPolicyContent] so it can also be shown in a dialog (e.g. the sign-up
/// consent link).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: PrivacyPolicyContent(),
      ),
    );
  }
}

/// The privacy-policy body, reusable in a page or a dialog.
class PrivacyPolicyContent extends StatelessWidget {
  const PrivacyPolicyContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Paragraph(
          'Last updated: August 2026.\n\nThis policy explains what ${AppInfo.appName} '
          'collects, why, and the control you have over your data.',
        ),
        _Section(
          title: 'No responsibility for transaction errors',
          body:
              '${AppInfo.appName} automates dialing your Zaad/eDahab USSD to forward '
              'money on your behalf. You are solely responsible for your transactions. '
              '${AppInfo.appName} is NOT responsible for any error in the transactions '
              '— including wrong amounts, wrong destinations, failed, delayed, '
              'duplicated or partial forwards, or any loss arising from them. Always '
              'verify your balances and confirmations yourself.',
        ),
        _Section(
          title: 'Information we collect',
          body: 'When you sign up we collect your name and phone number. When you set '
              'up forwarding, we store the phone number that receives money and your '
              'chosen payout destination (a bank account).',
        ),
        _Section(
          title: 'How we use it',
          body: 'We use this information solely to match incoming Zaad and eDahab '
              'receipts to your account and forward the money to the destination you '
              'configured. Your Zaad PIN, used for on-device forwarding, is stored '
              'encrypted on your phone only and is never transmitted to our servers.',
        ),
        _Section(
          title: 'Sharing',
          body: 'We do not sell your personal data. Information is shared only with the '
              'payment rails required to complete a forward you have requested, and '
              'where required by law.',
        ),
        _Section(
          title: 'Data retention & deletion',
          body: 'You can permanently delete your account and all associated data at any '
              'time from Settings → Delete account (or the menu). Deletion removes your '
              'profile, forwarding details and transaction records from our servers '
              'immediately.',
        ),
        _Section(
          title: 'Contact',
          body: 'Questions about this policy? Email ${AppInfo.supportEmail} or visit '
              '${AppInfo.websiteUrl}.',
        ),
      ],
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
