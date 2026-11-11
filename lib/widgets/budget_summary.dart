import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/budget_math.dart';
import '../utils/formatters.dart';
import 'animated_progress_bar.dart';

/// Ring-free monthly budget summary: period, limit, spent, a horizontal usage
/// bar and one status line.
///
/// All money is integer paise and every figure comes from [BudgetProgress], so
/// nothing here changes a financial calculation. The bar is clamped to 0..100%
/// of its width; the text always carries the *real* percentage (e.g. 150%).
class BudgetSummary extends StatelessWidget {
  final BudgetProgress progress;

  /// Heading for the budget period, e.g. "1 Oct – 31 Oct".
  final String periodLabel;

  const BudgetSummary({
    super.key,
    required this.progress,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasBudget = progress.hasBudget;
    final over = progress.isOver;
    final full =
        hasBudget && !over && progress.spentMinor == progress.budgetMinor;
    final nearLimit = hasBudget && !over && !full && progress.percentUsed >= 80;

    final Color tone = !hasBudget
        ? AppColors.textTertiary(context)
        : over
            ? AppColors.expenseRed
            : (full || nearLimit)
                ? AppColors.warning
                : AppColors.incomeGreen;
    final IconData icon = !hasBudget
        ? Icons.tune_rounded
        : over
            ? Icons.error_outline_rounded
            : (full || nearLimit)
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded;
    final String status = !hasBudget
        ? 'Set a budget'
        : over
            ? '${Formatters.currency.format(progress.overMinor)} over budget '
                '(+${progress.overPercent}%)'
            : full
                ? 'Budget fully used'
                : '${Formatters.currency.format(progress.remainingMinor)} left';

    // The status text sits on a 14% wash of its own tone. Warning amber and
    // income green fall under AA there on a light card, so the ink is resolved
    // against the colour actually behind it.
    final pillInk = AppColors.inkOnWash(context, tone);

    final spentText = 'Spent ${Formatters.currency.format(progress.spentMinor)}'
        '${hasBudget ? ' · ${progress.percentUsed}% used' : ''}';

    return Semantics(
      container: true,
      label: !hasBudget
          ? 'No budget set. $spentText'
          : '$spentText of '
              '${Formatters.currency.format(progress.budgetMinor)}. $status',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Budget limit',
            style: AppText.label(context).copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hasBudget
                  ? Formatters.currency.format(progress.budgetMinor)
                  : 'No budget set',
              maxLines: 1,
              style: AppText.amount(
                context,
                size: 24,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '$spentText \u00b7 $periodLabel',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption(context).copyWith(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _UsageBar(
            fraction: hasBudget ? progress.ringFraction : 0,
            tone: over
                ? AppColors.expenseRed
                : (full || nearLimit)
                    ? AppColors.warning
                    : AppColors.brandInk(context),
          ),
          const SizedBox(height: AppSpacing.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.wash(context, tone),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs + 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: pillInk),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(context).copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: pillInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  final double fraction;
  final Color tone;

  const _UsageBar({required this.fraction, required this.tone});

  @override
  Widget build(BuildContext context) {
    // A solid fill on the neutral tertiary track. The only colour is the
    // state (green / amber / red), and the percentage is always printed beside
    // it, so the bar never carries the reading alone.
    return AnimatedProgressBar(
      fraction: fraction.isNaN ? 0 : fraction,
      height: 8,
      trackColor: AppColors.surfaceTertiary(context),
      color: tone,
      semanticLabel: 'Budget used',
    );
  }
}
