import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';
import 'page_entry.dart';

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

    // A new page-entry generation remounts only this small tween, so the
    // amount counts up again from zero. Ordinary rebuilds keep the same key
    // and therefore never restart a finished count.
    final generation = PageEntryScope.maybeOf(context)?.generation ?? 0;
    return TweenAnimationBuilder<double>(
      key: ValueKey('amount-entry-$generation'),
      tween: Tween<double>(begin: 0, end: value),
      duration: d,
      curve: AppMotion.emphasized,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}
