import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A selectable typography preset (Settings → Appearance → Font style).
///
/// Every family below is served by the existing `google_fonts` dependency and
/// is licensed under the SIL Open Font License 1.1 (licence text checked in the
/// google/fonts repository: `ofl/<family>/OFL.txt`). No font file is copied
/// from a device, and no proprietary brand font is used or imitated by name in
/// the UI: the "inspired" presets are *approximations*, labelled as such.
///
/// [displayFamily] is used for large headings, hero figures and accents;
/// [bodyFamily] for everything else, so body text always stays readable even
/// when the display face is decorative (the dot-matrix preset).
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
    label: 'Dot-matrix (Nothing-inspired)',
    description:
        'DotGothic16 for headings and big numbers, Space Grotesk for text. '
        'An approximation, not the Nothing brand font.',
    displayFamily: 'DotGothic16',
    bodyFamily: 'Space Grotesk',
  );

  static const FontPreset cleanSans = FontPreset(
    id: 'clean_sans',
    label: 'Clean sans (Samsung-inspired)',
    description: 'Inter — neutral and precise. Not the Samsung One font.',
    displayFamily: 'Inter',
    bodyFamily: 'Inter',
  );

  static const FontPreset modernSans = FontPreset(
    id: 'modern_sans',
    label: 'Modern sans (Pixel-inspired)',
    description: 'Outfit — geometric and friendly. Not Google Sans.',
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

  /// Test seam: when true, styles carry the family NAME only and no font is
  /// fetched, so tests are deterministic and make no network request.
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
    return _safe(
      useDisplay ? p.displayFamily : p.bodyFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
      fontFeatures: fontFeatures,
    );
  }

  /// A style that never throws: an unknown family or a font-loading failure
  /// degrades to the platform default face with identical metrics settings.
  static TextStyle _safe(
    String family, {
    required double fontSize,
    required FontWeight fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
    List<FontFeature>? fontFeatures,
  }) {
    if (debugSkipFontLoading) {
      return TextStyle(
        fontFamily: family,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
        fontFeatures: fontFeatures,
      );
    }
    try {
      return GoogleFonts.getFont(
        family,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
        fontFeatures: fontFeatures,
      );
    } catch (_) {
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
        fontFeatures: fontFeatures,
      );
    }
  }

  /// Material text theme for [preset]: body face everywhere, display face for
  /// the display/headline roles.
  static TextTheme textTheme(TextTheme base, {FontPreset? preset}) {
    final p = preset ?? active;
    final body = _themeFor(p.bodyFamily, base);
    if (!p.hasDistinctDisplay) return body;
    final display = _themeFor(p.displayFamily, base);
    return body.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge,
      headlineMedium: display.headlineMedium,
    );
  }

  static TextTheme _themeFor(String family, TextTheme base) {
    if (debugSkipFontLoading) return base.apply(fontFamily: family);
    try {
      return GoogleFonts.getTextTheme(family, base);
    } catch (_) {
      return base;
    }
  }
}
