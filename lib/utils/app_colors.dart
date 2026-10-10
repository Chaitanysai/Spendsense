import 'package:flutter/material.dart';

/// SpendSense – redesigned colour palette inspired by the "After" UI.
/// Teal/green gauge aesthetic, clean whites, soft card surfaces.
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────────────────────────
  static const Color primaryTeal   = Color(0xFF0ABFBC); // gauge teal
  static const Color primaryGreen  = Color(0xFF06D6A0); // income / positive
  static const Color accentOrange  = Color(0xFFFF6B35); // warning / over-budget
  static const Color accentBlue    = Color(0xFF4361EE); // secondary accent

  // Legacy aliases kept so existing widgets compile without changes
  static const Color primaryPurple = Color(0xFF4361EE); // maps to accentBlue
  static const Color primaryPink   = Color(0xFFFF6B35); // maps to accentOrange
  static const Color accentTeal    = primaryTeal;

  // ── Gauge gradient (teal → green, used on the big arc) ────────────────────
  static const LinearGradient gaugeGradient = LinearGradient(
    colors: [Color(0xFF0ABFBC), Color(0xFF06D6A0)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ── Brand gradient (used on cards & buttons) ──────────────────────────────
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF4361EE), Color(0xFF0ABFBC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Alt gradient (teal → green, softer) ───────────────────────────────────
  static const LinearGradient altGradient = LinearGradient(
    colors: [Color(0xFF06D6A0), Color(0xFF0ABFBC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Expense / Income pill colours ─────────────────────────────────────────
  static const Color expenseRed   = Color(0xFFEF4444);
  static const Color incomeGreen  = Color(0xFF06D6A0);

  // ── Theme palette ─────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF5F7FA);
  static const Color darkBackground = Color(0xFF0F1117);
  static const Color darkSurface = Color(0xFF1A1D26);
  static const Color darkSurfaceAlt = Color(0xFF23273A);

  // ── Semantic ───────────────────────────────────────────────────────────────
  static Color scaffold(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBackground
          : background;

  static Color surfaceColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSurface
          : Colors.white;

  static Color surfaceAlt(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSurfaceAlt
          : const Color(0xFFF0F4F8);

  static Color panel(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E2130)
          : const Color(0xFFF0F4F8);

  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF1F5F9)
          : const Color(0xFF0F172A);

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF94A3B8)
          : const Color(0xFF64748B);

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2E3347)
          : const Color(0xFFE2E8F0);

  static Color shadow(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.black.withValues(alpha: 0.35)
          : const Color(0xFF0F172A).withValues(alpha: 0.06);
}
