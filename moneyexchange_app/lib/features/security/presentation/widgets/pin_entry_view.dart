import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A self-contained 6-digit PIN entry surface: a header, six dot indicators, an
/// on-screen numeric keypad, and an inline error line. It manages the entered
/// digits itself and calls [onSubmit] once the sixth digit lands; [onSubmit]
/// returns an error message (or null on success). On any submit the digits clear,
/// so the same widget powers the set-PIN, confirm-PIN, and unlock flows. Bump
/// [resetKey] to force a fresh clear between steps.
class PinEntryView extends StatefulWidget {
  const PinEntryView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSubmit,
    this.icon = Icons.lock_outline,
    this.footer,
    this.resetKey,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// Called with the 6 digits; return an error string to show (and clear the
  /// field), or null on success.
  final Future<String?> Function(String pin) onSubmit;

  /// Optional widget under the keypad (e.g. a "Forgot PIN" / dev action).
  final Widget? footer;

  /// Change this to reset the entered digits (e.g. moving to the confirm step).
  final Object? resetKey;

  @override
  State<PinEntryView> createState() => _PinEntryViewState();
}

class _PinEntryViewState extends State<PinEntryView> {
  static const _length = 6;
  String _digits = '';
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(PinEntryView old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) {
      _digits = '';
      _error = null;
    }
  }

  Future<void> _onKey(String d) async {
    if (_busy || _digits.length >= _length) return;
    // Fire-and-forget: never await the haptic, so the digit lands on this frame
    // and rapid taps aren't dropped waiting on the platform channel.
    HapticFeedback.selectionClick();
    setState(() {
      _digits += d;
      _error = null;
    });
    if (_digits.length == _length) await _submit();
  }

  void _onBackspace() {
    if (_busy || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final error = await widget.onSubmit(_digits);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _digits = '';
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, size: 40, color: primary),
            ),
            const SizedBox(height: 20),
            Text(
              widget.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            _Dots(count: _length, filled: _digits.length, error: _error != null),
            const SizedBox(height: 16),
            SizedBox(
              height: 20,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _error ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
            const Spacer(flex: 1),
            _Keypad(onKey: _onKey, onBackspace: _onBackspace),
            if (widget.footer != null) ...[
              const SizedBox(height: 8),
              widget.footer!,
            ],
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.filled, required this.error});

  final int count;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = error ? theme.colorScheme.error : theme.colorScheme.primary;
    final off = theme.colorScheme.outlineVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            // Snappy fill so the dot lands the instant the key is pressed —
            // a long fill made typing feel laggy.
            duration: const Duration(milliseconds: 60),
            margin: const EdgeInsets.symmetric(horizontal: 9),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? on : Colors.transparent,
              border: Border.all(color: i < filled ? on : off, width: 1.6),
            ),
          ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey, required this.onBackspace});

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              children: [
                for (final d in row)
                  Expanded(child: _Key(label: d, onTap: () => onKey(d))),
              ],
            ),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              Expanded(child: _Key(label: '0', onTap: () => onKey('0'))),
              Expanded(
                child: _Key(
                  icon: Icons.backspace_outlined,
                  onTap: onBackspace,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          // Register the press on pointer-DOWN, not on release: it feels instant
          // and never drops a digit during fast typing. onTap stays (a no-op) so
          // the ink ripple still animates on tap.
          onTapDown: (_) => onTap(),
          onTap: () {},
          child: SizedBox(
            height: 64,
            child: Center(
              child: icon != null
                  ? Icon(icon, color: theme.colorScheme.onSurface)
                  : Text(
                      label!,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
