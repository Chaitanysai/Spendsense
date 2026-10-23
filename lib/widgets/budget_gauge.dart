import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/budget_math.dart';
import '../utils/formatters.dart';

/// Circular budget gauge.
///
/// [spent] and [budget] are integer paise; all percentages come from
/// [BudgetProgress], so no floating-point money comparison happens here.
///
/// The ring fills to 100% when the budget is reached or exceeded, while the
/// centre figure always reports the *real* percentage used (e.g. 150%) so an
/// overspend is never disguised. A zero budget is a real state (the user can
/// clear the field) and renders a "no budget" prompt instead of dividing.
class BudgetGauge extends StatelessWidget {
  final int spent;
  final int budget;
  final double size;

  const BudgetGauge({
    super.key,
    required this.spent,
    required this.budget,
    this.size = 132,
  });

  BudgetProgress get _progress =>
      BudgetProgress(spentMinor: spent, budgetMinor: budget);

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final hasBudget = progress.hasBudget;
    final isOver = progress.isOver;
    final dark = AppColors.isDark(context);

    // The gauge sits on the theme-aware card surface rather than the balance
    // card, so the track and figure follow the surface brightness.
    final trackColor = dark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.brand.withValues(alpha: 0.13);
    final fillColors = isOver
        ? [AppColors.amber, AppColors.expenseRed]
        : dark
            ? [AppColors.brandBright, AppColors.lime]
            : [AppColors.brand, AppColors.brandBright];
    final figureColor =
        isOver ? AppColors.expenseRed : AppColors.brandInk(context);

    return Semantics(
      label: !hasBudget
          ? 'No budget set'
          : isOver
              ? '${progress.percentUsed} percent of budget used, '
                  '${Formatters.currency.format(progress.overMinor)} over'
              : '${progress.percentUsed} percent of budget used',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.ringFraction),
              duration: AppMotion.respect(context, AppMotion.chart),
              curve: AppMotion.emphasized,
              builder: (context, value, _) => CustomPaint(
                size: Size.square(size),
                painter: _GaugePainter(
                  value: value,
                  trackColor: trackColor,
                  fillColors: fillColors,
                  hasBudget: hasBudget,
                ),
              ),
            ),
            // Inset by the stroke + a gap so the figure never collides with the
            // arc, at any size.
            Padding(
              padding: EdgeInsets.all(size * 0.19),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      !hasBudget ? '—' : '${progress.percentUsed}%',
                      maxLines: 1,
                      style: AppText.amount(
                        context,
                        size: size * 0.24,
                        color: figureColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !hasBudget
                          ? 'no budget'
                          : isOver
                              ? 'over budget'
                              : 'of budget',
                      maxLines: 1,
                      style: AppText.label(context).copyWith(
                        fontSize: math.max(9, size * 0.085),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: isOver
                            ? AppColors.expenseRed
                            : AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

  static const double _startAngle = -math.pi / 2; // 12 o'clock
  static const double _sweepRange = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final center = size.center(Offset.zero);
    final radius = (size.width / 2) - stroke;
    if (radius <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
