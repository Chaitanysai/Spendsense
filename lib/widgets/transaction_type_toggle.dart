import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

/// Shared by the add sheet and the details screen, so both pick a type the same
/// way: two always-visible segments instead of a dropdown overlay.
/// Expense/income switch. The selected side is marked by tint, icon and weight,
/// never by colour alone.
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
        color: AppColors.surfaceAlt(context),
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
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        sound: SoundEventType.selectionChanged,
        child: AnimatedContainer(
          duration: AppMotion.respect(context, AppMotion.fast),
          curve: AppMotion.easeOut,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? tint.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? tint : AppColors.textTertiary(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppText.label(context).copyWith(
                  fontSize: 13,
                  color: selected ? tint : AppColors.textTertiary(context),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
