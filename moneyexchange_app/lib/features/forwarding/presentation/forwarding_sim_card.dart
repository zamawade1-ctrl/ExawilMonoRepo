import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/forwarding_channel.dart';
import 'forwarding_providers.dart';
import 'widgets/forwarding_section.dart';

/// The Home tab's "SIM card" section (Android only): which SIM dials the
/// balance/forward USSD on a dual-SIM phone. A banner at the top states the SIM
/// currently in use; saving pops a success dialog naming the chosen SIM. Same
/// shape as the forwarding-mode and destination sections.
class ForwardingSimCard extends ConsumerStatefulWidget {
  const ForwardingSimCard({super.key});

  @override
  ConsumerState<ForwardingSimCard> createState() => _ForwardingSimCardState();
}

class _ForwardingSimCardState extends ConsumerState<ForwardingSimCard> {
  static const _systemDefault = -1;

  int _selected = _systemDefault;
  bool _initFromNative = false;
  bool _saving = false;

  /// A human name for a saved/selected subscription id, given the current SIMs.
  static String _simLabel(int subscriptionId, List<SimCard> sims) {
    if (subscriptionId == _systemDefault) return 'the default SIM';
    final match = sims.where((s) => s.subscriptionId == subscriptionId);
    return match.isNotEmpty ? match.first.label : 'the default SIM';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(nativeForwardingProvider.notifier)
          .saveSim(simSubscriptionId: _selected);
      if (!mounted) return;
      final sims = ref.read(nativeForwardingProvider).value?.sims ?? const [];
      await showForwardingSuccessDialog(
        context,
        title: 'SIM saved',
        message:
            'The balance USSD will now be dialed on ${_simLabel(_selected, sims)}.',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the SIM. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final native =
        ref.watch(nativeForwardingProvider).value ??
        const NativeForwardingState();
    final status = native.status;
    final sims = native.sims;

    // Seed the local selection from the saved native state once it loads,
    // dropping a stored SIM that no longer exists back to the system default.
    if (status != null && !_initFromNative) {
      _selected = sims.any((s) => s.subscriptionId == status.simSubscriptionId)
          ? status.simSubscriptionId
          : _systemDefault;
      _initFromNative = true;
    }

    final banner = status == null
        ? (
            icon: Icons.hourglass_empty,
            text: 'Checking SIM…',
            tone: SectionBannerTone.neutral,
          )
        : (
            icon: Icons.sim_card,
            text:
                'Using ${_simLabel(status.simSubscriptionId, sims)} to dial the USSD.',
            tone: SectionBannerTone.active,
          );

    return ForwardingSectionCard(
      icon: Icons.sim_card_outlined,
      title: 'SIM card',
      children: [
        SectionStatusBanner(
          icon: banner.icon,
          text: banner.text,
          tone: banner.tone,
        ),
        const SizedBox(height: 20),
        Text(
          'Which SIM should dial the USSD?',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _selected,
          decoration: const InputDecoration(labelText: 'SIM card'),
          items: [
            const DropdownMenuItem(
              value: _systemDefault,
              child: Text('System default'),
            ),
            for (final sim in sims)
              DropdownMenuItem(
                value: sim.subscriptionId,
                child: Text(sim.label),
              ),
          ],
          onChanged: _saving
              ? null
              : (v) => setState(() => _selected = v ?? _systemDefault),
        ),
        if (sims.isEmpty) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only the default SIM is available. Grant the phone permission in '
                  'Settings to choose a specific SIM on a dual-SIM phone.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save SIM'),
        ),
      ],
    );
  }
}
