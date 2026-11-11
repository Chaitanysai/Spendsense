import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'pressable.dart';

/// The surface ladder, in order of distance from the page.
///
/// Modelled on PanelUI's `Surface` (`packages/panelui/src/components/surface`),
/// which expresses depth as a *ladder* rather than a palette: each step is one
/// level further from the canvas, and nesting them is how you build depth
/// without hardcoding a colour anywhere. PanelUI's `default`/`secondary`/
/// `tertiary`/`transparent` map to [raised]/[grouped]/[tertiary]/[canvas].
///
/// It never invents a colour: every value comes from [AppColors], so all 19
/// palettes and both brightnesses resolve without a per-screen override.
enum AppSurfaceLevel {
  /// The page itself. No decoration; exists so a widget can take a surface
  /// argument and still render "nothing" without a null check.
  canvas,

  /// A secondary block or list surface that sits *on* the page and must read
  /// one step quieter than a raised card. Hairline, no shadow.
  grouped,

  /// A band set *into* a surface — a card footer of actions, a totals strip.
  /// One step deeper than [grouped] by blending the palette's own ink into it.
  tertiary,

  /// The focal card on a screen (hero, chart, summary). The only level that
  /// casts a shadow by default, and that shadow is restrained (see
  /// [AppColors.glassShadows]).
  raised,
}

/// The one surface vocabulary for the app.
///
/// PanelUI's rules that carry over exactly:
///
/// * **Elevation is opt-in.** "A nested surface reads its depth from its fill,
///   not from a shadow it would only cast onto its parent." Only [raised]
///   shadows by default; anything nested inside it uses [grouped] or
///   [tertiary].
/// * **A hairline is what makes a plane readable.** A surface close in tone to
///   what it sits on gets `bordered`. [grouped] and [tertiary] always are (they
///   are deliberately one quiet step from their backdrop). [raised] is bordered
///   in dark mode and on light palettes whose card-to-page step is under
///   [AppColors.surfaceEdgeThreshold]; elsewhere the white card separates by
///   tone alone, as in the reference design.
/// * **Padding is a scale, not a number.** Pass `EdgeInsets.zero` when the
///   surface wraps a bled chart or list; otherwise use [AppSpacing] tokens.
///   The default is [AppSpacing.cardPadding], the one value every card, chart
///   and list surface in the app starts from.
///
/// Sizing, ink and motion stay with the caller: this is a container, not a
/// card template.
class AppSurface extends StatelessWidget {
  final Widget child;
  final AppSurfaceLevel level;
  final EdgeInsetsGeometry? padding;
  final double radius;

  /// Shadow override. Null means "whatever the level implies": true for
  /// [raised], false for everything else.
  final bool? shadow;

  /// Hairline override. Null means "whatever the level and palette need" (see
  /// the class notes).
  final bool? bordered;

  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final Border? border;

  /// When set, the surface is announced as one node instead of exposing every
  /// child separately. Use it for a surface whose whole content is one reading.
  final String? semanticLabel;

  const AppSurface({
    super.key,
    required this.child,
    this.level = AppSurfaceLevel.raised,
    this.padding,
    this.radius = AppRadius.card,
    this.shadow,
    this.bordered,
    this.onTap,
    this.gradient,
    this.color,
    this.border,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final resolvedPadding =
        padding ?? const EdgeInsets.all(AppSpacing.cardPadding);
    final resolvedShadow = shadow ?? level == AppSurfaceLevel.raised;
    final resolvedBordered = bordered ??
        switch (level) {
          AppSurfaceLevel.canvas => false,
          AppSurfaceLevel.raised => AppColors.needsSurfaceEdge(context),
          _ => true,
        };

    final BoxDecoration decoration;
    switch (level) {
      case AppSurfaceLevel.canvas:
        decoration = const BoxDecoration();
      case AppSurfaceLevel.grouped:
        decoration = BoxDecoration(
          color: AppColors.surfaceGrouped(context),
          borderRadius: borderRadius,
          border: resolvedBordered
              ? Border.all(color: AppColors.border(context))
              : null,
        );
      case AppSurfaceLevel.tertiary:
        decoration = BoxDecoration(
          color: AppColors.surfaceTertiary(context),
          borderRadius: borderRadius,
          border: resolvedBordered
              ? Border.all(
                  color: AppColors.border(context).withValues(alpha: 0.72),
                )
              : null,
        );
      case AppSurfaceLevel.raised:
        // The palette's measured panel tone: the same fill, hairline and
        // shadow contract every existing card already uses.
        decoration = AppColors.panelDecoration(
          context,
          borderRadius: borderRadius,
          shadow: resolvedShadow,
        ).copyWith(
          border: resolvedBordered
              ? Border.all(color: AppColors.glassBorder(context))
              : null,
        );
    }

    final resolved = decoration.copyWith(
      gradient: gradient,
      color: gradient != null ? null : (color ?? decoration.color),
      border: border ?? decoration.border,
    );

    final content = Container(
      decoration: resolved,
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
    final tappable = onTap == null ? clipped : PressFeedback(child: clipped);
    final label = semanticLabel;
    if (label == null) return tappable;
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: tappable,
    );
  }
}

/// The one hairline used between rows and groups.
class AppSeparator extends StatelessWidget {
  final double indent;
  final double endIndent;

  const AppSeparator({super.key, this.indent = 0, this.endIndent = 0});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        endIndent: endIndent,
        color: AppColors.border(context).withValues(alpha: 0.72),
      );
}
