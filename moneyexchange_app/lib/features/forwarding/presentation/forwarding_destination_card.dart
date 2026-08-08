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

/// The Home tab's "forwarding destination" section: where the user's USD is
/// sent — a mobile number (dialed via USSD on Android) or a bank account. A
/// banner at the top states the currently enabled destination; saving pops a
/// success dialog naming what was enabled. The full name is taken from the
/// signed-in Google identity, and the SIM lives in its own section below — this
/// card is purely about the destination.
///
/// Once a destination is saved the card opens read-only (just the values, no
/// input fields) behind an Edit button; a first-time setup opens straight into
/// the form. See [_DestinationForm].
class ForwardingDestinationCard extends ConsumerWidget {
  const ForwardingDestinationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On Android the on-device native settings are the source of truth for the
    // destination, so the card is ALWAYS ready instantly — it never waits on a
    // backend fetch and never shows a loading spinner. The backend profile is
    // read best-effort only, as an extra prefill/display fallback. On iOS
    // (management-only, no native forwarder) the backend profile is the sole
    // store, so keep the load/error gating there.
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
          // A load error must never dead-end the form: show it anyway (empty, so
          // it can still be filled and saved) with a small, non-blocking notice.
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

/// Banner stating the destination that's currently enabled (from the saved
/// backend profile, falling back to a native-only saved destination).
class _DestinationBanner extends ConsumerWidget {
  const _DestinationBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(customerProfileControllerProvider).value;
    final nativeStatus = ref.watch(nativeForwardingProvider).value?.status;

    IconData icon = Icons.info_outline;
    var tone = SectionBannerTone.neutral;
    var text = 'No destination set yet. Choose one below and save.';

    if (profile != null &&
        profile.forwardingMethod == ForwardingMethod.mobileNumber &&
        (profile.forwardingPhoneNumber?.isNotEmpty ?? false)) {
      icon = Icons.check_circle;
      tone = SectionBannerTone.active;
      text = 'Forwarding to mobile number ${profile.forwardingPhoneNumber}.';
    } else if (profile != null &&
        profile.forwardingMethod == ForwardingMethod.bankAccount &&
        (profile.bankAccountPin?.isNotEmpty ?? false)) {
      icon = Icons.check_circle;
      tone = SectionBannerTone.active;
      // Never surface the PIN itself in the always-visible banner.
      text = 'Forwarding to your bank account.';
    } else if (nativeStatus != null &&
        nativeStatus.isBankMethod &&
        nativeStatus.hasBankPin) {
      // Native (on-device) bank destination, no backend profile needed.
      icon = Icons.check_circle;
      tone = SectionBannerTone.active;
      text = 'Forwarding to your bank account.';
    } else if ((nativeStatus?.destination?.isNotEmpty ?? false) &&
        !(nativeStatus?.isBankMethod ?? false)) {
      icon = Icons.check_circle;
      tone = SectionBannerTone.active;
      text = 'Forwarding to mobile number ${nativeStatus!.destination}.';
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

  // Shared between the backend profile's `forwardingPhoneNumber` and the native
  // sweep's `destination` - they're the same number.
  late final _destinationController = TextEditingController(
    text: widget.initialProfile?.forwardingPhoneNumber ?? '',
  );
  // The mobile PINs live in the Android Keystore and are write-only from here
  // (the native side only reports whether one is stored, never its value), so
  // these start empty on edit - "leave blank to keep the saved one".
  final _pinController = TextEditingController();
  final _secondaryPinController = TextEditingController();
  // Bank forwarding collapsed to a single PIN. It's stored in the backend
  // profile (see CustomerProfile.bankAccountPin), so unlike the mobile PINs it
  // can be read back and pre-filled here.
  late final _bankPinController = TextEditingController(
    text: widget.initialProfile?.bankAccountPin ?? '',
  );

  late ForwardingMethod _method =
      widget.initialProfile?.forwardingMethod ?? ForwardingMethod.mobileNumber;
  // The balance-sweep interval lives here now (below the PINs) rather than in
  // the mode card; it only applies while auto-forward mode is active.
  int _intervalMinutes = 1;
  bool _seededFromNative = false;
  bool _saving = false;
  // Reveals the PIN field(s) as you type. Off by default so PINs stay masked.
  bool _showPin = false;
  // View (read-only) vs edit. A profile that already has a destination opens
  // read-only behind an Edit button; a first-time setup opens into the form.
  // Resolved in initState from the saved profile + native state.
  bool _editing = true;

  @override
  void initState() {
    super.initState();
    final status = ref.read(nativeForwardingProvider).value?.status;
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

  /// Whether a destination is already set up (so the card should open in the
  /// read-only view). True when the backend profile has a mobile number or a
  /// bank PIN, or the native side has a saved destination.
  bool _hasSavedDestination(ForwardingStatus? status) {
    final p = widget.initialProfile;
    final mobileSaved =
        p != null &&
        p.forwardingMethod == ForwardingMethod.mobileNumber &&
        (p.forwardingPhoneNumber?.isNotEmpty ?? false);
    final bankSaved =
        p != null &&
        p.forwardingMethod == ForwardingMethod.bankAccount &&
        (p.bankAccountPin?.isNotEmpty ?? false);
    // Native-side saved destinations (the source of truth on Android), matched to
    // the saved method so a leftover value for the other method doesn't count.
    final nativeMobileSaved =
        status != null &&
        !status.isBankMethod &&
        (status.destination?.isNotEmpty ?? false);
    final nativeBankSaved =
        status != null && status.isBankMethod && status.hasBankPin;
    return mobileSaved || bankSaved || nativeMobileSaved || nativeBankSaved;
  }

  /// Seeds the sweep interval, the destination field, and the primary/secondary
  /// PIN fields from the native side's saved values, once they load. The PINs are
  /// pre-filled (masked) so a returning user sees their saved values just like the
  /// bank PIN; a first-time user has none stored, so the fields stay empty.
  void _seedFromNative(ForwardingStatus? status) {
    if (_seededFromNative || status == null) return;
    _seededFromNative = true;
    _intervalMinutes = status.intervalMinutes.clamp(1, 5);
    // With no backend profile (the norm on Android), the native side is the only
    // record of which method was chosen, so adopt it. When a backend profile did
    // set the method, leave that in place.
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
    // Bank PIN now comes back from the native Keystore too, so the bank form
    // pre-fills without any backend round-trip.
    if (_bankPinController.text.isEmpty && (status.bankPin?.isNotEmpty ?? false)) {
      _bankPinController.text = status.bankPin!;
    }
  }

  void _cancelEdit() {
    // Revert every field to its saved value. The backend profile wins when
    // present; otherwise (the norm on Android) fall back to the native side,
    // which is the real source of truth for method / destination / all PINs.
    final status = ref.read(nativeForwardingProvider).value?.status;
    final nativeMethod = status != null
        ? ForwardingMethod.fromWire(status.forwardingMethod)
        : ForwardingMethod.mobileNumber;
    setState(() {
      _editing = false;
      _showPin = false;
      _method = widget.initialProfile?.forwardingMethod ?? nativeMethod;
      _destinationController.text =
          widget.initialProfile?.forwardingPhoneNumber ??
          status?.destination ??
          '';
      _bankPinController.text =
          widget.initialProfile?.bankAccountPin ?? status?.bankPin ?? '';
      _pinController.text = status?.pin ?? '';
      _secondaryPinController.text = status?.secondaryPin ?? '';
    });
  }

  /// Assembles the backend profile payload from the current form values. Used
  /// for the (best-effort on Android) backend sync and the iOS backend save.
  ForwardingProfileInput _buildInput() {
    final isMobile = _method == ForwardingMethod.mobileNumber;
    final destination = _destinationController.text.trim();
    // Full name comes from the signed-in Google identity (the backend still
    // requires it); this card no longer asks for it.
    final authName = ref.read(authControllerProvider).value?.fullName.trim() ?? '';
    final fullName = authName.isNotEmpty
        ? authName
        : (widget.initialProfile?.fullName ?? 'e-Xawil user');

    return ForwardingProfileInput(
      fullName: fullName,
      // The account's own number is read on-device from the *800# balance
      // screen, so it isn't collected here. Preserve any existing value.
      phoneNumber: widget.initialProfile?.phoneNumber,
      forwardingMethod: _method,
      forwardingPhoneNumber: isMobile ? destination : null,
      // Bank forwarding is a single PIN now, stored in `bankAccountNumber`;
      // the old bank name / holder fields are no longer collected.
      bankName: null,
      bankAccountNumber: isMobile ? null : _bankPinController.text.trim(),
      bankAccountHolderName: null,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final isMobile = _method == ForwardingMethod.mobileNumber;
    final destination = _destinationController.text.trim();
    setState(() => _saving = true);
    try {
      final input = _buildInput();

      if (Platform.isAndroid) {
        // The on-device forwarder is the source of truth, and saving to it is a
        // local, reliable operation (SharedPreferences + Android Keystore). This
        // is what makes forwarding actually work, so it must succeed for the save
        // to count. For a bank destination the native side dials the *800#
        // deposit walk and types the bank PIN; the mobile destination is left
        // untouched (passed null) so switching back still pre-fills it. The
        // account PIN (primary) is reused from what's already stored.
        await ref
            .read(nativeForwardingProvider.notifier)
            .saveDestination(
              forwardingMethod: _method.index,
              destination: isMobile ? destination : null,
              pin: _pinController.text.isEmpty
                  ? null
                  : _pinController.text.trim(),
              secondaryPin: _secondaryPinController.text.isEmpty
                  ? null
                  : _secondaryPinController.text.trim(),
              bankPin: isMobile ? null : _bankPinController.text.trim(),
              intervalMinutes: _intervalMinutes,
            );

        // Sync to the backend as a BEST-EFFORT background task: it's only a
        // history/management mirror, and forwarding runs entirely on-device, so a
        // backend that's unreachable (very common on a physical phone) must never
        // fail the save or block the UI. Capture the notifier up front so the
        // fire-and-forget call doesn't touch `ref` after this widget is gone.
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
        // iOS / other: no native forwarder, so the backend profile is the only
        // store. This one is awaited and surfaces failures via the snackbar.
        await ref.read(customerProfileControllerProvider.notifier).save(input);
      }

      if (!mounted) return;
      // Saved - collapse back to the read-only view.
      setState(() {
        _editing = false;
        _showPin = false;
      });
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
    final profile = widget.initialProfile;
    final isMobile = _method == ForwardingMethod.mobileNumber;

    final rows = <Widget>[];
    if (isMobile) {
      final destination = (profile?.forwardingPhoneNumber?.isNotEmpty ?? false)
          ? profile!.forwardingPhoneNumber!
          : (status?.destination ?? '—');
      rows.add(_ReadOnlyRow(label: 'Destination mobile number', value: destination));
      if (Platform.isAndroid) {
        rows.add(
          _ReadOnlyRow(
            label: 'Check every',
            value: '$_intervalMinutes minute${_intervalMinutes == 1 ? '' : 's'}',
          ),
        );
        if (status?.hasPin ?? false) {
          rows.add(const _ReadOnlyRow(label: 'PIN', value: '•••• saved'));
        }
      }
    } else {
      rows.add(const _ReadOnlyRow(label: 'Bank account PIN', value: '•••• saved'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your money is forwarded to', style: theme.textTheme.titleMedium),
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
            onSelectionChanged: (selection) =>
                setState(() => _method = selection.first),
          ),
          const SizedBox(height: 16),
          if (_method == ForwardingMethod.mobileNumber)
            ..._mobileNumberFields(theme, status)
          else
            ..._bankAccountFields(theme),
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

  /// The "Show PIN" checkbox that unmasks the PIN field(s) as they're typed.
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

  /// The "Check every" balance-sweep interval dropdown, shared by both the
  /// mobile and bank forms (the sweep's phase-1 balance check runs for both).
  Widget _checkIntervalField() {
    return DropdownButtonFormField<int>(
      initialValue: _intervalMinutes,
      decoration: const InputDecoration(
        labelText: 'Check every',
        helperText: 'How often the balance sweep runs (auto-forward mode)',
        helperMaxLines: 2,
      ),
      items: [
        for (var m = 1; m <= 5; m++)
          DropdownMenuItem(
            value: m,
            child: Text('$m minute${m == 1 ? '' : 's'}'),
          ),
      ],
      onChanged: _saving
          ? null
          : (v) => setState(() => _intervalMinutes = v ?? 1),
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

  List<Widget> _mobileNumberFields(ThemeData theme, ForwardingStatus? status) {
    if (!Platform.isAndroid) {
      return [
        _destinationField(),
        const SizedBox(height: 16),
        _InfoNote(
          theme: theme,
          text:
              'Automatic USSD forwarding runs on Android only — iOS can\'t dial the '
              'balance USSD or auto-fill the PIN. Use this screen on your Android phone '
              'with the Zaad SIM.',
        ),
      ];
    }

    return [
      _destinationField(),
      const SizedBox(height: 16),
      TextField(
        controller: _pinController,
        obscureText: !_showPin,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Primary PIN',
          helperText: status?.hasPin ?? false
              ? 'Saved — tap "Show PIN" to reveal. Typed on the *800# balance & *806# confirm prompts.'
              : 'Typed on the *800# balance and *806# confirm prompts.',
          helperMaxLines: 2,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _secondaryPinController,
        obscureText: !_showPin,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Secondary PIN',
          helperText: status?.hasSecondaryPin ?? false
              ? 'Saved — tap "Show PIN" to reveal. Sent inside the *806# command.'
              : 'Sent inside the *806# send command.',
          helperMaxLines: 2,
        ),
      ),
      _showPinToggle(),
      const SizedBox(height: 8),
      _checkIntervalField(),
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

  List<Widget> _bankAccountFields(ThemeData theme) {
    final hasSavedPin = widget.initialProfile?.bankAccountPin?.isNotEmpty ?? false;
    return [
      TextFormField(
        key: const ValueKey('bankAccountPin'),
        controller: _bankPinController,
        obscureText: !_showPin,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Bank account PIN',
          helperText: hasSavedPin
              ? 'Saved. Used to authorise transfers to your bank account.'
              : 'Used to authorise transfers to your bank account.',
          helperMaxLines: 2,
        ),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Required' : null,
      ),
      _showPinToggle(),
      const SizedBox(height: 8),
      _checkIntervalField(),
      const SizedBox(height: 12),
      _InfoNote(
        theme: theme,
        text:
            'The balance sweep dials *800#, then deposits to your bank account by '
            'entering this PIN on the deposit menu. "Check every" sets how often it '
            'runs in auto-forward mode.',
      ),
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
