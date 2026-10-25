import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/sound_service.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../../widgets/app_background.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/sound_scope.dart';
import 'widgets/auth_mode_toggle.dart';
import 'widgets/auth_notice.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/reset_password_dialog.dart';

/// Firebase email/password entry point.
///
/// One surface, two modes toggled in place — sign in, or create an account —
/// over the shared [AppBackground]. Submissions go through [AuthProvider]
/// only: on success the app-level auth gate swaps the tree (this screen
/// never navigates), on failure the provider's user-safe message surfaces
/// in the inline error strip above the primary button. Client-side
/// validation lands on the offending field instead.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static const int _minPasswordLength = 8;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  AuthMode _mode = AuthMode.signIn;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  /// True while the reset dialog is up: its failures are consumed and shown
  /// inside the dialog, so the screen never flashes the same error behind
  /// the scrim.
  bool _resetDialogOpen = false;

  @override
  void dispose() {
    for (final ctrl in [_nameCtrl, _emailCtrl, _passwordCtrl, _confirmCtrl]) {
      ctrl.dispose();
    }
    for (final node in [_nameFocus, _emailFocus, _passwordFocus, _confirmFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  // ── Mode and edits ────────────────────────────────────────────────────────

  void _switchMode(AuthMode mode) {
    final auth = context.read<AuthProvider>();
    if (mode == _mode || auth.isBusy) return;
    FocusScope.of(context).unfocus();
    auth.clearError();
    setState(() {
      _mode = mode;
      _nameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmError = null;
    });
  }

  /// Clears one field's client-side error plus any provider error, so a
  /// corrected field stops signalling the previous failure. Nothing is set
  /// while the user is simply typing.
  void _edited({
    required bool Function() hasFieldError,
    required void Function() clearFieldError,
  }) {
    if (hasFieldError()) setState(clearFieldError);
    final auth = context.read<AuthProvider>();
    if (auth.errorMessage != null) auth.clearError();
  }

  // ── Validation and submit ─────────────────────────────────────────────────

  /// Returns true when validation blocked the submit; errors land on the
  /// offending fields and the first one takes focus.
  bool _validate() {
    final signUp = _mode == AuthMode.createAccount;
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    String? nameError;
    String? emailError;
    String? passwordError;
    String? confirmError;

    if (email.isEmpty) {
      emailError = 'Enter your email';
    } else if (!_emailPattern.hasMatch(email)) {
      emailError = 'Enter a valid email address';
    }
    if (password.isEmpty) {
      passwordError = 'Enter your password';
    } else if (signUp && password.length < _minPasswordLength) {
      passwordError = 'Use at least $_minPasswordLength characters';
    }
    if (signUp) {
      if (name.isEmpty) nameError = 'Enter your name';
      if (confirm.isEmpty) {
        confirmError = 'Confirm your password';
      } else if (confirm != password) {
        confirmError = 'Passwords do not match';
      }
    }

    setState(() {
      _nameError = nameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = confirmError;
    });

    final firstError = nameError != null
        ? _nameFocus
        : emailError != null
            ? _emailFocus
            : passwordError != null
                ? _passwordFocus
                : confirmError != null
                    ? _confirmFocus
                    : null;
    if (firstError != null) {
      FocusScope.of(context).requestFocus(firstError);
      SoundScope.play(context, SoundEventType.actionFailed);
    }
    return nameError != null ||
        emailError != null ||
        passwordError != null ||
        confirmError != null;
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    if (auth.isBusy) return;
    FocusScope.of(context).unfocus();
    if (_validate()) return;
    auth.clearError();

    // Sign in has no length rule so short legacy accounts still work; the
    // 8-character minimum is a create-account requirement.
    final ok = _mode == AuthMode.signIn
        ? await auth.signIn(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          )
        : await auth.signUp(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            displayName: _nameCtrl.text.trim(),
          );
    if (!mounted) return;

    // Success needs no navigation: the app-level auth gate swaps the tree.
    if (!ok) SoundScope.play(context, SoundEventType.actionFailed);
  }

  Future<void> _openResetDialog() async {
    final auth = context.read<AuthProvider>();
    if (auth.isBusy) return;
    FocusScope.of(context).unfocus();
    auth.clearError();
    setState(() => _resetDialogOpen = true);
    await showResetPasswordDialog(context);
    if (!mounted) return;
    setState(() => _resetDialogOpen = false);
    auth.clearError();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.isBusy;
    final error = _resetDialogOpen ? null : auth.errorMessage;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              // Centered when the viewport allows, scrolling when the
              // keyboard or large text leaves no room.
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.xl,
                  AppSpacing.page,
                  AppSpacing.xxl,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _hero(context),
                        const SizedBox(height: AppSpacing.xxl),
                        _card(context, busy: busy, error: error),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Column(
      children: [
        const AppLogo(size: 56),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text('SpendSense', style: AppText.h2(context)),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context, {
    required bool busy,
    required String? error,
  }) {
    final signUp = _mode == AuthMode.createAccount;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthModeToggle(mode: _mode, enabled: !busy, onSelect: _switchMode),
          const SizedBox(height: AppSpacing.lg),
          AutofillGroup(
            child: AnimatedSwitcher(
              duration: AppMotion.respect(context, AppMotion.base),
              switchInCurve: AppMotion.easeOut,
              switchOutCurve: AppMotion.easeOut,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: KeyedSubtree(
                key: ValueKey(_mode),
                child: signUp
                    ? _signUpFields(busy: busy)
                    : _signInFields(busy: busy),
              ),
            ),
          ),
          // Inline error strip — never a SnackBar. Slides in as it appears
          // so the button below moves instead of jumping.
          AnimatedSize(
            duration: AppMotion.respect(context, AppMotion.fast),
            curve: AppMotion.easeOut,
            alignment: Alignment.topCenter,
            child: error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: AuthNotice(
                      kind: AuthNoticeKind.error,
                      text: error,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: signUp ? 'Sign up' : 'Sign in',
            icon: Icons.arrow_forward_rounded,
            loading: busy,
            onPressed: busy ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _signInFields({required bool busy}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Welcome back', style: AppText.title(context)),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthTextField(
          controller: _emailCtrl,
          focusNode: _emailFocus,
          label: 'Email',
          icon: Icons.mail_outline_rounded,
          hintText: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          autofillHint: AutofillHints.email,
          textInputAction: TextInputAction.next,
          enabled: !busy,
          errorText: _emailError,
          onSubmitted: (_) => _emailFocus.requestFocus(),
          onChanged: (_) => _edited(
            hasFieldError: () => _emailError != null,
            clearFieldError: () => _emailError = null,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthTextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          initiallyObscured: true,
          autofillHint: AutofillHints.password,
          textInputAction: TextInputAction.done,
          enabled: !busy,
          errorText: _passwordError,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => _edited(
            hasFieldError: () => _passwordError != null,
            clearFieldError: () => _passwordError = null,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 48),
            ),
            onPressed: busy ? null : _openResetDialog,
            child: const Text('Forgot password?'),
          ),
        ),
      ],
    );
  }

  Widget _signUpFields({required bool busy}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Create account', style: AppText.title(context)),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthTextField(
          controller: _nameCtrl,
          focusNode: _nameFocus,
          label: 'Name',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.name,
          autofillHint: AutofillHints.name,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          enabled: !busy,
          errorText: _nameError,
          onSubmitted: (_) => _emailFocus.requestFocus(),
          onChanged: (_) => _edited(
            hasFieldError: () => _nameError != null,
            clearFieldError: () => _nameError = null,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthTextField(
          controller: _emailCtrl,
          focusNode: _emailFocus,
          label: 'Email',
          icon: Icons.mail_outline_rounded,
          hintText: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          autofillHint: AutofillHints.email,
          textInputAction: TextInputAction.next,
          enabled: !busy,
          errorText: _emailError,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          onChanged: (_) => _edited(
            hasFieldError: () => _emailError != null,
            clearFieldError: () => _emailError = null,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthTextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          initiallyObscured: true,
          autofillHint: AutofillHints.newPassword,
          textInputAction: TextInputAction.next,
          enabled: !busy,
          helperText: 'At least $_minPasswordLength characters.',
          errorText: _passwordError,
          onSubmitted: (_) => _confirmFocus.requestFocus(),
          onChanged: (_) => _edited(
            hasFieldError: () => _passwordError != null,
            clearFieldError: () => _passwordError = null,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthTextField(
          controller: _confirmCtrl,
          focusNode: _confirmFocus,
          label: 'Confirm password',
          icon: Icons.lock_outline_rounded,
          initiallyObscured: true,
          autofillHint: AutofillHints.newPassword,
          textInputAction: TextInputAction.done,
          enabled: !busy,
          revealLabel: 'confirmed password',
          errorText: _confirmError,
          onSubmitted: (_) => _submit(),
          onChanged: (_) => _edited(
            hasFieldError: () => _confirmError != null,
            clearFieldError: () => _confirmError = null,
          ),
        ),
      ],
    );
  }
}
