import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// Animated numeric text: eases from zero on first build and between value
/// changes. Respects reduced-motion by snapping to the end value.
class AnimatedAmount extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final String Function(double value) format;
  final Duration? duration;

  const AnimatedAmount({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final d = duration ?? AppMotion.counter;

    if (reduced) {
      return Text(format(value), style: style);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: d,
      curve: AppMotion.emphasized,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}
