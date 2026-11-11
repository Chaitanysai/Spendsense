import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';

/// The one tinted plate every leading glyph sits on.
///
/// Settings rows, the dock, the assistant plates and any list that puts an icon
/// before its title use this so a well is the same size, radius and ink
/// everywhere. A well is a 12% (light) / 22% (dark) tint of the icon's own
/// colour, so painting the glyph in that colour measured ~2-3:1 and some icons
/// effectively vanished. [AppColors.inkOn] lifts the glyph until it clears AA
/// against the well it actually sits on — always route the colour through it.
///
/// [color] is a palette role (`AppColors.azure`, `brandBright`, …), not a fixed
/// hue: it resolves per palette, so check the result in every theme.
///
/// Screens that need a larger or rounder plate pass [size], [glyphSize],
/// [circular] or [borderRadius] rather than building a plate of their own —
/// a hand-rolled `Container` + `Icon` is exactly how the assistant screens
/// ended up with six different plate radii and an unmeasured glyph ink.
class IconWell extends StatelessWidget {
  final IconData icon;
  final Color color;

  /// Corner shape of the plate. Defaults to the semantic [AppRadius.icon]
  /// plate; pass `BorderRadius.circular(AppRadius.pill)` for a circle, or
  /// [AppRadius.nestedAll] to sit concentrically inside a larger card.
  final BorderRadius? borderRadius;

  /// Plate edge length. Defaults to the standard [AppSpacing.wellSize]; the
  /// assistant screens pass their own plate sizes (the 30/38/42dp plates that
  /// used to hold a literal radius each).
  final double size;

  /// Glyph size inside the plate. Defaults to [AppSpacing.wellGlyph]; scaled
  /// callers pass their own so the glyph keeps its proportion to [size].
  final double? glyphSize;

  /// Overrides [plateTint] for callers that have already resolved their own
  /// plate colour.
  ///
  /// This exists for plates that are *not* a tint of a palette role — the
  /// gradient hero plates, whose fill is a [LinearGradient] stop rather than a
  /// single hue. Passing the stop here keeps the plate/ink pairing measured by
  /// the same [AppColors.inkOn] rule as every other well instead of forking a
  /// second contrast calculation. Leave null to get the palette-aware tint.
  final Color? plateColor;

  /// Paints the plate as a circle instead of a rounded square.
  ///
  /// Kept as a switch rather than a `BorderRadius` because a circle cannot be
  /// expressed as a non-uniform corner (see [QuickActionTile]'s round plate).
  final bool circular;

  const IconWell({
    super.key,
    required this.icon,
    required this.color,
    this.borderRadius,
    this.size = AppSpacing.wellSize,
    this.glyphSize,
    this.plateColor,
    this.circular = false,
  });

  /// The well's fill for the current theme. Exposed so a caller that also
  /// tints a neighbouring element matches the plate exactly.
  static Color fill(Color color, bool isDark) =>
      color.withValues(alpha: isDark ? 0.22 : 0.12);

  /// Lowest plate-to-card contrast at which a well still reads as a plate.
  ///
  /// Light wells are a 12% tint on white and measure about 1.16-1.18:1 in every
  /// palette, which has always read as a soft plate, so the floor there only
  /// rejects a well with no plate at all. Dark wells are a 22% tint on a dark
  /// card; Deep Navy's slate `brand` measured about 1.1:1 and the plate
  /// disappeared, so the dark floor is stricter.
  static double minPlateContrast(bool isDark) => isDark ? 1.18 : 1.10;

  /// The colour the well is actually tinted with.
  ///
  /// A palette role such as `brand` can be a dark slate (Deep Navy's is
  /// #253745), and 22% of it over a #11212D card is invisible: the row then
  /// shows a floating glyph with no plate while its neighbours have one. When
  /// the requested tint would not separate from the card, the accent takes its
  /// place so every row in a section keeps the same plate.
  static Color plateTint(Color color, bool isDark) {
    final base = AppColors.glassBase(isDark);
    final plate = Color.alphaBlend(fill(color, isDark), base);
    if (AppColors.contrastRatio(plate, base) >= minPlateContrast(isDark)) {
      return color;
    }
    return AppColors.navAccentFor(isDark);
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    // A caller-supplied plate colour is already the hue; anything else is a
    // palette role that has to prove it separates from the card first.
    final tint = plateColor ?? plateTint(color, dark);
    final tinted = fill(tint, dark);
    final glyph = glyphSize ??
        (size == AppSpacing.wellSize
            ? AppSpacing.wellGlyph
            : size * (AppSpacing.wellGlyph / AppSpacing.wellSize));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tinted,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular
            ? null
            : (borderRadius ?? BorderRadius.circular(AppRadius.icon)),
      ),
      child: Icon(
        icon,
        size: glyph,
        // Measure against the card the plate is composited onto. Dark mode
        // used to measure against the LIGHT surface token, so the ink was
        // chosen for a white card that was never there.
        color: AppColors.inkOn(tint, tinted, AppColors.glassBase(dark)),
      ),
    );
  }
}
