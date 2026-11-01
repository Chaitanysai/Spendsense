import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';

/// The one tinted plate every leading glyph sits on.
///
/// Settings rows, the dock and any list that puts an icon before its title use
/// this so a well is the same size, radius and ink everywhere. A well is a
/// 12% (light) / 22% (dark) tint of the icon's own colour, so painting the
/// glyph in that colour measured ~2-3:1 and some icons effectively vanished.
/// [AppColors.inkOn] lifts the glyph until it clears AA against the well it
/// actually sits on — always route the colour through it.
///
/// [color] is a palette role (`AppColors.azure`, `brandBright`, …), not a fixed
/// hue: it resolves per palette, so check the result in every theme.
class IconWell extends StatelessWidget {
  final IconData icon;
  final Color color;

  /// Corner shape of the plate. Defaults to the squircle used by list rows;
  /// pass `BorderRadius.circular(AppRadius.pill)` for a circle.
  final BorderRadius? borderRadius;

  const IconWell({
    super.key,
    required this.icon,
    required this.color,
    this.borderRadius,
  });

  /// The well's fill for the current theme. Exposed so a caller that also
  /// tints a neighbouring element matches the plate exactly.
  static Color fill(Color color, bool isDark) =>
      color.withValues(alpha: isDark ? 0.22 : 0.12);

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final tinted = fill(color, dark);
    return Container(
      width: AppSpacing.wellSize,
      height: AppSpacing.wellSize,
      decoration: BoxDecoration(
        color: tinted,
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(
        icon,
        size: AppSpacing.wellGlyph,
        // Measure against the surface the plate is composited onto.
        color: AppColors.inkOn(
          color,
          tinted,
          dark ? AppColors.surface : AppColors.surfaceColor(context),
        ),
      ),
    );
  }
}
