import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_sheet.dart';
import 'package:provider/provider.dart';

import '../providers/period_provider.dart';
import '../providers/planner_provider.dart';
import '../providers/transaction_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/budget_math.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

/// Overall and per-category budgets for the current salary cycle.
///
/// Spending is derived from the ledger for the same period the dashboard uses
/// ([PeriodProvider.currentPeriod]); no budget changes a past transaction.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final tx = context.watch<TransactionProvider>();
    final period = context.watch<PeriodProvider>();
    final statuses =
        planner.categoryStatuses(tx.transactions, period.currentPeriod);
    final overall = BudgetProgress(
      spentMinor: tx.totalExpensesForPeriod(period.currentPeriod),
      budgetMinor: tx.monthlyBudgetMinor,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Budgets')),
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
              Text(
                'Budgets apply to ${period.periodLabel}.',
                style: AppText.body(context),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (planner.hasLoadError)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _Notice(
                    icon: Icons.gpp_maybe_rounded,
                    text: 'Saved budgets could not be read, so changes are '
                        'paused. Nothing was deleted.',
                    tone: AppColors.expenseRed,
                  ),
                ),
              const SectionHeader(title: 'Overall budget'),
              _BudgetRow(
                icon: Icons.savings_rounded,
                color: AppColors.brand,
                name: 'Monthly budget',
                progress: overall,
                onEdit: () => _editOverall(context, tx),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Warn me at'),
              _ThresholdPicker(planner: planner),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: 'Category budgets',
                actionLabel: 'Add',
                actionIcon: Icons.add_rounded,
                onAction: planner.hasLoadError
                    ? null
                    : () => _editCategory(context, planner, tx),
              ),
              if (statuses.isEmpty)
                GlassCard(
                  child: Text(
                    'No category budgets yet. Add one to track a single '
                    'category, like Food or Fuel.',
                    style: AppText.body(context),
                  ),
                )
              else
                for (final s in statuses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _BudgetRow(
                      icon: CategoryStyle.icon(s.category),
                      color: CategoryStyle.color(s.category),
                      name: s.category,
                      progress: s.progress,
                      thresholds: planner.thresholds,
                      onEdit: planner.hasLoadError
                          ? null
                          : () => _editCategory(context, planner, tx,
                              category: s.category,
                              current: s.progress.budgetMinor),
                      onDelete: planner.hasLoadError
                          ? null
                          : () => _confirmDeleteCategory(context, planner, s.category),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<bool?> _confirmDeleteCategory(
    BuildContext context,
    PlannerProvider planner,
    String category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $category budget?',
            style: AppText.title(ctx)),
        content: Text(
          'The $category budget will be removed. Your transactions stay unchanged.',
          style: AppText.body(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return null;
    await _guard(context, () => planner.removeCategoryBudget(category));
    return true;
  }

  static Future<void> _guard(
      BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That change could not be saved.')),
      );
    }
  }

  Future<void> _editOverall(
      BuildContext context, TransactionProvider tx) async {
    final minor = await _askAmount(
      context,
      title: 'Monthly budget',
      initialMinor: tx.monthlyBudgetMinor,
    );
    if (minor == null || !context.mounted) return;
    await _guard(context, () => tx.setMonthlyBudgetMinor(minor));
  }

  Future<void> _editCategory(
    BuildContext context,
    PlannerProvider planner,
    TransactionProvider tx, {
    String? category,
    int? current,
  }) async {
    var chosen = category;
    if (chosen == null) {
      final names = {
        ...CategoryStyle.pickerCategories,
        ...tx.availableCategories,
      }.where((c) => !planner.categoryBudgets.containsKey(c)).toList()
        ..sort();
      chosen = await showAppSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('Choose a category', style: AppText.h2(ctx)),
              const SizedBox(height: AppSpacing.sm),
              if (names.isEmpty)
                const Text('Every category already has a budget.'),
              for (final n in names)
                ListTile(
                  leading: Icon(CategoryStyle.icon(n),
                      color: CategoryStyle.color(n)),
                  title: Text(n),
                  onTap: () => Navigator.pop(ctx, n),
                ),
            ],
          ),
        ),
      );
    }
    if (chosen == null || !context.mounted) return;
    final target = chosen;
    final minor = await _askAmount(
      context,
      title: '$target budget',
      initialMinor: current ?? 0,
    );
    if (minor == null || !context.mounted) return;
    await _guard(context, () => planner.setCategoryBudget(target, minor));
  }

  /// Asks for a rupee amount; returns integer paise, or null if cancelled or
  /// invalid (an invalid entry shows a message and changes nothing).
  static Future<int?> _askAmount(
    BuildContext context, {
    required String title,
    required int initialMinor,
  }) async {
    final controller = TextEditingController(
      text: initialMinor > 0
          ? formatPaise(initialMinor, trimZeroPaise: true)
          : '',
    );
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: AppText.title(ctx)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
          ],
          decoration: const InputDecoration(
            prefixText: '₹ ',
            hintText: 'e.g. 5000',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return null;
    try {
      final minor = parseRupeesToPaise(text);
      if (minor <= 0 || minor > PlannerProvider.maxBudgetMinor) {
        throw const MoneyParseException('out of range');
      }
      return minor;
    } on MoneyParseException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter an amount greater than zero.')),
        );
      }
      return null;
    }
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color tone;

  const _Notice({required this.icon, required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: AppText.body(context))),
        ],
      ),
    );
  }
}

class _ThresholdPicker extends StatelessWidget {
  final PlannerProvider planner;

  const _ThresholdPicker({required this.planner});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final t in kBudgetThresholdChoices)
            FilterChip(
              label: Text('$t%'),
              selected: planner.thresholds.contains(t),
              onSelected: (on) {
                final next = {...planner.thresholds};
                on ? next.add(t) : next.remove(t);
                planner.setThresholds(next);
              },
            ),
        ],
      ),
    );
  }
}

/// One budget line: name, amounts, a bar that fills to 100% at most, and a
/// status that states the real percentage and any overspend.
class _BudgetRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name;
  final BudgetProgress progress;
  final List<int> thresholds;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _BudgetRow({
    required this.icon,
    required this.color,
    required this.name,
    required this.progress,
    this.thresholds = kDefaultBudgetThresholds,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final crossed = progress.crossedThreshold(thresholds);
    final tone = !progress.hasBudget
        ? AppColors.textTertiary(context)
        : progress.isOver
            ? AppColors.expenseRed
            : (crossed != null && crossed >= 80)
                ? AppColors.amber
                : AppColors.incomeGreen;
    final status = !progress.hasBudget
        ? 'No budget set'
        : progress.isOver
            ? '${Formatters.currency.format(progress.overMinor)} over '
                '(${progress.percentUsed}% used)'
            : '${Formatters.currency.format(progress.remainingMinor)} left '
                '(${progress.percentUsed}% used)';

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(context)),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit $name budget',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Remove $name budget',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            progress.hasBudget
                ? '${Formatters.currency.format(progress.spentMinor)} of '
                    '${Formatters.currency.format(progress.budgetMinor)}'
                : 'Spent ${Formatters.currency.format(progress.spentMinor)}',
            style: AppText.amount(context, size: 15),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress.ringFraction,
              minHeight: 8,
              color: tone,
              backgroundColor: tone.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(status,
              style:
                  AppText.label(context).copyWith(color: tone, fontSize: 12.5)),
        ],
      ),
    );
  }
}
