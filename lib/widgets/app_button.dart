import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';
import 'sound_scope.dart';

/// Primary action button — solid high-contrast fill, press feedback and
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
            color: gradient == null ? AppColors.filledBrand : null,
            gradient: gradient,
            borderRadius: borderRadius,
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

/// Icon-only action with an explicit accessible name.
///
/// PanelUI `button size="icon"`: one square target, no label, and therefore a
/// mandatory [semanticLabel] — an unlabelled glyph is unreachable for a screen
/// reader. 44dp is the target floor regardless of the visual glyph size.
enum AppIconButtonVariant {
  /// Tinted plate on a hairline. Sits inside a toolbar or a header.
  tonal,

  /// No plate: the glyph alone, for a crowded row.
  plain,
}

class AppIconButton extends StatelessWidget {
  final IconData icon;

  /// Required: what the control does, not what it looks like.
  final String semanticLabel;

  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;

  /// Long-press tooltip (Android) / accessibility hint.
  final String? tooltip;

  /// Paints the plate as selected (the toggle is on).
  final bool selected;

  /// Palette role for the glyph. Defaults to the readable brand ink.
  final Color? tone;

  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.variant = AppIconButtonVariant.tonal,
    this.tooltip,
    this.selected = false,
    this.tone,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final ink = tone ?? AppColors.brandInk(context);
    final fill = selected
        ? Color.alphaBlend(
            ink.withValues(alpha: 0.16),
            AppColors.surfaceColor(context),
          )
        : (variant == AppIconButtonVariant.tonal
            ? AppColors.surfaceAlt(context)
            : Colors.transparent);

    final button = Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onPressed,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: variant == AppIconButtonVariant.tonal
                  ? Border.all(
                      color: selected
                          ? ink.withValues(alpha: 0.42)
                          : AppColors.border(context),
                    )
                  : null,
            ),
            child: Icon(
              icon,
              size: 19,
              color: selected ? ink : AppColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );

    final hint = tooltip;
    return hint == null ? button : Tooltip(message: hint, child: button);
  }
}

/// The irreversible action: delete, remove, wipe.
///
/// Same anatomy and press contract as [AppPrimaryButton], but *quiet*: a danger
/// wash, a danger hairline and danger ink, measured against the fill it really
/// sits on. A solid red slab is the loudest object on any screen, which is the
/// wrong hierarchy for a button that should be reached deliberately — the solid
/// danger fill is reserved for the confirmation dialog that gates it.
class AppDestructiveButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;

  /// See [AppPrimaryButton.sound].
  final SoundEventType? sound;

  const AppDestructiveButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expand = true,
    this.sound = SoundEventType.buttonTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final borderRadius = BorderRadius.circular(AppRadius.md);
    final ink = AppColors.inkOnWash(context, AppColors.danger);

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
            color: AppColors.wash(context, AppColors.danger),
            borderRadius: borderRadius,
            border: Border.all(
              color: AppColors.danger.withValues(alpha: 0.42),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: enabled ? handle : null,
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ink,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: ink, size: 20),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.weight(
                                AppText.label(context),
                                FontWeight.w700,
                              ).copyWith(fontSize: 15, color: ink),
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
          color: AppColors.surfaceAlt(context),
          borderRadius: borderRadius,
          border: Border.all(
            color: AppColors.border(context),
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
                    style:
                        AppText.weight(AppText.label(context), FontWeight.w700)
                            .copyWith(
                      color: AppColors.brandInk(context),
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
