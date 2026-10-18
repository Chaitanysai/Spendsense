import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// Adds restrained press feedback (0.97 scale) to any tappable child.
/// Collapses to no-op when the platform requests reduced motion.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final BorderRadius? borderRadius;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.borderRadius,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: (_down && !reduced) ? widget.scale : 1.0,
        duration: AppMotion.respect(context, AppMotion.fast),
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}
