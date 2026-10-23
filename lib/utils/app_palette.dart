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

  /// Optional accent reserved for a single high-energy highlight (the lime in
  /// the green identity). Falls back to [accent] so other palettes are
  /// unaffected when the field is omitted.
  final Color? lime;

  // ── Derived tokens ────────────────────────────────────────────────────────

  /// The one deliberately loud highlight in the palette. Used sparingly: the
  /// balance pill, the selected marker and small positive cues.
  Color get limeAccent => lime ?? accent;

  /// True when the palette's dark canvas is pure black. AMOLED palettes skip
  /// broad glows and tinted washes so the canvas stays genuinely black.
  bool get isAmoled => darkBackground == amoledBackground;

  // ── Shared neutral AMOLED foundation ──────────────────────────────────────
  // Every palette shares one neutral black dark canvas. Palettes only supply
  // accents; they never tint backgrounds or surfaces (the old per-palette
  // maroon/navy/brown canvases are gone).
  static const Color amoledBackground = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF121212);
  static const Color amoledSurfaceAlt = Color(0xFF1A1A1A);
  static const Color amoledBorder = Color(0xFF2E2E2E);

  /// The balance-card treatment: the primary green into the deep canopy.
  ///
  /// White text sits on this surface, so the lightest stop is *derived* rather
  /// than taken raw from [mid]. Some palettes legitimately ship a bright mid
  /// stop (Ocean Blue's is ~2.8:1 against white); darkening toward [deep] until
  /// the stop clears 4.5:1 keeps every palette legible without changing the
  /// brand ramp the charts and icons read.
  LinearGradient get balanceGradient => LinearGradient(
        colors: [balanceTop, deep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// The lightest stop of [balanceGradient]: [mid] darkened toward [deep] until
  /// white text on it reaches the 4.5:1 AA threshold.
  Color get balanceTop {
    if (_contrastWithWhite(mid) >= 4.5) return mid;
    for (var t = 0.1; t <= 1.0; t += 0.1) {
      final candidate = Color.lerp(mid, deep, t) ?? mid;
      if (_contrastWithWhite(candidate) >= 4.5) return candidate;
    }
    return deep;
  }

  /// WCAG relative-luminance contrast against white. Kept private to the
  /// palette so the derived stop can be computed where it is defined.
  static double _contrastWithWhite(Color color) {
    final l = color.computeLuminance();
    return 1.05 / (l + 0.05);
  }

  /// Gradient used by the income surfaces. Both stops are deep enough that a
  /// white label clears AA, unlike a bright mint ramp.
  static const LinearGradient incomeGradient = LinearGradient(
    colors: [Color(0xFF0B6B43), Color(0xFF0F7A4A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

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
    this.lime,
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
        colors: [brand, mid, deep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.52, 1.0],
      );

  /// Alias with an explicit, semantic name for the hero treatment.
  LinearGradient get heroGradient => brandGradient;

  /// Fill for primary actions. Runs from the palette's mid stop into the deep
  /// stop so a white label keeps a comfortable contrast on every palette.
  LinearGradient get actionGradient => LinearGradient(
        colors: [mid, deep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Cool electric gradient for secondary highlights and small chips.
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

  /// Green fintech identity: primary green, deep canopy, one lime highlight on
  /// a true-black AMOLED dark canvas.
  ///
  /// `mid` sits at ~5.2:1 against white so it can back a white label as the
  /// lightest stop of the balance gradient; `bright` is the lighter ink stop
  /// used on dark surfaces.
  static const emerald = AppPalette(
    id: 'emerald',
    label: 'Emerald',
    deep: Color(0xFF0B3B2C),
    brand: Color(0xFF12A150),
    bright: Color(0xFF35C97A),
    mid: Color(0xFF0E7A42),
    accent: Color(0xFFC6F432),
    lime: Color(0xFFC6F432),
    warm: Color(0xFFF0B429),
    background: Color(0xFFF7F9F8),
    surface: Colors.white,
    surfaceMuted: Color(0xFFEEF3F0),
    borderLight: Color(0xFFE1EAE5),
    darkBackground: amoledBackground,
    darkSurface: amoledSurface,
    darkSurfaceAlt: amoledSurfaceAlt,
    borderDark: amoledBorder,
  );

  /// The previous default: the navy → electric-blue → cyan ramp, kept as a
  /// selectable palette so existing users can stay on it.
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
    darkBackground: amoledBackground,
    darkSurface: amoledSurface,
    darkSurfaceAlt: amoledSurfaceAlt,
    borderDark: amoledBorder,
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
    darkBackground: amoledBackground,
    darkSurface: amoledSurface,
    darkSurfaceAlt: amoledSurfaceAlt,
    borderDark: amoledBorder,
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
    darkBackground: amoledBackground,
    darkSurface: amoledSurface,
    darkSurfaceAlt: amoledSurfaceAlt,
    borderDark: amoledBorder,
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
    darkBackground: amoledBackground,
    darkSurface: amoledSurface,
    darkSurfaceAlt: amoledSurfaceAlt,
    borderDark: amoledBorder,
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
    darkBackground: amoledBackground,
    darkSurface: amoledSurface,
    darkSurfaceAlt: amoledSurfaceAlt,
    borderDark: amoledBorder,
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
    darkBackground: amoledBackground,
    darkSurface: amoledSurface,
    darkSurfaceAlt: amoledSurfaceAlt,
    borderDark: amoledBorder,
  );

  /// Shown in Settings → Appearance, in this order. Emerald is first and is the
  /// default / reset target; it carries the green fintech identity.
  static const List<AppPalette> all = [
    emerald,
    oceanBlue,
    warmAmber,
    forestGreen,
    royalPurple,
    rose,
    teal,
  ];

  static AppPalette byId(String? id) => all.firstWhere(
        (p) => p.id == id,
        orElse: () => emerald,
      );
}
