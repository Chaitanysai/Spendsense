import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'pressable.dart';

/// Shared glossy pill — capsule with gradient, curved highlight,
/// luminous edge and soft glow. No BackdropFilter; only DecoratedBox,
/// ClipRRect, gradients and restrained shadows.
class GlossyPill extends StatelessWidget {
  final Widget child;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Gradient? selectedGradient;
  final Gradient? unselectedGradient;
  final Color? selectedColor;
  final double highlightIntensity;
  final SoundEventType? sound;
  final double? width;
  final double? height;
  final bool showHighlight;

  /// Drops the fill, edge, shadow and highlight while unselected, so only the
  /// selected state carries the gloss.
  ///
  /// Controls that should read plain until they are chosen (the nav badges, the
  /// expense/income segment) use this rather than swapping between two widget
  /// types: one pill renders both states, so its `AnimatedContainer` can
  /// interpolate the gradient, glow and luminous edge in instead of popping.
  final bool bareWhenUnselected;

  const GlossyPill({
    super.key,
    required this.child,
    this.selected = false,
    this.enabled = true,
    this.onTap,
    this.padding,
    this.radius = AppRadius.pill,
    this.selectedGradient,
    this.unselectedGradient,
    this.selectedColor,
    this.highlightIntensity = 1.0,
    this.sound,
    this.width,
    this.height,
    this.showHighlight = true,
    this.bareWhenUnselected = false,
  });

  /// Convenience for icon+label chip style.
  factory GlossyPill.chip({
    Key? key,
    required String label,
    IconData? icon,
    IconData? trailing,
    bool selected = false,
    bool enabled = true,
    VoidCallback? onTap,
    TextStyle? labelStyle,
    double? iconSize,
    SoundEventType? sound,
  }) {
    return GlossyPill(
      key: key,
      selected: selected,
      enabled: enabled,
      onTap: onTap,
      sound: sound,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: _ChipContent(
        label: label,
        icon: icon,
        trailing: trailing,
        selected: selected,
        labelStyle: labelStyle,
        iconSize: iconSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final effectiveOnTap = enabled ? onTap : null;
    // Bare while unselected: no fill, edge, shadow or highlight, so only the
    // selected state carries the gloss.
    final bare = bareWhenUnselected && !selected;
    final double glossIntensity = bare ? 0.0 : highlightIntensity;

    final Gradient selGrad = selectedGradient ??
        (dark ? _darkSelectedGradient() : AppColors.electricGradient);
    final Color selBorder = Colors.white.withValues(alpha: dark ? 0.22 : 0.55);
    final List<BoxShadow> selShadows = [
      BoxShadow(
        color: AppColors.brandBright.withValues(alpha: dark ? 0.30 : 0.22),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
      if (dark)
        BoxShadow(
          color: AppColors.azure.withValues(alpha: 0.18),
          blurRadius: 22,
          offset: const Offset(0, 4),
        ),
    ];

    late final Color unselFill;
    late final Color unselBorderC;
    late final List<BoxShadow> unselShadows;
    if (dark) {
      unselFill = Color.alphaBlend(
        Colors.white.withValues(alpha: 0.06),
        AppColors.darkSurfaceAlt,
      ).withValues(alpha: 0.88);
      unselBorderC = Colors.white.withValues(alpha: 0.10);
      unselShadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ];
    } else {
      unselFill = Colors.white.withValues(alpha: 0.92);
      unselBorderC = Colors.white.withValues(alpha: 0.95);
      unselShadows = [
        BoxShadow(
          color: AppColors.brand.withValues(alpha: 0.07),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
    }

    final duration = AppMotion.respect(context, AppMotion.fast);
    final borderRadius = BorderRadius.circular(radius);

    Widget pill = AnimatedContainer(
      duration: duration,
      curve: AppMotion.easeOut,
      width: width,
      height: height,
      alignment: width != null || height != null ? Alignment.center : null,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: selected ? selGrad : unselectedGradient,
        color: selected
            ? selectedColor
            : (bare
                ? Colors.transparent
                : (unselectedGradient == null ? unselFill : null)),
        borderRadius: borderRadius,
        border: bare
            ? null
            : Border.all(
                color: selected ? selBorder : unselBorderC,
                width: selected ? 1.2 : 1,
              ),
        boxShadow:
            (enabled && !bare) ? (selected ? selShadows : unselShadows) : null,
      ),
      child: child,
    );

    if (showHighlight) {
      pill = ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            pill,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient:
                        _highlightGradient(dark, selected, glossIntensity),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 1,
              right: 1,
              child: IgnorePointer(
                child: Container(
                  height: 1.1,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(radius)),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(
                            alpha: (selected
                                    ? (dark ? 0.38 : 0.55)
                                    : (dark ? 0.14 : 0.48)) *
                                glossIntensity),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      pill = ClipRRect(borderRadius: borderRadius, child: pill);
    }

    if (!enabled) {
      pill = Opacity(opacity: 0.48, child: pill);
    }

    if (effectiveOnTap != null) {
      pill = Pressable(
        onTap: effectiveOnTap,
        sound: sound,
        borderRadius: borderRadius,
        child: pill,
      );
    }

    return pill;
  }

  LinearGradient _darkSelectedGradient() {
    final c1 = AppColors.brandBright;
    final c2 =
        Color.lerp(AppColors.brandBright, const Color(0xFF7C5CFF), 0.32) ??
            AppColors.azure;
    final c3 = Color.lerp(AppColors.navyDeep, const Color(0xFF3B1D6E), 0.35) ??
        AppColors.navyDeep;
    return LinearGradient(
      colors: [c1, c2, c3],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.52, 1.0],
    );
  }

  LinearGradient _highlightGradient(
      bool dark, bool selected, double intensity) {
    if (selected) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: (dark ? 0.22 : 0.28) * intensity),
          Colors.white.withValues(alpha: (dark ? 0.08 : 0.12) * intensity),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.28, 0.58],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withValues(alpha: (dark ? 0.10 : 0.42) * intensity),
        Colors.white.withValues(alpha: (dark ? 0.02 : 0.10) * intensity),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.32, 0.62],
    );
  }
}

class _ChipContent extends StatelessWidget {
  final String label;
  final IconData? icon;
  final IconData? trailing;
  final bool selected;
  final TextStyle? labelStyle;
  final double? iconSize;

  const _ChipContent({
    required this.label,
    this.icon,
    this.trailing,
    required this.selected,
    this.labelStyle,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final Color c = selected ? Colors.white : AppColors.textSecondary(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize ?? 15, color: c),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: (labelStyle ??
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))
              .copyWith(color: c),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 4),
          Icon(trailing, size: 15, color: c),
        ],
      ],
    );
  }
}
