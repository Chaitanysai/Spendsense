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
                ? AppColors.amber
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
            periodLabel.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.overline(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Budget limit', style: AppText.label(context)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hasBudget
                  ? Formatters.currency.format(progress.budgetMinor)
                  : 'No budget set',
              maxLines: 1,
              style: AppText.amount(context, size: 28),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            spentText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyStrong(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          _UsageBar(
            fraction: hasBudget ? progress.ringFraction : 0,
            tone: over
                ? AppColors.expenseRed
                : (full || nearLimit)
                    ? AppColors.amber
                    : AppColors.brandBright,
          ),
          const SizedBox(height: AppSpacing.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
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
                  Icon(icon, size: 15, color: tone),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title(context)
                          .copyWith(fontSize: 12.5, color: tone),
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
    final dark = AppColors.isDark(context);
    final track = dark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.brand.withValues(alpha: 0.12);

    return AnimatedProgressBar(
      fraction: fraction.isNaN ? 0 : fraction,
      height: 10,
      trackColor: track,
      semanticLabel: 'Budget used',
      gradient: LinearGradient(
        colors: [
          Color.lerp(tone, Colors.black, 0.25)!,
          tone,
        ],
      ),
    );
  }
}
