import 'package:flutter/material.dart';

/// A selectable typography preset (Settings → Appearance → Font style).
///
/// Every family below is **bundled in the APK** (`assets/fonts/`) and licensed
/// under the SIL Open Font License 1.1 — the licence text for each family is
/// checked in at `assets/fonts/licenses/`. Nothing is fetched from the network
/// at runtime, which is what previously made the chosen face silently fall back
/// on a cold or offline start.
///
/// NDot-55 and NDot-57 (Nothing Technology) are **not** bundled: they are
/// proprietary brand typefaces with no redistribution licence for a third-party
/// application. The dot-matrix preset therefore uses DotGothic16, an OFL face
/// chosen for the same technical character. See `docs/typography.md`.
///
/// [displayFamily] is used for large headings, hero figures and accents;
/// [bodyFamily] for everything else. Monetary figures always use the body face
/// (see `AppText.amount`) because decorative display faces routinely lack the
/// rupee sign and lining figures.
class FontPreset {
  final String id;
  final String label;
  final String description;
  final String displayFamily;
  final String bodyFamily;

  /// Licence of the families in this preset.
  final String licence;

  const FontPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.displayFamily,
    required this.bodyFamily,
    this.licence = 'SIL Open Font License 1.1',
  });

  /// True when the display face differs from the body face.
  bool get hasDistinctDisplay => displayFamily != bodyFamily;

  static const FontPreset standard = FontPreset(
    id: 'standard',
    label: 'SpendSense Default',
    description: 'Poppins — the original SpendSense look.',
    displayFamily: 'Poppins',
    bodyFamily: 'Poppins',
  );

  static const FontPreset dotMatrix = FontPreset(
    id: 'dot_matrix',
    label: 'Dot-matrix (technical)',
    description:
        'DotGothic16 for headings, Space Grotesk for text. '
        'An OFL approximation of the Nothing dot-matrix style.',
    displayFamily: 'DotGothic16',
    bodyFamily: 'Space Grotesk',
  );

  static const FontPreset cleanSans = FontPreset(
    id: 'clean_sans',
    label: 'Clean sans',
    description: 'Inter — neutral and precise.',
    displayFamily: 'Inter',
    bodyFamily: 'Inter',
  );

  static const FontPreset modernSans = FontPreset(
    id: 'modern_sans',
    label: 'Modern sans',
    description: 'Outfit — geometric and friendly.',
    displayFamily: 'Outfit',
    bodyFamily: 'Outfit',
  );

  static const List<FontPreset> all = [
    standard,
    dotMatrix,
    cleanSans,
    modernSans,
  ];

  /// Unknown or missing ids resolve to [standard], never to an error.
  static FontPreset byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => standard);
}

/// Allowed user font-scale range and steps (multiplies the system text scale).
class FontScale {
  FontScale._();

  static const double min = 0.85;
  static const double max = 1.3;
  static const double standard = 1.0;
  static const List<double> steps = [0.85, 1.0, 1.15, 1.3];

  static double sanitize(double? value) {
    if (value == null || value.isNaN) return standard;
    return value.clamp(min, max).toDouble();
  }
}

/// Resolves text styles for the *active* preset.
///
/// [active] follows the same pattern as `AppColors.palette`: the theme provider
/// sets it before notifying, and the app theme changes with it, so dependents
/// rebuild and re-resolve their styles.
class AppTypography {
  AppTypography._();

  static FontPreset active = FontPreset.standard;

  /// Display face threshold: below this size the body face is used even in a
  /// preset with a decorative display face, so small numbers stay legible.
  static const double displayMinSize = 20;

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Families declared with a single variable file. Their weight axis is set
  /// explicitly so `w600` really renders semibold instead of synthesised bold.
  static const Set<String> variableFamilies = {
    'Space Grotesk',
    'Inter',
    'Outfit',
  };

  /// Retained for existing tests. Fonts are bundled now, so nothing needs to be
  /// skipped for determinism; the flag no longer changes the result.
  @visibleForTesting
  static bool debugSkipFontLoading = false;

  /// Style in the display family when [large] (or forced), else body family.
  static TextStyle resolve({
    FontPreset? preset,
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
    List<FontFeature>? fontFeatures,
    bool? display,
  }) {
    final p = preset ?? active;
    final useDisplay =
        (display ?? fontSize >= displayMinSize) && p.hasDistinctDisplay;
    return styleFor(
      useDisplay ? p.displayFamily : p.bodyFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      fontFeatures: fontFeatures,
    );
  }

  /// A style for an explicit bundled family. Unknown families fall back to the
  /// platform face rather than throwing.
  static TextStyle styleFor(
    String family, {
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
    List<FontFeature>? fontFeatures,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      fontFeatures: fontFeatures,
      fontVariations: variableFamilies.contains(family)
          ? <FontVariation>[FontVariation('wght', fontWeight.value.toDouble())]
          : null,
    );
  }

  /// Material text theme for [preset]: body face everywhere, display face for
  /// the display/headline roles.
  static TextTheme textTheme(TextTheme base, {FontPreset? preset}) {
    final p = preset ?? active;
    final body = base.apply(fontFamily: p.bodyFamily);
    if (!p.hasDistinctDisplay) return body;
    final display = base.apply(fontFamily: p.displayFamily);
    return body.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge,
      headlineMedium: display.headlineMedium,
    );
  }
}
