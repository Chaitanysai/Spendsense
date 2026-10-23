import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';

/// Bubble-cluster category visualisation: one circle per category, sized by its
/// share of total spend, each ringed by an arc showing that same share.
///
/// Sized by value rather than laid out in a fixed grid so the dominant category
/// reads first. The bubbles sit on the shared card surface, so body, ring and
/// label colours all resolve against the current canvas — the dominant bubble
/// is emphasised with a stronger category tint, not with white text that would
/// vanish on a light card.
class CategoryBubbleCluster extends StatelessWidget {
  final Map<String, double> totals;
  final int maxBubbles;

  const CategoryBubbleCluster({
    super.key,
    required this.totals,
    this.maxBubbles = 6,
  });

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return const _EmptyCluster(text: 'No spending to chart yet');
    }

    final shown = entries.take(maxBubbles).toList();
    final grandTotal = shown.fold<double>(0, (s, e) => s + e.value);
    if (grandTotal <= 0) {
      return const _EmptyCluster(text: 'No spending to chart yet');
    }

    final topShare = shown.first.value / grandTotal;
    // Normalise against the largest bubble so a 60/40 split still reads as a
    // clear size difference instead of collapsing every circle to one size.
    final diameters = shown.map((e) {
      final share = e.value / grandTotal;
      final scaled = 62 + (share / topShare) * 46;
      return scaled.clamp(62.0, 108.0);
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
            amount: shown[i].value,
          ),
      ],
    );
  }
}

class _EmptyCluster extends StatelessWidget {
  final String text;

  const _EmptyCluster({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline_rounded,
              size: 18, color: AppColors.textTertiary(context)),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.body(context),
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
  final double amount;

  const _Bubble({
    required this.category,
    required this.share,
    required this.diameter,
    required this.isLargest,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.color(category);
    final labelWidth = (diameter + 26).clamp(70.0, 112.0);
    final dark = AppColors.isDark(context);
    // The dominant bubble is the only one that uses a solid fill; the rest stay
    // translucent. Ink on the solid fill is chosen for contrast against the
    // category hue rather than assuming white.
    final ink = isLargest
        ? (color.computeLuminance() > 0.5
            ? const Color(0xFF0A1A14)
            : Colors.white)
        : (dark
            ? Color.lerp(color, Colors.white, 0.22) ?? color
            : Color.lerp(color, Colors.black, 0.25) ?? color);

    return Semantics(
      label: '$category, ${(share * 100).toStringAsFixed(0)} percent',
      excludeSemantics: true,
      child: SizedBox(
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
                        dark: dark,
                      ),
                    ),
                    child!,
                  ],
                ),
              ),
              // Scale down rather than overflow: at large accessibility text
              // scales the icon+percentage group must still fit the circle.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CategoryStyle.icon(category),
                      size: diameter * 0.24,
                      color: ink,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${(share * 100).toStringAsFixed(0)}%',
                      style: AppText.amount(
                        context,
                        size: diameter * 0.16,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.label(context).copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double share;
  final Color color;
  final bool prominent;
  final bool dark;

  _RingPainter({
    required this.share,
    required this.color,
    required this.prominent,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = prominent ? size.width * 0.070 : size.width * 0.055;
    final inset = stroke / 2;
    final rect =
        Offset(inset, inset) & Size(size.width - stroke, size.height - stroke);
    if (rect.shortestSide <= 0) return;

    // Bubble body. The dominant bubble gets a solid category fill; the others a
    // translucent wash that still reads on white and on near-black.
    canvas.drawCircle(
      size.center(Offset.zero),
      rect.shortestSide / 2 - inset,
      Paint()
        ..color = prominent
            ? Color.lerp(color, Colors.white, dark ? 0.06 : 0.10)!
            : color.withValues(alpha: dark ? 0.18 : 0.11),
    );

    canvas.drawCircle(
      size.center(Offset.zero),
      rect.shortestSide / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.22),
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
        ..color = dark
            ? Colors.white.withValues(alpha: 0.10)
            : color.withValues(alpha: 0.14),
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
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.share != share ||
      old.color != color ||
      old.prominent != prominent ||
      old.dark != dark;
}
