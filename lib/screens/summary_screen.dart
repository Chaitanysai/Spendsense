import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/period_provider.dart';
import '../providers/planner_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/financial_summary.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../utils/period_math.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

enum _SummaryPeriod { thisCycle, lastCycle, thisMonth }

/// Period summary: income, spending, net cash flow, top categories and budget
/// status. Saving writes a small text file to app storage only when the user
/// taps Save — nothing is sent anywhere.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  _SummaryPeriod _period = _SummaryPeriod.thisCycle;

  @override
  Widget build(BuildContext context) {
    final tx = context.watch<TransactionProvider>();
    final periods = context.watch<PeriodProvider>();
    final planner = context.watch<PlannerProvider>();

    final fmt = DateFormat('d MMM');
    String label(DateTimeRange r) =>
        '${fmt.format(r.start)} – ${fmt.format(r.end)}';

    final last = periods.previousPeriod;
    final DateTimeRange range;
    final String title;
    switch (_period) {
      case _SummaryPeriod.thisCycle:
        range = periods.currentPeriod;
        title = 'This cycle';
      case _SummaryPeriod.lastCycle:
        range = last ?? periods.currentPeriod;
        title = last == null ? 'This cycle' : 'Last cycle';
      case _SummaryPeriod.thisMonth:
        range = PeriodMath.calendarMonth(DateTime.now());
        title = 'This month';
    }

    final summary = FinancialSummary.compute(
      periodLabel: '$title (${label(range)})',
      range: range,
      transactions: tx.transactions,
      monthlyBudgetMinor: tx.monthlyBudgetMinor,
      categoryBudgets: planner.categoryBudgets,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Financial summary')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              MediaQuery.paddingOf(context).bottom + AppSpacing.xxxl,
            ),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final p in _SummaryPeriod.values)
                    if (p != _SummaryPeriod.lastCycle || last != null)
                      ChoiceChip(
                        label: Text(switch (p) {
                          _SummaryPeriod.thisCycle => 'This cycle',
                          _SummaryPeriod.lastCycle => 'Last cycle',
                          _SummaryPeriod.thisMonth => 'This month',
                        }),
                        selected: _period == p,
                        onSelected: (_) => setState(() => _period = p),
                      ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(label(range), style: AppText.body(context)),
              const SizedBox(height: AppSpacing.lg),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Net cash flow', style: AppText.label(context)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Formatters.currency.format(summary.netMinor),
                        style: AppText.amount(
                          context,
                          size: 30,
                          color: summary.netMinor < 0
                              ? AppColors.expenseRed
                              : AppColors.incomeGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _row(context, 'Income', summary.incomeMinor),
                    _row(context, 'Spent', summary.expenseMinor),
                    _row(context, 'Transactions', summary.transactionCount,
                        isMoney: false),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'Top categories'),
              GlassCard(
                child: summary.topCategories.isEmpty
                    ? Text('No spending in this period.',
                        style: AppText.body(context))
                    : Column(
                        children: [
                          for (final c in summary.topCategories)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: Row(
                                children: [
                                  Icon(CategoryStyle.icon(c.category),
                                      size: 16,
                                      color: CategoryStyle.color(c.category)),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                      child: Text(c.category,
                                          style: AppText.label(context))),
                                  Text(
                                      '${(c.shareTenths / 10).toStringAsFixed(1)}%  ',
                                      style: AppText.label(context)),
                                  Text(
                                      Formatters.currency.format(c.amountMinor),
                                      style: AppText.amount(context, size: 13)),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'Budget status'),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !summary.budget.hasBudget
                          ? 'No monthly budget set.'
                          : summary.budget.isOver
                              ? '${Formatters.currency.format(summary.budget.overMinor)} over your '
                                  '${Formatters.currency.format(summary.budget.budgetMinor)} budget '
                                  '(${summary.budget.percentUsed}% used)'
                              : '${Formatters.currency.format(summary.budget.remainingMinor)} left of your '
                                  '${Formatters.currency.format(summary.budget.budgetMinor)} budget '
                                  '(${summary.budget.percentUsed}% used)',
                      style: AppText.body(context)
                          .copyWith(color: AppColors.textPrimary(context)),
                    ),
                    if (summary.overBudgetCategories.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          'Over budget: ${summary.overBudgetCategories.join(', ')}',
                          style: AppText.label(context)
                              .copyWith(color: AppColors.expenseRed),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () => _save(context, summary),
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Save summary to this device'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The saved file has totals and category names only — no '
                'merchants, accounts or SMS text. Nothing is shared unless '
                'you share the file yourself.',
                style: AppText.body(context).copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, int value,
      {bool isMoney = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.label(context))),
          Text(isMoney ? Formatters.currency.format(value) : '$value',
              style: AppText.amount(context, size: 15)),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, FinancialSummary summary) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final file = File(path.join(dir.path, 'spendsense-summary-$stamp.txt'));
      await file.writeAsString(summary.toText(), flush: true);
      messenger.showSnackBar(
          const SnackBar(content: Text('Summary saved in app storage.')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Summary could not be saved.')));
    }
  }
}
