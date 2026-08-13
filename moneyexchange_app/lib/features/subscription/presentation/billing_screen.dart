import 'package:flutter/material.dart';

import '../../../core/config/app_info.dart';
import '../../../core/config/billing_info.dart';

/// Public pricing page: the subscription plans and how to pay. Reachable both
/// before signing in (from the sign-in/sign-up screen) and after (from the menu),
/// so it is deliberately not gated behind auth.
class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Plans & pricing')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'Choose your ${AppInfo.appName} plan',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'All plans include automatic Zaad/eDahab forwarding on your phone.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          for (final plan in BillingInfo.plans) ...[
            _PlanCard(plan: plan),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          _HowToPay(),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});
  final BillingPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlighted = plan.highlighted;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(plan.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    if (highlighted) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('BEST VALUE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w800,
                            )),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(plan.tagline,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${plan.priceUsd}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  )),
              Text(plan.period,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

class _HowToPay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to pay',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Send your chosen amount via Zaad or eDahab, then contact us on '
            '${BillingInfo.supportNumber} to receive your activation code.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _PayLine(label: 'Zaad', number: BillingInfo.zaadNumber),
          const SizedBox(height: 6),
          _PayLine(label: 'eDahab', number: BillingInfo.edahabNumber),
        ],
      ),
    );
  }
}

class _PayLine extends StatelessWidget {
  const _PayLine({required this.label, required this.number});
  final String label;
  final String number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        ),
        SelectableText(number,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            )),
      ],
    );
  }
}
