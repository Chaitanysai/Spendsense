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
/// the chips keep every option visible and one tap away.
///
/// Every chip is neutral until chosen: a quiet card-toned pill with a hairline
/// and the category glyph in secondary ink. The chosen chip is the only place
/// the category's own hue appears, as a tinted fill, a 1.5dp border in that hue
/// and a check, so the choice is carried by shape and glyph as well as colour.
/// Twelve differently tinted outlines at rest (the original) made the whole
/// picker read as selected.
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
    final dark = AppColors.isDark(context);
    final base = AppColors.glassSurface(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: CategoryStyle.pickerCategories.map((c) {
        final isSelected = selected == c;
        final color = CategoryStyle.color(c);
        // The pill's chosen fill, composited over the card so the ink is
        // measured against the colour that is really there.
        final tinted = Color.alphaBlend(
          color.withValues(alpha: dark ? 0.22 : 0.16),
          base,
        );
        final ink = AppColors.resolveInk(color, tinted);
        return Semantics(
          button: true,
          selected: isSelected,
          label: c,
          excludeSemantics: true,
          // `excludeSemantics` hides the Pressable's own tap action, so without
          // this a screen reader reaches the chip, hears "Food, selected,
          // button", and cannot activate it. The original had the same gap.
          onTap: () => onSelect(c),
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
                color: isSelected ? tinted : base,
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
                    isSelected ? Icons.check_rounded : CategoryStyle.icon(c),
                    size: 16,
                    color: isSelected ? ink : AppColors.textSecondary(context),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    c,
                    style: AppText.label(context).copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? AppColors.textPrimary(context)
                          : AppColors.textSecondary(context),
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
