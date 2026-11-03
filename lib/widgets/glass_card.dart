import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'pressable.dart';

/// Kept for source compatibility with the floating navigation widget.
class GlassHighlight extends StatelessWidget {
  final double inset;

  const GlassHighlight({super.key, this.inset = 16});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Shared opaque surface for content groups and interactive rows.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final VoidCallback? onTap;
  final bool sheen;
  final Color? tint;
  final Gradient? gradient;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppRadius.lg,
    this.blur = 0,
    this.onTap,
    this.sheen = false,
    this.tint,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final resolvedPadding = padding ?? const EdgeInsets.all(AppSpacing.xl);
    final fill = tint ?? AppColors.surfaceColor(context);
    final content = Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: gradient,
        color: gradient == null ? fill : null,
        border: Border.all(
          color:
              gradient == null ? AppColors.border(context) : Colors.transparent,
        ),
      ),
      child: onTap == null
          ? Padding(padding: resolvedPadding, child: child)
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: borderRadius,
                onTap: onTap,
                child: Padding(padding: resolvedPadding, child: child),
              ),
            ),
    );
    final clipped = ClipRRect(borderRadius: borderRadius, child: content);
    return onTap == null ? clipped : PressFeedback(child: clipped);
  }
}
