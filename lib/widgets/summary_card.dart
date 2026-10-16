import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/formatters.dart';
import 'animated_amount.dart';
import 'gradient_hero_card.dart';

/// Premium gradient hero card: oversized animated balance, a circular
/// bubble-like budget ring, and supporting stats. Replaces the old arc gauge.
class SummaryCard extends StatelessWidget {
  final double total;
  final int count;
  final String topCat;
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
    final fraction = budget <= 0 ? 0.0 : (total / budget).clamp(0.0, 1.0);
    final isOver = total > budget;
    final pct = (fraction * 100).round();

    return GradientHeroCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TOTAL SPENT',
                style: AppText.onGradient(
                  size: 11,
                  weight: FontWeight.w700,
                  opacity: 0.85,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'Budget ${Formatters.currency.format(budget)}',
                  style: AppText.onGradient(size: 11, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedAmount(
                        value: total,
                        format: (v) => Formatters.currency.format(v),
                        style: AppText.hero(context).copyWith(
                          color: Colors.white,
                          fontSize: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        isOver
                            ? 'Over by ${Formatters.currency.format(total - budget)}'
                            : '${Formatters.currency.format(remaining)} remaining',
                        style: AppText.onGradient(
                          size: 11,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              _BudgetRing(fraction: fraction, percent: pct, isOver: isOver),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Stat(
                icon: Icons.receipt_long_rounded,
                label: '$count transaction${count == 1 ? '' : 's'}',
              ),
              const SizedBox(width: AppSpacing.xl),
              Flexible(
                child: _Stat(
                  icon: Icons.local_fire_department_rounded,
                  label: topCat,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Stat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.onGradient(size: 12, weight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _BudgetRing extends StatelessWidget {
  final double fraction;
  final int percent;
  final bool isOver;

  const _BudgetRing({
    required this.fraction,
    required this.percent,
    required this.isOver,
  });

  @override
  Widget build(BuildContext context) {
    const size = 104.0;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: fraction),
        duration: AppMotion.respect(context, AppMotion.counter),
        curve: AppMotion.emphasized,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _RingPainter(value: value, isOver: isOver),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$percent%',
                    style: AppText.onGradient(
                      size: 22,
                      weight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'used',
                    style: AppText.onGradient(
                      size: 10,
                      weight: FontWeight.w600,
                      opacity: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final bool isOver;

  _RingPainter({required this.value, required this.isOver});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    canvas.drawCircle(center, radius, track);

    if (value > 0) {
      final sweep = (2 * math.pi) * value;
      final progress = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: isOver
              ? [Colors.white, const Color(0xFFFFD9A0)]
              : [Colors.white, const Color(0xFFFFE3C2)],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, -math.pi / 2, sweep, false, progress);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.isOver != isOver;
}
