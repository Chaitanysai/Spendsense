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

/// Floating glass navigation bar. All destinations are retained; the centre
/// slot renders as an elevated gradient action that pops out of the capsule.
class FloatingNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int? actionIndex;

  const FloatingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.actionIndex,
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
                        AppColors.crimson.withValues(alpha: dark ? 0.24 : 0.14),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(items.length, (i) {
                  if (i == actionIndex) {
                    return Expanded(child: _actionButton(context));
                  }
                  return Expanded(
                    child: _navSlot(context, i, items[i]),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(BuildContext context) {
    final active = currentIndex == actionIndex;
    return Center(
      child: GestureDetector(
        onTap: () => onTap(actionIndex!),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.respect(context, AppMotion.base),
          curve: AppMotion.easeOut,
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: AppColors.flameGradient,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    AppColors.vermilion.withValues(alpha: active ? 0.5 : 0.38),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _navSlot(BuildContext context, int index, NavItem item) {
    final selected = index == currentIndex;
    final color =
        selected ? AppColors.crimson : AppColors.textSecondary(context);

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: AppMotion.respect(context, AppMotion.base),
            curve: AppMotion.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.crimson.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Icon(item.icon, size: 22, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: AppText.onGradient(
              size: 9,
              weight: selected ? FontWeight.w700 : FontWeight.w500,
            ).copyWith(color: color, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}
