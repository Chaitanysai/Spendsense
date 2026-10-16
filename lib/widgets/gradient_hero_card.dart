import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'pressable.dart';

/// Rich gradient card (the reference's "premium red-to-orange" hero surface):
/// layered gradient, diagonal sheen, soft coloured glow shadow, and optional
/// press feedback. Text inside should use [AppText.onGradient].
class GradientHeroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final bool glow;
  final Color? glowColor;

  const GradientHeroCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppRadius.xl,
    this.gradient,
    this.onTap,
    this.glow = true,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    final card = Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: gradient ?? AppColors.heroGradient,
        borderRadius: borderRadius,
        boxShadow: glow
            ? [
                BoxShadow(
                  color:
                      (glowColor ?? AppColors.crimson).withValues(alpha: 0.32),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          // Soft top-left highlight, as described in the brief.
          Positioned(
            top: -30,
            left: -20,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.28),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );

    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child: card,
    );

    if (onTap == null) return clipped;
    return Pressable(onTap: onTap, borderRadius: borderRadius, child: clipped);
  }
}
