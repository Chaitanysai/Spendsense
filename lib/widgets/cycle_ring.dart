import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// A single radial progress dial: a quiet full-circle track, an animated
/// brand-ramp arc, and a lit head that marks exactly where the cycle stands.
///
/// This is the one loud instrument on the dashboard. It exists because a
/// percentage of a budget is a *position on a circle*, not a paragraph: the
/// reference home screens this design follows (GO Club's step ring, Suno's
/// circular play controls) all answer "how am I doing?" with one geometry the
/// eye reads before it reads a number.
///
/// The arc is deliberately a fixed-width stroke with a round cap; the track is
/// thinner than the progress so the filled part reads as the object and the
/// empty part as the surface it moves on. The head glow is a radial *paint*,
/// not a [MaskFilter], so the cost stays one small gradient per frame.
class CycleRing extends StatelessWidget {
  /// 0..1 of the ring that is filled. Values outside the range are clamped:
  /// over-budget is represented by a full ring plus the tone change, never by
  /// an arc that wraps past its own start.
  final double fraction;

  final double size;
  final double strokeWidth;
  final Color trackColor;
  final Color startColor;
  final Color endColor;
  final Color headColor;

  /// The number, label and status that sit inside the ring.
  final Widget child;

  const CycleRing({
    super.key,
    required this.fraction,
    required this.size,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
    required this.headColor,
    required this.child,
    this.strokeWidth = 11,
  });

  @override
  Widget build(BuildContext context) {
    final target = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;

    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: reduced ? Duration.zero : const Duration(milliseconds: 900),
        curve: AppMotion.emphasized,
        builder: (context, value, _) => CustomPaint(
          painter: _CycleRingPainter(
            fraction: value,
            strokeWidth: strokeWidth,
            trackColor: trackColor,
            startColor: startColor,
            endColor: endColor,
            headColor: headColor,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _CycleRingPainter extends CustomPainter {
  final double fraction;
  final double strokeWidth;
  final Color trackColor;
  final Color startColor;
  final Color endColor;
  final Color headColor;

  const _CycleRingPainter({
    required this.fraction,
    required this.strokeWidth,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
    required this.headColor,
  });

  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.max(0.0, size.shortestSide / 2 - strokeWidth / 2 - 2);
    if (radius <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.78
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (fraction <= 0) return;

    final sweep = 2 * math.pi * fraction;
    // A three-stop sweep that returns to its first colour keeps the seam
    // invisible when the ring is complete; the gradient still travels through
    // the accent as the arc fills.
    final shader = SweepGradient(
      colors: [startColor, endColor, startColor],
      stops: const [0.0, 0.55, 1.0],
      transform: const GradientRotation(_startAngle),
    ).createShader(rect);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawArc(rect, _startAngle, sweep, false, arc);

    // The head only appears once there is a real arc to point at; at 0% a dot
    // sitting on the start line would read as progress that does not exist.
    if (fraction < 0.012) return;

    final head = Offset(
      center.dx + math.cos(_startAngle + sweep) * radius,
      center.dy + math.sin(_startAngle + sweep) * radius,
    );
    final halo = Rect.fromCircle(center: head, radius: strokeWidth * 2.1);
    canvas.drawCircle(
      head,
      strokeWidth * 2.1,
      Paint()
        ..shader = RadialGradient(
          colors: [
            headColor.withValues(alpha: 0.34),
            headColor.withValues(alpha: 0.0),
          ],
        ).createShader(halo),
    );
    canvas.drawCircle(head, strokeWidth * 0.42, Paint()..color = headColor);
  }

  @override
  bool shouldRepaint(covariant _CycleRingPainter old) =>
      old.fraction != fraction ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor ||
      old.startColor != startColor ||
      old.endColor != endColor ||
      old.headColor != headColor;
}
