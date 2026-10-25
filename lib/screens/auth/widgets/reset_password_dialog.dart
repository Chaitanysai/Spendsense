import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/sound_service.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/sound_scope.dart';
import 'auth_notice.dart';
import 'auth_text_field.dart';

/// Opened from "Forgot password?" on the auth screen: collects the account
/// email and requests a password reset link.
///
/// The dialog runs its own micro state machine — idle, sending, sent, or
/// error — and consumes the provider's user-safe message inline, so a
/// failure never SnackBars and never pops the dialog. A success swaps the
/// body to a confirmation naming the address the link went to.
Future<void> showResetPasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ResetPasswordDialog(),
  );
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog();

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final TextEditingController _emailCtrl = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  String? _emailError;
  String? _error;
  String? _sentTo;
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final auth = context.read<AuthProvider>();
    if (_sending || auth.isBusy) return;

    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Enter your email');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email address');
      return;
    }

    auth.clearError();
    setState(() {
      _emailError = null;
      _error = null;
      _sending = true;
    });

    final ok = await auth.sendPasswordReset(email);
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (ok) {
        _sentTo = email;
      } else {
        // Consume the provider's message here so the screen behind the
        // dialog never flashes the same failure.
        _error = auth.errorMessage ?? 'Could not send the reset link. Try again.';
      }
    });
    if (ok) SoundScope.play(context, SoundEventType.actionSucceeded);
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentTo != null;

    return AlertDialog(
      title: Text('Reset password', style: AppText.title(context)),
      content: AnimatedSize(
        duration: AppMotion.respect(context, AppMotion.base),
        curve: AppMotion.easeOut,
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: sent ? _confirmation(context) : _form(context),
        ),
      ),
      actions: sent
          ? null
          : [
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 48),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
    );
  }

  Widget _form(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter your account email and a reset link will be sent.',
          style: AppText.body(context),
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
          textInputAction: TextInputAction.done,
          autofocus: true,
          enabled: !_sending,
          errorText: _emailError,
          onSubmitted: (_) => _send(),
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          AuthNotice(kind: AuthNoticeKind.error, text: _error!),
        ],
        const SizedBox(height: AppSpacing.xl),
        AppPrimaryButton(
          label: 'Send reset link',
          loading: _sending,
          onPressed: _sending ? null : _send,
        ),
      ],
    );
  }

  Widget _confirmation(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthNotice(
          kind: AuthNoticeKind.success,
          text: 'Reset link sent to $_sentTo',
        ),
        const SizedBox(height: AppSpacing.xl),
        AppPrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
