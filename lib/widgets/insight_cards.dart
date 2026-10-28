import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction_model.dart';
import '../services/spending_insights.dart';
import '../utils/app_colors.dart';
import 'animated_progress_bar.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../utils/period_math.dart';
import 'glass_card.dart';

/// "12.3% more" / "5.0% less" text for a tenths-of-percent change.
String describeChange(int? tenths, {String basis = 'last period'}) {
  if (tenths == null) return 'No spending in the comparison period';
  if (tenths == 0) return 'Same as $basis';
  final value = (tenths.abs() / 10).toStringAsFixed(1);
  return '$value% ${tenths > 0 ? 'more' : 'less'} than $basis';
}

/// Week/month comparisons, category breakdown, largest expenses and a
/// six-month trend — all recomputed from [transactions] on every build.
class InsightComparisons extends StatelessWidget {
  final List<TransactionModel> transactions;
  final DateTime? now;

  const InsightComparisons({super.key, required this.transactions, this.now});

  @override
  Widget build(BuildContext context) {
    final clock = now ?? DateTime.now();
    final week = SpendingInsights.weekOverWeek(transactions, clock);
    final month = SpendingInsights.monthOverMonth(transactions, clock);
    final monthRange = PeriodMath.calendarMonth(clock);
    final breakdown =
        SpendingInsights.categoryBreakdown(transactions, monthRange);
    final largest = SpendingInsights.largestExpenses(transactions, monthRange);
    final trend = SpendingInsights.monthlyTrend(transactions, clock);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComparisonCard(week: week, month: month),
        const SizedBox(height: AppSpacing.lg),
        _BreakdownCard(shares: breakdown),
        const SizedBox(height: AppSpacing.lg),
        _LargestCard(expenses: largest),
        const SizedBox(height: AppSpacing.lg),
        _TrendCard(months: trend),
      ],
    );
  }
}

String _range(DateTimeRange r) {
  final f = DateFormat('d MMM');
  return r.start == r.end
      ? f.format(r.start)
      : '${f.format(r.start)} – ${f.format(r.end)}';
}

class _ComparisonCard extends StatelessWidget {
  final PeriodComparison week;
  final PeriodComparison month;

  const _ComparisonCard({required this.week, required this.month});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Comparisons', style: AppText.title(context)),
          const SizedBox(height: AppSpacing.md),
          _line(context, 'This week', week, 'last week'),
          const SizedBox(height: AppSpacing.md),
          _line(context, 'This month', month, 'last month'),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Each period is compared with the same number of days earlier, '
            'so a partly finished week or month is never judged against a '
            'full one. Income is not subtracted from spending.',
            style: AppText.caption(context),
          ),
        ],
      ),
    );
  }

  Widget _line(
      BuildContext context, String title, PeriodComparison c, String basis) {
    final tenths = c.changeTenthsOfPercent;
    final tone = tenths == null || tenths == 0
        ? AppColors.textSecondary(context)
        : tenths > 0
            ? AppColors.expenseRed
            : AppColors.incomeGreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppText.label(context))),
            Text(Formatters.currency.format(c.currentMinor),
                style: AppText.amount(context, size: 16)),
          ],
        ),
        Text(
          '${_range(c.current)}  vs  ${_range(c.previous)} '
          '(${Formatters.currency.format(c.previousMinor)})',
          style: AppText.caption(context),
        ),
        Text(describeChange(tenths, basis: basis),
            style: AppText.label(context).copyWith(color: tone)),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  final List<CategoryShare> shares;

  const _BreakdownCard({required this.shares});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Category breakdown',
                      style: AppText.title(context))),
              Text('THIS MONTH', style: AppText.overline(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (shares.isEmpty)
            Text('No spending this month yet.', style: AppText.body(context))
          else
            for (final s in shares.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(CategoryStyle.icon(s.category),
                        size: 16, color: CategoryStyle.color(s.category)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(s.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(context)),
                    ),
                    Text(
                      '${(s.shareTenths / 10).toStringAsFixed(1)}%  ',
                      style: AppText.label(context),
                    ),
                    Text(Formatters.currency.format(s.amountMinor),
                        style: AppText.amount(context, size: 13)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _LargestCard extends StatelessWidget {
  final List<TransactionModel> expenses;

  const _LargestCard({required this.expenses});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child:
                      Text('Largest expenses', style: AppText.title(context))),
              Text('THIS MONTH', style: AppText.overline(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (expenses.isEmpty)
            Text('No expenses this month yet.', style: AppText.body(context))
          else
            for (final t in expenses)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.merchant,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(context).copyWith(
                                  color: AppColors.textPrimary(context))),
                          Text(
                            '${t.category} · ${DateFormat('d MMM').format(t.date)}',
                            style: AppText.caption(context),
                          ),
                        ],
                      ),
                    ),
                    Text(Formatters.currency.format(t.amountMinor),
                        style: AppText.amount(context, size: 14)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<MonthTotal> months;

  const _TrendCard({required this.months});

  @override
  Widget build(BuildContext context) {
    final maxMinor =
        months.fold<int>(0, (m, e) => e.amountMinor > m ? e.amountMinor : m);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Spending trend', style: AppText.title(context))),
              Text('6 MONTHS', style: AppText.overline(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (maxMinor == 0)
            Text('No spending recorded in the last six months.',
                style: AppText.body(context))
          else
            for (final (i, m) in months.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(DateFormat('MMM').format(m.month),
                          style: AppText.label(context)),
                    ),
                    Expanded(
                      child: AnimatedProgressBar(
                        // Presentation only: a bar length, not a money value.
                        fraction: maxMinor > 0
                            ? m.amountMinor / maxMinor
                            : 0,
                        height: 10,
                        color: m.isPartial
                            ? AppColors.brandBright
                            : AppColors.brand,
                        trackColor:
                            AppColors.brand.withValues(alpha: 0.10),
                        delay: Duration(milliseconds: 30 * i),
                        semanticLabel:
                            '${DateFormat('MMM').format(m.month)} spending',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      Formatters.currency.format(m.amountMinor),
                      style: AppText.amount(context, size: 12),
                    ),
                  ],
                ),
              ),
          if (months.isNotEmpty && maxMinor > 0)
            Text(
              'The latest month is still in progress.',
              style: AppText.caption(context),
            ),
        ],
      ),
    );
  }
}
