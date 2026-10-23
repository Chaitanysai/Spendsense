import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// Plays a one-shot fade + slight upward glide when the widget first mounts.
/// Cheap (a single controller) and reduced-motion aware: when the OS disables
/// animations the child renders immediately at rest.
///
/// Because tab bodies live inside the shell's [IndexedStack] wrapped in
/// [TickerMode], an entrance on an off-screen tab stays parked until the tab is
/// actually shown — so it animates exactly once, on first view.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final double offset;

  const FadeSlideIn({super.key, required this.child, this.offset = 0.06});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  // Built once: a rebuild of the parent must not allocate a new curve (and its
  // listener bookkeeping) for every entrance wrapper on screen.
  late final Animation<double> _curved =
      CurvedAnimation(parent: _c, curve: AppMotion.emphasized);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.offset),
          end: Offset.zero,
        ).animate(_curved),
        child: widget.child,
      ),
    );
  }
}
