import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';

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
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          // Keeps the effective tap target at/above the 48dp minimum even at
          // small system font scales.
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: duration,
                curve: AppMotion.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? selectedColor.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(item.icon, size: 22, color: color),
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
