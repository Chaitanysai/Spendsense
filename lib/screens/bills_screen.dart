import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/recurring_plan.dart';
import '../providers/planner_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/bill_classifier.dart';
import '../services/bill_detection_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../widgets/app_sheet.dart';
import '../widgets/app_states.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/page_entry.dart';
import '../widgets/plan_editor.dart';
import '../widgets/pressable.dart';

/// Bills: recurring and upcoming payments, plus payments that already look
/// completed.
///
/// Everything here is derived from data SpendSense already stores: confirmed
/// recurring plans (encrypted, edited by the user) and parsed expense
/// transactions. Opening this screen never requests SMS permission and never
/// starts an SMS scan, and detection writes nothing, so repeated syncs cannot
/// create duplicate bills.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  static const String routeName = '/bills';

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  static const _detector = BillDetectionService();

  BillState? _filter;

  @override
  Widget build(BuildContext context) {
    final tx = context.watch<TransactionProvider>();
    // Optional so an embedded preview or a test harness without the planner
    // still renders the bills already derivable from transactions.
    final planner = context.watch<PlannerProvider?>();
    final today = DateTime.now();

    final all = _detector.detect(
      plans: planner?.plans ?? const [],
      transactions: tx.transactions,
      today: today,
      hiddenBillKeys: planner?.hiddenBillKeys ?? const {},
    );
    final visible =
        _filter == null ? all : all.where((v) => v.state == _filter).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageEntrance(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.lg,
                    AppSpacing.page,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Bills', style: AppText.h1(context)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: (planner == null || planner.hasLoadError)
                                ? null
                                : () => showPlanEditor(context),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      Text(
                        'Detected bills and the commitments you planned',
                        style: AppText.body(context),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      PageEntrance(
                        index: 1,
                        child: _Overview(views: all, today: today),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      PageEntrance(
                        index: 2,
                        child: _Filters(
                          selected: _filter,
                          onSelect: (s) => setState(() => _filter = s),
                          counts: {
                            for (final state in BillState.values)
                              state: all.where((v) => v.state == state).length,
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (planner?.hasLoadError ?? false)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                child: GlassCard(
                  child: Text(
                    'Bill data could not be read. Your records are intact; '
                    'changes are disabled until it loads.',
                    style: AppText.body(context),
                  ),
                ),
              ),
            )
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                child: Center(
                  child: AppEmptyState(
                    icon: Icons.event_available_rounded,
                    title: _filter == null
                        ? 'No bills detected yet'
                        : 'Nothing here',
                    message: _filter == null
                        ? 'SpendSense adds utility, loan, insurance, rent and '
                            'subscription bills automatically from your '
                            'payments. You can also add one manually.'
                        : 'No bills in this state right now.',
                    actionLabel: _filter == null && planner != null
                        ? 'Add a bill'
                        : null,
                    onAction: _filter == null && planner != null
                        ? () => showPlanEditor(context)
                        : null,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.tabBottomInset(context),
              ),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final view = visible[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: PageEntrance(
                      index: index,
                      offset: 0.04,
                      child: _BillRow(
                        view: view,
                        onTap: () => _openDetail(context, view),
                        onMarkPaid: () => _markPaid(context, view),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _markPaid(BuildContext context, BillView view) async {
    final plan = view.plan;
    if (plan == null) return;
    final planner = context.read<PlannerProvider?>();
    final messenger = ScaffoldMessenger.of(context);
    if (planner == null) return;
    await planner.markPlanPaid(plan.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('${plan.title} marked paid'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => planner.updatePlan(plan),
        ),
      ),
    );
  }

  Future<void> _hideAutoBill(BuildContext sheetContext, BillView view) async {
    final key = view.billerKey;
    final planner = context.read<PlannerProvider?>();
    if (key == null || planner == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await planner.hideAutoBill(key);
    if (!mounted || !sheetContext.mounted) return;
    Navigator.of(sheetContext).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${view.title} hidden from bills'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => planner.unhideAutoBill(key),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, BillView view) {
    showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _BillDetail(
        view: view,
        onHide: view.isAutoDetected
            ? () => _hideAutoBill(sheetContext, view)
            : null,
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  final List<BillView> views;
  final DateTime today;

  const _Overview({required this.views, required this.today});

  @override
  Widget build(BuildContext context) {
    final dueSoon = views.where(
        (v) => v.state == BillState.overdue || v.state == BillState.dueSoon);
    final dueTotal = dueSoon.fold<int>(0, (sum, v) => sum + v.amountMinor);
    final overdue = views.where((v) => v.state == BillState.overdue).length;
    final paid = views.where((v) => v.state == BillState.paid).length;

    return GradientHeroCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      gradient: AppColors.heroSurfaceGradient(context),
      glow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DUE NOW OR SOON',
            style: AppText.onGradient(
              size: 10,
              weight: FontWeight.w700,
              opacity: 0.76,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formatters.currency.format(dueTotal),
              maxLines: 1,
              style: AppText.onGradient(size: 34, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: overdue == 1 ? '1 overdue' : '$overdue overdue',
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: _HeroStat(
                  label: paid == 1 ? '1 paid' : '$paid paid',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  const _HeroStat({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 6, color: Colors.white.withValues(alpha: 0.7)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.onGradient(size: 12, weight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  final BillState? selected;
  final ValueChanged<BillState?> onSelect;
  final Map<BillState, int> counts;

  const _Filters({
    required this.selected,
    required this.onSelect,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(context, 'All', null, null),
          for (final state in BillState.values)
            if ((counts[state] ?? 0) > 0)
              _chip(context, state.label, state, counts[state]),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    BillState? state,
    int? count,
  ) {
    final active = selected == state;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Pressable(
        onTap: () => onSelect(state),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.brand.withValues(alpha: 0.14)
                : AppColors.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: active
                  ? AppColors.brand.withValues(alpha: 0.40)
                  : AppColors.border(context),
            ),
          ),
          child: Text(
            count == null ? label : '$label $count',
            style: AppText.label(context).copyWith(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active
                  ? AppColors.brandInk(context)
                  : AppColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final BillView view;
  final VoidCallback onTap;
  final VoidCallback onMarkPaid;

  const _BillRow({
    required this.view,
    required this.onTap,
    required this.onMarkPaid,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.color(view.category);
    final tone = _tone(context, view.state);

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(CategoryStyle.icon(view.category),
                    size: 19, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(view),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.currency.format(view.amountMinor),
                    style: AppText.amount(context, size: 15),
                  ),
                  const SizedBox(height: 4),
                  _StateChip(label: view.state.label, tone: tone),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (view.isConfirmed && view.state != BillState.paid) ...[
                OutlinedButton(
                  onPressed: onMarkPaid,
                  child: const Text('Mark paid'),
                ),
              ] else if (view.state == BillState.paid)
                Text(
                  'Matched to a payment',
                  style: AppText.bodySmall(context),
                ),
              const Spacer(),
              TextButton(
                onPressed: onTap,
                child: const Text('Details'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _tone(BuildContext context, BillState state) => switch (state) {
        BillState.paid => AppColors.incomeGreen,
        BillState.overdue => AppColors.expenseRed,
        BillState.dueSoon => AppColors.amber,
        BillState.upcoming => AppColors.textSecondary(context),
      };

  static String _subtitle(BillView view) {
    final fmt = DateFormat('d MMM');
    if (view.isAutoDetected) {
      final auto = view.autoBill!;
      final confidence = '${(auto.confidence * 100).round()}% confidence';
      if (view.state == BillState.paid) {
        final paidOn = view.matchedPayment?.date;
        return 'Auto-detected · paid ${fmt.format(paidOn ?? auto.dueDate)}'
            ' · $confidence';
      }
      final kind = auto.kind.label;
      final pattern =
          auto.isRecurring ? '$kind · ${auto.occurrenceCount} payments' : kind;
      final due = view.dueDate;
      return due == null
          ? '$pattern · $confidence'
          : '$pattern · due ${fmt.format(due)} · $confidence';
    }
    final due = view.dueDate;
    if (due == null) return view.category;
    switch (view.state) {
      case BillState.paid:
        final paidOn = view.matchedPayment?.date;
        return paidOn == null
            ? 'Paid this cycle'
            : 'Paid · ${fmt.format(paidOn)}';
      case BillState.overdue:
        final days = DateTime.now().difference(due).inDays;
        return '${days <= 0 ? 1 : days} ${days == 1 ? 'day' : 'days'} overdue'
            ' · was due ${fmt.format(due)}';
      case BillState.dueSoon:
      case BillState.upcoming:
        return 'Due ${fmt.format(due)} · ${view.plan?.frequency.label ?? ''}';
    }
  }
}

class _StateChip extends StatelessWidget {
  final String label;
  final Color tone;

  const _StateChip({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppText.label(context).copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }
}

class _BillDetail extends StatelessWidget {
  final BillView view;
  final VoidCallback? onHide;

  const _BillDetail({required this.view, this.onHide});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(view.title, style: AppText.h2(context)),
            const SizedBox(height: 4),
            Text(
              '${view.state.label} · ${Formatters.currency.format(view.amountMinor)}',
              style: AppText.body(context),
            ),
            if (view.dueDate != null) ...[
              const SizedBox(height: 2),
              Text(
                view.state == BillState.paid
                    ? 'Paid on ${fmt.format(view.dueDate!)}'
                    : 'Next due ${fmt.format(view.dueDate!)}',
                style: AppText.label(context),
              ),
            ],
            if (view.confidence != null) ...[
              const SizedBox(height: 2),
              Text(
                'Auto-detected · '
                '${(view.confidence! * 100).round()}% confidence',
                style: AppText.caption(context),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text('PAYMENT HISTORY', style: AppText.overline(context)),
            const SizedBox(height: AppSpacing.sm),
            if (view.history.isEmpty)
              Text('No matching payments found.', style: AppText.body(context))
            else
              for (final t in view.history)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${fmt.format(t.date)} · ${t.merchant}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppText.bodySmall(context),
                        ),
                      ),
                      Text(Formatters.currency.format(t.amountMinor),
                          style: AppText.amount(context, size: 13)),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Payments need a biller, reference or category match plus a 2% '
              'amount tolerance inside the due window. A reminder alone never '
              'marks a bill paid.',
              style: AppText.caption(context),
            ),
            if (onHide != null) ...[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onHide,
                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                  label: const Text('Not a bill'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
