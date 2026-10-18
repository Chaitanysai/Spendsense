import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';

/// Frosted-glass surface: translucent fill + light border + controlled blur,
/// with an optional diagonal sheen. Blur is intentionally modest (readability +
/// performance) and is applied only to this card, never the full screen.
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
    this.blur = 14,
    this.onTap,
    this.sheen = true,
    this.tint,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: gradient,
        color: gradient == null ? (tint ?? AppColors.glassFill(context)) : null,
        border: Border.all(color: AppColors.glassBorder(context), width: 1),
      ),
      child: child,
    );

    if (sheen) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: AppColors.glassSheenFor(context),
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget glass = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      ),
    );

    if (onTap != null) {
      glass = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: glass,
        ),
      );
    }

    return glass;
  }
}
