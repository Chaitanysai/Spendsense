import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_spacing.dart';
import 'sound_scope.dart';

/// Adds restrained press feedback (0.97 scale) to any tappable child.
/// Collapses to no-op when the platform requests reduced motion.
///
/// Optionally emits a semantic sound cue on tap. It defaults to silent so that
/// existing uses keep behaving exactly as before; surfaces that should tick opt
/// in explicitly, which also keeps the cue out of gestures that are not really
/// "buttons".
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final BorderRadius? borderRadius;

  /// Cue to fire when tapped, or `null` for no sound.
  final SoundEventType? sound;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.borderRadius,
    this.sound,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  Offset? _downAt;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  void _lift() {
    _downAt = null;
    _set(false);
  }

  /// The winning tap, and the only place a cue is ever emitted.
  ///
  /// Deliberately not wired to the [Listener] below: a raw pointer-down fires
  /// before the gesture arena has decided anything, so a scroll drag that starts
  /// on this control would tick even though no tap happened. By the time the tap
  /// recognizer wins, the interaction is a real tap, so the sound matches it.
  void _handleTap() {
    final sound = widget.sound;
    if (sound != null) SoundScope.play(context, sound);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final tap = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap == null ? null : _handleTap,
      child: AnimatedScale(
        scale: (_down && !reduced) ? widget.scale : 1.0,
        duration: AppMotion.respect(context, AppMotion.fast),
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
    if (widget.onTap == null) return tap;
    // Raw pointer events, not GestureDetector callbacks: inside a Scrollable the
    // tap recognizer has to wait for the drag recognizer to stand down before
    // onTapDown fires, so the dip would never show while the finger is held.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _downAt = e.position;
        _set(true);
      },
      // A drag that starts on this control belongs to the scrollable, not to it.
      onPointerMove: (e) {
        if (_downAt != null && (e.position - _downAt!).distance > kTouchSlop) {
          _lift();
        }
      },
      onPointerUp: (_) => _lift(),
      onPointerCancel: (_) => _lift(),
      child: tap,
    );
  }
}
