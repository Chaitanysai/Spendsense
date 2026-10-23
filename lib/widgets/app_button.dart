import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';
import 'sound_scope.dart';

/// Primary action button — green action gradient, soft glow, press feedback and
/// an inline loading state. Uses a real [Material] + [InkWell] for accessibility.
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;
  final Gradient? gradient;

  /// Cue fired when pressed. Defaults to [SoundEventType.buttonTap]; pass
  /// `null` on buttons whose real feedback is a state-changing cue.
  final SoundEventType? sound;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expand = true,
    this.gradient,
    this.sound = SoundEventType.buttonTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final borderRadius = BorderRadius.circular(AppRadius.md);

    // The InkWell below is the only tap handler, so a press can never run the
    // callback twice. PressFeedback only observes the pointer for the scale.
    void handle() {
      final event = sound;
      if (event != null) SoundScope.play(context, event);
      onPressed!();
    }

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: PressFeedback(
        enabled: enabled,
        child: Container(
          width: expand ? double.infinity : null,
          height: 54,
          decoration: BoxDecoration(
            gradient: gradient ?? AppColors.actionGradient,
            borderRadius: borderRadius,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.brand.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: enabled ? handle : null,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: Colors.white, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.onGradient(
                                size: 16,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle secondary action — tinted fill, brand ink.
class AppGhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// See [AppPrimaryButton.sound].
  final SoundEventType? sound;

  const AppGhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.sound = SoundEventType.buttonTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppRadius.md);

    // Single cue owner, exactly as on the primary button.
    void handle() {
      final event = sound;
      if (event != null) SoundScope.play(context, event);
      onPressed!();
    }

    final enabled = onPressed != null;

    return PressFeedback(
      enabled: enabled,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.brand.withValues(alpha: 0.09),
          borderRadius: borderRadius,
          border: Border.all(
            color: AppColors.brand.withValues(alpha: 0.18),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: enabled ? handle : null,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: AppColors.brandInk(context), size: 18),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(
                    label,
                    style: AppText.label(context).copyWith(
                      color: AppColors.brandInk(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
