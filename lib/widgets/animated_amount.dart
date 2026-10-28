import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// Animated numeric text: eases from zero on first build, then eases between
/// value changes. Respects reduced-motion by snapping to the end value.
///
/// It deliberately does NOT re-count from zero when the page is re-entered.
/// Keying the tween to the page-entry generation made the hero balance count up
/// from ₹0 on every tab switch, which reads as a loading state that never
/// finishes. A value that has not changed stays put.
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

    // No page-entry key: the tween is keyed to nothing, so an ordinary rebuild
    // (or a page re-entry) keeps the finished value and only a genuine `value`
    // change animates — from wherever it currently is.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: d,
      curve: AppMotion.emphasized,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}
