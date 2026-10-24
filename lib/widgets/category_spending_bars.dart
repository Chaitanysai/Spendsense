import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import 'animated_progress_bar.dart';

/// Compact horizontal category-spending rows.
///
/// Replaces the circular bubble cluster: one row per category with its icon,
/// name, share of total spending and amount, plus a proportional bar. The rows
/// use the same bar treatment as the monthly budget summary so the dashboard
/// reads as one system.
///
/// Input is integer paise — the widget never receives or produces a money
/// double. Only the *share* is a double, computed for display.
class CategorySpendingBars extends StatelessWidget {
  /// Category name → spending in paise.
  final Map<String, int> totalsMinor;

  /// How many rows to draw. Remaining categories are summarised in one line.
  final int maxRows;

  const CategorySpendingBars({
    super.key,
    required this.totalsMinor,
    this.maxRows = 6,
  });

  @override
  Widget build(BuildContext context) {
    final entries = totalsMinor.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) return const _EmptyBars();

    // Denominator is every category, not just the visible rows, so a percentage
    // is always a share of real spending and never of an arbitrary subset.
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    if (total <= 0) return const _EmptyBars();

    final shown = entries.take(maxRows).toList();
    final hidden = entries.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++)
          _CategoryBarRow(
            category: shown[i].key,
            amountMinor: shown[i].value,
            share: shown[i].value / total,
            delay: Duration(milliseconds: 40 * i),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '+$hidden more ${hidden == 1 ? 'category' : 'categories'}',
              style: AppText.label(context).copyWith(
                fontSize: 11.5,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryBarRow extends StatelessWidget {
  final String category;
  final int amountMinor;
  final double share;
  final Duration delay;

  const _CategoryBarRow({
    required this.category,
    required this.amountMinor,
    required this.share,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.color(category);
    final percent = (share * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CategoryStyle.icon(category), size: 15, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(context).copyWith(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    Formatters.currency.format(amountMinor),
                    maxLines: 1,
                    style: AppText.amount(context, size: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedProgressBar(
            fraction: share,
            height: 8,
            color: color,
            trackColor: color.withValues(alpha: 0.12),
            delay: delay,
            semanticLabel: '$category, $percent percent of spending',
          ),
        ],
      ),
    );
  }
}

class _EmptyBars extends StatelessWidget {
  const _EmptyBars();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.pie_chart_outline_rounded,
              size: 18, color: AppColors.textTertiary(context)),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'No spending to chart yet',
              style: AppText.body(context),
            ),
          ),
        ],
      ),
    );
  }
}
