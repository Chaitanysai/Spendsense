import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// An [IndexedStack] that keeps every child alive (so providers, scroll
/// positions and text fields survive tab switches) while softly fading and
/// lifting the incoming page. Reduced-motion aware.
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = AppMotion.tab,
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

  /// Built once, not per frame: a fresh [CurvedAnimation] per build would leave
  /// its listener attached to the controller.
  late final CurvedAnimation _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.015),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void didUpdateWidget(covariant FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      // Reduced motion shortens this to Duration.zero, so the controller jumps
      // to 1 on the same frame and the swap reads as instant.
      _c.duration = AppMotion.respect(context, widget.duration);
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(widget.children.length, (i) {
        final active = i == widget.index;
        // Every slot keeps the same wrapper chain whether it is showing or not.
        // Varying the shape (animating child versus bare child) makes the
        // reconciler drop the outgoing and incoming subtrees' Elements, which
        // silently discards their State — scroll position, text fields,
        // controllers. Stable shape is what keeps the "keeps every child alive"
        // promise in the class doc true.
        return Offstage(
          offstage: !active,
          child: TickerMode(
            enabled: active,
            child: FadeTransition(
              opacity: _fade,
              child:
                  SlideTransition(position: _slide, child: widget.children[i]),
            ),
          ),
        );
      }),
    );
  }
}
