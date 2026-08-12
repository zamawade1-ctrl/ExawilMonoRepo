import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_api.dart';
import '../domain/admin_models.dart';
import 'admin_providers.dart';

/// Admin page to mint an activation code for a specific customer. Duration and expiry are entered in
/// days + hours + minutes, so a 2-minute test code is possible (not just whole days). The generated
/// code is shown with a copy button so the admin can send it over WhatsApp.
class GenerateCodeScreen extends ConsumerStatefulWidget {
  const GenerateCodeScreen({super.key, this.initialPhone});

  final String? initialPhone;

  @override
  ConsumerState<GenerateCodeScreen> createState() => _GenerateCodeScreenState();
}

class _GenerateCodeScreenState extends ConsumerState<GenerateCodeScreen> {
  late final TextEditingController _phone =
      TextEditingController(text: widget.initialPhone ?? '');

  // Duration (how long the plan lasts once redeemed).
  int _durDays = 30;
  int _durHours = 0;
  int _durMinutes = 0;

  // Expiry (how long the unredeemed code stays valid).
  int _expDays = 14;
  int _expHours = 0;
  int _expMinutes = 0;

  bool _busy = false;
  String? _error;
  GeneratedCode? _result;

  int get _durationMinutes => _durDays * 1440 + _durHours * 60 + _durMinutes;
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
    if (_durationMinutes <= 0) {
      setState(() => _error = 'Duration must be greater than zero.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final code = await ref.read(adminApiProvider).generateCode(
            phone: phone,
            durationMinutes: _durationMinutes,
            expiresInMinutes: _expiryMinutes,
          );
      setState(() => _result = code);
    } on AdminException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not generate the code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyPreset(int days, int hours, int minutes) {
    setState(() {
      _durDays = days;
      _durHours = hours;
      _durMinutes = minutes;
    });
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
          Text('Plan duration', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _PresetChip('2 min', () => _applyPreset(0, 0, 2)),
              _PresetChip('1 hour', () => _applyPreset(0, 1, 0)),
              _PresetChip('1 day', () => _applyPreset(1, 0, 0)),
              _PresetChip('7 days', () => _applyPreset(7, 0, 0)),
              _PresetChip('30 days', () => _applyPreset(30, 0, 0)),
              _PresetChip('90 days', () => _applyPreset(90, 0, 0)),
            ],
          ),
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
            label: const Text('Generate code'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 24),
            _ResultCard(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final GeneratedCode result;

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
            Text('Activation code', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    result.code,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: result.code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Grants ${_dhm(result.durationMinutes)}'
              '${result.assignedToPhone != null ? ' · bound to ${result.assignedToPhone}' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Send this to the customer over WhatsApp. Only their number can redeem it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dhm(int minutes) {
    final d = minutes ~/ 1440;
    final h = (minutes % 1440) ~/ 60;
    final m = minutes % 60;
    final parts = <String>[];
    if (d > 0) parts.add('${d}d');
    if (h > 0) parts.add('${h}h');
    if (m > 0) parts.add('${m}m');
    return parts.isEmpty ? '0m' : parts.join(' ');
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      ActionChip(label: Text(label), onPressed: onTap);
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
