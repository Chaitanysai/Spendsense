import 'package:flutter/material.dart';

import 'app_palette.dart';

/// SpendSense design tokens — a premium green fintech identity (primary green,
/// deep green canopy, one lime highlight) by default, and user-selectable beyond
/// that.
///
/// This class is the single read point for every colour in the app. The values
/// below mirror the **active** [AppPalette] into mutable statics, which keeps
/// every existing call site (`AppColors.brand`, `AppColors.heroGradient`, …)
/// working unchanged while still allowing the palette to be swapped at runtime:
/// [applyPalette] rewrites these fields and the widget tree then rebuilds.
///
/// The brand ramp is deliberately calm at the base so the balance card reads as
/// "premium finance", with the lime accent reserved for selective highlights
/// (the cycle-change pill, the selected marker). A single warm accent is kept
/// for money/salary cues, because an all-green palette gives the eye nothing to
/// prioritise against.
class AppColors {
  AppColors._();

  // ── Active palette ───────────────────────────────────────────────────────────
  static AppPalette _palette = AppPalette.emerald;

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
    lime = next.limeAccent;

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
    balanceGradient = next.balanceGradient;
    actionGradient = next.actionGradient;
    filledBrand = next.filledBrand;
    electricGradient = next.electricGradient;
    amberGradient = next.amberGradient;
    gaugeGradient = next.gaugeGradient;
    chartPalette = next.chartPalette;
    // The income ramp is shared by the income hero and the "spending went
    // down" stat, so it must refresh with the palette like every other token.
    successGradient = AppPalette.incomeGradient;
  }

  /// True when the active palette paints a genuine black dark-mode canvas.
  /// Broad ambient washes are suppressed in that case so the canvas stays black.
  static bool get isAmoledCanvas => _palette.isAmoled;

  /// True when the active palette draws translucent navy glass cards over the
  /// pure-black canvas (Midnight). The canvas itself is still #000000; this
  /// flag only selects the card, hero, border and overlay treatment.
  static bool get isGlassPalette => _palette.glass;

  // ── Brand ramp ─────────────────────────────────────────────────────────────
  static Color navyDeep = AppPalette.emerald.deep; // deepest stop
  static Color brand = AppPalette.emerald.brand; // primary
  static Color brandBright = AppPalette.emerald.bright; // highlight
  static Color azure = AppPalette.emerald.mid; // CTA / mid stop
  static Color cyan = AppPalette.emerald.accent; // selective highlight

  /// The single loud highlight. Used sparingly — never as a surface fill.
  static Color lime = AppPalette.emerald.limeAccent;

  /// Warm accent for salary, wallet and budget cues. Kept intentionally outside
  /// the green ramp so it reads as a highlight, not a second brand colour.
  static Color amber = AppPalette.emerald.warm;

  // ── Semantic ───────────────────────────────────────────────────────────────
  // Fixed across every palette: red must always mean money out.
  static const Color expenseRed = AppPalette.expenseRed;
  static const Color incomeGreen = AppPalette.incomeGreen;
  static const Color danger = AppPalette.danger;

  // ── Gradients ────────────────────────────────────────────────────────────────
  /// Rich gradient used on balance cards, CTAs and the app logo.
  static LinearGradient brandGradient = AppPalette.emerald.brandGradient;

  /// Alias with an explicit, semantic name for the hero treatment.
  static LinearGradient heroGradient = AppPalette.emerald.heroGradient;

  /// The balance-card treatment: primary green into the deep green canopy with a
  /// controlled diagonal. Dark mode confines it to the hero card only.
  static LinearGradient balanceGradient = AppPalette.emerald.balanceGradient;

  /// Primary action fill. Ends deep so a white label stays legible.
  static LinearGradient actionGradient = AppPalette.emerald.actionGradient;

  /// Secondary gradient for small highlights and chips.
  static LinearGradient electricGradient = AppPalette.emerald.electricGradient;

  /// Amber accent gradient for small highlights.
  static LinearGradient amberGradient = AppPalette.emerald.amberGradient;

  static Color filledBrand = AppPalette.emerald.filledBrand;

  /// Positive / money-in gradient. Uses the palette's measured income ramp
  /// rather than a bright mint, so a white label keeps its contrast.
  static LinearGradient successGradient = AppPalette.incomeGradient;

  /// Budget gauge arc.
  static LinearGradient gaugeGradient = AppPalette.emerald.gaugeGradient;

  /// Diagonal white sheen overlay for frosted glass highlights.
  static const LinearGradient glassSheen = LinearGradient(
    colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Categorical palette for charts and bubbles. Hues are spaced around the
  /// wheel rather than staying in the brand ramp so adjacent slices stay
  /// separable for colour-blind viewers.
  static List<Color> chartPalette = AppPalette.emerald.chartPalette;

  // ── Theme surfaces ────────────────────────────────────────────────────────────
  static Color background = AppPalette.emerald.background; // airy off-white
  static Color surface = AppPalette.emerald.surface;
  static Color surfaceMuted = AppPalette.emerald.surfaceMuted;
  static Color borderLight = AppPalette.emerald.borderLight;

  static Color darkBackground =
      AppPalette.emerald.darkBackground; // true AMOLED black
  static Color darkSurface = AppPalette.emerald.darkSurface;
  static Color darkSurfaceAlt = AppPalette.emerald.darkSurfaceAlt;
  static Color borderDark = AppPalette.emerald.borderDark;

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
      isDark(context) ? const Color(0xFFF5F5F5) : const Color(0xFF0A1A14);

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? const Color(0xFFB3B3B3) : const Color(0xFF4A5A53);

  static Color textTertiary(BuildContext context) =>
      isDark(context) ? const Color(0xFF8A8A8A) : const Color(0xFF6B7A72);

  static Color border(BuildContext context) =>
      isDark(context) ? borderDark : borderLight;

  /// Border colour from a plain brightness flag (for ThemeData construction).
  static Color borderDarkOrLight(bool isDark) =>
      isDark ? borderDark : borderLight;

  static Color shadow(BuildContext context) => isDark(context)
      ? Colors.black.withValues(alpha: 0.6)
      : const Color(0xFF0B3B2C).withValues(alpha: 0.08);

  /// Brand colour that is safe as *text or icon ink* on the current canvas.
  ///
  /// The primary green measures ~3.4:1 on white — fine for a filled button, too
  /// weak for a 12px link. Light mode therefore deepens the brand toward the
  /// palette's deep stop (≥5.5:1), while dark mode steps up to the bright stop
  /// (≥8:1 on black). Filled surfaces keep using [brand] directly.
  static Color brandInk(BuildContext context) => brandInkFor(isDark(context));

  /// Context-free form of [brandInk], for building [ThemeData] where no
  /// [BuildContext] exists yet.
  static Color brandInkFor(bool isDark) =>
      isDark ? _darkBrandInk() : Color.lerp(brand, navyDeep, 0.45) ?? brand;

  /// [brandBright], lightened toward white only when it falls under 4.5:1 on
  /// the raised dark surface that dialogs and sheets use. Palettes whose bright
  /// stop already clears the bar (most of them) are returned unchanged.
  static Color _darkBrandInk() {
    final surface = darkSurfaceAlt;
    if (_contrast(brandBright, surface) >= 4.5) return brandBright;
    for (var t = 0.05; t < 1.0; t += 0.05) {
      final candidate = Color.lerp(brandBright, Colors.white, t) ?? brandBright;
      if (_contrast(candidate, surface) >= 4.5) return candidate;
    }
    return Colors.white;
  }

  static double _contrast(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Foreground for the selected navigation item. Same contrast rule as
  /// [brandInk]: the small 9px label needs the deeper green in light mode.
  static Color navSelected(BuildContext context) => brandInk(context);

  /// Ink used *on* a lime highlight (the cycle-change pill). Lime is a light
  /// accent in every palette, so this stays a near-black green: ~13:1.
  static Color onLime(BuildContext context) => const Color(0xFF0B3B2C);

  /// A green fill that white text can sit on. The primary green is only ~3.4:1
  /// against white, so filled text surfaces (chat bubbles, badges) use this
  /// deeper variant, which measures ~5:1.
  static Color deepFill(BuildContext context) =>
      Color.lerp(brand, navyDeep, 0.42) ?? brand;

  /// The hero gradient, restrained for the current canvas.
  ///
  /// Light mode keeps the full green ramp. Dark mode pulls every stop toward the
  /// dark surface, so a green card reads as an intentional focal panel instead
  /// of a saturated block sitting on the black canvas.
  static LinearGradient heroSurfaceGradient(BuildContext context) {
    if (!isDark(context)) return balanceGradient;
    if (isGlassPalette) {
      // Navy glass hero: a lit electric-blue corner falling into deep navy.
      // Every stop stays dark enough for white figures (>= 9:1).
      return LinearGradient(
        colors: [
          Color.lerp(darkSurfaceAlt, brand, 0.42)!,
          Color.lerp(darkSurface, navyDeep, 0.5)!,
          darkSurface,
        ],
        stops: const [0.0, 0.6, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    // Neutral near-black base with only a measured accent wash: the lit corner
    // carries the palette, the far corner falls away to the surface so a deep
    // palette (Rose, Purple) never reads as a large coloured block on black.
    final base = darkSurface;
    final colors = balanceGradient.colors;
    return LinearGradient(
      colors: [
        for (var i = 0; i < colors.length; i++)
          Color.lerp(base, colors[i], i == 0 ? 0.34 : 0.16) ?? colors[i],
      ],
      begin: balanceGradient.begin,
      end: balanceGradient.end,
      stops: balanceGradient.stops,
    );
  }

  // ── Glass tokens ──────────────────────────────────────────────────────────────
  /// True on a navy (non-AMOLED) dark canvas, where cards are real glass.
  static bool isGlassCanvas(BuildContext context) =>
      isDark(context) && isGlassPalette;

  /// Edge of a hero card: a light hairline on navy glass, the neutral border on
  /// AMOLED, none in light mode.
  static Border? heroBorder(BuildContext context) {
    if (!isDark(context)) return null;
    return Border.all(
      color: isGlassPalette ? Colors.white.withValues(alpha: 0.14) : borderDark,
    );
  }

  /// Opacity of the soft blue light under hero cards.
  static double heroGlowAlpha(BuildContext context) {
    if (!isDark(context)) return 0.30;
    return isGlassPalette ? 0.32 : 0.18;
  }

  /// Card fill. Light mode is deliberately near-opaque white: on the airy
  /// off-white canvas a translucent card made the thin green-grey border the
  /// only thing separating card from page. Dark mode stays a restrained
  /// near-black wash so cards read as surfaces, never as green panels.
  static Color glassFill(BuildContext context) {
    if (!isDark(context)) return Colors.white.withValues(alpha: 0.90);
    // The canvas is pure black for every palette. Glass palettes (Midnight)
    // keep translucent navy cards on it; the others keep their opaque ones.
    return isGlassPalette
        ? darkSurfaceAlt.withValues(alpha: 0.62)
        : darkSurface.withValues(alpha: 0.94);
  }

  static Color glassBorder(BuildContext context) {
    if (!isDark(context)) return borderLight;
    return isGlassPalette ? Colors.white.withValues(alpha: 0.10) : borderDark;
  }
}
