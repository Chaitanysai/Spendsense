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
    // the premium (glass) palettes ship surfaces designed for that role and are
    // used exactly as authored — see [_tintDarkSurface].
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
  /// Blend the palette's own hue into a dark surface — but only when the
  /// palette does not already ship a designed one.
  ///
  /// The legacy AMOLED palettes ship neutral (near-black, desaturated) card
  /// tokens, so they need a tint to gain identity. The premium "glass" set
  /// already ships tinted surfaces, and tinting those a second time was
  /// compounding saturation instead of adding depth: `premium_blue` defines
  /// `#052659` and rendered `#224574`, `plum_blush` defines `#2B124C` and
  /// rendered `#4a2d5e`. Every card became a saturated mid-blue slab and
  /// stacked cards could no longer be told apart from the canvas. A designed
  /// surface must be used as authored.
  static Color _tintDarkSurface(
    AppPalette palette,
    Color base, {
    required bool raised,
  }) {
    if (palette.glass) return base;
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
  static Color inkOn(Color tint, Color tinted, Color base) =>
      resolveInk(tint, Color.alphaBlend(tinted, base));

  /// WCAG contrast ratio between two opaque colours.
  static double contrastRatio(Color a, Color b) => _contrast(a, b);

  /// The foreground to draw on [background], resolved by measurement.
  ///
  /// Returns [preferred] when it already reaches [minContrast] on the *actual*
  /// (already composited) background. Otherwise it walks [preferred] toward
  /// whichever of white or black reads better on that background and stops at
  /// the first step that clears the bar, so the hue survives wherever it can.
  /// It never assumes a palette's deep stop is dark against its bright stop:
  /// that assumption is what turned the Deep Navy nav icon into a near-black
  /// glyph on a grey pill.
  static Color resolveInk(
    Color preferred,
    Color background, {
    double minContrast = 4.5,
  }) {
    if (_contrast(preferred, background) >= minContrast) return preferred;
    final toward =
        _contrast(Colors.white, background) >= _contrast(Colors.black, background)
            ? Colors.white
            : Colors.black;
    for (var t = 0.05; t < 1.0; t += 0.05) {
      final candidate = Color.lerp(preferred, toward, t) ?? preferred;
      if (_contrast(candidate, background) >= minContrast) return candidate;
    }
    return toward;
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

  // ── Glass recipe ──────────────────────────────────────────────────────────────
  // One recipe for every translucent surface (cards and the navigation pill).
  // The numbers live here so the two cannot drift apart again: fill alpha,
  // hairline alpha, lit top edge, blur and shadow.

  /// Backdrop blur of a glass surface. Modest for readability and cost.
  static const double glassBlurSigma = 14;

  /// Fill alpha of a dark glass card over its canvas.
  static const double glassFillAlpha = 0.62;

  /// Alpha of the white hairline around a dark glass surface.
  static const double glassBorderAlpha = 0.10;

  /// Alpha at the centre of the lit top edge (see `GlassEdge`).
  static const double glassHighlightAlpha = 0.18;

  /// Fill alpha of the floating navigation pill. Lower than a card on purpose:
  /// the pill floats over scrolling content and should stay see-through.
  static const double navFillAlpha = 0.56;

  /// Alpha of the unselected navigation foreground, identical in every theme.
  static const double navIdleAlpha = 0.82;

  /// True on a tinted or black glass dark canvas, where cards are real glass.
  static bool isGlassCanvas(BuildContext context) =>
      isDark(context) && isGlassPalette;

  /// Context-free card fill (see [glassFill]).
  static Color glassFillFor(bool dark) {
    if (!dark) return surface.withValues(alpha: 0.92);
    return isGlassPalette
        ? darkSurfaceAlt.withValues(alpha: glassFillAlpha)
        : darkSurface.withValues(alpha: 0.94);
  }

  /// Context-free card edge (see [glassBorder]).
  static Color glassBorderFor(bool dark) {
    if (!dark) return borderLight;
    return isGlassPalette
        ? Colors.white.withValues(alpha: glassBorderAlpha)
        : borderDark;
  }

  /// The opaque colour a glass card actually shows over its canvas. Use this as
  /// the background when measuring ink that sits on a card.
  static Color glassBase(bool dark) => Color.alphaBlend(
        glassFillFor(dark),
        dark ? darkBackground : background,
      );

  /// Separation shadow of a glass surface. [floating] is the deeper, softer
  /// shadow used by the navigation pill.
  static List<BoxShadow> glassShadows(
    BuildContext context, {
    bool floating = false,
  }) =>
      [
        BoxShadow(
          color: isGlassCanvas(context)
              ? Colors.black.withValues(alpha: floating ? 0.42 : 0.35)
              : shadow(context),
          blurRadius: floating ? 24 : (isDark(context) ? 18 : 16),
          offset: Offset(0, floating ? 10 : 6),
        ),
      ];

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
  static Color glassFill(BuildContext context) =>
      glassFillFor(isDark(context));

  static Color glassBorder(BuildContext context) =>
      glassBorderFor(isDark(context));

  // ── Panels, overlays and ink on fills ─────────────────────────────────────────

  /// Barrier behind every sheet and dialog. One value so none dims more than
  /// another.
  static const Color scrim = Color(0x6B000000);

  /// Opaque surface of dialogs, sheets, menus and pickers. Glass palettes lift
  /// overlays one step above the canvas; AMOLED and light keep their surface.
  static Color overlaySurfaceFor(bool dark) => !dark
      ? surface
      : isGlassPalette
          ? darkSurfaceAlt
          : darkSurface;

  static Color overlaySurface(BuildContext context) =>
      overlaySurfaceFor(isDark(context));

  /// Hairline around an overlay: the shared glass border on glass palettes.
  static BorderSide overlayEdgeFor(bool dark) => dark && isGlassPalette
      ? BorderSide(color: Colors.white.withValues(alpha: glassBorderAlpha))
      : BorderSide.none;

  /// The opaque colour a glass card shows over its canvas, for panels that do
  /// not need their own blur (rows, strips, chips, sheets).
  static Color glassSurface(BuildContext context) =>
      glassBase(isDark(context));

  /// The shared panel look for widgets that are not a [GlassCard]: the same
  /// tone, hairline and shadow, with no backdrop blur. Every screen-level
  /// container that used to pair `surfaceColor` with an ad-hoc border and
  /// shadow goes through this, so a panel never differs from a card.
  static BoxDecoration panelDecoration(
    BuildContext context, {
    required BorderRadiusGeometry borderRadius,
    bool shadow = true,
  }) =>
      BoxDecoration(
        color: glassSurface(context),
        borderRadius: borderRadius,
        border: Border.all(color: glassBorder(context)),
        boxShadow: shadow ? glassShadows(context) : null,
      );

  /// The ink for text and glyphs drawn on [gradient], measured against its
  /// worst stop. White when it clears [minContrast] on every stop, otherwise
  /// whichever of white or black holds up better. Never assumes a palette's
  /// deep stop is dark.
  static Color inkOnGradient(
    Gradient gradient, {
    double minContrast = 4.5,
  }) {
    double worst(Color ink) => gradient.colors
        .map((stop) => _contrast(ink, stop))
        .reduce((a, b) => a < b ? a : b);
    if (worst(Colors.white) >= minContrast) return Colors.white;
    return worst(Colors.black) > worst(Colors.white)
        ? Colors.black
        : Colors.white;
  }

  /// Ink on a hero card ([heroSurfaceGradient]); [alpha] for secondary marks.
  static Color onHero(BuildContext context, {double alpha = 1}) =>
      inkOnGradient(heroSurfaceGradient(context)).withValues(alpha: alpha);

  /// Switch "on" thumb: the accent ink, which already clears 4.5:1 on the
  /// raised surface.
  static Color switchThumbOnFor(bool dark) => brandInkFor(dark);

  /// Switch "on" track: a translucent accent over the card it sits on.
  static Color switchTrackOnFor(bool dark) =>
      navAccentFor(dark).withValues(alpha: dark ? 0.30 : 0.34);

  /// Opaque track colour as painted over the card, for contrast checks.
  static Color switchTrackOnBackdropFor(bool dark) => Color.alphaBlend(
        switchTrackOnFor(dark),
        dark ? darkSurface : surface,
      );

  /// Ink on [accentHeroGradient] (assistant avatars, the smart-tip glyph).
  static Color onAccentHero(BuildContext context) =>
      inkOnGradient(accentHeroGradient(context));

  /// Label ink on a [danger] fill.
  static Color get onDanger => resolveInk(Colors.white, danger);

  /// Ink for a glyph or label on [brand] itself (avatars, date-picker header).
  /// Buttons sit on [filledBrand] instead; see `onPrimary` in the theme.
  static Color get onBrand => resolveInk(Colors.white, brand);

  // ── Washes: badges, chips and glyph wells ────────────────────────────────────

  /// One alpha for the tinted wash behind a status badge, chip or glyph well,
  /// so equivalent containers stop drifting between 0.10 and 0.18.
  static double washAlphaFor(bool dark) => dark ? 0.16 : 0.10;

  static Color wash(BuildContext context, Color tone) =>
      tone.withValues(alpha: washAlphaFor(isDark(context)));

  /// Ink for a glyph or label of [tone] drawn on its own [wash] over the card.
  /// A same-hue wash collapses the hue distance, so the tone is lifted or
  /// deepened until it clears AA against the colour actually behind it.
  /// [alpha] overrides the wash when a widget uses a stronger one.
  static Color inkOnWash(BuildContext context, Color tone, {double? alpha}) =>
      inkOnWashFor(isDark(context), tone, alpha: alpha);

  /// Context-free form of [inkOnWash].
  static Color inkOnWashFor(bool dark, Color tone, {double? alpha}) => inkOn(
        tone,
        tone.withValues(alpha: alpha ?? washAlphaFor(dark)),
        glassBase(dark),
      );

  /// Translucent chip or well drawn over a gradient card: a light wash in the
  /// gradient's own ink where that keeps the label at 4.5:1 on every stop, a
  /// dark scrim where it would not. A light wash over a stop that is only just
  /// dark enough for white text lifts it below the bar.
  static Color heroChipFill(BuildContext context, {Gradient? gradient}) {
    final g = gradient ?? heroSurfaceGradient(context);
    final ink = inkOnGradient(g);
    final lift = ink.withValues(alpha: 0.18);
    final worst = g.colors
        .map((stop) => _contrast(ink, Color.alphaBlend(lift, stop)))
        .reduce((a, b) => a < b ? a : b);
    if (worst >= 4.5) return lift;
    return (ink.computeLuminance() > 0.5 ? Colors.black : Colors.white)
        .withValues(alpha: 0.20);
  }

  /// Fill of a selected segment/pill inside a card. Dark mode lifts with a
  /// neutral white wash (a brand wash over a dark card lands *below* its
  /// neighbours); light mode lays a brand tint down.
  static Color pillSelectedFillFor(bool dark) =>
      dark ? Colors.white.withValues(alpha: 0.10) : brand.withValues(alpha: 0.12);

  /// The vivid stat/CTA card gradient that still holds white text.
  ///
  /// Light mode is [actionGradient] (its lightest stop is derived to clear
  /// 4.5:1 against white). Dark mode lights the card with the brand over the
  /// raised surface instead of painting a bright brand slab on the canvas; every
  /// stop stays dark enough for white text (asserted for all palettes in
  /// `theme_tokens_contrast_test.dart`).
  static LinearGradient accentHeroGradient(BuildContext context) {
    if (!isDark(context)) return actionGradient;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _holdWhite(Color.lerp(darkSurfaceAlt, brand, 0.62)!),
        _holdWhite(Color.lerp(darkSurface, navyDeep, 0.5)!),
      ],
    );
  }

  /// The "money went down" stat card. Light mode keeps the measured income
  /// ramp. Dark mode lights the card with the income green over the raised
  /// surface, the same construction as [accentHeroGradient], so it reads as a
  /// green-tinted glass card instead of a solid slab that fights the palette.
  static LinearGradient successHeroGradient(BuildContext context) {
    if (!isDark(context)) return successGradient;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _holdWhite(Color.lerp(darkSurfaceAlt, incomeGreen, 0.42)!),
        _holdWhite(Color.lerp(darkSurface, incomeGreen, 0.16)!),
      ],
    );
  }

  /// [c] darkened toward black only as far as needed for white text to reach
  /// 4.5:1. A bright brand (Emerald, Forest) would otherwise fail on its own
  /// lit corner.
  static Color _holdWhite(Color c) {
    if (_contrast(Colors.white, c) >= 4.5) return c;
    for (var t = 0.05; t < 1.0; t += 0.05) {
      final candidate = Color.lerp(c, Colors.black, t) ?? c;
      if (_contrast(Colors.white, candidate) >= 4.5) return candidate;
    }
    return Colors.black;
  }

  // ── Floating add button ──────────────────────────────────────────────────────
  // Quieter than the navigation pill's selected state is not the goal; it only
  // has to read as one control without a glow: the nav glass tinted with the
  // accent, and a resolved accent glyph.

  /// Translucent: the nav glass with a stronger accent tint than the selected
  /// tab, so it reads as the one action without a solid fill or a glow.
  static Color fabFillFor(bool dark) => Color.alphaBlend(
        navAccentFor(dark).withValues(alpha: dark ? 0.30 : 0.18),
        navFillFor(dark),
      );

  /// What the button sits on when nothing scrolls behind it.
  static Color fabBackdropFor(bool dark) => Color.alphaBlend(
        fabFillFor(dark),
        dark ? darkBackground : background,
      );

  static Color fabInkFor(bool dark) =>
      resolveInk(brandInkFor(dark), fabBackdropFor(dark));

  // ── Analytics tokens ─────────────────────────────────────────────────────────
  // The two dashboard analytics surfaces ("Last 7 days" and "Spending by
  // category") share one visual grammar: a hairline grid, one accent line, a
  // quiet wash, and value ink that never competes with the figure above it.

  /// Hairline horizontal grid inside the weekly chart. Tinted by theme rather
  /// than by palette: a grid is structure, not identity.
  static Color chartGrid(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.black.withValues(alpha: 0.055);

  /// The weekly chart's line and its unselected data points.
  static Color chartLine(BuildContext context) =>
      isDark(context) ? brandBright : brandInk(context);

  /// Vertical wash under the weekly line. Fades to fully transparent at the
  /// baseline so the card surface (not a grey block) stays the chart's floor.
  static LinearGradient chartArea(BuildContext context) {
    final line = chartLine(context);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        line.withValues(alpha: isDark(context) ? 0.30 : 0.22),
        line.withValues(alpha: 0.02),
      ],
    );
  }

  /// Track behind a category's proportional bar.
  static Color categoryTrack(Color color, BuildContext context) =>
      color.withValues(alpha: isDark(context) ? 0.20 : 0.13);

  /// Skeleton surface and the highlight that travels across it.
  ///
  /// The base is the *text* ink at 8% over the local surface rather than a fixed
  /// grey: it then reads correctly on a white card, a tinted dark card and a
  /// coloured hero without a second token per surface.
  static Color skeletonBase(BuildContext context) => Color.alphaBlend(
        textPrimaryFor(isDark(context)).withValues(alpha: 0.08),
        surfaceColor(context),
      );

  static Color skeletonHighlight(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.white.withValues(alpha: 0.85);

  // ── Navigation pill ──────────────────────────────────────────────────────────
  // The bar is translucent glass; the selected state is a translucent accent
  // container, never a solid slab. Every value is context-free (`For(dark)`) so
  // tests and widgets measure exactly the same colours.

  /// The accent hue the selection is tinted with: the lit stop on dark canvases
  /// (where `brand` sits close to the surface) and the white-text-safe fill on
  /// light ones.
  static Color navAccentFor(bool dark) => dark ? brandBright : filledBrand;

  /// Fill of the floating bar.
  static Color navFillFor(bool dark) =>
      (dark ? darkSurfaceAlt : surface).withValues(alpha: navFillAlpha);

  /// What the bar is composited onto when nothing scrolls behind it.
  static Color navBackdropFor(bool dark) => Color.alphaBlend(
        navFillFor(dark),
        dark ? darkBackground : background,
      );

  /// Translucent accent container behind the selected tab.
  static Color navSelectedFillFor(bool dark) =>
      navAccentFor(dark).withValues(alpha: dark ? 0.22 : 0.14);

  /// Opaque colour the selected tab's foreground sits on.
  static Color navSelectedBackdropFor(bool dark) => Color.alphaBlend(
        navSelectedFillFor(dark),
        navBackdropFor(dark),
      );

  /// Foreground of the selected tab, resolved against the container it sits on.
  static Color navSelectedInkFor(bool dark) =>
      resolveInk(brandInkFor(dark), navSelectedBackdropFor(dark));

  /// Foreground of an unselected tab: the neutral secondary text tier at one
  /// alpha in every theme.
  static Color navIdleInkFor(bool dark) =>
      textSecondaryFor(dark).withValues(alpha: navIdleAlpha);

  static Color navFill(BuildContext context) => navFillFor(isDark(context));

  static Color navSelectedFill(BuildContext context) =>
      navSelectedFillFor(isDark(context));

  static Color navSelectedInk(BuildContext context) =>
      navSelectedInkFor(isDark(context));

  static Color navIdleInk(BuildContext context) =>
      navIdleInkFor(isDark(context));

  /// Kept for compatibility: the selected container as a (flat) gradient.
  static LinearGradient navPillGradient(BuildContext context) {
    final fill = navSelectedFill(context);
    return LinearGradient(colors: [fill, fill]);
  }

  /// Ink on the selected container.
  static Color onNavPill(BuildContext context) => navSelectedInk(context);

  // ── Semantic tokens ──────────────────────────────────────────────────────────
  /// Role-based view over the active palette. See [AppTokens].
  static AppTokens tokens(BuildContext context) =>
      AppTokens.forBrightness(isDark(context));
}

/// Semantic colour roles for the active palette and one brightness.
///
/// This is a computed view, not another store: every value is derived from the
/// fields [AppColors.applyPalette] mirrors, so it can never go stale when the
/// palette changes. Existing call sites keep using the `AppColors` names; new
/// code should prefer these roles.
///
/// Money and status colours ([success], [warning], [error]) are the invariant
/// fills. Draw text in them through [AppColors.inkOn] or [AppColors.resolveInk].
@immutable
class AppTokens {
  final Color background;
  final Color backgroundElevated;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceGlass;
  final Color surfaceGlassElevated;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconDisabled;

  final Color accentPrimary;
  final Color accentSecondary;
  final Color accentContainer;
  final Color onAccent;
  final Color onAccentContainer;
  final Color selected;
  final Color focus;

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  final Color divider;
  final Color border;
  final Color scrim;

  const AppTokens._({
    required this.background,
    required this.backgroundElevated,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceGlass,
    required this.surfaceGlassElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconDisabled,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.accentContainer,
    required this.onAccent,
    required this.onAccentContainer,
    required this.selected,
    required this.focus,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.divider,
    required this.border,
    required this.scrim,
  });

  factory AppTokens.of(BuildContext context) =>
      AppTokens.forBrightness(AppColors.isDark(context));

  factory AppTokens.forBrightness(bool dark) {
    final canvas = dark ? AppColors.darkBackground : AppColors.background;
    final surface = dark ? AppColors.darkSurface : AppColors.surface;
    final raised = dark ? AppColors.darkSurfaceAlt : AppColors.surface;

    final accent = AppColors.brandInkFor(dark);
    final container =
        AppColors.navAccentFor(dark).withValues(alpha: dark ? 0.22 : 0.14);
    final containerBase = Color.alphaBlend(container, AppColors.glassBase(dark));
    final secondary = AppColors.resolveInk(
      dark ? AppColors.cyan : AppColors.azure,
      AppColors.glassBase(dark),
    );
    final textMuted = AppColors.textTertiaryFor(dark);

    return AppTokens._(
      background: canvas,
      backgroundElevated: dark ? AppColors.darkSurface : AppColors.surfaceMuted,
      surface: surface,
      surfaceElevated: raised,
      surfaceGlass: AppColors.glassFillFor(dark),
      surfaceGlassElevated: dark
          ? AppColors.darkSurfaceAlt.withValues(
              alpha: AppColors.isGlassPalette ? 0.74 : 0.96)
          : AppColors.surface.withValues(alpha: 0.96),
      textPrimary: AppColors.textPrimaryFor(dark),
      textSecondary: AppColors.textSecondaryFor(dark),
      textMuted: textMuted,
      iconPrimary: AppColors.textPrimaryFor(dark),
      iconSecondary: AppColors.textSecondaryFor(dark),
      iconDisabled: textMuted.withValues(alpha: 0.55),
      accentPrimary: accent,
      accentSecondary: secondary,
      accentContainer: container,
      onAccent: AppColors.resolveInk(Colors.white, AppColors.filledBrand),
      onAccentContainer: AppColors.resolveInk(accent, containerBase),
      selected: container,
      focus: accent,
      success: AppColors.incomeGreen,
      warning: AppColors.warning,
      error: AppColors.danger,
      info: secondary,
      divider: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
      border: AppColors.borderDarkOrLight(dark),
      scrim: AppColors.scrim,
    );
  }

  /// Every role by name, for diffing two snapshots.
  Map<String, Color> toMap() => {
        'background': background,
        'backgroundElevated': backgroundElevated,
        'surface': surface,
        'surfaceElevated': surfaceElevated,
        'surfaceGlass': surfaceGlass,
        'surfaceGlassElevated': surfaceGlassElevated,
        'textPrimary': textPrimary,
        'textSecondary': textSecondary,
        'textMuted': textMuted,
        'iconPrimary': iconPrimary,
        'iconSecondary': iconSecondary,
        'iconDisabled': iconDisabled,
        'accentPrimary': accentPrimary,
        'accentSecondary': accentSecondary,
        'accentContainer': accentContainer,
        'onAccent': onAccent,
        'onAccentContainer': onAccentContainer,
        'selected': selected,
        'focus': focus,
        'success': success,
        'warning': warning,
        'error': error,
        'info': info,
        'divider': divider,
        'border': border,
        'scrim': scrim,
      };
}
