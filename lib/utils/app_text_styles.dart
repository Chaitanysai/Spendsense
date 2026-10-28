import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Typography tokens. Faces come from the active [FontPreset] (Poppins by
/// default); only large headings, hero figures and large amounts use the
/// preset's display face. Monetary figures use tabular figures so live-updating
/// numbers do not jitter.
class AppText {
  AppText._();

  static const List<FontFeature> _tabular = AppTypography.tabular;

  /// Oversized hero balance (e.g. the dashboard total).
  static TextStyle hero(BuildContext context) => AppTypography.resolve(
        fontSize: 40,
        display: false,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.05,
        color: AppColors.textPrimary(context),
        fontFeatures: _tabular,
      );

  static TextStyle display(BuildContext context) => AppTypography.resolve(
        fontSize: 32,
        display: false,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: AppColors.textPrimary(context),
        fontFeatures: _tabular,
      );

  static TextStyle h1(BuildContext context) => AppTypography.resolve(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.textPrimary(context),
      );

  static TextStyle h2(BuildContext context) => AppTypography.resolve(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.textPrimary(context),
      );

  static TextStyle title(BuildContext context) => AppTypography.resolve(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary(context),
      );

  /// Smallest readable supporting text: timestamps, meta lines, dense labels.
  ///
  /// The scale used to stop at [label] (12), so screens that needed something
  /// smaller invented their own size — 11, 10.5, 10, 9.5, 8.5 — and the app
  /// ended up with 22 distinct font sizes. These named steps exist so a caller
  /// picks a role instead of a number.
  static TextStyle caption(BuildContext context) => AppTypography.resolve(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textTertiary(context),
      );

  /// Secondary body text: one step down from [body], still comfortably legible.
  static TextStyle bodySmall(BuildContext context) => AppTypography.resolve(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: AppColors.textSecondary(context),
      );

  /// Emphasised body text, for a value that sits inside a [body] paragraph.
  static TextStyle bodyStrong(BuildContext context) => AppTypography.resolve(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: AppColors.textPrimary(context),
      );

  static TextStyle body(BuildContext context) => AppTypography.resolve(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: AppColors.textSecondary(context),
      );

  static TextStyle label(BuildContext context) => AppTypography.resolve(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary(context),
      );

  /// Small uppercase eyebrow text (e.g. section labels).
  static TextStyle overline(BuildContext context) => AppTypography.resolve(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.textTertiary(context),
      );

  /// Numeric amount text with tabular figures. Amounts always use the body
  /// face, at every size, so the rupee sign and comparable digits are
  /// guaranteed even when the display face is a decorative dot-matrix.
  static TextStyle amount(
    BuildContext context, {
    double size = 16,
    FontWeight weight = FontWeight.w800,
    Color? color,
    double letterSpacing = -0.3,
  }) =>
      AppTypography.resolve(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color ?? AppColors.textPrimary(context),
        fontFeatures: _tabular,
        // Money always uses the body face: display faces often lack the
        // rupee sign and lining figures.
        display: false,
      );

  /// Text style used on coloured (gradient) surfaces.
  static TextStyle onGradient({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    double opacity = 1.0,
    double letterSpacing = 0,
    double height = 1.2,
  }) =>
      AppTypography.resolve(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
        color: Colors.white.withValues(alpha: opacity),
      );
}
