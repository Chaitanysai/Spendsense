import 'package:flutter/material.dart';

import '../models/assistant_models.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import 'glass_card.dart';

class AssistantSummaryCard extends StatelessWidget {
  final AssistantSummary summary;

  const AssistantSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize_rounded,
                  size: 18, color: AppColors.brandInk(context)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Summary · ${summary.label}',
                    style: AppText.bodyStrong(context)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(summary.rangeLabel, style: AppText.bodySmall(context)),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            label:
                'Spending ${Formatters.currency.format(summary.spendingMinor)}',
            child: Text(
              Formatters.currency.format(summary.spendingMinor),
              style: AppText.amount(context, size: 28),
            ),
          ),
          Text('Spending (excluded rows not counted)',
              style: AppText.caption(context)),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _Metric(
                icon: Icons.south_west_rounded,
                label: 'Expenses',
                value: Formatters.currency.format(summary.spendingMinor),
                detail: '${summary.expenseCount} counted',
                color: AppColors.expenseRed,
              ),
              if (summary.incomeCount > 0 || summary.incomeMinor > 0)
                _Metric(
                  icon: Icons.north_east_rounded,
                  label: 'Income / credits',
                  value: Formatters.currency.format(summary.incomeMinor),
                  detail: '${summary.incomeCount} records',
                  color: AppColors.incomeGreen,
                ),
              if (summary.investmentMinor > 0)
                _Metric(
                  icon: Icons.trending_up_rounded,
                  label: 'Investments',
                  value: Formatters.currency.format(summary.investmentMinor),
                  detail: 'included in spending',
                  color: AppColors.warning,
                ),
              if (summary.transferMinor > 0)
                _Metric(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Transfers',
                  value: Formatters.currency.format(summary.transferMinor),
                  detail: 'included in spending',
                  color: AppColors.azure,
                ),
              if (summary.excludedCount > 0)
                _Metric(
                  icon: Icons.visibility_off_outlined,
                  label: 'Excluded',
                  value: Formatters.currency.format(summary.excludedMinor),
                  detail: '${summary.excludedCount} not counted',
                  color: AppColors.textTertiary(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(context).copyWith(fontSize: 10.5)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(context).copyWith(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w700,
                    )),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(context).copyWith(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantSectionCard extends StatelessWidget {
  final AssistantSection section;

  const AssistantSectionCard({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final visible = section.transactions;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.title,
                        style: AppText.title(context).copyWith(fontSize: 15)),
                    if (section.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(section.subtitle!, style: AppText.caption(context)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.currency.format(section.totalMinor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppText.amount(context, size: 15),
                    ),
                    Text(
                        '${section.matchedCount} match'
                        '${section.matchedCount == 1 ? '' : 'es'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label(context).copyWith(fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
          if (section.hasInvestmentTransfers) ...[
            const SizedBox(height: AppSpacing.sm),
            _InlineNote(
              icon: Icons.trending_up_rounded,
              color: AppColors.warning,
              text: '${Formatters.currency.format(section.investmentMinor)} is '
                  'money moved to investments/transfers, not consumption.',
            ),
          ],
          if (section.excludedCount > 0) ...[
            const SizedBox(height: 6),
            _InlineNote(
              icon: Icons.visibility_off_outlined,
              color: AppColors.textTertiary(context),
              text: '${section.excludedCount} excluded '
                  '(${Formatters.currency.format(section.excludedMinor)}) '
                  'not counted in spending.',
            ),
          ],
          if (visible.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('No transaction rows to show.', style: AppText.body(context)),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: AppColors.border(context)),
            for (final tx in visible) AssistantTransactionRow(transaction: tx),
          ],
          if (section.truncated) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Showing ${visible.length} of ${section.matchedCount}. Totals use '
              'all matching records; narrow the date range to see more.',
              style: AppText.caption(context),
            ),
          ],
        ],
      ),
    );
  }
}

class AssistantTransactionRow extends StatelessWidget {
  final AssistantTransactionView transaction;

  const AssistantTransactionRow({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final color = _kindColor(context, transaction.kind);
    final isIncome = transaction.isIncome;
    final excluded = transaction.isExcluded;
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 18.2;
    final amountColor = excluded
        ? AppColors.textTertiary(context)
        : isIncome
            ? AppColors.incomeGreen
            : AppColors.textPrimary(context);
    return Semantics(
      label: '${transaction.merchant}, ${transaction.dateLabel}, '
          '${transaction.kind.label}, ${transaction.signedLabel}'
          '${excluded ? ', excluded from spending' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                transaction.kind == AssistantTransactionKind.investment
                    ? Icons.trending_up_rounded
                    : CategoryStyle.icon(transaction.category),
                size: 17,
                color: color,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.merchant,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(context).copyWith(
                      fontSize: 13,
                      decoration: excluded ? TextDecoration.lineThrough : null,
                      color: excluded
                          ? AppColors.textTertiary(context)
                          : AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${transaction.dateLabel} · ${transaction.category}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(context).copyWith(fontSize: 10.5),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      _Badge(
                        label: transaction.kind.label,
                        color: color,
                      ),
                      if (excluded)
                        _Badge(
                          label: 'Excluded',
                          color: AppColors.textTertiary(context),
                        ),
                    ],
                  ),
                  if (largeText) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        transaction.signedLabel,
                        style: AppText.amount(context, size: 13).copyWith(
                          color: amountColor,
                          decoration:
                              excluded ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!largeText) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                transaction.signedLabel,
                style: AppText.amount(context, size: 13).copyWith(
                  color: amountColor,
                  decoration: excluded ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _kindColor(BuildContext context, AssistantTransactionKind kind) {
    return switch (kind) {
      AssistantTransactionKind.income => AppColors.incomeGreen,
      AssistantTransactionKind.refund => AppColors.incomeGreen,
      AssistantTransactionKind.transfer => AppColors.azure,
      AssistantTransactionKind.investment => AppColors.incomeGreen,
      AssistantTransactionKind.expense => AppColors.expenseRed,
    };
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: AppText.label(context).copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InlineNote({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child:
              Text(text, style: AppText.body(context).copyWith(fontSize: 10.5)),
        ),
      ],
    );
  }
}

class AssistantComparisonCard extends StatelessWidget {
  final AssistantComparison comparison;

  const AssistantComparisonCard({super.key, required this.comparison});

  @override
  Widget build(BuildContext context) {
    final up = comparison.deltaMinor > 0;
    final deltaColor = up ? AppColors.expenseRed : AppColors.incomeGreen;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Month comparison',
              style: AppText.title(context).copyWith(fontSize: 15)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _CompareColumn(
                  label: comparison.currentLabel,
                  amount: comparison.currentSpendingMinor,
                  accent: AppColors.brandInk(context),
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: AppColors.border(context),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _CompareColumn(
                  label: comparison.previousLabel,
                  amount: comparison.previousSpendingMinor,
                  accent: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 8),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: deltaColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 16,
                  color: deltaColor,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${up ? 'Up' : 'Down'} '
                    '${Formatters.currency.format(comparison.deltaMinor.abs())} '
                    '(${comparison.percentChange.abs().toStringAsFixed(1)}%)',
                    style: AppText.label(context).copyWith(
                      fontSize: 11.5,
                      color: deltaColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (comparison.categoryDrivers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Category drivers', style: AppText.caption(context)),
            const SizedBox(height: 6),
            for (final driver in comparison.categoryDrivers.take(3))
              _DriverRow(
                  driver: driver, icon: CategoryStyle.icon(driver.label)),
          ],
          if (comparison.merchantDrivers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Merchant drivers', style: AppText.caption(context)),
            const SizedBox(height: 6),
            for (final driver in comparison.merchantDrivers.take(3))
              _DriverRow(driver: driver, icon: Icons.storefront_rounded),
          ],
        ],
      ),
    );
  }
}

class _CompareColumn extends StatelessWidget {
  final String label;
  final int amount;
  final Color accent;

  const _CompareColumn({
    required this.label,
    required this.amount,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(context).copyWith(fontSize: 10.5)),
        const SizedBox(height: 2),
        Text(Formatters.currency.format(amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.amount(context, size: 17).copyWith(color: accent)),
      ],
    );
  }
}

class _DriverRow extends StatelessWidget {
  final AssistantDriver driver;
  final IconData icon;

  const _DriverRow({required this.driver, required this.icon});

  @override
  Widget build(BuildContext context) {
    final positive = driver.deltaMinor > 0;
    final color = positive ? AppColors.expenseRed : AppColors.incomeGreen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textTertiary(context)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(driver.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption(context)),
          ),
          Text(
            '${positive ? '+' : '−'}${Formatters.currency.format(driver.deltaMinor.abs())}',
            style: AppText.label(context).copyWith(
              fontSize: 10.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantBillsCard extends StatelessWidget {
  final List<AssistantBillCard> bills;

  const AssistantBillsCard({super.key, required this.bills});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Unpaid bills',
                    style: AppText.title(context).copyWith(fontSize: 15)),
              ),
              Text(
                Formatters.currency.format(
                  bills.fold<int>(0, (sum, bill) => sum + bill.amountMinor),
                ),
                style: AppText.amount(context, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('Derived from your local plans and transactions',
              style: AppText.caption(context)),
          const SizedBox(height: AppSpacing.sm),
          for (final bill in bills)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _statusColor(context, bill.status)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_long_rounded,
                        size: 16, color: _statusColor(context, bill.status)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bill.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppText.title(context).copyWith(fontSize: 13)),
                        Text(
                          '${bill.status} · ${bill.dueLabel}'
                          '${bill.isRecurring ? ' · recurring' : ''}',
                          style: AppText.body(context).copyWith(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(Formatters.currency.format(bill.amountMinor),
                      style: AppText.amount(context, size: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Color _statusColor(BuildContext context, String status) {
    return switch (status) {
      'Overdue' => AppColors.danger,
      'Due soon' => AppColors.warning,
      'Paid' => AppColors.incomeGreen,
      _ => AppColors.azure,
    };
  }
}

class AssistantPendingActionCard extends StatelessWidget {
  final AssistantPendingAction action;
  final VoidCallback? onReview;

  const AssistantPendingActionCard({
    super.key,
    required this.action,
    this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final danger = action.isDeletion;
    final accent = danger ? AppColors.danger : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                danger
                    ? Icons.delete_forever_rounded
                    : Icons.visibility_off_rounded,
                color: accent,
                size: 19,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  danger ? 'Confirm permanent deletion' : 'Confirm exclusion',
                  style: AppText.bodyStrong(context),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('NOT APPLIED',
                    style: AppText.label(context).copyWith(
                        fontSize: 9,
                        color: accent,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${action.expectedCount} transaction'
            '${action.expectedCount == 1 ? '' : 's'} · '
            '${Formatters.currency.format(action.expectedTotalMinor)}',
            style: AppText.title(context).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(action.explanation,
              style:
                  AppText.body(context).copyWith(fontSize: 11.5, height: 1.4)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(context),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Spending · ${action.spendingScopeLabel}',
                      style: AppText.body(context).copyWith(fontSize: 10.5)),
                ),
                Flexible(
                  child: Text(
                    '${Formatters.currency.format(action.spendingBeforeMinor)} → '
                    '${Formatters.currency.format(action.spendingAfterMinor)}',
                    textAlign: TextAlign.right,
                    style: AppText.label(context).copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReview,
                  child: const Text('Review & confirm'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Expires at ${TimeOfDay.fromDateTime(action.expiresAt).format(context)}. '
            'Only the button above can apply it.',
            style: AppText.body(context).copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

Future<bool> showAssistantConfirmationSheet(
  BuildContext context, {
  required AssistantPendingAction action,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ConfirmSheet(action: action),
  );
  return confirmed == true;
}

class _ConfirmSheet extends StatelessWidget {
  final AssistantPendingAction action;

  const _ConfirmSheet({required this.action});

  @override
  Widget build(BuildContext context) {
    final danger = action.isDeletion;
    final accent = danger ? AppColors.danger : AppColors.warning;
    final media = MediaQuery.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xl),
            children: [
              Row(
                children: [
                  Icon(
                    danger
                        ? Icons.delete_forever_rounded
                        : Icons.visibility_off_rounded,
                    color: accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      danger ? 'Delete permanently?' : 'Exclude from spending?',
                      style: AppText.h2(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                danger
                    ? 'This removes ${action.expectedCount} records from your '
                        'encrypted ledger. It is only reversible while the '
                        'assistant audit copy is available.'
                    : 'This keeps ${action.expectedCount} records in your ledger '
                        'and removes them from spending, Insights, budgets and '
                        'instrument totals. You can undo it.',
                style: AppText.body(context),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(context),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Column(
                  children: [
                    _SheetRow(
                      label: 'Records',
                      value: '${action.expectedCount}',
                    ),
                    _SheetRow(
                      label: 'Total',
                      value:
                          Formatters.currency.format(action.expectedTotalMinor),
                    ),
                    _SheetRow(
                      label: 'Spending · ${action.spendingScopeLabel}',
                      value:
                          '${Formatters.currency.format(action.spendingBeforeMinor)} → '
                          '${Formatters.currency.format(action.spendingAfterMinor)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Exact records', style: AppText.title(context)),
              const SizedBox(height: 4),
              for (final tx in action.transactions)
                AssistantTransactionRow(transaction: tx),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        danger ? AppColors.danger : AppColors.filledBrand,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    danger ? 'Delete permanently' : 'Exclude from spending',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel — change nothing'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetRow extends StatelessWidget {
  final String label;
  final String value;

  const _SheetRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: AppText.caption(context)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppText.label(context).copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
