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
///
/// The name is historical: nothing here is glass. It paints the same solid
/// card tone as [AppSurface]'s raised level, with the hairline only where the
/// palette needs it ([AppColors.needsSurfaceEdge]). Its default padding stays
/// 20dp until each consuming screen is migrated to [AppSurface] in its own
/// stage, so this change re-styles every card without re-flowing any screen.
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
        border: gradient == null && AppColors.needsSurfaceEdge(context)
            ? Border.all(color: AppColors.border(context))
            : null,
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
