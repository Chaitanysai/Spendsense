import 'package:flutter/material.dart';

import 'app_palette.dart';

/// SpendSense design tokens, now led by the 2026 premium palette set
/// (Premium Blue by default): tinted canvases, glass surfaces, one highlight
/// accent and neutral typography.
///
/// This class is the single read point for every colour in the app. The values
/// below mirror the **active** [AppPalette] into mutable statics, which keeps
/// every existing call site (`AppColors.brand`, `AppColors.heroGradient`, …)
/// working unchanged while still allowing the palette to be swapped at runtime:
/// [applyPalette] rewrites these fields and the widget tree then rebuilds.
///
/// Two kinds of colour are deliberately *not* palette-driven: money semantics
/// (red out, green in) and [warning]. Everything else — surfaces, borders,
/// shadows, the highlight pill's ink, category tints and chart ramps — follows
/// the selected world.
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
    // Cards carry the palette's glance instead of sitting black-on-black. The
    // legacy AMOLED palettes ship neutral card tokens, so they are tinted here;
    // the premium palettes are already tinted and simply gain a little more
    // separation. The canvas itself stays as the palette defines it.
    darkSurface = _tintDarkSurface(next, next.darkSurface, raised: false);
    darkSurfaceAlt = _tintDarkSurface(next, next.darkSurfaceAlt, raised: true);
    borderDark = Color.alphaBlend(
      next.brand.withValues(alpha: 0.32),
      next.borderDark,
    );

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

    // Lime is a light highlight in every palette, but its hue ranges from lime
    // through blush to ice blue. The ink has to follow the palette's deep stop
    // instead of staying green, or the cycle pill clashes with the world.
    final limeAccent = next.limeAccent;
    // A palette may pin its highlight ink (saturated highlights need white);
    // otherwise keep the contrast-aware deep-stop choice.
    _limeInk = next.onLimeInk ??
        (_contrast(limeAccent, next.deep) >= 4.5 ? next.deep : (Colors.black));
  }

  /// A dark card tinted with the palette's own brand and accent.
  ///
  /// The raised surface gets more tint so a card is distinguishable from the
  /// canvas even on a pure-black AMOLED background. A light lift toward white is
  /// added on top: without it dark tiles collapsed into the canvas and read as
  /// flat black blocks rather than lit glass (the "light shade of the colour on
  /// the tiles" the UI pass asked for).
  static Color _tintDarkSurface(
    AppPalette palette,
    Color base, {
    required bool raised,
  }) {
    final brandAmount = raised ? 0.24 : 0.16;
    final accentAmount = raised ? 0.07 : 0.05;
    final branded = Color.alphaBlend(
      palette.brand.withValues(alpha: brandAmount),
      base,
    );
    final accented = Color.alphaBlend(
      palette.accent.withValues(alpha: accentAmount),
      branded,
    );
    // AMOLED canvases must stay genuinely black, so only lift tinted ones.
    if (palette.isAmoled) return accented;
    return Color.alphaBlend(
      Colors.white.withValues(alpha: raised ? 0.06 : 0.035),
      accented,
    );
  }

  static Color _limeInk = AppPalette.emerald.deep;

  /// Fixed semantic warning. Warning is not a brand accent: it must stay
  /// recognisable as "attention" in every palette, including the monochrome
  /// navy and ice-blue ones.
  static const Color warning = Color(0xFFF0B429);

  /// True when the active palette paints a genuine black dark-mode canvas.
  /// Broad ambient washes are suppressed in that case so the canvas stays black.
  static bool get isAmoledCanvas => _palette.isAmoled;

  /// True when the active palette draws translucent glass cards over its dark
  /// canvas (Midnight and the 2026 premium set). This flag only selects the
  /// card, hero, border and overlay treatment; the canvas colour comes from the
  /// palette and may be black or tinted.
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

  // Neutral typography, deliberately colour-agnostic: the palette lives in the
  // surfaces, accents and borders, while text stays a clean ink so it keeps its
  // contrast on pastel off-whites, navy, ice blue and plum alike.
  static Color textPrimary(BuildContext context) =>
      textPrimaryFor(isDark(context));

  static Color textSecondary(BuildContext context) =>
      textSecondaryFor(isDark(context));

  static Color textTertiary(BuildContext context) =>
      textTertiaryFor(isDark(context));

  /// Context-free text tiers, for [ThemeData] construction.
  static Color textPrimaryFor(bool isDark) =>
      isDark ? const Color(0xFFF5F5F5) : const Color(0xFF101314);

  static Color textSecondaryFor(bool isDark) =>
      isDark ? const Color(0xFFDCDCDC) : const Color(0xFF4B5355);

  static Color textTertiaryFor(bool isDark) =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF566063);

  static Color border(BuildContext context) =>
      isDark(context) ? borderDark : borderLight;

  /// Border colour from a plain brightness flag (for ThemeData construction).
  static Color borderDarkOrLight(bool isDark) =>
      isDark ? borderDark : borderLight;

  static Color shadow(BuildContext context) => isDark(context)
      ? Colors.black.withValues(alpha: 0.6)
      : _palette.deep.withValues(alpha: 0.10);

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

  /// Alpha of the brand-tinted capsule that sits behind small icons in the
  /// action dock and settings rows.
  static double brandWellAlpha(bool isDark) => isDark ? 0.20 : 0.11;

  /// Ink for an icon drawn on a brand-tinted capsule (see [brandWellAlpha]).
  ///
  /// [brandInk] is computed against the *canvas*, but a capsule is the brand
  /// colour blended over the surface, so it collapses the hue distance: in dark
  /// mode cyan-on-navy measured 3.6:1 and ultramarine-on-indigo 3.1:1 — icons
  /// effectively disappeared. This returns the highest-contrast choice against
  /// the actual blended capsule, preferring an on-brand tint when it clears AA
  /// and falling back to white.
  static Color brandWellInk(BuildContext context) {
    final isDarkMode = isDark(context);
    final capsule = Color.alphaBlend(
      brand.withValues(alpha: brandWellAlpha(isDarkMode)),
      isDarkMode ? darkSurface : surface,
    );
    final onBrand = isDarkMode ? _darkBrandInk() : brandInkFor(false);
    if (_contrast(onBrand, capsule) >= 4.5) return onBrand;
    // White is the readable fallback for both saturated and mid-tone brands.
    if (_contrast(Colors.white, capsule) >= 4.5) return Colors.white;
    return _contrast(Colors.black, capsule) > _contrast(Colors.white, capsule)
        ? Colors.black
        : Colors.white;
  }

  /// Ink for a glyph drawn on a translucent tint of [tint] over [base].
  ///
  /// A well painted in 12% of the icon's own colour leaves little contrast for
  /// an icon of that same colour (~2-3:1). This returns [tint] when it clears
  /// AA on the real blended well, otherwise a lightened copy, otherwise white
  /// or black — whichever reads best.
  static Color inkOn(Color tint, Color tinted, Color base) {
    final well = Color.alphaBlend(tinted, base);
    if (_contrast(tint, well) >= 4.5) return tint;
    for (var t = 0.1; t < 1.0; t += 0.1) {
      final candidate = Color.lerp(tint, Colors.white, t) ?? tint;
      if (_contrast(candidate, well) >= 4.5) return candidate;
    }
    final white = _contrast(Colors.white, well);
    final black = _contrast(Colors.black, well);
    return black > white ? Colors.black : Colors.white;
  }

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

  /// Ink used *on* a lime highlight (the cycle-change pill). The highlight is
  /// light in every palette, so the palette's deep stop is the natural ink; a
  /// black fallback covers palettes whose deep stop does not clear 4.5:1.
  static Color onLime(BuildContext context) => _limeInk;

  /// Context-free form for building [ThemeData].
  static Color get onLimeInk => _limeInk;

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

  /// Card fill. Light mode is deliberately near-opaque: on a pastel canvas a
  /// translucent card made the thin border the only thing separating card from
  /// page. Dark mode stays a restrained wash so cards read as surfaces; glass
  /// palettes (Midnight and the 2026 premium set) let the tinted canvas show
  /// through their cards.
  static Color glassFill(BuildContext context) {
    if (!isDark(context)) return surface.withValues(alpha: 0.92);
    return isGlassPalette
        ? darkSurfaceAlt.withValues(alpha: 0.62)
        : darkSurface.withValues(alpha: 0.94);
  }

  static Color glassBorder(BuildContext context) {
    if (!isDark(context)) return borderLight;
    return isGlassPalette ? Colors.white.withValues(alpha: 0.10) : borderDark;
  }
}
