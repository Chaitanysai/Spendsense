import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';

/// Semicircular budget gauge.
///
/// [fraction] is clamped here rather than at the call sites: a zero or negative
/// budget is a real state (the user can clear the budget field), and dividing by
/// it must never leak NaN into the arc or the label.
class BudgetGauge extends StatelessWidget {
  final double spent;
  final double budget;
  final double size;

  const BudgetGauge({
    super.key,
    required this.spent,
    required this.budget,
    this.size = 132,
  });

  /// Null when no budget is set, so callers can render a "set a budget" state
  /// instead of a misleading 0%.
  double? get _fraction =>
      budget <= 0 ? null : (spent / budget).clamp(0.0, 1.0);

  bool get _isOver => budget > 0 && spent > budget;

  @override
  Widget build(BuildContext context) {
    final fraction = _fraction;
    final dark = AppColors.isDark(context);

    // The gauge now sits on a theme-aware glass card rather than only on the
    // navy hero, so the track and figure have to follow the surface brightness.
    final trackColor = dark
        ? Colors.white.withValues(alpha: 0.20)
        : AppColors.brand.withValues(alpha: 0.14);
    final fillColors = _isOver
        ? const [AppColors.amber, AppColors.expenseRed]
        : dark
            ? const [AppColors.cyan, Colors.white]
            : const [AppColors.brand, AppColors.cyan];
    final figureColor = _isOver
        ? AppColors.expenseRed
        : dark
            ? Colors.white
            : AppColors.brand;

    return SizedBox(
      width: size,
      height: size * 0.66,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction ?? 0),
            duration: AppMotion.respect(context, AppMotion.chart),
            curve: AppMotion.emphasized,
            builder: (context, value, _) => CustomPaint(
              size: Size.infinite,
              painter: _GaugePainter(
                value: value,
                trackColor: trackColor,
                fillColors: fillColors,
                hasBudget: fraction != null,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fraction == null ? '—' : '${(fraction * 100).round()}%',
                  style: AppText.amount(
                    context,
                    size: 24,
                    color: figureColor,
                  ),
                ),
                Text(
                  fraction == null ? 'no budget' : 'of budget',
                  style: AppText.label(context).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color trackColor;
  final List<Color> fillColors;
  final bool hasBudget;

  _GaugePainter({
    required this.value,
    required this.trackColor,
    required this.fillColors,
    required this.hasBudget,
  });

  static const double _startAngle = math.pi; // 180deg, left
  static const double _sweepRange = math.pi; // through the top, to the right

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final center = Offset(size.width / 2, size.height);
    final radius = (size.width / 2) - stroke;
    if (radius <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      _startAngle,
      _sweepRange,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = trackColor,
    );

    if (!hasBudget || value <= 0) return;

    canvas.drawArc(
      rect,
      _startAngle,
      _sweepRange * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: fillColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value ||
      old.trackColor != trackColor ||
      old.fillColors != fillColors ||
      old.hasBudget != hasBudget;
}
