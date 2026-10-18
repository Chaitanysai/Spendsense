import 'package:flutter/material.dart';

import 'app_palette.dart';

/// SpendSense design tokens — deep navy → rich blue → electric cyan by default,
/// and user-selectable beyond that.
///
/// This class is the single read point for every colour in the app. The values
/// below mirror the **active** [AppPalette] into mutable statics, which keeps
/// every existing call site (`AppColors.brand`, `AppColors.heroGradient`, …)
/// working unchanged while still allowing the palette to be swapped at runtime:
/// [applyPalette] rewrites these fields and the widget tree then rebuilds.
///
/// The brand ramp is deliberately cool and low-saturation at the base so the
/// hero gradient reads as "premium finance", with the accent reserved for
/// selective highlights. A single warm accent is kept for money/salary cues,
/// because an all-blue palette gives the eye nothing to prioritise against.
class AppColors {
  AppColors._();

  // ── Active palette ───────────────────────────────────────────────────────────
  static AppPalette _palette = AppPalette.oceanBlue;

  static AppPalette get palette => _palette;

  /// Mirrors [palette] into the fields below. Call before rebuilding the tree
  /// that reads them (see `ThemeProvider.setPalette`).
  static void applyPalette(AppPalette next) {
    _palette = next;

    navyDeep = next.deep;
    brand = next.brand;
    brandBright = next.bright;
    azure = next.mid;
    cyan = next.accent;
    amber = next.warm;

    background = next.background;
    surface = next.surface;
    surfaceMuted = next.surfaceMuted;
    borderLight = next.borderLight;

    darkBackground = next.darkBackground;
    darkSurface = next.darkSurface;
    darkSurfaceAlt = next.darkSurfaceAlt;
    borderDark = next.borderDark;

    brandGradient = next.brandGradient;
    heroGradient = next.heroGradient;
    electricGradient = next.electricGradient;
    amberGradient = next.amberGradient;
    gaugeGradient = next.gaugeGradient;
    chartPalette = next.chartPalette;
  }

  // ── Brand ramp ─────────────────────────────────────────────────────────────
  static Color navyDeep = AppPalette.oceanBlue.deep; // deepest navy
  static Color brand = AppPalette.oceanBlue.brand; // primary
  static Color brandBright = AppPalette.oceanBlue.bright; // electric blue
  static Color azure = AppPalette.oceanBlue.mid; // CTA / mid stop
  static Color cyan = AppPalette.oceanBlue.accent; // selective highlight
  static Color blueDeep = AppPalette.oceanBlue.deep; // gradient end

  /// Warm accent for salary, wallet and budget cues. Kept intentionally outside
  /// the cool ramp so it reads as a highlight, not a fourth brand colour.
  static Color amber = AppPalette.oceanBlue.warm;

  // ── Semantic ───────────────────────────────────────────────────────────────
  // Fixed across every palette: red must always mean money out.
  static const Color expenseRed = AppPalette.expenseRed;
  static const Color incomeGreen = AppPalette.incomeGreen;
  static const Color danger = AppPalette.danger;

  // ── Gradients ────────────────────────────────────────────────────────────────
  /// Rich hero gradient used on balance cards, CTAs and the app logo.
  static LinearGradient brandGradient = AppPalette.oceanBlue.brandGradient;

  /// Alias with an explicit, semantic name for the hero treatment.
  static LinearGradient heroGradient = AppPalette.oceanBlue.heroGradient;

  /// Cool electric gradient for primary buttons and the nav action.
  static LinearGradient electricGradient =
      AppPalette.oceanBlue.electricGradient;

  /// Amber accent gradient for small highlights.
  static LinearGradient amberGradient = AppPalette.oceanBlue.amberGradient;

  /// Positive / money-in gradient. Shared by the income hero and the "spending
  /// went down" stat so a favourable state reads the same everywhere.
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF0E8A55), Color(0xFF22C77B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Budget gauge arc.
  static LinearGradient gaugeGradient = AppPalette.oceanBlue.gaugeGradient;

  /// Diagonal white sheen overlay for frosted glass highlights.
  static const LinearGradient glassSheen = LinearGradient(
    colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Categorical palette for charts and bubbles. Hues are spaced around the
  /// wheel rather than staying in the brand ramp so adjacent slices stay
  /// separable for colour-blind viewers.
  static List<Color> chartPalette = AppPalette.oceanBlue.chartPalette;

  // ── Theme surfaces ────────────────────────────────────────────────────────────
  static Color background = AppPalette.oceanBlue.background; // cool off-white
  static Color surface = AppPalette.oceanBlue.surface;
  static Color surfaceMuted = AppPalette.oceanBlue.surfaceMuted;
  static Color borderLight = AppPalette.oceanBlue.borderLight;

  static Color darkBackground =
      AppPalette.oceanBlue.darkBackground; // deep navy
  static Color darkSurface = AppPalette.oceanBlue.darkSurface;
  static Color darkSurfaceAlt = AppPalette.oceanBlue.darkSurfaceAlt;
  static Color borderDark = AppPalette.oceanBlue.borderDark;

  // ── Context-aware helpers ─────────────────────────────────────────────────────
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color scaffold(BuildContext context) =>
      isDark(context) ? darkBackground : background;

  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? darkSurface : surface;

  static Color surfaceAlt(BuildContext context) =>
      isDark(context) ? darkSurfaceAlt : surfaceMuted;

  static Color panel(BuildContext context) =>
      isDark(context) ? darkSurfaceAlt : surfaceMuted;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF1FF) : const Color(0xFF0A1734);

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFA9BAD8) : const Color(0xFF4A5A78);

  static Color textTertiary(BuildContext context) =>
      isDark(context) ? const Color(0xFF74879F) : const Color(0xFF8391AC);

  static Color border(BuildContext context) =>
      isDark(context) ? borderDark : borderLight;

  /// Border colour from a plain brightness flag (for ThemeData construction).
  static Color borderDarkOrLight(bool isDark) =>
      isDark ? borderDark : borderLight;

  static Color shadow(BuildContext context) => isDark(context)
      ? Colors.black.withValues(alpha: 0.5)
      : const Color(0xFF0E2E86).withValues(alpha: 0.10);

  /// Foreground for the selected navigation item.
  ///
  /// `brand` on the near-white light-mode glass bar measures ~7.2:1 and clears
  /// AA comfortably. The same `brand` on the dark bar falls to ~2.5:1, which is
  /// below the 4.5:1 needed for the 9px label, so dark mode steps up to
  /// `azure` (~6.8:1) while staying in the same blue family.
  static Color navSelected(BuildContext context) =>
      isDark(context) ? azure : brand;

  // ── Glass tokens ──────────────────────────────────────────────────────────────

  /// Fill for frosted content cards.
  ///
  /// A neutral white wash over the near-black dark scaffold reads as a flat grey
  /// slab, disconnected from the navy identity, so the dark fill is tinted toward
  /// the palette's own navy surface. Light keeps the cool white frost.
  static Color glassFill(BuildContext context) => isDark(context)
      ? Color.alphaBlend(
          Colors.white.withValues(alpha: 0.06),
          darkSurfaceAlt,
        ).withValues(alpha: 0.72)
      : Colors.white.withValues(alpha: 0.66);

  static Color glassBorder(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.14)
      : Colors.white.withValues(alpha: 0.85);

  /// Diagonal sheen overlay for glass surfaces.
  ///
  /// Kept deliberately faint in dark mode: the light-mode sheen is what washed
  /// dark cards toward grey. [glassSheen] remains the light-mode value.
  static LinearGradient glassSheenFor(BuildContext context) =>
      isDark(context) ? darkGlassSheen : glassSheen;

  static const LinearGradient darkGlassSheen = LinearGradient(
    colors: [Color(0x12FFFFFF), Color(0x00FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
