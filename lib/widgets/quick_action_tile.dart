import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

/// One action in the dashboard's quick-action grid.
class QuickAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// Equal-size, evenly distributed quick-action tiles.
///
/// The column count is derived from the width actually available and from the
/// effective text scale, never from a device width: four across when each tile
/// can keep at least [AppSpacing.tileMinWidth] at normal text sizes, otherwise a
/// 2 x 2 grid (narrow screens, display scaling, accessibility text sizes).
/// Every row is wrapped in an [IntrinsicHeight] with stretched tiles, so a
/// label that wraps to a second line can never make one tile taller than its
/// neighbours.
class QuickActionGrid extends StatelessWidget {
  final List<QuickAction> actions;

  const QuickActionGrid({super.key, required this.actions});

  /// Visible for tests.
  static int columnsFor({
    required double width,
    required double textScale,
    required int count,
  }) {
    if (count <= 0) return 1;
    final gaps = AppSpacing.tileGap * (count - 1);
    final fitsOneRow = (width - gaps) / count >=
        AppSpacing.tileMinWidth * (textScale > 1 ? textScale : 1);
    if (fitsOneRow && textScale <= 1.3) return count;
    return (count / 2).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(
          width: constraints.maxWidth,
          textScale: textScale,
          count: actions.length,
        );
        final rows = <List<QuickAction>>[
          for (var i = 0; i < actions.length; i += columns)
            actions.sublist(i, (i + columns).clamp(0, actions.length)),
        ];

        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: AppSpacing.tileGap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: AppSpacing.tileGap),
                      // Short final rows keep tile width via an empty slot, so
                      // tiles in every row stay the same size.
                      Expanded(
                        child: c < rows[r].length
                            ? QuickActionTile(action: rows[r][c])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class QuickActionTile extends StatelessWidget {
  final QuickAction action;

  const QuickActionTile({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppText.label(context).copyWith(
      fontSize: 11.5,
      height: 1.15,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary(context),
    );
    // Two lines at the effective text scale, rounded up to whole pixels.
    final labelHeight =
        (2 * 11.5 * 1.15 * MediaQuery.textScalerOf(context).scale(1))
                .ceilToDouble() +
            1;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        sound: SoundEventType.buttonTap,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: AppSpacing.tileMinHeight),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceColor(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border(context)),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow(context),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: AppSpacing.tileIconBox,
                height: AppSpacing.tileIconBox,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.11),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  action.icon,
                  size: 19,
                  color: AppColors.brandInk(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // The label always reserves exactly two lines, so a label that
              // wraps can never change a tile's height (in any row).
              SizedBox(
                height: labelHeight,
                child: Center(
                  child: Text(
                    action.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: labelStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
