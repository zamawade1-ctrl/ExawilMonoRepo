import 'package:flutter/material.dart';

/// Shared building blocks for the Home tab's forwarding sections (mode,
/// destination, SIM). Each section is a self-contained card that follows the
/// same shape: a titled card, a status banner at the top stating the currently
/// saved value, its own inputs, a Save button, and a success dialog on save.
/// Keeping these here makes the three sections visually and behaviourally
/// consistent.

/// Colour treatment for [SectionStatusBanner], by meaning rather than colour.
enum SectionBannerTone {
  /// A value is saved and fully in effect.
  active,

  /// A value is chosen but something else is still needed to make it effective.
  pending,

  /// Nothing set yet / informational.
  neutral,
}

/// The banner shown at the top of a forwarding section, stating the current
/// saved value (e.g. "Forwarding to 2526…", "Using Telesom", "Auto forward
/// mode is active").
class SectionStatusBanner extends StatelessWidget {
  const SectionStatusBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.tone,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final SectionBannerTone tone;

  /// When non-null, the whole banner becomes tappable (e.g. a pending banner
  /// whose missing piece is a permission — tapping it opens the right settings).
  /// A trailing chevron is shown to signal it's actionable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color bg, Color fg) = switch (tone) {
      SectionBannerTone.active => (
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
      SectionBannerTone.pending => (
        theme.colorScheme.tertiaryContainer,
        theme.colorScheme.onTertiaryContainer,
      ),
      SectionBannerTone.neutral => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: fg, size: 20),
          ],
        ],
      ),
    );

    final radius = BorderRadius.circular(12);
    return Material(
      color: bg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? SizedBox(width: double.infinity, child: content)
          : InkWell(
              onTap: onTap,
              child: SizedBox(width: double.infinity, child: content),
            ),
    );
  }
}

/// The titled card scaffold every forwarding section sits in: an icon + title
/// header, then the section's content.
class ForwardingSectionCard extends StatelessWidget {
  const ForwardingSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// The consistent success popup shown after saving any forwarding section. It
/// auto-dismisses after 3 seconds so the user isn't required to tap anything,
/// while still offering an OK button to close it immediately.
Future<void> showForwardingSuccessDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ForwardingSuccessDialog(title: title, message: message),
  );
}

/// Success dialog that closes itself after [_autoDismiss] or when OK is tapped —
/// whichever comes first. A depleting progress bar across the TOP of the card,
/// plus a "Closing in Ns" label, shows how long is left before it auto-closes.
/// The bar is driven by the same [AnimationController] whose completion triggers
/// the close, so the countdown and the actual dismissal are always in sync. A
/// guarded [_close] makes the timer and OK paths idempotent so the dialog route
/// can never be popped twice.
class _ForwardingSuccessDialog extends StatefulWidget {
  const _ForwardingSuccessDialog({required this.title, required this.message});

  final String title;
  final String message;

  static const _autoDismiss = Duration(seconds: 3);

  @override
  State<_ForwardingSuccessDialog> createState() =>
      _ForwardingSuccessDialogState();
}

class _ForwardingSuccessDialogState extends State<_ForwardingSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: _ForwardingSuccessDialog._autoDismiss)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _close();
          })
          ..forward();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _controller.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const totalSeconds = 3;
    // Rounded top corners so the progress bar sits flush inside the dialog.
    const radius = Radius.circular(28);

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reverse (depleting) countdown bar across the top of the card.
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final remaining = 1 - _controller.value; // 1 → 0 over 3s
              return LinearProgressIndicator(
                value: remaining,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: theme.colorScheme.primary,
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                  size: 44,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.message,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Live seconds-remaining label, rebuilt with the bar.
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final secondsLeft =
                        ((1 - _controller.value) * totalSeconds).ceil().clamp(
                          0,
                          totalSeconds,
                        );
                    return Text(
                      'Closing in ${secondsLeft}s',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _close, child: const Text('OK')),
            ),
          ),
        ],
      ),
    );
  }
}
