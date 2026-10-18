import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/period_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../widgets/animated_amount.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_states.dart';
import '../widgets/budget_gauge.dart';
import '../widgets/category_bubble_cluster.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/pressable.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/section_header.dart';
import '../widgets/sms_import_prompt.dart';
import '../widgets/transaction_tile.dart';
import 'activity_screen.dart';
import 'add_transaction_screen.dart';

/// Bottom gutter for the scrollable dashboard. Clears the floating navigation
/// bar *and* the floating Add button stacked above it, so neither obscures the
/// weekly chart or the last activity row.
const double _scrollBottomInset = AppSpacing.fabClearance;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _didCheckSmsStartDate = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);
    final auth = context.watch<AuthProvider>();

    if (!_didCheckSmsStartDate && !provider.isLoadingCache) {
      _didCheckSmsStartDate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || provider.hasSmsScanStartDate) return;
        SmsImportPrompt.show(context);
      });
    }

    final trackedTransactions = provider.trackedTransactions.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final trackedExpenses = provider.trackedExpenses.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: AppRefreshIndicator(
        onRefresh: () => provider.syncFromSms(),
        child: CustomScrollView(
          slivers: [
            // 1–3: compact greeting, spending period, prominent amount and the
            // transaction-count indicator, all on the navy hero header.
            SliverToBoxAdapter(
              child: _HeroPanel(
                auth: auth,
                provider: provider,
                logCount: trackedTransactions.length,
              ),
            ),
            // 4–7: budget card, actions, category chart, weekly chart and the
            // recent-activity list, each in its own inset, scrollable section.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                _scrollBottomInset,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 4: monthly budget card, clearly separated from the hero.
                  const _BudgetCard(),
                  const SizedBox(height: AppSpacing.xxl),

                  // 5: Add Expense / Add Income, fully below the hero region.
                  const _QuickActions(),
                  const SizedBox(height: AppSpacing.xxxl),

                  // 6: spending by category.
                  const SectionHeader(title: 'Spending by category'),
                  _CategoryCard(expenses: trackedExpenses),
                  const SizedBox(height: AppSpacing.xxxl),

                  // 7: last seven days.
                  const SectionHeader(title: 'Last 7 days'),
                  _DailySpendCard(expenses: trackedExpenses),
                  const SizedBox(height: AppSpacing.xxxl),

                  SectionHeader(
                    title: 'Recent activity',
                    actionLabel: 'View all',
                    actionIcon: Icons.chevron_right_rounded,
                    onAction: () => Navigator.of(context).push(
                      AppPageRoute(builder: (_) => const ActivityScreen()),
                    ),
                  ),
                  if (trackedTransactions.isEmpty && provider.isSyncing)
                    const SkeletonList(count: 4)
                  else if (!provider.hasSmsScanStartDate)
                    AppEmptyState(
                      icon: Icons.sms_rounded,
                      title: 'No transactions yet',
                      message:
                          'Pick an SMS start date and SpendSense will build your transactions automatically.',
                      actionLabel: 'Choose start date',
                      onAction: () => SmsImportPrompt.show(context),
                    )
                  else if (trackedTransactions.isEmpty)
                    AppEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Nothing found',
                      message:
                          'No transactions were detected after your selected SMS start date.',
                      actionLabel: 'Sync now',
                      onAction: () => provider.syncFromSms(),
                    )
                  else
                    ...trackedTransactions
                        .take(20)
                        .map((tx) => TransactionTile(transaction: tx)),
                  if (trackedTransactions.isNotEmpty && provider.isSyncing)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.brandBright),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero panel ───────────────────────────────────────────────────────────────

/// The reference's navy header: a compact identity row, then a centred headline
/// figure with the period label and a transaction-count / trend indicator.
/// The budget card now lives *outside* this header so the two never compete.
class _HeroPanel extends StatelessWidget {
  final AuthProvider auth;
  final TransactionProvider provider;
  final int logCount;

  const _HeroPanel({
    required this.auth,
    required this.provider,
    required this.logCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.xl),
        ),
        // The navy drop-shadow suits the dark theme, but over the pale light
        // background it read as an unintended dark band under the header, so it
        // is applied only in dark mode.
        boxShadow: AppColors.isDark(context)
            ? [
                BoxShadow(
                  color: AppColors.navyDeep.withValues(alpha: 0.28),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.xl),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.cyan.withValues(alpha: 0.30),
                      AppColors.cyan.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _identityRow(context),
                    const SizedBox(height: AppSpacing.lg),
                    _headline(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identityRow(BuildContext context) {
    final name = auth.greetingName;
    final greeting = Formatters.greeting(DateTime.now());
    final greetingLine = name.isEmpty ? greeting : '$greeting, $name';

    return Row(
      children: [
        const AppLogo(size: 30),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greetingLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.onGradient(size: 15, weight: FontWeight.w700),
              ),
              Text(
                '$logCount logs · pull to sync',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.onGradient(
                  size: 11,
                  weight: FontWeight.w500,
                  opacity: 0.72,
                ),
              ),
            ],
          ),
        ),
        const _SyncPill(),
        const SizedBox(width: AppSpacing.sm),
        ProfileAvatar(
          imageBytes: auth.profileImageBytes,
          name: auth.name,
          radius: 18,
        ),
      ],
    );
  }

  Widget _headline(BuildContext context) {
    return Consumer<PeriodProvider>(
      builder: (context, period, _) {
        final cycleExpenses =
            provider.expensesInPeriod(period.currentPeriod).toList();
        final total = cycleExpenses.fold<double>(0, (sum, t) => sum + t.amount);
        final count = cycleExpenses.length;

        final previous = period.previousPeriod;
        final previousTotal = previous == null
            ? null
            : provider
                .expensesInPeriod(previous)
                .fold<double>(0, (sum, t) => sum + t.amount);

        return Column(
          children: [
            Text(
              'SPENT · ${period.periodLabel.toUpperCase()}',
              textAlign: TextAlign.center,
              style: AppText.onGradient(
                size: 10.5,
                weight: FontWeight.w700,
                opacity: 0.7,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedAmount(
                value: total,
                format: (v) => Formatters.currency.format(v),
                style: AppText.hero(context).copyWith(
                  color: Colors.white,
                  fontSize: 44,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _HeroPill(
                    icon: Icons.receipt_long_rounded,
                    label: count == 1 ? '1 transaction' : '$count transactions',
                  ),
                  if (previousTotal != null && previousTotal > 0)
                    _trendPill(total, previousTotal),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Cycle-over-cycle change. Only shown when a comparable previous window
  /// exists, rather than inventing a percentage.
  Widget _trendPill(double current, double previous) {
    final delta = (current - previous) / previous * 100;
    final rising = delta > 0.05;
    final falling = delta < -0.05;

    return _HeroPill(
      icon: rising
          ? Icons.trending_up_rounded
          : falling
              ? Icons.trending_down_rounded
              : Icons.swap_horiz_rounded,
      iconColor: rising
          ? AppColors.amber
          : falling
              ? AppColors.cyan
              : Colors.white,
      label: '${delta.abs() < 0.05 ? '0' : delta.abs().toStringAsFixed(1)}%'
          ' vs last cycle',
    );
  }
}

/// Pill used for the hero's status / count indicators.
class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;

  const _HeroPill({
    required this.icon,
    required this.label,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppText.onGradient(size: 11.5, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The SMS-sync affordance, restyled for the navy hero: shows when the last
/// sync completed and spins while one is running.
class _SyncPill extends StatelessWidget {
  const _SyncPill();

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => SmsImportPrompt.show(context),
      sound: SoundEventType.buttonTap,
      child: Consumer<TransactionProvider>(
        builder: (context, provider, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (provider.isSyncing)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(Icons.sync_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                provider.lastSynced == null
                    ? 'Sync'
                    : DateFormat('hh:mm a').format(provider.lastSynced!),
                style: AppText.onGradient(size: 11, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Budget card ──────────────────────────────────────────────────────────────

/// Monthly budget as its own glass card: the gauge and the remaining figure,
/// with no dependency on the hero's height or position.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Consumer2<TransactionProvider, PeriodProvider>(
        builder: (context, txProvider, period, _) {
          final spent = txProvider
              .expensesInPeriod(period.currentPeriod)
              .fold<double>(0, (sum, t) => sum + t.amount);
          final budget = txProvider.monthlyBudget;
          final remaining = budget - spent;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BudgetGauge(spent: spent, budget: budget, size: 118),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MONTHLY BUDGET',
                      style: AppText.overline(context)
                          .copyWith(letterSpacing: 1.3),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Formatters.currency.format(budget),
                        style: AppText.amount(context, size: 20),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Spent ${Formatters.currency.format(spent)}',
                      style: AppText.label(context).copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      budget <= 0
                          ? 'Set a budget in Settings'
                          : remaining >= 0
                              ? '${Formatters.currency.format(remaining)} left'
                              : '${Formatters.currency.format(-remaining)} over',
                      style: AppText.title(context).copyWith(
                        fontSize: 13,
                        color: budget <= 0
                            ? AppColors.textTertiary(context)
                            : remaining >= 0
                                ? AppColors.incomeGreen
                                : AppColors.expenseRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Quick actions ────────────────────────────────────────────────────────────

/// The reference's Deposit / Withdraw pair, mapped to what SpendSense actually
/// supports: logging money in, and logging money out. Laid out in normal flow
/// below the hero so the pills are never covered by the header.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionPill(
            label: 'Add expense',
            icon: Icons.trending_down_rounded,
            tint: AppColors.expenseRed,
            onTap: () => _open(context, TransactionType.expense),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _ActionPill(
            label: 'Add income',
            icon: Icons.trending_up_rounded,
            tint: AppColors.incomeGreen,
            onTap: () => _open(context, TransactionType.income),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, TransactionType type) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => AddTransactionScreen(initialType: type),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  const _ActionPill({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      sound: SoundEventType.buttonTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: tint),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title(context).copyWith(fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Category card ────────────────────────────────────────────────────────────

/// Spending by category, presented on the same brand-gradient card as the rest
/// of the dashboard's prominent surfaces so it reads as one family rather than a
/// pale outlier. Falls back to a described empty state instead of a bare line.
class _CategoryCard extends StatelessWidget {
  final List<TransactionModel> expenses;

  const _CategoryCard({required this.expenses});

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final t in expenses) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    final hasSpending = totals.values.any((v) => v > 0);

    return GradientHeroCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: hasSpending
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CategoryBubbleCluster(totals: totals, onGradient: true),
                const SizedBox(height: AppSpacing.lg),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
                const SizedBox(height: AppSpacing.md),
                _TopCategories(totals: totals),
              ],
            )
          : const _CategoryEmptyState(),
    );
  }
}

/// Empty state for the category breakdown: says what will appear and offers the
/// one action that produces it.
class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: const Icon(
            Icons.donut_large_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'No spending to break down yet',
          textAlign: TextAlign.center,
          style: AppText.onGradient(size: 16, weight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Log an expense — or set an SMS start date — and SpendSense will sort '
          'it into categories automatically.',
          textAlign: TextAlign.center,
          style: AppText.onGradient(size: 12.5, opacity: 0.85, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.lg),
        Pressable(
          onTap: () => Navigator.of(context).push(
            AppPageRoute(
              builder: (_) => const AddTransactionScreen(
                  initialType: TransactionType.expense),
            ),
          ),
          sound: SoundEventType.buttonTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 18, color: AppColors.brand),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Add expense',
                  style: AppText.title(context)
                      .copyWith(fontSize: 13.5, color: AppColors.brand),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Exact rupee figures for the leading categories — the bubbles convey share,
/// but a bubble alone cannot be read for an amount.
class _TopCategories extends StatelessWidget {
  final Map<String, double> totals;

  const _TopCategories({required this.totals});

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: entries
          .take(3)
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(CategoryStyle.icon(e.key),
                      size: 15, color: CategoryStyle.color(e.key)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      e.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.onGradient(
                          size: 12.5, weight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    Formatters.currency.format(e.value),
                    style:
                        AppText.onGradient(size: 13, weight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Daily spend ──────────────────────────────────────────────────────────────

class _DailySpendCard extends StatelessWidget {
  final List<TransactionModel> expenses;

  const _DailySpendCard({required this.expenses});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i));
      final total = expenses
          .where((t) =>
              t.date.year == day.year &&
              t.date.month == day.month &&
              t.date.day == day.day)
          .fold<double>(0, (s, t) => s + t.amount);
      return _DayBar(day: day, amount: total);
    });

    final todayTotal = days.last.amount;
    final maxAmount =
        days.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    final barMax = maxAmount <= 0 ? 100.0 : maxAmount * 1.25;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Today', style: AppText.label(context)),
              const Spacer(),
              // Counts with the bars below it, so the figure and the chart reach
              // the same value together instead of the number snapping ahead.
              AnimatedAmount(
                value: todayTotal,
                format: (v) => Formatters.currency.format(v),
                style: AppText.amount(context, size: 18),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 104,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.respect(context, AppMotion.chart),
              curve: AppMotion.emphasized,
              builder: (context, t, _) => BarChart(
                BarChartData(
                  maxY: barMax,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= days.length) {
                            return const SizedBox.shrink();
                          }
                          final isToday = i == days.length - 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('EEEEE')
                                  .format(days[i].day)
                                  .substring(0, 1),
                              style: AppText.label(context).copyWith(
                                fontSize: 10,
                                color: isToday
                                    ? AppColors.brandBright
                                    : AppColors.textTertiary(context),
                                fontWeight:
                                    isToday ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: AppColors.navyDeep,
                      getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                        '${DateFormat('d MMM').format(days[group.x].day)}\n'
                        '${Formatters.currency.format(rod.toY)}',
                        AppText.onGradient(size: 11, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                  barGroups: days.asMap().entries.map((e) {
                    final isToday = e.key == days.length - 1;
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.amount * t,
                          width: 15,
                          borderRadius: BorderRadius.circular(7),
                          gradient: isToday
                              ? AppColors.electricGradient
                              : LinearGradient(
                                  colors: [
                                    AppColors.azure.withValues(alpha: 0.38),
                                    AppColors.azure.withValues(alpha: 0.16),
                                  ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayBar {
  final DateTime day;
  final double amount;
  const _DayBar({required this.day, required this.amount});
}
