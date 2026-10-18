import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';

/// Bubble-cluster category visualisation matching the reference: one circle per
/// category, sized by its share of total spend, each ringed by an arc showing
/// that same share.
///
/// Sized by value rather than laid out in a fixed grid so the dominant category
/// reads first — the point of the reference's treatment.
///
/// [onGradient] says which backdrop the cluster sits on. On a brand hero card
/// (its intended home) the neutral ring/track and the leading bubble are white,
/// so they read against the navy. On a plain surface they resolve through the
/// theme tokens instead, because white-on-white is invisible.
class CategoryBubbleCluster extends StatelessWidget {
  final Map<String, double> totals;
  final int maxBubbles;
  final bool onGradient;

  const CategoryBubbleCluster({
    super.key,
    required this.totals,
    this.maxBubbles = 6,
    this.onGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return _EmptyCluster(
        text: 'No spending to chart yet',
        onGradient: onGradient,
      );
    }

    final shown = entries.take(maxBubbles).toList();
    final grandTotal = shown.fold<double>(0, (s, e) => s + e.value);
    if (grandTotal <= 0) {
      return _EmptyCluster(
        text: 'No spending to chart yet',
        onGradient: onGradient,
      );
    }

    final topShare = shown.first.value / grandTotal;
    // Normalise against the largest bubble so a 60/40 split still reads as a
    // clear size difference instead of collapsing every circle to one size.
    final diameters = shown.map((e) {
      final share = e.value / grandTotal;
      final scaled = 66 + (share / topShare) * 50;
      return scaled.clamp(66.0, 116.0);
    }).toList();

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.lg,
      children: [
        for (var i = 0; i < shown.length; i++)
          _Bubble(
            category: shown[i].key,
            share: shown[i].value / grandTotal,
            diameter: diameters[i],
            isLargest: i == 0,
            onGradient: onGradient,
          ),
      ],
    );
  }
}

class _EmptyCluster extends StatelessWidget {
  final String text;
  final bool onGradient;

  const _EmptyCluster({required this.text, required this.onGradient});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.pie_chart_outline_rounded,
            size: 18,
            color: onGradient
                ? Colors.white.withValues(alpha: 0.8)
                : AppColors.textTertiary(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: onGradient
                  ? AppText.onGradient(size: 12.5, opacity: 0.85)
                  : AppText.body(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String category;
  final double share;
  final double diameter;
  final bool isLargest;
  final bool onGradient;

  const _Bubble({
    required this.category,
    required this.share,
    required this.diameter,
    required this.isLargest,
    required this.onGradient,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.color(category);
    final labelWidth = (diameter + 26).clamp(72.0, 116.0);

    // The leading bubble inverts to white only where the backdrop is a brand
    // gradient; on a plain surface it keeps its category colour so it still
    // contrasts with the card behind it.
    final emphasiseText = isLargest && onGradient;
    final arcColor = onGradient ? Colors.white : color;
    final outlineColor = onGradient
        ? Colors.white.withValues(alpha: 0.20)
        : AppColors.border(context).withValues(alpha: 0.9);
    final trackColor = onGradient
        ? Colors.white.withValues(alpha: 0.14)
        : color.withValues(alpha: 0.16);

    return SizedBox(
      width: labelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: share),
            duration: AppMotion.respect(context, AppMotion.chart),
            curve: AppMotion.emphasized,
            builder: (context, animatedShare, child) => SizedBox(
              width: diameter,
              height: diameter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(diameter, diameter),
                    painter: _RingPainter(
                      share: animatedShare,
                      color: color,
                      prominent: isLargest,
                      arcColor: arcColor,
                      outlineColor: outlineColor,
                      trackColor: trackColor,
                    ),
                  ),
                  child!,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CategoryStyle.icon(category),
                  size: diameter * 0.26,
                  color: emphasiseText ? Colors.white : color,
                ),
                const SizedBox(height: 2),
                Text(
                  '${(share * 100).toStringAsFixed(1)}%',
                  style: AppText.amount(
                    context,
                    size: diameter * 0.15,
                    color: emphasiseText ? Colors.white : color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            category,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: onGradient
                ? AppText.onGradient(
                    size: 10.5, weight: FontWeight.w600, height: 1.15)
                : AppText.label(context).copyWith(fontSize: 10.5, height: 1.15),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double share;
  final Color color;
  final bool prominent;
  final Color arcColor;
  final Color outlineColor;
  final Color trackColor;

  _RingPainter({
    required this.share,
    required this.color,
    required this.prominent,
    required this.arcColor,
    required this.outlineColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = prominent ? size.width * 0.075 : size.width * 0.06;
    final inset = stroke / 2;
    final rect =
        Offset(inset, inset) & Size(size.width - stroke, size.height - stroke);
    if (rect.shortestSide <= 0) return;

    // Bubble body: translucent category fill so the surface behind reads through.
    canvas.drawCircle(
      size.center(Offset.zero),
      rect.shortestSide / 2 - inset,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topLeft,
          colors: [
            color.withValues(alpha: prominent ? 0.55 : 0.22),
            color.withValues(alpha: prominent ? 0.30 : 0.10),
          ],
        ).createShader(rect),
    );

    canvas.drawCircle(
      size.center(Offset.zero),
      rect.shortestSide / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outlineColor,
    );

    // Progress ring, starting at 12 o'clock.
    const start = -math.pi / 2;
    canvas.drawArc(
      rect,
      start,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    if (share > 0) {
      canvas.drawArc(
        rect,
        start,
        2 * math.pi * share,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = arcColor,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share ||
      old.color != color ||
      old.prominent != prominent ||
      old.arcColor != arcColor ||
      old.outlineColor != outlineColor ||
      old.trackColor != trackColor;
}
