import 'package:flutter/material.dart';

/// SpendSense design tokens — premium crimson → vermilion → warm-orange.
///
/// Light-first, with an adapted dark scheme. Legacy names (primaryPurple,
/// primaryPink, primaryTeal, accentBlue…) are retained and re-pointed at the
/// new ramp so existing widgets keep compiling while screens migrate.
class AppColors {
  AppColors._();

  // ── Brand ramp ─────────────────────────────────────────────────────────────
  static const Color crimsonDeep = Color(0xFF7A0F2B);
  static const Color crimson = Color(0xFFC81E3A); // primary
  static const Color crimsonBright = Color(0xFFE23A2E); // expense / mid stop
  static const Color vermilion = Color(0xFFF0432B); // CTA / mid stop
  static const Color orange = Color(0xFFFF7A1A); // gradient end / highlight
  static const Color amber = Color(0xFFFFB020); // restrained highlight

  /// Deeper burnt-orange used as the *end* of white-text gradients so small
  /// labels keep readable contrast (white on bright #FF7A1A fails WCAG AA).
  static const Color orangeDeep = Color(0xFFC94A12);

  // ── Legacy aliases (re-pointed to the new ramp) ─────────────────────────────
  static const Color primaryPurple = crimson;
  static const Color primaryPink = vermilion;
  static const Color primaryTeal = orange;
  static const Color accentTeal = orange;
  static const Color accentBlue = crimson;
  static const Color primaryGreen = incomeGreen;
  static const Color accentOrange = orange;

  // ── Semantic ────────────────────────────────────────────────────────────────
  static const Color expenseRed = crimsonBright;
  static const Color incomeGreen = Color(0xFF12B76A);
  static const Color danger = Color(0xFFDC2626);

  // ── Gradients ────────────────────────────────────────────────────────────────
  /// Rich hero gradient used on balance cards, CTAs and the app logo.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [crimson, crimsonBright, orangeDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.62, 1.0],
  );

  /// Alias with an explicit, semantic name for the hero treatment.
  static const LinearGradient heroGradient = brandGradient;

  /// Warm flame gradient for primary buttons.
  static const LinearGradient flameGradient = LinearGradient(
    colors: [crimsonBright, orangeDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Amber accent gradient for small highlights.
  static const LinearGradient amberGradient = LinearGradient(
    colors: [Color(0xFFFF9A2B), amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Kept for compatibility — now a warm crimson→orange arc.
  static const LinearGradient gaugeGradient = LinearGradient(
    colors: [crimson, orange],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Softer secondary gradient (amber → orange).
  static const LinearGradient altGradient = amberGradient;

  /// Diagonal white sheen overlay for frosted glass highlights.
  static const LinearGradient glassSheen = LinearGradient(
    colors: [Color(0x4DFFFFFF), Color(0x00FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Categorical palette for charts/bubbles — warm-first with two cool
  /// accents kept for colour-blind separability.
  static const List<Color> chartPalette = [
    crimson,
    orange,
    amber,
    crimsonBright,
    Color(0xFFE8A0A8),
    Color(0xFF5B6B8C), // cool accent for contrast
    Color(0xFF12B76A),
  ];

  // ── Theme surfaces ────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFFDF7F5); // warm off-white
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF6EDEA);
  static const Color borderLight = Color(0xFFEFE1DD);

  static const Color darkBackground = Color(0xFF14100F); // warm black
  static const Color darkSurface = Color(0xFF1E1817);
  static const Color darkSurfaceAlt = Color(0xFF271F1E);
  static const Color borderDark = Color(0xFF3A2E2C);

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
      isDark(context) ? const Color(0xFFF7F0EE) : const Color(0xFF1A1113);

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFB9A8A5) : const Color(0xFF7C6B6E);

  static Color textTertiary(BuildContext context) =>
      isDark(context) ? const Color(0xFF8A7A77) : const Color(0xFFA89693);

  static Color border(BuildContext context) =>
      isDark(context) ? borderDark : borderLight;

  /// Border colour from a plain brightness flag (for ThemeData construction).
  static Color borderDarkOrLight(bool isDark) =>
      isDark ? borderDark : borderLight;

  static Color shadow(BuildContext context) => isDark(context)
      ? Colors.black.withValues(alpha: 0.45)
      : const Color(0xFF7A0F2B).withValues(alpha: 0.08);

  // ── Glass tokens ──────────────────────────────────────────────────────────────
  static Color glassFill(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.white.withValues(alpha: 0.62);

  static Color glassBorder(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.75);
}
