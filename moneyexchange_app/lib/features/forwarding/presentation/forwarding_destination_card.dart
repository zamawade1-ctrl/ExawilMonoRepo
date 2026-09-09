import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../customer/domain/customer_profile.dart';
import '../../customer/presentation/customer_providers.dart';
import '../../notifications/presentation/destination_change_confirm_screen.dart';
import '../../security/presentation/require_app_pin.dart';
import '../data/forwarding_channel.dart';
import 'forwarding_providers.dart';
import 'widgets/forwarding_section.dart';

/// The Home tab's "forwarding destination" section: where the user's USD is sent
/// — a **mobile number** (forwarded via the `*806*dest*amount*secondaryPin#`
/// one-shot on Android) or a **bank account** (the `*800#` deposit walk). A
/// banner states the currently enabled destination; saving pops a success dialog.
///
/// The destination and every PIN live **on-device only** (Android Keystore) — never
/// on the backend, so a server-side change can't redirect a user's money. Editing
/// the form is gated behind the app PIN, and saving asks for a confirmation first.
///
/// Once a destination is saved the card opens read-only (just the values) behind
/// an Edit button; a first-time setup opens straight into the form.
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
        icon: Icons.account_balance_wallet_outlined,
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
      icon: Icons.account_balance_wallet_outlined,
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

/// Banner stating whether (and where) a destination is set up, read from the
/// native status — the destination + PINs are on-device only.
class _DestinationBanner extends ConsumerWidget {
  const _DestinationBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(nativeForwardingProvider).value?.status;

    IconData icon = Icons.info_outline;
    var tone = SectionBannerTone.neutral;
    var text = 'No destination set yet. Choose one below and save.';

    if (status != null && status.isBankMethod && status.hasBankPin) {
      icon = Icons.check_circle;
      tone = SectionBannerTone.active;
      text = 'Forwarding to your bank account.';
    } else if (status != null &&
        !status.isBankMethod &&
        (status.destination?.isNotEmpty ?? false)) {
      icon = Icons.check_circle;
      tone = SectionBannerTone.active;
      text = 'Forwarding to mobile number ${status.destination}.';
    }

    return SectionStatusBanner(icon: icon, text: text, tone: tone);
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

  // Destination + all PINs are on-device only, so every field starts empty and is
  // seeded from the native status (see [_seedFromNative]).
  final _destinationController = TextEditingController();
  final _pinController = TextEditingController();
  final _secondaryPinController = TextEditingController();
  final _bankPinController = TextEditingController();

  late ForwardingMethod _method =
      widget.initialProfile?.forwardingMethod ?? ForwardingMethod.mobileNumber;

  // The balance-sweep interval in SECONDS; only applies while auto-forward mode
  // is active. Defaults to the fastest cadence (every 30 seconds).
  int _intervalSeconds = 30;
  bool _seededFromNative = false;
  bool _saving = false;
  // Reveals the PIN fields as you type. Off by default so PINs stay masked.
  bool _showPin = false;
  // View (read-only) vs edit. A profile that already has a destination opens
  // read-only behind an Edit button; a first-time setup opens into the form.
  bool _editing = true;

  @override
  void initState() {
    super.initState();
    final status = ref.read(nativeForwardingProvider).value?.status;
    // First-time setup (nothing saved) opens the form directly; a saved
    // destination starts read-only, behind the app-PIN-gated Edit button. If the
    // native status hasn't loaded yet this is re-resolved in [_seedFromNative]
    // once it does — so a saved destination never flashes into an ungated form.
    _editing = !_hasSavedDestination(status);
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _pinController.dispose();
    _secondaryPinController.dispose();
    _bankPinController.dispose();
    super.dispose();
  }

  /// Whether a destination is already set up (so the card opens read-only),
  /// matched to the saved method so a leftover value for the other method doesn't
  /// count. Based solely on the native side — the source of truth on Android.
  bool _hasSavedDestination(ForwardingStatus? status) {
    if (status == null) return false;
    return status.isBankMethod
        ? status.hasBankPin
        : (status.destination?.isNotEmpty ?? false);
  }

  /// Seeds the interval, method, destination, and all PIN fields from the native
  /// side's saved values, once they load, so a returning user sees their saved
  /// values (masked). A first-time user has none stored, so the fields stay empty.
  void _seedFromNative(ForwardingStatus? status) {
    if (_seededFromNative || status == null) return;
    _seededFromNative = true;
    // Now that the real status is in, re-resolve the view: a saved destination
    // opens read-only (Edit is app-PIN-gated); a first-time setup stays in the
    // form. This runs once, before any user interaction, so it never fights a
    // user who has since tapped Edit/Cancel.
    _editing = !_hasSavedDestination(status);
    _intervalSeconds = _nearestIntervalOption(status.intervalSeconds);
    // With no backend profile (the norm on Android), the native side is the only
    // record of which method was chosen, so adopt it.
    if (widget.initialProfile == null) {
      _method = ForwardingMethod.fromWire(status.forwardingMethod);
    }
    if (_destinationController.text.isEmpty &&
        (status.destination?.isNotEmpty ?? false)) {
      _destinationController.text = status.destination!;
    }
    if (_pinController.text.isEmpty && (status.pin?.isNotEmpty ?? false)) {
      _pinController.text = status.pin!;
    }
    if (_secondaryPinController.text.isEmpty &&
        (status.secondaryPin?.isNotEmpty ?? false)) {
      _secondaryPinController.text = status.secondaryPin!;
    }
    if (_bankPinController.text.isEmpty &&
        (status.bankPin?.isNotEmpty ?? false)) {
      _bankPinController.text = status.bankPin!;
    }
  }

  /// Opens the edit form — but only after the user confirms the app PIN. Editing
  /// the destination could redirect money, so it's gated the same way the app
  /// unlock is (no-op when the user hasn't set an app PIN).
  Future<void> _beginEdit() async {
    final ok = await requireAppPin(
      context,
      ref,
      subtitle: 'Confirm your PIN to edit your forwarding destination.',
    );
    if (!ok || !mounted) return;
    setState(() {
      _editing = true;
      _showPin = false;
    });
  }

  void _cancelEdit() {
    // Revert every field to the native side's saved value — the source of truth.
    final status = ref.read(nativeForwardingProvider).value?.status;
    final nativeMethod = status != null
        ? ForwardingMethod.fromWire(status.forwardingMethod)
        : ForwardingMethod.mobileNumber;
    setState(() {
      _editing = false;
      _showPin = false;
      _method = nativeMethod;
      _destinationController.text = status?.destination ?? '';
      _pinController.text = status?.pin ?? '';
      _secondaryPinController.text = status?.secondaryPin ?? '';
      _bankPinController.text = status?.bankPin ?? '';
    });
  }

  /// The backend profile payload (best-effort sync on Android, the store on iOS).
  /// The destination + PINs are never sent — just identity + the chosen method.
  ForwardingProfileInput _buildInput() {
    final authName =
        ref.read(authControllerProvider).value?.fullName.trim() ?? '';
    final fullName = authName.isNotEmpty
        ? authName
        : (widget.initialProfile?.fullName ?? 'e-Xawil user');

    return ForwardingProfileInput(
      fullName: fullName,
      phoneNumber: widget.initialProfile?.phoneNumber,
      forwardingMethod: _method,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final isMobile = _method == ForwardingMethod.mobileNumber;
    final destination = _destinationController.text.trim();

    // No confirm modal here anymore. For a mobile number the save only PARKS the
    // new number (pending) and we redirect to the dedicated confirmation screen
    // below — where the change is reviewed and, on Confirm, the app PIN is required
    // before it goes live. Bank / unchanged saves just save and show success.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final input = _buildInput();

      // Whether this save parked a NEW/CHANGED mobile number into the pending
      // state (native decides by comparing against the stored number). Only then
      // do we redirect to the confirmation screen. False for bank + unchanged.
      var pendingChange = false;

      if (Platform.isAndroid) {
        // The on-device forwarder is the source of truth. For a mobile
        // destination it dials *806*dest*amount*secondaryPin# and auto-fills the
        // primary PIN on the confirmation popup; for a bank destination it runs
        // the *800# deposit walk and types the bank PIN. Whichever method isn't
        // selected has its extra field passed null so switching back re-prefills.
        pendingChange = await ref
            .read(nativeForwardingProvider.notifier)
            .saveDestination(
              forwardingMethod: _method.index,
              destination: isMobile ? destination : null,
              pin: _pinController.text.isEmpty
                  ? null
                  : _pinController.text.trim(),
              secondaryPin: isMobile
                  ? (_secondaryPinController.text.isEmpty
                        ? null
                        : _secondaryPinController.text.trim())
                  : null,
              bankPin: isMobile ? null : _bankPinController.text.trim(),
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

      // A changed mobile number is now pending confirmation: money won't forward
      // to it until confirmed. Redirect straight to the confirmation screen (also
      // logged in the Notifications tab) instead of the generic success dialog.
      if (isMobile && pendingChange) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DestinationChangeConfirmScreen(),
          ),
        );
        return;
      }

      await showForwardingSuccessDialog(
        context,
        title: isMobile ? 'Mobile number enabled' : 'Bank account enabled',
        message: isMobile
            ? 'Your Zaad & eDahab USD will be forwarded to $destination.'
            : 'Your Zaad & eDahab USD will be forwarded to your bank account.',
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

  // --- Read-only view (a destination is saved and we're not editing) ---------

  Widget _buildReadOnly(ThemeData theme, ForwardingStatus? status) {
    final isMobile = _method == ForwardingMethod.mobileNumber;
    final rows = <Widget>[];

    if (isMobile) {
      rows.add(
        _ReadOnlyRow(
          label: 'Destination number',
          value: status?.destination ?? '—',
        ),
      );
      if (Platform.isAndroid && (status?.hasPin ?? false)) {
        rows.add(const _ReadOnlyRow(label: 'Primary PIN', value: '•••• saved'));
      }
      if (Platform.isAndroid && (status?.hasSecondaryPin ?? false)) {
        rows.add(
          const _ReadOnlyRow(label: 'Secondary PIN', value: '•••• saved'),
        );
      }
    } else {
      if (Platform.isAndroid && (status?.hasPin ?? false)) {
        rows.add(const _ReadOnlyRow(label: 'Primary PIN', value: '•••• saved'));
      }
      rows.add(
        const _ReadOnlyRow(label: 'Bank account PIN', value: '•••• saved'),
      );
    }
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
          isMobile ? 'A mobile number' : 'Your bank account',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...rows,
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _beginEdit,
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
          Text('Forward my money to', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<ForwardingMethod>(
            segments: const [
              ButtonSegment(
                value: ForwardingMethod.mobileNumber,
                label: Text('Mobile number'),
                icon: Icon(Icons.phone_android),
              ),
              ButtonSegment(
                value: ForwardingMethod.bankAccount,
                label: Text('Bank account'),
                icon: Icon(Icons.account_balance),
              ),
            ],
            selected: {_method},
            onSelectionChanged: _saving
                ? null
                : (selection) => setState(() => _method = selection.first),
          ),
          const SizedBox(height: 16),
          if (_method == ForwardingMethod.mobileNumber)
            ..._mobileNumberFields(theme, status)
          else
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

  Widget _destinationField() {
    return TextFormField(
      key: const ValueKey('destination'),
      controller: _destinationController,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Destination mobile number',
        helperText: 'Where your Zaad/eDahab USD is forwarded',
      ),
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? 'Required' : null,
    );
  }

  // --- Mobile-number method: destination + primary PIN + secondary PIN + interval

  List<Widget> _mobileNumberFields(ThemeData theme, ForwardingStatus? status) {
    if (!Platform.isAndroid) {
      return [
        _destinationField(),
        const SizedBox(height: 16),
        _InfoNote(
          theme: theme,
          text:
              'Automatic USSD forwarding runs on Android only — iOS can\'t dial the '
              'balance USSD or auto-fill the PINs. Use this screen on your Android '
              'phone with the Zaad SIM.',
        ),
      ];
    }

    final isAuto = status?.mode == ForwardingMode.autoForward;

    return [
      _destinationField(),
      const SizedBox(height: 16),
      // Primary PIN — auto-typed on the *806# confirmation popup (and used to
      // unlock the *800# balance check).
      TextFormField(
        key: const ValueKey('primaryPin'),
        controller: _pinController,
        obscureText: !_showPin,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Primary PIN',
          helperText: (status?.hasPin ?? false)
              ? 'Saved — tap "Show PIN" to reveal. Auto-filled on the *806# confirm prompt.'
              : 'Your Zaad account PIN. Auto-filled on the *806# confirm prompt.',
          helperMaxLines: 2,
        ),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Required' : null,
      ),
      const SizedBox(height: 12),
      // Secondary PIN — embedded inline in the *806*dest*amount*secondaryPin#
      // send command.
      TextFormField(
        key: const ValueKey('secondaryPin'),
        controller: _secondaryPinController,
        obscureText: !_showPin,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Secondary PIN',
          helperText: (status?.hasSecondaryPin ?? false)
              ? 'Saved — tap "Show PIN" to reveal. Sent inside the *806# command.'
              : 'Sent inside the *806# send command.',
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
            ? 'The balance sweep dials *800# with your Primary PIN, then sends via '
                  '*806# to your destination number using the Secondary PIN, confirming '
                  'with the Primary PIN. "Check every" sets how often it runs.'
            : 'When a Zaad balance message arrives, the app sends via *806# to your '
                  'destination number using the Secondary PIN, confirming with the '
                  'Primary PIN.',
      ),
      if (status?.lastAccountPhone != null) ...[
        const SizedBox(height: 12),
        _AccountPhoneNote(theme: theme, phone: status!.lastAccountPhone!),
      ],
    ];
  }

  // --- Bank-account method: primary PIN + bank PIN + interval ----------------

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
      TextFormField(
        key: const ValueKey('primaryPinBank'),
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
        _AccountPhoneNote(theme: theme, phone: status!.lastAccountPhone!),
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

/// A small note showing the account's own Zaad number as last read from the
/// *800# balance screen.
class _AccountPhoneNote extends StatelessWidget {
  const _AccountPhoneNote({required this.theme, required this.phone});

  final ThemeData theme;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.sim_card_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Your Zaad number (read from the balance screen): $phone',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
