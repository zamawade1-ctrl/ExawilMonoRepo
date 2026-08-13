import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_info.dart';
import '../../../core/routing/app_router.dart';
import '../../info/presentation/privacy_policy_screen.dart';
import 'auth_providers.dart';

/// The Somali country calling code. The phone field only ever collects the 9
/// national digits; this prefix is fixed in the UI and prepended on submit, so a
/// user can't mistype or omit it.
const String _kCountryCode = '+252';

/// The two things a signed-out user can do on the first page.
enum _AuthMode { signIn, signUp }

/// The app's first page: a combined sign-in / sign-up form. Users authenticate
/// with a username-or-email + password (the flow that replaced Google Sign-In).
/// The Telesom OTP second factor is a follow-up, so no code is asked for here.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscurePassword = true;

  /// Sign-up requires agreeing to the privacy policy first.
  bool _agreedToPrivacy = false;

  bool get _isSignUp => _mode == _AuthMode.signUp;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final signingUp = _isSignUp;
    // Can't sign up without agreeing to the privacy policy.
    if (signingUp && !_agreedToPrivacy) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _snack(Theme.of(context).colorScheme,
              'Please agree to the Privacy Policy to sign up.',
              success: false),
        );
      return;
    }
    final notifier = ref.read(authControllerProvider.notifier);
    // Captured before the await: on success the router immediately swaps this
    // screen for /home, but MaterialApp's root ScaffoldMessenger survives the
    // route change, so the success toast still shows on the home screen. The
    // color scheme is captured too, since `context` may be unmounting by then.
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    // The field holds only the 9 national digits; the fixed +252 prefix is
    // prepended here so the backend always receives a full E.164-style number.
    final phoneNumber = '$_kCountryCode${_phoneController.text.trim()}';

    try {
      if (signingUp) {
        await notifier.register(
          fullName: _fullNameController.text.trim(),
          phoneNumber: phoneNumber,
          password: _passwordController.text,
        );
      } else {
        await notifier.login(
          phoneNumber: phoneNumber,
          password: _passwordController.text,
        );
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _snack(
            scheme,
            signingUp
                ? 'Account created — you\'re signed in.'
                : 'Signed in successfully.',
            success: true,
          ),
        );
    } on AuthException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(_snack(scheme, e.message, success: false));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _snack(scheme, 'Something went wrong. Please try again.', success: false),
        );
    }
  }

  SnackBar _snack(ColorScheme scheme, String message, {required bool success}) {
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: success ? scheme.primary : scheme.error,
      content: Row(
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.error_outline,
            color: success ? scheme.onPrimary : scheme.onError,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: success ? scheme.onPrimary : scheme.onError,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/branding/app_icon.png',
                        width: 84,
                        height: 84,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppInfo.appName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSignUp
                          ? 'Create an account to set up automatic USSD '
                                'forwarding from your Zaad or eDahab account.'
                          : 'Sign in to manage your automatic USSD forwarding.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SegmentedButton<_AuthMode>(
                      segments: const [
                        ButtonSegment(
                          value: _AuthMode.signIn,
                          label: Text('Sign in'),
                          icon: Icon(Icons.login),
                        ),
                        ButtonSegment(
                          value: _AuthMode.signUp,
                          label: Text('Sign up'),
                          icon: Icon(Icons.person_add_alt),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: isLoading
                          ? null
                          : (s) => _switchMode(s.first),
                    ),
                    const SizedBox(height: 24),
                    ..._fields(),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isSignUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () => _switchMode(
                              _isSignUp ? _AuthMode.signIn : _AuthMode.signUp,
                            ),
                      child: Text(
                        _isSignUp
                            ? 'Already have an account? Sign in'
                            : "Don't have an account? Sign up",
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Pricing is public: reachable before signing in (see the router's
                    // signed-out allow-list).
                    OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.billing),
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: const Text('View plans & pricing'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The mode-specific fields. Phone + password are shared; sign-up adds a name.
  /// Every field carries an explicit label above it for clarity.
  List<Widget> _fields() {
    return [
      if (_isSignUp) ...[
        const _FieldLabel('Full name'),
        _TextField(
          controller: _fullNameController,
          label: 'Full name',
          icon: Icons.badge_outlined,
          textCapitalization: TextCapitalization.words,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Enter your full name'
              : null,
        ),
        const SizedBox(height: 16),
      ],
      const _FieldLabel('Phone number'),
      _TextField(
        controller: _phoneController,
        label: 'Phone number',
        icon: Icons.phone_outlined,
        keyboardType: TextInputType.number,
        // Fixed country code + exactly 9 national digits.
        prefixText: '$_kCountryCode ',
        hintText: '61 234 5678',
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(9),
        ],
        validator: (v) {
          final value = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
          if (value.isEmpty) return 'Enter your phone number';
          if (value.length != 9) return 'Enter the 9 digits after $_kCountryCode';
          return null;
        },
      ),
      const SizedBox(height: 16),
      const _FieldLabel('Password'),
      _passwordField(isNew: _isSignUp),
      if (_isSignUp) ...[
        const SizedBox(height: 8),
        _privacyConsent(),
      ],
    ];
  }

  /// The required privacy-policy consent row shown on sign-up: a checkbox plus a
  /// tappable "Privacy Policy" link that opens the policy in a dialog.
  Widget _privacyConsent() {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: _agreedToPrivacy,
          onChanged: (v) => setState(() => _agreedToPrivacy = v ?? false),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('I agree to the ', style: theme.textTheme.bodyMedium),
              GestureDetector(
                onTap: _showPrivacyDialog,
                child: Text(
                  'Privacy Policy',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showPrivacyDialog() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Privacy Policy',
                        style: Theme.of(ctx).textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: const PrivacyPolicyContent(),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() => _agreedToPrivacy = true);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('I agree'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({required bool isNew}) {
    return _TextField(
      controller: _passwordController,
      label: 'Password',
      icon: Icons.lock_outline,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submit(),
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
      validator: (v) {
        final value = v ?? '';
        if (value.isEmpty) return 'Enter your password';
        if (isNew && value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
    );
  }
}

/// A small bold label rendered above a form field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// A themed text field used throughout the auth form.
class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixText,
    this.hintText,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? prefixText;
  final String? hintText;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final void Function(String)? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      inputFormatters: inputFormatters,
      autofillHints: null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        prefixText: prefixText,
        suffixIcon: suffixIcon,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
