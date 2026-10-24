import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'pressable.dart';

/// The shared card surface: a subtle green-grey border, a restrained shadow and
/// an optional diagonal sheen.
///
/// Light mode is a clean white card on the airy off-white canvas. Dark mode is a
/// near-black surface so cards read as panes on the AMOLED black canvas rather
/// than as green panels. Blur is intentionally modest (readability +
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
    this.sheen = false,
    this.tint,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final dark = AppColors.isDark(context);
    final glassCanvas = AppColors.isGlassCanvas(context);
    final resolvedPadding = padding ?? const EdgeInsets.all(AppSpacing.xl);
    final fill = tint ?? AppColors.glassFill(context);

    // On navy glass the card gets a faint lit top-left edge instead of a flat
    // fill, which is what reads as "glass" in the reference, at no blur cost.
    final Gradient? surfaceGradient = gradient ??
        (glassCanvas && tint == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(Colors.white.withValues(alpha: 0.05), fill),
                  fill,
                ],
              )
            : null);

    // The fill stays on the Container; the ink layer goes *inside* it. A Material
    // placed outside the decoration paints its ripple underneath the fill, where
    // the near-opaque light surface hides it completely, so nesting alone is not
    // proof that a splash is visible. Padding moves inside the ink layer so the
    // ripple covers the whole card.
    Widget content = Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: surfaceGradient,
        color: surfaceGradient == null ? fill : null,
        border: Border.all(
          color: gradient == null
              ? AppColors.glassBorder(context)
              : Colors.transparent,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: glassCanvas
                ? Colors.black.withValues(alpha: 0.35)
                : AppColors.shadow(context),
            blurRadius: dark ? 18 : 16,
            offset: const Offset(0, 6),
          ),
        ],
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

    if (sheen) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: AppColors.glassSheen,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Blurring an almost-opaque surface costs a saveLayer for no visual gain, so
    // it is only applied where the fill is actually translucent. Previously the
    // blur ran on every card, including the 90-94% opaque light and AMOLED
    // fills, so each card on a scrolling screen paid for an invisible effect.
    final translucent = gradient == null && fill.a < 0.9;
    Widget glass = ClipRRect(
      borderRadius: borderRadius,
      child: !translucent || blur <= 0
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: content,
            ),
    );

    if (onTap == null) return glass;
    // The InkWell owns the tap; this adds the immediate press scale on top of
    // the ripple, without touching the card's own design.
    return PressFeedback(child: glass);
  }
}
