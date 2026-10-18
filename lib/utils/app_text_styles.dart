import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography tokens. Poppins is already a dependency (google_fonts) — no new
/// packages. Monetary figures use tabular figures so live-updating numbers do
/// not jitter.
class AppText {
  AppText._();

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// Oversized hero balance (e.g. the dashboard total).
  static TextStyle hero(BuildContext context) => GoogleFonts.poppins(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.05,
        color: AppColors.textPrimary(context),
        fontFeatures: _tabular,
      );

  static TextStyle display(BuildContext context) => GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: AppColors.textPrimary(context),
        fontFeatures: _tabular,
      );

  static TextStyle h1(BuildContext context) => GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.textPrimary(context),
      );

  static TextStyle h2(BuildContext context) => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary(context),
      );

  static TextStyle title(BuildContext context) => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary(context),
      );

  static TextStyle body(BuildContext context) => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: AppColors.textSecondary(context),
      );

  static TextStyle label(BuildContext context) => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary(context),
      );

  /// Small uppercase eyebrow text (e.g. section labels).
  static TextStyle overline(BuildContext context) => GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.textTertiary(context),
      );

  /// Numeric amount text with tabular figures.
  static TextStyle amount(
    BuildContext context, {
    double size = 16,
    FontWeight weight = FontWeight.w800,
    Color? color,
    double letterSpacing = -0.3,
  }) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color ?? AppColors.textPrimary(context),
        fontFeatures: _tabular,
      );

  /// Text style used on coloured (gradient) surfaces.
  static TextStyle onGradient({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    double opacity = 1.0,
    double letterSpacing = 0,
    double height = 1.2,
  }) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
        color: Colors.white.withValues(alpha: opacity),
      );
}
