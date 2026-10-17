import 'package:flutter/material.dart';

/// SpendSense design tokens — deep navy → rich blue → electric cyan.
///
/// The brand ramp is deliberately cool and low-saturation at the base so the
/// hero gradient reads as "premium finance", with cyan reserved for selective
/// highlights. A single warm accent (amber) is kept for money/salary cues,
/// because an all-blue palette gives the eye nothing to prioritise against.
class AppColors {
  AppColors._();

  // ── Brand ramp ─────────────────────────────────────────────────────────────
  static const Color navyDeep = Color(0xFF071638); // deepest navy
  static const Color brand = Color(0xFF1B44C8); // primary
  static const Color brandBright = Color(0xFF2F6BFF); // electric blue
  static const Color azure = Color(0xFF4C9BFF); // CTA / mid stop
  static const Color cyan = Color(0xFF22D3EE); // selective highlight
  static const Color blueDeep = Color(0xFF0E2E86); // gradient end

  /// Warm accent for salary, wallet and budget cues. Kept intentionally outside
  /// the cool ramp so it reads as a highlight, not a fourth brand colour.
  static const Color amber = Color(0xFFFFB020);

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const Color expenseRed = Color(0xFFF0577B);
  static const Color incomeGreen = Color(0xFF12B76A);
  static const Color danger = Color(0xFFDC2626);

  // ── Gradients ────────────────────────────────────────────────────────────────
  /// Rich hero gradient used on balance cards, CTAs and the app logo.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [brand, brandBright, blueDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.48, 1.0],
  );

  /// Alias with an explicit, semantic name for the hero treatment.
  static const LinearGradient heroGradient = brandGradient;

  /// Cool electric gradient for primary buttons and the nav action.
  static const LinearGradient electricGradient = LinearGradient(
    colors: [brandBright, azure],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Amber accent gradient for small highlights.
  static const LinearGradient amberGradient = LinearGradient(
    colors: [Color(0xFFFFC44D), amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Positive / money-in gradient. Shared by the income hero and the "spending
  /// went down" stat so a favourable state reads the same everywhere.
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF0E8A55), Color(0xFF22C77B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Budget gauge arc.
  static const LinearGradient gaugeGradient = LinearGradient(
    colors: [brand, cyan],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Diagonal white sheen overlay for frosted glass highlights.
  static const LinearGradient glassSheen = LinearGradient(
    colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Categorical palette for charts and bubbles. Hues are spaced around the
  /// wheel rather than staying in the brand ramp so adjacent slices stay
  /// separable for colour-blind viewers.
  static const List<Color> chartPalette = [
    brandBright,
    cyan,
    Color(0xFF7C5CFF),
    incomeGreen,
    amber,
    expenseRed,
    Color(0xFF5B8DEF),
  ];

  // ── Theme surfaces ────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF3F6FD); // cool off-white
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFE9EFFB);
  static const Color borderLight = Color(0xFFDDE6F7);

  static const Color darkBackground = Color(0xFF050D24); // deep navy
  static const Color darkSurface = Color(0xFF0B1738);
  static const Color darkSurfaceAlt = Color(0xFF122249);
  static const Color borderDark = Color(0xFF22345F);

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

  // ── Glass tokens ──────────────────────────────────────────────────────────────
  static Color glassFill(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.white.withValues(alpha: 0.66);

  static Color glassBorder(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.14)
      : Colors.white.withValues(alpha: 0.85);
}
