import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'sound_scope.dart';

/// Adds restrained press feedback (0.97 scale) to any tappable child.
/// Collapses to no-op when the platform requests reduced motion.
///
/// Optionally emits a semantic sound cue on tap. It defaults to silent so that
/// existing uses keep behaving exactly as before; surfaces that should tick opt
/// in explicitly, which also keeps the cue out of gestures that are not really
/// "buttons".
///
/// ## Keyboard and switch access
///
/// A bare [GestureDetector] is invisible to keyboard, D-pad and switch control:
/// it cannot take focus and cannot be activated without a touch. Every control
/// built on [Pressable] (quick actions, transaction rows, nav slots, filter
/// chips, the type toggle, the salary-day grid) therefore used to be
/// touch-only. This wraps the child in a [FocusableActionDetector] so it joins
/// the focus traversal order, activates on Enter/Space/select, and paints a
/// visible focus ring — while leaving the tap path untouched.
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
  bool _focused = false;

  /// The winning tap, and the only place a cue is ever emitted.
  ///
  /// Wired to `onTap` rather than `onTapDown` on purpose: a raw pointer-down
  /// fires before the gesture arena has decided anything, so a scroll drag that
  /// starts on this control would tick even though no tap happened.
  void _handleTap() {
    final cue = widget.sound;
    if (cue != null) SoundScope.play(context, cue);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to activate: stay a plain child, so a static card never grows a
    // feedback layer or a hit-test surface it does not need.
    if (widget.onTap == null) return widget.child;

    final ring = widget.borderRadius ?? BorderRadius.circular(AppRadius.sm);

    return FocusableActionDetector(
      onShowFocusHighlight: (value) {
        if (value != _focused) setState(() => _focused = value);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _handleTap();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) {
            _handleTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Stack(
          children: [
            PressFeedback(scale: widget.scale, child: widget.child),
            // Drawn above the child, outside its layout, so a focus ring can
            // never shift or clip the content it decorates.
            if (_focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: ring,
                      border: Border.all(
                        color: AppColors.brandInk(context),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Immediate press feedback for a child that owns its own tap handling — an
/// [InkWell], a [GestureDetector], a navigation slot, and so on.
///
/// Feedback starts on the raw pointer-down instead of on tap-down: a tap
/// recognizer only reports a press once the gesture arena has resolved it,
/// which is after a scrollable's drag recognizer has had its chance to win. A
/// [Listener] reports the touch immediately and never competes for the gesture,
/// so taps, long presses and drags reach the child unchanged and no callback can
/// fire twice.
///
/// The pressed state is dropped when the pointer lifts, is cancelled, or travels
/// past the touch slop (a scroll or fling has taken over), so a dragged list
/// never leaves a row stuck under the finger. Disabled controls and platforms
/// that request reduced motion stay completely still.
class PressFeedback extends StatefulWidget {
  final Widget child;

  /// A disabled control must not react to touch at all.
  final bool enabled;

  /// How far the child shrinks while pressed. 0.97 is felt rather than seen.
  final double scale;

  const PressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  /// Only the pointer that started the press drives the visual, so a second
  /// finger landing elsewhere cannot flicker the control.
  int? _pointer;
  Offset _origin = Offset.zero;
  bool _pressed = false;

  @override
  void didUpdateWidget(PressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) {
      // A control disabled mid-press (a button entering its loading state) drops
      // the pressed look without waiting for the pointer to lift.
      _pointer = null;
      _pressed = false;
    }
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    if (!_pressed) setState(() => _pressed = true);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if ((event.position - _origin).distance > kTouchSlop) _release(event);
  }

  void _release(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion removes the scale entirely; the control still taps.
    final active =
        widget.enabled && MediaQuery.maybeDisableAnimationsOf(context) != true;
    final target = (_pressed && active) ? widget.scale : 1.0;
    final pressing = target < 1.0;

    return Listener(
      // Opaque so a child that does not paint (a bare SizedBox, a spacer) still
      // reports the press. A Listener never joins the gesture arena, so this
      // cannot swallow the tap or the scroll.
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: AnimatedScale(
        // Press-in and release have different durations; the implicit animation
        // always starts from the value on screen, so reversing never jumps.
        scale: target,
        duration: AppMotion.respect(
          context,
          pressing ? AppMotion.pressIn : AppMotion.pressOut,
        ),
        curve: pressing ? AppMotion.easeOut : AppMotion.emphasized,
        child: widget.child,
      ),
    );
  }
}
