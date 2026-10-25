import 'package:flutter/material.dart';

import '../../../services/sound_service.dart';
import '../../../utils/app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';
import '../../../widgets/pressable.dart';

/// The two in-place states of the auth screen.
enum AuthMode { signIn, createAccount }

/// Segmented pill toggle between the sign-in and create-account forms.
///
/// Same visual language as the transaction type toggle: one tinted track,
/// with the selected segment marked by fill, weight and ink — never by
/// colour alone. Labels may wrap instead of ellipsising so the toggle stays
/// legible at large text scales.
class AuthModeToggle extends StatelessWidget {
  final AuthMode mode;
  final ValueChanged<AuthMode> onSelect;

  /// False while a request is in flight, so the mode cannot be swapped out
  /// from under a submit.
  final bool enabled;

  const AuthModeToggle({
    super.key,
    required this.mode,
    required this.onSelect,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              context,
              label: 'Sign in',
              selected: mode == AuthMode.signIn,
              onTap: enabled ? () => onSelect(AuthMode.signIn) : null,
            ),
          ),
          Expanded(
            child: _segment(
              context,
              label: 'Create account',
              selected: mode == AuthMode.createAccount,
              onTap: enabled ? () => onSelect(AuthMode.createAccount) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final ink = selected
        ? AppColors.brandInk(context)
        : AppColors.textTertiary(context);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: Pressable(
          onTap: onTap,
          sound: SoundEventType.selectionChanged,
          child: AnimatedContainer(
            duration: AppMotion.respect(context, AppMotion.fast),
            curve: AppMotion.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.brand.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: AppText.label(context).copyWith(
                fontSize: 13,
                color: ink,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
