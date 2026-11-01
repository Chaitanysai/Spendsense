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

  // ── Shared AMOLED foundation ──────────────────────────────────────────────
  // The legacy identities share one neutral black dark canvas. The 2026
  // premium set deliberately tints its dark canvas and glass surfaces; both
  // kinds use the same money semantics and text tokens.
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

  /// Dark-mode cards are translucent navy glass with blue-lit hero cards. The
  /// canvas behind them is still [darkBackground], which must stay pure black;
  /// this flag changes only how cards, heroes, borders and overlays look.
  final bool glass;

  /// Explicit ink for text/icons drawn on [limeAccent].
  ///
  /// Most palettes have a *light* highlight, so dark ink is correct. A palette
  /// with a saturated highlight (Paper's ultramarine) needs white instead. When
  /// null the contrast-aware resolver picks the deep stop or black.
  final Color? onLimeInk;

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
    this.glass = false,
    this.onLimeInk,
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
        colors: [actionTop, deep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Cool electric gradient for secondary highlights and small chips.
  LinearGradient get electricGradient => LinearGradient(
        colors: [bright, mid],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// White text on a solid brand fill must clear 4.5:1. Most palettes
  /// already do; for the two shapes whose [brand] was under the bar this
  /// darkens toward [deep] just enough to pass while keeping hue. Palettes
  /// that already clear stay unchanged.
  Color get filledBrand {
    if (_contrastWithWhite(brand) >= 4.5) return brand;
    for (var t = 0.05; t <= 1.0; t += 0.05) {
      final candidate = Color.lerp(brand, deep, t) ?? brand;
      if (_contrastWithWhite(candidate) >= 4.5) return candidate;
    }
    return deep;
  }

  /// Lightest stop of [actionGradient] — [mid] darkened toward [deep] until
  /// white text on it reaches 4.5:1. Palettes whose mid already clears (e.g.
  /// Emerald, Midnight) keep mid unchanged.
  Color get actionTop {
    if (_contrastWithWhite(mid) >= 4.5) return mid;
    for (var t = 0.1; t <= 1.0; t += 0.1) {
      final candidate = Color.lerp(mid, deep, t) ?? mid;
      if (_contrastWithWhite(candidate) >= 4.5) return candidate;
    }
    return deep;
  }

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

  // ── 2026 premium set ────────────────────────────────────────────────────────
  // Four curated six-colour palettes. Unlike the older identities these tint
  // the dark canvas and their glass surfaces with the palette's own hue, so
  // every screen carries the selected world instead of only its accents.
  // Money semantics (red out / green in) and the warning amber stay invariant.

  /// Soft pastel neutrals with a muted-teal brand and a blush highlight.
  static const softPastelTeal = AppPalette(
    id: 'soft_pastel_teal',
    label: 'Soft Pastel Teal',
    deep: Color(0xFF384A4A),
    brand: Color(0xFF5D6B6B),
    bright: Color(0xFFB0D7D8),
    mid: Color(0xFF7E9A9A),
    accent: Color(0xFFB0D7D8),
    warm: Color(0xFFF7CBCA),
    lime: Color(0xFFF7CBCA),
    background: Color(0xFFF1F7F7),
    surface: Colors.white,
    surfaceMuted: Color(0xFFD5E5E5),
    borderLight: Color(0xFFDDD3D3),
    darkBackground: Color(0xFF0E1818),
    darkSurface: Color(0xFF1B2A29),
    darkSurfaceAlt: Color(0xFF243635),
    borderDark: Color(0xFF3A4C4B),
    glass: true,
  );

  /// Deep navy and cool neutrals — the most restrained of the premium set.
  static const deepNavy = AppPalette(
    id: 'deep_navy',
    label: 'Deep Navy',
    deep: Color(0xFF06141B),
    brand: Color(0xFF253745),
    bright: Color(0xFF9BA8AB),
    mid: Color(0xFF4A5C6A),
    accent: Color(0xFFCCD0CF),
    warm: Color(0xFFCCD0CF),
    lime: Color(0xFFCCD0CF),
    background: Color(0xFFF2F5F6),
    surface: Colors.white,
    surfaceMuted: Color(0xFFE4E9EA),
    borderLight: Color(0xFFCCD0CF),
    darkBackground: Color(0xFF06141B),
    darkSurface: Color(0xFF11212D),
    darkSurfaceAlt: Color(0xFF253745),
    borderDark: Color(0xFF4A5C6A),
    glass: true,
  );

  /// Royal blue into ice blue; the new default identity.
  static const premiumBlue = AppPalette(
    id: 'premium_blue',
    label: 'Premium Blue',
    deep: Color(0xFF021024),
    brand: Color(0xFF5483B3),
    bright: Color(0xFF7DA0CA),
    mid: Color(0xFF5187C1),
    accent: Color(0xFFC1E8FF),
    warm: Color(0xFFC1E8FF),
    lime: Color(0xFFC1E8FF),
    background: Color(0xFFF2F8FF),
    surface: Colors.white,
    surfaceMuted: Color(0xFFE1F0FF),
    borderLight: Color(0xFFC1E8FF),
    darkBackground: Color(0xFF0B1220),
    // A card is a surface, not a colour field.
    //
    // The original #052659 carried 27% chroma: every card read as a blue slab
    // and stacked cards merged into one field of blue, with no step to the
    // raised surface. Chroma (how colourful the tone looks) is the measure that
    // matters near black — HSV saturation stays ~70% for any dark navy and told
    // us nothing. This holds the navy identity at ~11% chroma: dark glass, not
    // paint, while keeping a real step up to the raised surface.
    darkSurface: Color(0xFF141E30),
    darkSurfaceAlt: Color(0xFF1C2A42),
    borderDark: Color(0xFF2B3D59),
    glass: true,
  );

  /// Plum, mauve and blush — warm, editorial, still high contrast.
  static const plumBlush = AppPalette(
    id: 'plum_blush',
    label: 'Plum & Blush',
    deep: Color(0xFF190019),
    brand: Color(0xFF854F6C),
    bright: Color(0xFFDFB6B2),
    mid: Color(0xFF522B5B),
    accent: Color(0xFFFBE4D8),
    warm: Color(0xFFDFB6B2),
    lime: Color(0xFFDFB6B2),
    background: Color(0xFFFFF7F2),
    surface: Colors.white,
    surfaceMuted: Color(0xFFF6E7E1),
    borderLight: Color(0xFFE8CFC8),
    darkBackground: Color(0xFF1C1020),
    // The card sat at #2B124C: an ultramarine-violet surface on a maroon-black
    // canvas, so the two hues fought and the card read as a purple slab. Keep
    // the plum family, drop the clash and the chroma.
    darkSurface: Color(0xFF2A1E30),
    darkSurfaceAlt: Color(0xFF382A41),
    borderDark: Color(0xFF4C3A57),
    glass: true,
  );

  /// Deep-navy glass identity: navy hero gradients, translucent navy glass
  /// cards over a pure-black AMOLED canvas, and a restrained electric-blue
  /// accent. Money semantics stay unchanged.
  static const midnight = AppPalette(
    id: 'midnight',
    label: 'Midnight',
    deep: Color(0xFF081A4A),
    brand: Color(0xFF2A5BE0),
    bright: Color(0xFF6C97FF),
    mid: Color(0xFF2F63EA),
    accent: Color(0xFF38BDF8),
    lime: Color(0xFF7CC4FF),
    warm: Color(0xFFFFB020),
    background: Color(0xFFF3F6FD),
    surface: Colors.white,
    surfaceMuted: Color(0xFFE9EFFB),
    borderLight: Color(0xFFDDE6F7),
    // Pitch-black canvas (AMOLED); only the card surfaces carry navy.
    darkBackground: amoledBackground,
    darkSurface: Color(0xFF0B1430),
    darkSurfaceAlt: Color(0xFF111C3D),
    borderDark: Color(0xFF22305A),
    glass: true,
  );

  /// Paper: warm paper-white tiles, black ink and a single ultramarine accent.
  ///
  /// Flat by design — no gradients, no glass, minimal shadow — so numerals and
  /// rules do the work instead of colour. Money semantics stay unchanged.
  static const paper = AppPalette(
    id: 'paper',
    label: 'Paper',
    deep: Color(0xFF141416),
    brand: Color(0xFF2B36FF),
    bright: Color(0xFF5A63FF),
    mid: Color(0xFF2B36FF),
    accent: Color(0xFF2B36FF),
    warm: Color(0xFFB4531E),
    background: Color(0xFFE7E5E0),
    surface: Color(0xFFF8F7F4),
    surfaceMuted: Color(0xFFEFEDE8),
    borderLight: Color(0xFFDDD9D1),
    darkBackground: Color(0xFF111114),
    // Paper's dark state is declared glass, so its cards have to actually lift
    // off the canvas. The previous pair (#121215 canvas / #1B1B1F card) sat at
    // 1.09:1 — a card you cannot see is not a glass card, and it was the one
    // palette whose dark mode still read as flat blocks. These hold the same
    // neutral (hue 240, very low saturation) while separating the layers.
    darkSurface: Color(0xFF1D1D23),
    darkSurfaceAlt: Color(0xFF282830),
    borderDark: Color(0xFF3A3A44),
    // Light mode stays flat, but the dark state is glass like the other
    // palettes: without this the dark canvas rendered as flat opaque blocks,
    // which is the "no glassmorphism in dark mode" the UI pass was about.
    glass: true,
    // Ultramarine is a saturated highlight: white ink is the only readable
    // choice (6.8:1), and dark ink would fail AA.
    onLimeInk: Colors.white,
  );

  /// Palette used when nothing valid is stored (new installs, reset).
  /// Premium Blue is the 2026 default identity.
  static const AppPalette defaultPalette = premiumBlue;
  /// Shown in Settings → Appearance, in this order. The 2026 premium set is
  /// first and Premium Blue is the default / reset target.
  static const List<AppPalette> all = [
    premiumBlue,
    paper,
    deepNavy,
    softPastelTeal,
    plumBlush,
    midnight,
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
        orElse: () => defaultPalette,
      );
}
