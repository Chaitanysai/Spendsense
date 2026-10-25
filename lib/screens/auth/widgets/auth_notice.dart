import 'package:flutter/material.dart';

import '../../../utils/app_colors.dart';
import '../../../utils/app_spacing.dart';
import '../../../utils/app_text_styles.dart';

enum AuthNoticeKind { error, success }

/// Inline status surface for the auth flows: a tinted strip with an icon
/// and the message. State is always signalled by icon *and* text, never by
/// colour alone, and the node is a live region so screen readers announce
/// it the moment it appears.
class AuthNotice extends StatelessWidget {
  final AuthNoticeKind kind;
  final String text;

  const AuthNotice({
    super.key,
    required this.kind,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isError = kind == AuthNoticeKind.error;
    // Error keeps the fixed danger token. Success is brand ink, not
    // incomeGreen — that green is reserved for money-in semantics, and this
    // notice is not a money signal.
    final tint = isError ? AppColors.danger : AppColors.brand;
    final ink =
        isError ? AppColors.danger : AppColors.brandInk(context);
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: ink.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: ink),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                style: AppText.label(context).copyWith(
                  fontSize: 13,
                  height: 1.35,
                  // Message ink stays neutral; the icon and tint carry the
                  // kind, keeping the sentence readable on both canvases.
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
