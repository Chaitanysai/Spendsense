import 'package:flutter/material.dart';

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
    this.duration = const Duration(milliseconds: 260),
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
        return Offstage(
          offstage: !active,
          child: TickerMode(
            enabled: active,
            child: active && !reduced
                ? FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _c,
                      curve: Curves.easeOutCubic,
                    ),
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.015),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _c,
                        curve: Curves.easeOutCubic,
                      )),
                      child: widget.children[i],
                    ),
                  )
                : widget.children[i],
          ),
        );
      }),
    );
  }
}
