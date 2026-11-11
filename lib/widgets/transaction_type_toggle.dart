import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

/// Shared by the add sheet and the details screen, so both pick a type the same
/// way: two always-visible segments instead of a dropdown overlay.
///
/// A segmented control in the PanelUI `tabs` mould: a quiet track, and the
/// selected side lifts onto a solid card-coloured pill with a hairline. The
/// selection is carried by the lifted fill, a heavier label and a check-bearing
/// direction glyph, never by tint alone; the money colour appears only on the
/// glyph, where it means "out" or "in".
class TransactionTypeToggle extends StatelessWidget {
  final bool isIncome;
  final ValueChanged<TransactionType> onSelect;

  const TransactionTypeToggle({
    super.key,
    required this.isIncome,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceTertiary(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              context,
              label: 'Expense',
              icon: Icons.south_west_rounded,
              selected: !isIncome,
              tint: AppColors.expenseRed,
              onTap: () => onSelect(TransactionType.expense),
            ),
          ),
          Expanded(
            child: _segment(
              context,
              label: 'Income',
              icon: Icons.north_east_rounded,
              selected: isIncome,
              tint: AppColors.incomeGreen,
              onTap: () => onSelect(TransactionType.income),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required Color tint,
    required VoidCallback onTap,
  }) {
    final dark = AppColors.isDark(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      // See CategoryChipPicker: excluding semantics hides the Pressable's tap
      // action, so a screen reader could not switch between Expense and Income.
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        sound: SoundEventType.selectionChanged,
        child: AnimatedContainer(
          duration: AppMotion.respect(context, AppMotion.fast),
          curve: AppMotion.easeOut,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            // Opaque: the pill is the card tone, so it reads the same on every
            // palette. The hairline is what separates it from the track.
            color:
                selected ? AppColors.glassSurface(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColors.border(context) : Colors.transparent,
            ),
            boxShadow:
                selected && !dark ? AppColors.surfaceShadowFor(dark) : const [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                // The money colour, resolved against the pill it sits on so a
                // light palette's green or red never falls under 3:1.
                color: selected
                    ? AppColors.resolveInk(
                        tint,
                        AppColors.glassSurface(context),
                        minContrast: 3,
                      )
                    : AppColors.textTertiary(context),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(context).copyWith(
                    fontSize: 13,
                    color: selected
                        ? AppColors.textPrimary(context)
                        : AppColors.textTertiary(context),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
