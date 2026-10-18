import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';
import 'sound_scope.dart';

/// Primary action button — glossy pill with highlight and soft glow.
/// Stateless, no BackdropFilter, cooperates with Pressable.
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
    final dark = AppColors.isDark(context);
    final borderRadius = BorderRadius.circular(AppRadius.pill);
    final handler = !enabled
        ? null
        : () {
            final s = sound;
            if (s != null) SoundScope.play(context, s);
            onPressed!();
          };

    final Gradient fillGrad = gradient ??
        (dark
            ? LinearGradient(
                colors: [
                  AppColors.brandBright,
                  Color.lerp(AppColors.brandBright, const Color(0xFF7C5CFF),
                          0.30) ??
                      AppColors.azure,
                  Color.lerp(
                          AppColors.navyDeep, const Color(0xFF3B1D6E), 0.32) ??
                      AppColors.navyDeep,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.50, 1.0],
              )
            : AppColors.electricGradient);

    Widget btn = AnimatedContainer(
      duration: AppMotion.respect(context, AppMotion.fast),
      curve: AppMotion.easeOut,
      width: expand ? double.infinity : null,
      height: 54,
      decoration: BoxDecoration(
        gradient: fillGrad,
        borderRadius: borderRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? 0.20 : 0.48),
          width: 1.15,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.brandBright
                      .withValues(alpha: dark ? 0.28 : 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: dark ? 0.18 : 0.24),
                        Colors.white.withValues(alpha: dark ? 0.06 : 0.10),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.30, 0.62],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              child: IgnorePointer(
                child: Container(
                  height: 1.1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: dark ? 0.34 : 0.52),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: handler,
                child: Center(
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, color: Colors.white, size: 20),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            Text(
                              label,
                              style: AppText.onGradient(
                                  size: 16, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    btn = Opacity(opacity: enabled ? 1 : 0.55, child: btn);

    if (handler != null && !loading) {
      btn = Pressable(
          onTap: handler, borderRadius: borderRadius, sound: null, child: btn);
      // sound already handled via handler wrapper; Pressable sound suppressed to avoid double.
    }

    return btn;
  }
}

/// Subtle secondary action — tinted glossy pill, brand text.
/// Kept as capsule to stay consistent with the pill language.
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
    final dark = AppColors.isDark(context);
    final borderRadius = BorderRadius.circular(AppRadius.pill);
    final handler = onPressed == null
        ? null
        : () {
            final s = sound;
            if (s != null) SoundScope.play(context, s);
            onPressed!();
          };

    Widget btn = Container(
      height: 50,
      decoration: BoxDecoration(
        color: dark
            ? Color.alphaBlend(Colors.white.withValues(alpha: 0.06),
                    AppColors.darkSurfaceAlt)
                .withValues(alpha: 0.90)
            : Colors.white,
        borderRadius: borderRadius,
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : AppColors.brand.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: 0.20)
                : AppColors.brand.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: dark ? 0.08 : 0.40),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.55],
                    ),
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: handler,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: AppColors.brand, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Text(
                        label,
                        style: AppText.label(context).copyWith(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (handler != null) {
      btn = Pressable(
          onTap: handler, borderRadius: borderRadius, sound: null, child: btn);
    }

    return btn;
  }
}
