import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/transaction_provider.dart';
import '../services/recurring_detector_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_states.dart';
import '../widgets/category_bubble.dart';
import '../widgets/gradient_hero_card.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);
    final detector = RecurringDetectorService();
    final recurring = detector.detectRecurring(provider.transactions);
    final subscriptions = detector.findSubscriptions(recurring);
    final monthlyCost = detector.getEstimatedMonthlyCost(subscriptions);
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
                            Text('₹${monthlyCost.toStringAsFixed(0)}',
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
                title: 'No recurring payments yet',
                message:
                    'Make at least two transactions to the same merchant and SpendSense will detect the pattern automatically.',
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
                      '${sub.frequencyLabel} • ₹${sub.averageAmount.toStringAsFixed(0)} avg',
                      style: AppText.body(context).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${sub.averageAmount.toStringAsFixed(0)}',
                      style: AppText.amount(context,
                          size: 18, color: AppColors.brand)),
                  const SizedBox(height: 2),
                  Text('${sub.occurrenceCount} payments',
                      style: AppText.body(context).copyWith(fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: AppColors.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('First: ${DateFormat('dd MMM').format(sub.firstOccurrence)}',
                  style: AppText.body(context).copyWith(fontSize: 11)),
              Text('Last: ${DateFormat('dd MMM').format(sub.lastOccurrence)}',
                  style: AppText.body(context).copyWith(fontSize: 11)),
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
                Text(recurring.merchant,
                    style: AppText.title(context).copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${recurring.frequencyLabel} • ₹${recurring.averageAmount.toStringAsFixed(0)}',
                  style: AppText.body(context).copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.textTertiary(context)),
        ],
      ),
    );
  }
}
