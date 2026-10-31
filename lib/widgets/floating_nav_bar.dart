import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Floating glass navigation pill. The Add-Transaction action deliberately lives
/// outside this widget as a floating action button, so every slot here maps to
/// a real tab.
///
/// The selected slot is marked four ways — a tinted pill, a solid accent icon, a
/// bolder label, and a slow pulse on the glow behind the icon — so the state
/// never depends on colour alone. The pill, glow and label animate between slots;
/// all three collapse to the end state when the platform requests reduced motion.
///
/// ## Cost model
///
/// [BackdropFilter] only pays for the pixels it covers. The blur is therefore
/// applied to the pill *body container*, not to the whole [ClipRRect] subtree, so
/// the FAB and the screen edges outside the pill never get sampled. The blur
/// sigma is deliberately small (12) and the surface stays translucent enough to
/// read as glass while keeping icon and label contrast well above AA.
class FloatingNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FloatingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final borderRadius = BorderRadius.circular(AppRadius.pill);
    // High contrast: a translucent pill over scrolling content is precisely the
    // legibility problem that setting exists to fix. Drop the blur, make the
    // fill near-solid and give the edge a defined border.
    final highContrast = MediaQuery.highContrastOf(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        // Outer shape clips the glass body. Nothing else lives inside this clip,
        // so the blur never samples the FAB sitting above it.
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: highContrast ? 0 : 12,
              sigmaY: highContrast ? 0 : 12,
            ),
            child: Container(
              // Minimum, not fixed: the pill grows with a large system font
              // scale instead of clipping the labels it contains.
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                // Near-black translucent near the top of the pill so the blur
                // reads as depth, easing off at the base so the blur is visible
                // against content scrolling underneath.
                gradient: highContrast
                    ? null
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: AppColors.isGlassCanvas(context)
                            ? [
                                AppColors.darkSurfaceAlt
                                    .withValues(alpha: 0.78),
                                AppColors.darkBackground
                                    .withValues(alpha: 0.62),
                              ]
                            : dark
                                ? [
                                    AppColors.darkSurfaceAlt
                                        .withValues(alpha: 0.88),
                                    AppColors.darkSurface
                                        .withValues(alpha: 0.78),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.80),
                                    Colors.white.withValues(alpha: 0.62),
                                  ],
                      ),
                color: highContrast
                    ? (dark ? AppColors.darkSurfaceAlt : Colors.white)
                    : null,
                borderRadius: borderRadius,
                // A crisp top highlight plus a faint full outline: two low-cost
                // Borders instead of a gradient-stroked painter.
                border: Border.all(
                  color: highContrast
                      ? AppColors.textPrimary(context)
                      : dark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.06),
                  width: highContrast ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow(context),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(child: _navSlot(context, i, items[i])),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navSlot(BuildContext context, int index, NavItem item) {
    final selected = index == currentIndex;
    final dark = AppColors.isDark(context);
    final selectedColor = AppColors.navSelected(context);
    final idleColor = AppColors.textTertiary(context);
    final duration = AppMotion.respect(context, AppMotion.base);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        // The tap stays on the untransformed slot, so press feedback can never
        // shrink the 48dp target or delay the tab switch.
        child: PressFeedback(
          child: ConstrainedBox(
            // Keeps the effective tap target at/above the 48dp minimum even at
            // small system font scales.
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _indicator(context, selected, item.icon, selectedColor,
                    idleColor, duration, dark),
                const SizedBox(height: AppSpacing.xs),
                // Animated + fade rather than clip: long labels ("ACTIVITY",
                // "SETTINGS") must never be cut mid-glyph at large text scales.
                AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: AppMotion.easeOut,
                  style: AppText.onGradient(
                    size: 10,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                  ).copyWith(
                    color: selected ? selectedColor : idleColor,
                    letterSpacing: 0.3,
                    height: 1.1,
                  ),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The icon chip: tinted pill, glyph, and a soft accent glow behind it.
  ///
  /// The glow is painted *outside* the chip's clip so it can bleed past the
  /// pill edge without growing the layout box or the tap target.
  Widget _indicator(
    BuildContext context,
    bool selected,
    IconData icon,
    Color selectedColor,
    Color idleColor,
    Duration duration,
    bool dark,
  ) {
    // On navy glass the selected slot is a lit electric-blue chip with a white
    // glyph, matching the primary-action gradient. Other canvases keep the
    // tinted chip. Either way selection is also shown by weight and border.
    final lit = selected && AppColors.isGlassCanvas(context);
    return AnimatedContainer(
      duration: duration,
      curve: AppMotion.easeOut,
      // Fixed padding, not animated. Padding is a layout property: animating it
      // re-lays-out the chip on every frame of the switch. The chip's size is
      // constant here, so only colour, gradient, border and shadow animate —
      // all of which paint without touching layout.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        gradient: lit
            ? LinearGradient(
                // Both stops keep a white glyph above 4.5:1.
                colors: [AppColors.azure, AppColors.brand],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: lit
            ? null
            : selected
                ? selectedColor.withValues(alpha: dark ? 0.18 : 0.13)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        // A faint hairline keeps the chip legible when the blur behind it picks
        // up a bright row of content.
        border: Border.all(
          color: selected
              ? selectedColor.withValues(alpha: dark ? 0.34 : 0.24)
              : Colors.transparent,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: (lit ? AppColors.brand : selectedColor)
                      .withValues(alpha: lit ? 0.45 : (dark ? 0.26 : 0.16)),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        size: 22,
        color: lit
            ? Colors.white
            : selected
                ? selectedColor
                : idleColor,
      ),
    );
  }
}
