import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'pressable.dart';

/// Theme-led highlight surface reserved for the primary summary on a screen.
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
    this.glow = false,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final card = Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: gradient ?? AppColors.heroSurfaceGradient(context),
        borderRadius: borderRadius,
        border: AppColors.heroBorder(context),
      ),
      child: child,
    );
    final clipped = ClipRRect(borderRadius: borderRadius, child: card);
    if (onTap == null) return clipped;
    return Pressable(onTap: onTap, borderRadius: borderRadius, child: clipped);
  }
}
