import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/admin_api.dart';
import '../domain/admin_models.dart';
import 'admin_providers.dart';

/// The plan kinds an admin can grant. "Forever" and "Free unlimited" are both the
/// backend never-expires sentinel (they differ only in price — $200 vs $0);
/// "custom" reveals the days/hours/minutes steppers.
enum _PlanKind { month, month5, sixMonths, year, forever, freeUnlimited, custom }

extension on _PlanKind {
  String get label => switch (this) {
    _PlanKind.month => '1 month · \$10',
    _PlanKind.month5 => '1 month · \$5',
    _PlanKind.sixMonths => '6 months',
    _PlanKind.year => '1 year · \$60',
    _PlanKind.forever => 'Forever · \$200',
    _PlanKind.freeUnlimited => 'Free unlimited',
    _PlanKind.custom => 'Custom',
  };

  /// Duration in minutes for the fixed kinds (custom + the forever kinds handled separately).
  int get minutes => switch (this) {
    _PlanKind.month || _PlanKind.month5 => 30 * 1440,
    _PlanKind.sixMonths => 182 * 1440,
    _PlanKind.year => 365 * 1440,
    _ => 0,
  };

  /// Both "Forever" and "Free unlimited" mint a never-expiring code.
  bool get isForever => this == _PlanKind.forever || this == _PlanKind.freeUnlimited;

  /// USD price recorded for the admin billing view. Null = unpriced (6 months / custom):
  /// the admin billing falls back to the duration-derived price.
  int? get priceUsd => switch (this) {
    _PlanKind.month => 10,
    _PlanKind.month5 => 5,
    _PlanKind.year => 60,
    _PlanKind.forever => 200,
    _PlanKind.freeUnlimited => 0,
    _PlanKind.sixMonths || _PlanKind.custom => null,
  };
}

/// Admin page to mint activation code(s) for a customer. The admin picks a plan
/// kind (1 month / 6 months / 1 year / Forever / custom), how many codes to mint,
/// and an expiry. Each generated code has a Share button that opens the system
/// share sheet (WhatsApp, SMS, …) so it's one tap to send — no copy/paste.
class GenerateCodeScreen extends ConsumerStatefulWidget {
  const GenerateCodeScreen({super.key, this.initialPhone});

  final String? initialPhone;

  @override
  ConsumerState<GenerateCodeScreen> createState() => _GenerateCodeScreenState();
}

class _GenerateCodeScreenState extends ConsumerState<GenerateCodeScreen> {
  late final TextEditingController _phone =
      TextEditingController(text: widget.initialPhone ?? '');

  _PlanKind _kind = _PlanKind.month;

  // Custom duration (only used when _kind == custom).
  int _durDays = 30;
  int _durHours = 0;
  int _durMinutes = 0;

  // How many codes to mint at once.
  int _count = 1;

  // Expiry (how long an unredeemed code stays valid).
  int _expDays = 14;
  int _expHours = 0;
  int _expMinutes = 0;

  bool _busy = false;
  String? _error;
  List<GeneratedCode> _results = const [];

  int get _customMinutes => _durDays * 1440 + _durHours * 60 + _durMinutes;
  int get _expiryMinutes => _expDays * 1440 + _expHours * 60 + _expMinutes;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter the customer\'s phone number.');
      return;
    }
    final forever = _kind.isForever;
    final durationMinutes = _kind == _PlanKind.custom ? _customMinutes : _kind.minutes;
    if (!forever && durationMinutes <= 0) {
      setState(() => _error = 'Duration must be greater than zero.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _results = const [];
    });
    try {
      final codes = await ref.read(adminApiProvider).generateCodes(
            phone: phone,
            durationMinutes: forever ? 1 : durationMinutes,
            expiresInMinutes: _expiryMinutes,
            forever: forever,
            count: _count,
            priceUsd: _kind.priceUsd,
          );
      setState(() => _results = codes);
    } on AdminException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not generate the code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Generate activation code')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Customer phone number',
              hintText: '+2526XXXXXXX',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Plan', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final k in _PlanKind.values)
                ChoiceChip(
                  label: Text(k.label),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          if (_kind == _PlanKind.custom) ...[
            const SizedBox(height: 12),
            _DhmRow(
              days: _durDays,
              hours: _durHours,
              minutes: _durMinutes,
              onChanged: (d, h, m) => setState(() {
                _durDays = d;
                _durHours = h;
                _durMinutes = m;
              }),
            ),
          ],
          const SizedBox(height: 24),
          Text('How many codes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _CountStepper(
            value: _count,
            onChanged: (v) => setState(() => _count = v),
          ),
          const SizedBox(height: 24),
          Text('Code expires in (if unredeemed)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _DhmRow(
            days: _expDays,
            hours: _expHours,
            minutes: _expMinutes,
            onChanged: (d, h, m) => setState(() {
              _expDays = d;
              _expHours = h;
              _expMinutes = m;
            }),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.vpn_key),
            label: Text(_count > 1 ? 'Generate $_count codes' : 'Generate code'),
          ),
          for (final r in _results) ...[
            const SizedBox(height: 16),
            _ResultCard(result: r),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final GeneratedCode result;

  String get _shareText =>
      'Your Xawil Pro activation code: ${result.code}'
      '${result.planKind != null ? ' (${result.planKind})' : ''}. '
      'Open the Xawil app → Activate, and enter this code.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activation code${result.planKind != null ? ' · ${result.planKind}' : ''}',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SelectableText(
              result.code,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            if (result.assignedToPhone != null)
              Text('Bound to ${result.assignedToPhone}',
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share'),
                    onPressed: () =>
                        Share.share(_shareText, subject: 'Xawil activation code'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple +/- stepper for the code count (1–100).
class _CountStepper extends StatelessWidget {
  const _CountStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: value <= 1 ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 56,
          child: Text('$value',
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        ),
        IconButton.filledTonal(
          onPressed: value >= 100 ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// A days / hours / minutes stepper row.
class _DhmRow extends StatelessWidget {
  const _DhmRow({
    required this.days,
    required this.hours,
    required this.minutes,
    required this.onChanged,
  });

  final int days;
  final int hours;
  final int minutes;
  final void Function(int days, int hours, int minutes) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Stepper(
            label: 'Days',
            value: days,
            max: 3650,
            onChanged: (v) => onChanged(v, hours, minutes),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Stepper(
            label: 'Hours',
            value: hours,
            max: 23,
            onChanged: (v) => onChanged(days, v, minutes),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Stepper(
            label: 'Minutes',
            value: minutes,
            max: 59,
            onChanged: (v) => onChanged(days, hours, v),
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: value >= max ? null : () => onChanged(value + 1),
              ),
              Text('$value', style: theme.textTheme.titleLarge),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: value <= 0 ? null : () => onChanged(value - 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
