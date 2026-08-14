import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_info.dart';
import '../../../core/config/billing_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/subscription_api.dart';
import '../domain/pending_activation_code.dart';
import 'plan_providers.dart';

/// The gate shown when a trial or paid plan has expired: every other page is
/// blocked and the user lands here. Entering a valid activation code re-opens Pro
/// access (and on-device forwarding) for a month; the router then routes back in.
class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The code we last auto-filled from a delivered pending code — so when a *newer* code arrives we
  /// replace it, but we never clobber something the user typed themselves.
  String? _autofilled;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Copies a freshly delivered pending code into the input the first time it lands (and whenever a
  /// different one replaces it), unless the user has typed their own code in the meantime.
  void _syncAutofill(PendingActivationCode? pending) {
    if (pending == null) return;
    final current = _codeController.text.trim();
    if (current.isEmpty || current == _autofilled) {
      if (current != pending.code) {
        _codeController.text = pending.code;
        _codeController.selection =
            TextSelection.collapsed(offset: pending.code.length);
      }
      _autofilled = pending.code;
    }
  }

  Future<void> _activate() async {
    final typed = _codeController.text.trim();
    final code =
        typed.isNotEmpty ? typed : (ref.read(pendingActivationCodeProvider)?.code ?? '');
    if (code.isEmpty) {
      setState(() => _error = 'Enter your activation code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(planControllerProvider.notifier).redeem(code);
      // Success: the plan flips to Pro, the router redirects to home.
    } on SubscriptionException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not activate. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The admin-minted code waiting for this account, delivered live by the session poll. When it
    // appears (or a newer one replaces it) we drop it straight into the input — no typing, no refresh.
    final pending = ref.watch(pendingActivationCodeProvider);
    ref.listen<PendingActivationCode?>(
      pendingActivationCodeProvider,
      (_, next) {
        if (!mounted) return;
        setState(() {
          _syncAutofill(next);
          if (next != null) _error = null;
        });
      },
    );
    // Also handle a code that was already present when this screen first mounted (listen only fires
    // on change), so it's pre-filled on first paint.
    _syncAutofill(pending);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: pending != null
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      pending != null
                          ? Icons.vpn_key_rounded
                          : Icons.lock_clock_outlined,
                      size: 44,
                      color: pending != null
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    pending != null
                        ? 'Your activation code is ready'
                        : 'Your access has expired',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandNameGreen,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    pending != null
                        ? 'We\'ve added your code below. Just tap Activate to '
                            'reactivate your account and continue.'
                        : 'Your ${AppInfo.appName} trial or plan has ended, so '
                            'forwarding is paused. Enter an activation code to '
                            'reactivate your account and get another month of Pro.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (pending != null)
                    _PendingCodeCard(pending: pending)
                  else
                    const _PayToCard(),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _activate(),
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(32),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Activation code',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _activate,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Activate'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the activation code the admin just minted for this account, delivered live to the user's
/// page. The code is displayed in full (no copy-from-WhatsApp needed) with a Copy button; it's also
/// pre-filled into the input above, so the user only has to tap Activate.
class _PendingCodeCard extends StatelessWidget {
  const _PendingCodeCard({required this.pending});
  final PendingActivationCode pending;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: pending.code));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Activation code copied')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pending.planKind != null
                      ? 'Activation code · ${pending.planKind}'
                      : 'Your activation code',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The code itself is a tappable surface: tapping anywhere on it copies, and the trailing
          // copy icon repeats the affordance for discoverability.
          Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _copy(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pending.code,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Icon(Icons.copy_rounded,
                        size: 20, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy code'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tells the user which Zaad / eDahab account to send the subscription payment to
/// before they can be issued an activation code. Each number is copyable.
class _PayToCard extends StatelessWidget {
  const _PayToCard();

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
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Send your payment to',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Pay via Zaad or eDahab, then contact us for your activation code.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _PayRow(label: 'Zaad', number: BillingInfo.zaadNumber),
          const SizedBox(height: 8),
          _PayRow(label: 'eDahab', number: BillingInfo.edahabNumber),
        ],
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow({required this.label, required this.number});
  final String label;
  final String number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            number,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy $label number',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: number));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label number copied')),
            );
          },
        ),
      ],
    );
  }
}

/// Upper-cases activation-code input as it's typed (codes are stored upper-cased).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
