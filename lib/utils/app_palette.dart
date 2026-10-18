import 'package:flutter/material.dart';

/// An immutable, curated colour scheme for SpendSense.
///
/// SpendSense ships several palettes rather than a single hard-coded brand ramp,
/// so each one carries the complete set of values the UI reads: the brand ramp,
/// the light-mode surfaces, the dark-mode surfaces and the gradients derived
/// from them. [AppColors] mirrors the active palette into its own static
/// fields, which is why widgets can keep reading `AppColors.brand` and friends
/// without threading a palette through every call site.
///
/// Money semantics are deliberately **not** per-palette. `expenseRed`,
/// `incomeGreen` and `danger` stay constant in every palette so that "red means
/// money out" never changes meaning when a user picks a different theme.
@immutable
class AppPalette {
  final String id;
  final String label;

  // Brand ramp
  final Color deep; // deepest stop, gradient end
  final Color brand; // primary
  final Color bright; // electric / highlight
  final Color mid; // CTA / gradient mid stop
  final Color accent; // selective highlight
  final Color warm; // warm accent for money & salary cues

  // Light-mode surfaces
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color borderLight;

  // Dark-mode surfaces
  final Color darkBackground;
  final Color darkSurface;
  final Color darkSurfaceAlt;
  final Color borderDark;

  const AppPalette({
    required this.id,
    required this.label,
    required this.deep,
    required this.brand,
    required this.bright,
    required this.mid,
    required this.accent,
    required this.warm,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.borderLight,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkSurfaceAlt,
    required this.borderDark,
  });

  // ── Gradients derived from the ramp ─────────────────────────────────────────

  /// Rich hero gradient used on balance cards, CTAs and the app logo.
  LinearGradient get brandGradient => LinearGradient(
        colors: [brand, bright, deep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.48, 1.0],
      );

  /// Alias with an explicit, semantic name for the hero treatment.
  LinearGradient get heroGradient => brandGradient;

  /// Cool electric gradient for primary buttons and the nav action.
  LinearGradient get electricGradient => LinearGradient(
        colors: [bright, mid],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Warm accent gradient for small highlights.
  LinearGradient get amberGradient => LinearGradient(
        colors: [Color.lerp(warm, Colors.white, 0.35)!, warm],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Budget gauge arc.
  LinearGradient get gaugeGradient => LinearGradient(
        colors: [brand, accent],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );

  /// Categorical palette for charts and bubbles. Hues are spaced around the
  /// wheel rather than staying in the brand ramp so adjacent slices stay
  /// separable for colour-blind viewers.
  List<Color> get chartPalette => [
        bright,
        accent,
        mid,
        incomeGreen,
        warm,
        expenseRed,
        Color.lerp(mid, expenseRed, 0.45)!,
      ];

  // ── Palette-invariant money semantics ───────────────────────────────────────
  // Declared here (rather than read from AppColors) so a palette can reference
  // them without a circular import. They are identical in every palette: red
  // must always mean money out.
  static const Color expenseRed = Color(0xFFF0577B);
  static const Color incomeGreen = Color(0xFF12B76A);
  static const Color danger = Color(0xFFDC2626);

  // ── Curated palettes ────────────────────────────────────────────────────────

  /// Default. The navy → electric-blue → cyan ramp.
  static const oceanBlue = AppPalette(
    id: 'ocean_blue',
    label: 'Ocean Blue',
    deep: Color(0xFF071638),
    brand: Color(0xFF1B44C8),
    bright: Color(0xFF2F6BFF),
    mid: Color(0xFF4C9BFF),
    accent: Color(0xFF22D3EE),
    warm: Color(0xFFFFB020),
    background: Color(0xFFF3F6FD),
    surface: Colors.white,
    surfaceMuted: Color(0xFFE9EFFB),
    borderLight: Color(0xFFDDE6F7),
    darkBackground: Color(0xFF050D24),
    darkSurface: Color(0xFF0B1738),
    darkSurfaceAlt: Color(0xFF122249),
    borderDark: Color(0xFF22345F),
  );

  static const warmAmber = AppPalette(
    id: 'warm_amber',
    label: 'Warm Amber',
    deep: Color(0xFF3B1D02),
    brand: Color(0xFFB45309),
    bright: Color(0xFFF59E0B),
    mid: Color(0xFFFBBF24),
    accent: Color(0xFFFDE68A),
    warm: Color(0xFFEA580C),
    background: Color(0xFFFFF9F0),
    surface: Colors.white,
    surfaceMuted: Color(0xFFFDEEDC),
    borderLight: Color(0xFFF5E2C7),
    darkBackground: Color(0xFF1F1206),
    darkSurface: Color(0xFF33210D),
    darkSurfaceAlt: Color(0xFF4A3216),
    borderDark: Color(0xFF6B4A22),
  );

  static const forestGreen = AppPalette(
    id: 'forest_green',
    label: 'Forest Green',
    deep: Color(0xFF05291B),
    brand: Color(0xFF15803D),
    bright: Color(0xFF22C55E),
    mid: Color(0xFF4ADE80),
    accent: Color(0xFFA7F3D0),
    warm: Color(0xFFEAB308),
    background: Color(0xFFF2FBF5),
    surface: Colors.white,
    surfaceMuted: Color(0xFFE3F5E9),
    borderLight: Color(0xFFCFE9D8),
    darkBackground: Color(0xFF04180F),
    darkSurface: Color(0xFF0A2418),
    darkSurfaceAlt: Color(0xFF113524),
    borderDark: Color(0xFF1B5033),
  );

  static const royalPurple = AppPalette(
    id: 'royal_purple',
    label: 'Royal Purple',
    deep: Color(0xFF1D0B36),
    brand: Color(0xFF6D28D9),
    bright: Color(0xFF8B5CF6),
    mid: Color(0xFFA78BFA),
    accent: Color(0xFFDDD6FE),
    warm: Color(0xFFF59E0B),
    background: Color(0xFFF8F5FE),
    surface: Colors.white,
    surfaceMuted: Color(0xFFEEE7FC),
    borderLight: Color(0xFFE0D6F8),
    darkBackground: Color(0xFF150824),
    darkSurface: Color(0xFF241141),
    darkSurfaceAlt: Color(0xFF34195C),
    borderDark: Color(0xFF4A2A80),
  );

  static const rose = AppPalette(
    id: 'rose',
    label: 'Rose',
    deep: Color(0xFF3A0A1D),
    brand: Color(0xFFBE123C),
    bright: Color(0xFFF43F5E),
    mid: Color(0xFFFB7185),
    accent: Color(0xFFFECDD3),
    warm: Color(0xFFF59E0B),
    background: Color(0xFFFFF5F7),
    surface: Colors.white,
    surfaceMuted: Color(0xFFFCE7EB),
    borderLight: Color(0xFFF5D2D9),
    darkBackground: Color(0xFF260610),
    darkSurface: Color(0xFF3D0C1B),
    darkSurfaceAlt: Color(0xFF551327),
    borderDark: Color(0xFF75203A),
  );

  static const teal = AppPalette(
    id: 'teal',
    label: 'Teal',
    deep: Color(0xFF04262B),
    brand: Color(0xFF0D9488),
    bright: Color(0xFF14B8A6),
    mid: Color(0xFF2DD4BF),
    accent: Color(0xFF99F6E4),
    warm: Color(0xFFF59E0B),
    background: Color(0xFFF0FBFA),
    surface: Colors.white,
    surfaceMuted: Color(0xFFDFF5F2),
    borderLight: Color(0xFFCDE9E5),
    darkBackground: Color(0xFF03191C),
    darkSurface: Color(0xFF0A2B30),
    darkSurfaceAlt: Color(0xFF103E45),
    borderDark: Color(0xFF17565F),
  );

  /// Shown in Settings → Appearance, in this order. Ocean Blue is first and is
  /// the default / reset target.
  static const List<AppPalette> all = [
    oceanBlue,
    warmAmber,
    forestGreen,
    royalPurple,
    rose,
    teal,
  ];

  static AppPalette byId(String? id) => all.firstWhere(
        (p) => p.id == id,
        orElse: () => oceanBlue,
      );
}
