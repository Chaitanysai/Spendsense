import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/recurring_plan.dart';
import '../providers/planner_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/bill_classifier.dart';
import '../services/recurring_detector_service.dart';
import '../utils/formatters.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_states.dart';
import '../widgets/category_bubble.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/glass_card.dart';
import '../widgets/plan_editor.dart';
import '../widgets/section_header.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);
    final planner = context.watch<PlannerProvider>();
    final detector = RecurringDetectorService();
    // Only obligations belong on this screen. A repeated grocery, restaurant
    // or fuel merchant is recurring spending, not a bill to plan.
    final recurring = detector
        .detectRecurring(provider.transactions)
        .where((r) => r.transactions.any(BillClassifier.isBillLike))
        .toList();
    final subscriptions = detector.findSubscriptions(recurring);
    final monthlyCost = detector.getEstimatedMonthlyCostMinor(subscriptions);
    final others = recurring.where((r) => !subscriptions.contains(r)).toList();

    return Scaffold(
      // Opaque themed background: this screen is pushed as an opaque route, so a
      // transparent scaffold would expose an unpainted/blank surface behind it.
      backgroundColor: AppColors.scaffold(context),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            // Pushed route: the shell's nav bar and Add button are not on screen
            // here, so this matches the other pushed routes instead of reserving
            // a phantom 108px nav gap.
            AppSpacing.xxl,
          ),
          children: [
            Text('Recurring', style: AppText.h1(context)),
            const SizedBox(height: 4),
            Text('Subscriptions and repeating payments',
                style: AppText.body(context)),
            const SizedBox(height: AppSpacing.xl),
            _PlannedBills(planner: planner),
            const SizedBox(height: AppSpacing.xxl),
            GradientHeroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.subscriptions_rounded,
                          color: Colors.white.withValues(alpha: 0.85),
                          size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Text('Subscription overview',
                          style: AppText.onGradient(
                              size: 13, weight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Monthly cost',
                                style: AppText.onGradient(
                                    size: 12, opacity: 0.85)),
                            const SizedBox(height: 4),
                            Text(Formatters.currency.format(monthlyCost),
                                style: AppText.onGradient(
                                    size: 28, weight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Active subs',
                              style:
                                  AppText.onGradient(size: 12, opacity: 0.85)),
                          const SizedBox(height: 4),
                          Text('${subscriptions.length}',
                              style: AppText.onGradient(
                                  size: 28, weight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (subscriptions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxl),
              Text('Your subscriptions', style: AppText.h2(context)),
              const SizedBox(height: AppSpacing.md),
              ...subscriptions.map((sub) => _SubscriptionCard(sub: sub)),
            ],
            if (others.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxl),
              Text('Other recurring payments', style: AppText.h2(context)),
              const SizedBox(height: AppSpacing.md),
              ...others.map((r) => _RecurringCard(recurring: r)),
            ],
            if (recurring.isEmpty) ...[
              const SizedBox(height: AppSpacing.xxl),
              const AppEmptyState(
                icon: Icons.repeat_rounded,
                title: 'No recurring bills yet',
                message:
                    'SpendSense looks for repeated utility, loan, insurance, '
                    'rent and subscription payments. Groceries and one-off '
                    'spending stay out of this list.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final RecurringTransaction sub;

  const _SubscriptionCard({required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryBubble(category: sub.category, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.merchant,
                        style: AppText.title(context).copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      '${sub.frequencyLabel} • ${Formatters.currency.format(sub.averageAmountMinor)} avg',
                      style: AppText.bodySmall(context),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Formatters.currency.format(sub.averageAmountMinor),
                      style: AppText.amount(context,
                          size: 18, color: AppColors.brand)),
                  const SizedBox(height: 2),
                  Text('${sub.occurrenceCount} payments',
                      style: AppText.caption(context)),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: AppColors.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  showPlanEditor(context, from: sub.transactions.last),
              icon: const Icon(Icons.event_available_rounded, size: 18),
              label: const Text('Plan this bill'),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('First: ${DateFormat('dd MMM').format(sub.firstOccurrence)}',
                  style: AppText.caption(context)),
              Text('Last: ${DateFormat('dd MMM').format(sub.lastOccurrence)}',
                  style: AppText.caption(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecurringCard extends StatelessWidget {
  final RecurringTransaction recurring;

  const _RecurringCard({required this.recurring});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          CategoryBubble(category: recurring.category, size: 44),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recurring.merchant, style: AppText.bodyStrong(context)),
                const SizedBox(height: 2),
                Text(
                  '${recurring.frequencyLabel} • ${Formatters.currency.format(recurring.averageAmountMinor)}',
                  style: AppText.caption(context),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Plan this as a bill',
            onPressed: () =>
                showPlanEditor(context, from: recurring.transactions.last),
            icon: Icon(Icons.event_available_rounded,
                color: AppColors.textTertiary(context)),
          ),
        ],
      ),
    );
  }
}

/// User-planned bills: upcoming dues and the estimated monthly commitment.
/// Everything here is a PLAN — "Mark paid" only moves the due date forward and
/// never writes a transaction, so nothing can be duplicated in the ledger.
class _PlannedBills extends StatelessWidget {
  final PlannerProvider planner;

  const _PlannedBills({required this.planner});

  static String dueLabel(int days) {
    if (days < 0) return 'Overdue by ${-days} day${days == -1 ? '' : 's'}';
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    return 'Due in $days days';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final plans = planner.upcomingPlans;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Planned bills',
          actionLabel: 'Add',
          actionIcon: Icons.add_rounded,
          onAction: planner.hasLoadError ? null : () => showPlanEditor(context),
        ),
        if (planner.hasLoadError)
          Text('Saved bills could not be read, so changes are paused.',
              style: AppText.body(context))
        else if (plans.isEmpty)
          GlassCard(
            child: Text(
              'Plan a rent, EMI or subscription to see what is due next. '
              'Plans are reminders — they never add transactions.',
              style: AppText.body(context),
            ),
          )
        else ...[
          GlassCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Planned per month', style: AppText.label(context)),
                      const SizedBox(height: 2),
                      Text(
                        Formatters.currency
                            .format(planner.plannedMonthlyCommitmentMinor),
                        style: AppText.amount(context, size: 22),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Text(
                    'Estimate from your ${plans.length} plan'
                    '${plans.length == 1 ? '' : 's'}; not yet spent.',
                    textAlign: TextAlign.end,
                    style: AppText.caption(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final plan in plans)
            _PlanTile(plan: plan, planner: planner, today: today),
        ],
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  final RecurringPlan plan;
  final PlannerProvider planner;
  final DateTime today;

  const _PlanTile(
      {required this.plan, required this.planner, required this.today});

  @override
  Widget build(BuildContext context) {
    final days = plan.daysUntilDue(today);
    final tone = days < 0
        ? AppColors.expenseRed
        : days <= 3
            ? AppColors.warning
            : AppColors.textSecondary(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryBubble(category: plan.category, size: 40),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title(context).copyWith(fontSize: 14.5)),
                    Text(
                      '${plan.frequency.label} · PLANNED',
                      style: AppText.caption(context),
                    ),
                  ],
                ),
              ),
              Text(Formatters.currency.format(plan.amountMinor),
                  style: AppText.amount(context, size: 16)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_PlannedBills.dueLabel(days)} · '
            '${DateFormat('d MMM yyyy').format(plan.nextDue)}',
            style: AppText.label(context).copyWith(color: tone, fontSize: 12),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    _run(context, () => planner.markPlanPaid(plan.id)),
                child: const Text('Mark paid'),
              ),
              TextButton(
                onPressed: () => showPlanEditor(context, plan: plan),
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () =>
                    _run(context, () => planner.removePlan(plan.id)),
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _run(
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
}
