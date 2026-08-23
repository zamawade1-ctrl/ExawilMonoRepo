import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../customer/domain/customer_profile.dart';
import '../../customer/presentation/customer_providers.dart';
import '../data/forwarding_channel.dart';
import 'forwarding_providers.dart';
import 'widgets/forwarding_section.dart';

/// The Home tab's "forwarding destination" section. The app forwards to a **bank
/// account only** now (the mobile-number option was removed), so this card just
/// collects the two PINs the bank deposit needs:
///   - the **Primary PIN** (the account PIN that unlocks `*800#` — required both
///     to dial the balance check and to run the bank deposit walk), and
///   - the **Bank account PIN** (authorises the transfer on the deposit menu).
///
/// Both PINs live on-device only (Android Keystore) — never on the backend. Once
/// saved, the card opens read-only behind an Edit button; a first-time setup opens
/// straight into the form. See [_DestinationForm].
class ForwardingDestinationCard extends ConsumerWidget {
  const ForwardingDestinationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On Android the on-device native settings are the source of truth, so the
    // card is ALWAYS ready instantly — it never waits on a backend fetch. On iOS
    // (management-only) the backend profile is the sole store, so keep the
    // load/error gating there.
    if (Platform.isAndroid) {
      final profile = ref.watch(customerProfileControllerProvider).value;
      return ForwardingSectionCard(
        icon: Icons.account_balance_outlined,
        title: 'Forwarding destination',
        children: [
          const _DestinationBanner(),
          const SizedBox(height: 20),
          _DestinationForm(initialProfile: profile),
        ],
      );
    }

    final profileState = ref.watch(customerProfileControllerProvider);
    return ForwardingSectionCard(
      icon: Icons.account_balance_outlined,
      title: 'Forwarding destination',
      children: [
        const _DestinationBanner(),
        const SizedBox(height: 20),
        profileState.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LoadErrorNotice(
                onRetry: () =>
                    ref.invalidate(customerProfileControllerProvider),
              ),
              const SizedBox(height: 16),
              const _DestinationForm(initialProfile: null),
            ],
          ),
          data: (profile) => _DestinationForm(initialProfile: profile),
        ),
      ],
    );
  }
}

/// Banner stating whether a bank-account destination is set up (read from the
/// native status — the destination + PINs are on-device only).
class _DestinationBanner extends ConsumerWidget {
  const _DestinationBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nativeStatus = ref.watch(nativeForwardingProvider).value?.status;

    if (nativeStatus != null && nativeStatus.hasBankPin) {
      return const SectionStatusBanner(
        icon: Icons.check_circle,
        text: 'Forwarding to your bank account.',
        tone: SectionBannerTone.active,
      );
    }
    return const SectionStatusBanner(
      icon: Icons.info_outline,
      text: 'No bank account set up yet. Add your PINs below and save.',
      tone: SectionBannerTone.neutral,
    );
  }
}

/// A slim, non-blocking banner shown above the form when the saved destination
/// couldn't be fetched - the form below stays fully usable.
class _LoadErrorNotice extends StatelessWidget {
  const _LoadErrorNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Couldn't load your saved destination. You can still edit and save below.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _DestinationForm extends ConsumerStatefulWidget {
  const _DestinationForm({required this.initialProfile});

  final CustomerProfile? initialProfile;

  @override
  ConsumerState<_DestinationForm> createState() => _DestinationFormState();
}

class _DestinationFormState extends ConsumerState<_DestinationForm> {
  final _formKey = GlobalKey<FormState>();

  // Bank-only now: the account (primary) PIN that unlocks *800#, and the bank PIN
  // that authorises the deposit. Both are on-device only, seeded from the native
  // status (see [_seedFromNative]).
  final _pinController = TextEditingController();
  final _bankPinController = TextEditingController();

  // The balance-sweep interval in SECONDS; only applies while auto-forward mode is
  // active. Defaults to the fastest cadence (every 30 seconds).
  int _intervalSeconds = 30;
  bool _seededFromNative = false;
  bool _saving = false;
  // Reveals the PIN fields as you type. Off by default so PINs stay masked.
  bool _showPin = false;
  // View (read-only) vs edit. A profile that already has a bank PIN opens
  // read-only behind an Edit button; a first-time setup opens into the form.
  bool _editing = true;

  @override
  void initState() {
    super.initState();
    final status = ref.read(nativeForwardingProvider).value?.status;
    _editing = !_hasSavedDestination(status);
  }

  @override
  void dispose() {
    _pinController.dispose();
    _bankPinController.dispose();
    super.dispose();
  }

  /// Whether a bank destination is already set up (so the card opens read-only).
  /// The bank PIN is the signal that setup was completed; it lives on-device.
  bool _hasSavedDestination(ForwardingStatus? status) =>
      status != null && status.hasBankPin;

  /// Seeds the interval + both PIN fields from the native side's saved values,
  /// once they load, so a returning user sees their saved values (masked). A
  /// first-time user has none stored, so the fields stay empty.
  void _seedFromNative(ForwardingStatus? status) {
    if (_seededFromNative || status == null) return;
    _seededFromNative = true;
    _intervalSeconds = _nearestIntervalOption(status.intervalSeconds);
    if (_pinController.text.isEmpty && (status.pin?.isNotEmpty ?? false)) {
      _pinController.text = status.pin!;
    }
    if (_bankPinController.text.isEmpty && (status.bankPin?.isNotEmpty ?? false)) {
      _bankPinController.text = status.bankPin!;
    }
  }

  void _cancelEdit() {
    // Revert every field to the native side's saved value.
    final status = ref.read(nativeForwardingProvider).value?.status;
    setState(() {
      _editing = false;
      _showPin = false;
      _pinController.text = status?.pin ?? '';
      _bankPinController.text = status?.bankPin ?? '';
    });
  }

  /// The backend profile payload (best-effort sync on Android, the store on iOS).
  /// The destination + PINs are never sent — just identity + the (bank) method.
  ForwardingProfileInput _buildInput() {
    final authName =
        ref.read(authControllerProvider).value?.fullName.trim() ?? '';
    final fullName = authName.isNotEmpty
        ? authName
        : (widget.initialProfile?.fullName ?? 'e-Xawil user');

    return ForwardingProfileInput(
      fullName: fullName,
      phoneNumber: widget.initialProfile?.phoneNumber,
      forwardingMethod: ForwardingMethod.bankAccount,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final input = _buildInput();

      if (Platform.isAndroid) {
        // The on-device forwarder is the source of truth. Save the bank method
        // with BOTH PINs: the primary (account) PIN unlocks *800#, and the bank
        // PIN authorises the deposit. The mobile destination / secondary PIN are
        // no longer used, so they're left untouched (passed null).
        await ref
            .read(nativeForwardingProvider.notifier)
            .saveDestination(
              forwardingMethod: ForwardingMethod.bankAccount.index,
              destination: null,
              pin: _pinController.text.isEmpty
                  ? null
                  : _pinController.text.trim(),
              secondaryPin: null,
              bankPin: _bankPinController.text.trim(),
              intervalSeconds: _intervalSeconds,
            );

        // Best-effort backend mirror — forwarding runs entirely on-device, so an
        // unreachable backend must never fail the save.
        final profileNotifier = ref.read(
          customerProfileControllerProvider.notifier,
        );
        unawaited(() async {
          try {
            await profileNotifier.save(input);
          } catch (_) {
            // Ignore — the on-device destination is already saved and active.
          }
        }());
      } else {
        await ref.read(customerProfileControllerProvider.notifier).save(input);
      }

      if (!mounted) return;
      setState(() {
        _editing = false;
        _showPin = false;
      });
      await showForwardingSuccessDialog(
        context,
        title: 'Bank account enabled',
        message:
            'Your Zaad & eDahab USD will be forwarded to your bank account.',
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not save your destination. Please try again.'),
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
    final status = ref.watch(nativeForwardingProvider).value?.status;
    _seedFromNative(status);

    if (!_editing) return _buildReadOnly(theme, status);
    return _buildForm(theme, status);
  }

  // --- Read-only view (a bank destination is saved and we're not editing) -----

  Widget _buildReadOnly(ThemeData theme, ForwardingStatus? status) {
    final rows = <Widget>[];
    if (Platform.isAndroid && (status?.hasPin ?? false)) {
      rows.add(const _ReadOnlyRow(label: 'Primary PIN', value: '•••• saved'));
    }
    rows.add(const _ReadOnlyRow(label: 'Bank account PIN', value: '•••• saved'));
    if (Platform.isAndroid && status?.mode == ForwardingMode.autoForward) {
      rows.add(
        _ReadOnlyRow(
          label: 'Check every',
          value: _intervalLabel(_intervalSeconds),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your money is forwarded to', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Your bank account',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...rows,
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _editing = true;
            _showPin = false;
          }),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit'),
        ),
      ],
    );
  }

  // --- Edit form -------------------------------------------------------------

  Widget _buildForm(ThemeData theme, ForwardingStatus? status) {
    final canCancel = _hasSavedDestination(status);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Forward my money to my bank account',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ..._bankAccountFields(theme, status),
          const SizedBox(height: 24),
          Row(
            children: [
              if (canCancel) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _cancelEdit,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(canCancel ? 'Save' : 'Save destination'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The "Show PIN" checkbox that unmasks the PIN fields as they're typed.
  Widget _showPinToggle() {
    return InkWell(
      onTap: () => setState(() => _showPin = !_showPin),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _showPin,
                onChanged: (v) => setState(() => _showPin = v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Show PIN'),
          ],
        ),
      ),
    );
  }

  /// The balance-sweep interval choices, in seconds — as fast as every 30 seconds.
  static const _intervalOptions = <int>[30, 60, 120, 180, 300];

  /// Formats an interval (seconds) as a human label, e.g. "30 seconds" / "2 minutes".
  static String _intervalLabel(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    final minutes = seconds ~/ 60;
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }

  /// Snaps an arbitrary saved interval to the closest offered option, so a value
  /// stored by an older client still selects a valid dropdown entry.
  static int _nearestIntervalOption(int seconds) {
    var best = _intervalOptions.first;
    for (final option in _intervalOptions) {
      if ((option - seconds).abs() < (best - seconds).abs()) best = option;
    }
    return best;
  }

  /// The "Check every" balance-sweep interval dropdown (auto-forward mode only).
  Widget _checkIntervalField() {
    return DropdownButtonFormField<int>(
      initialValue: _nearestIntervalOption(_intervalSeconds),
      decoration: const InputDecoration(
        labelText: 'Check every',
        helperText: 'How often the balance sweep runs (auto-forward mode)',
        helperMaxLines: 2,
      ),
      items: [
        for (final seconds in _intervalOptions)
          DropdownMenuItem(
            value: seconds,
            child: Text(_intervalLabel(seconds)),
          ),
      ],
      onChanged: _saving
          ? null
          : (v) => setState(() => _intervalSeconds = v ?? 30),
    );
  }

  List<Widget> _bankAccountFields(ThemeData theme, ForwardingStatus? status) {
    if (!Platform.isAndroid) {
      return [
        _InfoNote(
          theme: theme,
          text:
              'Automatic USSD forwarding runs on Android only — iOS can\'t dial the '
              'balance USSD or auto-fill the PINs. Use this screen on your Android '
              'phone with the Zaad SIM.',
        ),
      ];
    }

    final hasSavedPin = status?.hasPin ?? false;
    final hasSavedBankPin = status?.hasBankPin ?? false;
    final isAuto = status?.mode == ForwardingMode.autoForward;

    return [
      // Primary (account) PIN — required for BOTH dialing the *800# balance check
      // and running the bank deposit walk, so it lives here in the bank form now.
      TextFormField(
        key: const ValueKey('primaryPin'),
        controller: _pinController,
        obscureText: !_showPin,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Primary PIN',
          helperText: hasSavedPin
              ? 'Saved — tap "Show PIN" to reveal. Unlocks the *800# balance check and bank deposit.'
              : 'Your Zaad account PIN. Unlocks the *800# balance check and bank deposit.',
          helperMaxLines: 2,
        ),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Required' : null,
      ),
      const SizedBox(height: 12),
      // Bank account PIN — authorises the transfer on the deposit menu.
      TextFormField(
        key: const ValueKey('bankAccountPin'),
        controller: _bankPinController,
        obscureText: !_showPin,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Bank account PIN',
          helperText: hasSavedBankPin
              ? 'Saved. Used to authorise transfers to your bank account.'
              : 'Used to authorise transfers to your bank account.',
          helperMaxLines: 2,
        ),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Required' : null,
      ),
      _showPinToggle(),
      if (isAuto) ...[
        const SizedBox(height: 8),
        _checkIntervalField(),
      ],
      const SizedBox(height: 12),
      _InfoNote(
        theme: theme,
        text: isAuto
            ? 'The balance sweep dials *800# with your Primary PIN, then deposits to '
                  'your bank account using the Bank account PIN. "Check every" sets how '
                  'often it runs in auto-forward mode.'
            : 'When a Zaad balance message arrives, the app dials *800# with your '
                  'Primary PIN and deposits to your bank account using the Bank account PIN.',
      ),
      if (status?.lastAccountPhone != null) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.sim_card_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your Zaad number (read from the balance screen): ${status!.lastAccountPhone}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

/// One "label: value" line in the read-only destination view — shows a saved
/// value plainly, without an input field.
class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.theme, required this.text});

  final ThemeData theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
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
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
