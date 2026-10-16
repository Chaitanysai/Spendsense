import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

/// Section header with an overline label and an optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.md,
      ),
      child: Row(
        children: [
          Text(title, style: AppText.h2(context)),
          const Spacer(),
          if ((actionLabel != null || actionIcon != null) && onAction != null)
            Pressable(
              onTap: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (actionLabel != null)
                    Text(
                      actionLabel!,
                      style: AppText.label(context).copyWith(
                        color: AppColors.crimson,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (actionIcon != null) ...[
                    if (actionLabel != null)
                      const SizedBox(width: AppSpacing.xs),
                    Icon(actionIcon, size: 16, color: AppColors.crimson),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
