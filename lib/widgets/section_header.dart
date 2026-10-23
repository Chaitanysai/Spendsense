import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

/// Section header: a bold title with an optional trailing text action.
///
/// The action is given a full 48dp-high tap target rather than being wrapped
/// tightly around the 11px label it renders.
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
    final hasAction =
        (actionLabel != null || actionIcon != null) && onAction != null;

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.h2(context).copyWith(fontSize: 17),
            ),
          ),
          if (hasAction)
            Semantics(
              button: true,
              label: actionLabel ?? 'Open',
              excludeSemantics: true,
              child: Pressable(
                onTap: onAction,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: 48, minWidth: 48),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (actionLabel != null)
                        Text(
                          actionLabel!,
                          style: AppText.label(context).copyWith(
                            color: AppColors.brandInk(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (actionIcon != null) ...[
                        if (actionLabel != null)
                          const SizedBox(width: AppSpacing.xs),
                        Icon(
                          actionIcon,
                          size: 16,
                          color: AppColors.brandInk(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
