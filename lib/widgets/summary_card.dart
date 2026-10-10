import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/formatters.dart';

/// Large arc-gauge card showing spent vs budget — redesigned with modern
/// Material 3 liquid glass / aurora aesthetic.
class SummaryCard extends StatelessWidget {
  final double total;
  final int count;
  final String topCat;

  /// Monthly budget cap. Defaults to 50 000 if not supplied.
  final double budget;

  const SummaryCard({
    super.key,
    required this.total,
    required this.count,
    required this.topCat,
    this.budget = 50000,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (budget - total).clamp(0, budget);
    final fraction = (total / budget).clamp(0.0, 1.0);
    final isOver = total > budget;
    final subtitle = isOver
        ? 'Over by ${Formatters.currency.format(total - budget)}'
        : '${Formatters.currency.format(remaining)} remaining';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.border(context).withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryTeal.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOver
                            ? AppColors.accentOrange
                            : AppColors.primaryTeal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Monthly Budget: ₹${budget.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_forward_ios_rounded,
                    size: 12, color: AppColors.textSecondary(context)),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Arc gauge ─────────────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final gaugeWidth = constraints.maxWidth;
              final gaugeHeight = gaugeWidth * 0.65;
              return Center(
                child: SizedBox(
                  height: gaugeHeight + 18,
                  width: gaugeWidth,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(gaugeWidth, gaugeHeight),
                        painter: _ArcGaugePainter(
                          fraction: fraction,
                          isOver: isOver,
                          trackColor: AppColors.surfaceAlt(context),
                        ),
                      ),
                      Positioned(
                        bottom: 2,
                        child: Column(
                          children: [
                            Text(
                              Formatters.currency.format(total),
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary(context),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Total Spent',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary(context),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isOver
                                        ? AppColors.accentOrange
                                        : AppColors.primaryTeal)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isOver
                                      ? AppColors.accentOrange
                                      : AppColors.primaryTeal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // ── Legend row ────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(AppColors.primaryTeal),
              const SizedBox(width: 6),
              Text(
                'Spent ${Formatters.currency.format(total)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(width: 24),
              _legendDot(AppColors.surfaceAlt(context),
                  border: AppColors.border(context)),
              const SizedBox(width: 6),
              Text(
                'Budget ${Formatters.currency.format(budget)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, {Color? border}) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border != null ? Border.all(color: border, width: 1.5) : null,
      ),
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double fraction;
  final bool isOver;
  final Color trackColor;

  _ArcGaugePainter({
    required this.fraction,
    required this.isOver,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 10);
    final radius = math.min(size.width / 2, size.height) - 16;
    const strokeWidth = 18.0;

    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // Background track arc
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, trackPaint);

    // Draw tick marks along the arc
    _drawTicks(canvas, center, radius, strokeWidth, size);

    // Filled progress arc
    if (fraction > 0) {
      final progressPaint = Paint()
        ..shader = LinearGradient(
          colors: isOver
              ? [AppColors.accentOrange, const Color(0xFFFFB347)]
              : [const Color(0xFF0ABFBC), const Color(0xFF06D6A0)],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle * fraction,
        false,
        progressPaint,
      );
    }
  }

  void _drawTicks(
    Canvas canvas,
    Offset center,
    double radius,
    double strokeWidth,
    Size size,
  ) {
    const totalTicks = 48;
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i <= totalTicks; i++) {
      final angle = math.pi + (math.pi / totalTicks) * i;
      final isFilled = i / totalTicks <= fraction;
      tickPaint.color = isFilled
          ? (isOver ? AppColors.accentOrange : AppColors.primaryTeal)
              .withValues(alpha: 0.8)
          : trackColor.withValues(alpha: 0.6);

      final outerR = radius - strokeWidth * 0.6;
      final innerR = outerR - 10;

      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      canvas.drawLine(
        Offset(center.dx + cosA * innerR, center.dy + sinA * innerR),
        Offset(center.dx + cosA * outerR, center.dy + sinA * outerR),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) =>
      old.fraction != fraction || old.isOver != isOver;
}
