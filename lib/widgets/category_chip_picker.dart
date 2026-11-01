import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import 'pressable.dart';

/// The one category picker: a chip [Wrap], shared by Add and Edit so the same
/// data never wears two different controls in the same flow.
///
/// A dropdown for twelve categories is a full-screen overlay for a single tap;
/// the chips keep every option visible and one tap away. The selected chip is
/// unmistakable: its own category colour fills the pill, draws the border, and
/// drives the ink through [AppColors.inkOn] — the same contrast-aware routing
/// every IconWell uses — so light hues (Food's amber) darken their ink instead
/// of vanishing into their own tint.
class CategoryChipPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const CategoryChipPicker({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: CategoryStyle.pickerCategories.map((c) {
        final isSelected = selected == c;
        final color = CategoryStyle.color(c);
        // The pill's fill at well strength; inkOn measures the glyph against
        // this real composite, exactly as it does for icon wells.
        final dark = AppColors.isDark(context);
        final tinted = color.withValues(alpha: dark ? 0.22 : 0.18);
        final ink =
            AppColors.inkOn(color, tinted, AppColors.surfaceColor(context));
        return Semantics(
          button: true,
          selected: isSelected,
          label: c,
          excludeSemantics: true,
          child: Pressable(
            onTap: () => onSelect(c),
            sound: SoundEventType.selectionChanged,
            child: AnimatedContainer(
              duration: AppMotion.respect(context, AppMotion.fast),
              curve: AppMotion.easeOut,
              // A chip is tappable, so it meets the 48dp minimum everywhere.
              constraints:
                  const BoxConstraints(minHeight: AppSpacing.wellTouchTarget),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? Color.alphaBlend(tinted, AppColors.surfaceColor(context))
                    : AppColors.surfaceColor(context),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  width: isSelected ? 1.5 : 1,
                  color: isSelected ? color : AppColors.border(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CategoryStyle.icon(c),
                    size: 16,
                    color: isSelected ? ink : AppColors.textSecondary(context),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    c,
                    style: AppText.label(context).copyWith(
                      fontWeight: FontWeight.w700,
                      color:
                          isSelected ? ink : AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
