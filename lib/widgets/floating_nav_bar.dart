import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'glossy_pill.dart';
import 'pressable.dart';

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Floating glass navigation bar. The Add-Transaction action deliberately lives
/// outside this widget as a floating action button, so every slot here maps to
/// a real tab.
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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.black.withValues(alpha: 0.38)
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: borderRadius,
                border: Border.all(color: AppColors.glassBorder(context)),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.brand.withValues(alpha: dark ? 0.24 : 0.14),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
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
    final selectedColor = AppColors.navSelected(context);
    final color = selected ? selectedColor : AppColors.textSecondary(context);
    final duration = AppMotion.respect(context, AppMotion.base);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: () => onTap(index),
        child: ConstrainedBox(
          // Keeps the effective tap target at/above the 48dp minimum even at
          // small system font scales.
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // One widget for both states: the shared glossy pill. Rebuilding
              // the badge as a different widget when a tab is selected would
              // replace the element and pop; keeping the same pill lets the
              // gradient, glow and curved highlight animate in. Bare while
              // unselected, so the inactive slots stay understated.
              GlossyPill(
                selected: selected,
                bareWhenUnselected: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Icon(
                  item.icon,
                  size: 22,
                  // The selected icon sits on the gradient, so it takes the
                  // on-gradient white. The label below stays on the translucent
                  // bar and keeps the contrast-calibrated nav colour.
                  color: selected ? Colors.white : color,
                ),
              ),
              const SizedBox(height: 2),
              // Animated + fade rather than clip: long labels ("ACTIVITY",
              // "SETTINGS") must never be cut mid-glyph at large text scales.
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: AppMotion.easeOut,
                style: AppText.onGradient(
                  size: 9,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                ).copyWith(color: color, letterSpacing: 0.2),
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
    );
  }
}
