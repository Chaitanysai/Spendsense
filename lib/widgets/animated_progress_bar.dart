import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// The one horizontal progress bar used across SpendSense.
///
/// Behaviour:
/// * On first build it grows from zero to [fraction] with [curve], then settles
///   **exactly** on the target.
/// * When [fraction] genuinely changes it continues from the value currently on
///   screen instead of snapping or restarting at zero.
/// * An unrelated rebuild (theme change, parent setState, scroll) never
///   restarts the animation, because the target is compared, not the widget.
/// * A list can pass [delay] to stagger the starts; the timer is cancelled when
///   the widget is disposed, so nothing keeps running off screen.
/// * Reduced motion, a zero target or a zero [duration] paint the final value
///   immediately.
///
/// The bar only ever displays a ratio. Money stays integer paise in the caller;
/// this widget never performs a financial calculation.
class AnimatedProgressBar extends StatefulWidget {
  /// Ratio in 0..1. Values outside the range are clamped; NaN and infinity are
  /// treated as zero so a broken aggregate cannot crash a row.
  final double fraction;

  final double height;
  final double radius;

  /// Track (unfilled) colour. Defaults to the theme's surface container.
  final Color? trackColor;

  /// Fill colour. Ignored when [gradient] is set.
  final Color? color;

  /// Optional gradient fill (used by the budget bar).
  final Gradient? gradient;

  /// Start delay, for staggering a list of rows.
  final Duration delay;

  final Duration duration;
  final Curve curve;

  /// When set, the row is announced as a labelled progress value instead of
  /// relying on colour alone.
  final String? semanticLabel;
  final String? semanticValue;

  /// Set false for a bar that must appear already filled (for example inside a
  /// screen that is being restored with a saved scroll position).
  final bool animate;

  const AnimatedProgressBar({
    super.key,
    required this.fraction,
    this.height = 8,
    this.radius = AppRadius.pill,
    this.trackColor,
    this.color,
    this.gradient,
    this.delay = Duration.zero,
    this.duration = AppMotion.counter,
    this.curve = Curves.easeOutCubic,
    this.semanticLabel,
    this.semanticValue,
    this.animate = true,
  });

  @override
  State<AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);

  Timer? _delayTimer;
  double _from = 0;
  double _to = 0;
  bool _started = false;
  bool _reduceMotion = false;

  double get _target {
    final value = widget.fraction;
    if (!value.isFinite) return 0;
    return value.clamp(0.0, 1.0);
  }

  /// Value currently painted, in 0..1.
  double get _displayed {
    final t = widget.curve.transform(_controller.value.clamp(0.0, 1.0));
    return _from + (_to - _from) * t;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is only readable from here, not initState.
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (_started) {
      // The accessibility setting changed mid-life: settle on the target.
      if (_reduceMotion) _settle();
      return;
    }
    _started = true;
    _to = _target;
    if (!widget.animate ||
        _reduceMotion ||
        _to <= 0 ||
        widget.duration == Duration.zero) {
      _settle();
      return;
    }
    _from = 0;
    _controller.value = 0;
    _scheduleStart(widget.delay);
  }

  @override
  void didUpdateWidget(covariant AnimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    final next = _target;
    // Unrelated rebuild: keep whatever is on screen, do not replay.
    if (next == _to) return;

    _delayTimer?.cancel();
    final current = _displayed;
    _controller.stop();
    _from = current;
    _to = next;

    if (_reduceMotion || widget.duration == Duration.zero) {
      _settle();
      return;
    }
    _controller.value = 0;
    _controller.forward();
  }

  void _scheduleStart(Duration delay) {
    if (delay <= Duration.zero) {
      _controller.forward();
      return;
    }
    _delayTimer = Timer(delay, () {
      if (!mounted) return;
      _controller.forward();
    });
  }

  void _settle() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _from = _target;
    _to = _target;
    _controller.value = 1;
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.trackColor ??
        Theme.of(context).colorScheme.surfaceContainerHighest;
    final fill = widget.color ?? Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(widget.radius);

    final bar = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = _displayed;
        return ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            height: widget.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: track),
                FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.gradient == null ? fill : null,
                        gradient: widget.gradient,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: bar);
    return Semantics(
      container: true,
      label: label,
      value: widget.semanticValue ?? '${(_to * 100).round()}%',
      child: ExcludeSemantics(child: bar),
    );
  }
}
