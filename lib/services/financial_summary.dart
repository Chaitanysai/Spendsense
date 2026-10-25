import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../utils/budget_math.dart';
import '../utils/formatters.dart';
import '../utils/period_math.dart';
import 'spending_insights.dart';

/// Income, spending and net cash flow for one period, derived from the ledger.
/// Integer paise throughout; excluded transactions never count.
class FinancialSummary {
  final String periodLabel;
  final DateTimeRange range;
  final int incomeMinor;
  final int expenseMinor;
  final int transactionCount;
  final List<CategoryShare> topCategories;

  /// Overall budget progress for the same period (no budget => hasBudget false).
  final BudgetProgress budget;

  /// Category budgets exceeded in this period.
  final List<String> overBudgetCategories;

  const FinancialSummary({
    required this.periodLabel,
    required this.range,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.transactionCount,
    required this.topCategories,
    required this.budget,
    required this.overBudgetCategories,
  });

  /// Income minus spending. Negative means more went out than came in.
  int get netMinor => incomeMinor - expenseMinor;

  factory FinancialSummary.compute({
    required String periodLabel,
    required DateTimeRange range,
    required Iterable<TransactionModel> transactions,
    required int monthlyBudgetMinor,
    Map<String, int> categoryBudgets = const {},
  }) {
    var income = 0;
    var expense = 0;
    var count = 0;
    final spentByCategory = <String, int>{};
    for (final t in transactions) {
      if (t.isExcluded || !PeriodMath.containsLocalDate(range, t.date)) {
        continue;
      }
      count++;
      if (t.type == TransactionType.income) {
        income += t.amountMinor;
      } else {
        expense += t.amountMinor;
        spentByCategory[t.category] =
            (spentByCategory[t.category] ?? 0) + t.amountMinor;
      }
    }
    final over = [
      for (final e in categoryBudgets.entries)
        if ((spentByCategory[e.key] ?? 0) > e.value) e.key,
    ]..sort();
    return FinancialSummary(
      periodLabel: periodLabel,
      range: range,
      incomeMinor: income,
      expenseMinor: expense,
      transactionCount: count,
      topCategories: SpendingInsights.categoryBreakdown(transactions, range)
          .take(3)
          .toList(),
      budget:
          BudgetProgress(spentMinor: expense, budgetMinor: monthlyBudgetMinor),
      overBudgetCategories: over,
    );
  }

  /// Plain-text summary for an explicit save/share action. Contains totals and
  /// category names only: no merchants, accounts, references or SMS text.
  String toText() {
    String money(int v) => Formatters.currency.format(v);
    final b = StringBuffer()
      ..writeln('SpendSense summary — $periodLabel')
      ..writeln('Income: ${money(incomeMinor)}')
      ..writeln('Spent: ${money(expenseMinor)}')
      ..writeln('Net cash flow: ${money(netMinor)}')
      ..writeln('Transactions counted: $transactionCount');
    if (topCategories.isNotEmpty) {
      b.writeln('Top categories:');
      for (final c in topCategories) {
        b.writeln(
            '  ${c.category}: ${money(c.amountMinor)} (${(c.shareTenths / 10).toStringAsFixed(1)}%)');
      }
    }
    if (budget.hasBudget) {
      b.writeln(budget.isOver
          ? 'Budget: ${money(budget.overMinor)} over '
              '${money(budget.budgetMinor)} (${budget.percentUsed}% used)'
          : 'Budget: ${money(budget.remainingMinor)} left of '
              '${money(budget.budgetMinor)} (${budget.percentUsed}% used)');
    }
    if (overBudgetCategories.isNotEmpty) {
      b.writeln('Over budget: ${overBudgetCategories.join(', ')}');
    }
    return b.toString();
  }
}
