import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// An [IndexedStack] that keeps every child alive (so providers, scroll
/// positions and text fields survive tab switches) while softly fading and
/// lifting the incoming page. Reduced-motion aware.
///
/// Every child is wrapped in the *same* widget chain whether it is active or
/// not. Only the animation driving that chain differs. Wrapping just the active
/// child would change its widget type on every switch, and Flutter would then
/// dispose the old tab and build the new one from scratch, losing its scroll
/// position and re-running its `initState`.
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = AppMotion.base,
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  // Built once instead of on every rebuild.
  late final Animation<double> _curve =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.015),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void didUpdateWidget(covariant FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;

    return Stack(
      children: List.generate(widget.children.length, (i) {
        final active = i == widget.index;
        // With reduced motion no wrapper exists for ANY child, so the chain is
        // still identical for active and inactive tabs and nothing is rebuilt
        // on a switch.
        final Widget page = reduced
            ? widget.children[i]
            : FadeTransition(
                // Resting pages use the completed animation: opacity 1 paints
                // the child directly (no layer) and the offset is zero.
                opacity: active ? _curve : kAlwaysCompleteAnimation,
                child: SlideTransition(
                  position: active
                      ? _slide
                      : const AlwaysStoppedAnimation<Offset>(Offset.zero),
                  child: widget.children[i],
                ),
              );
        return Offstage(
          offstage: !active,
          child: TickerMode(enabled: active, child: page),
        );
      }),
    );
  }
}
