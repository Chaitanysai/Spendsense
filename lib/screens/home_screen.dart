import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/period_provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_tile.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_logo.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import '../widgets/app_states.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/sms_import_prompt.dart';

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

    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE, d MMMM').format(now);
    final logCount = trackedTransactions.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppRefreshIndicator(
        onRefresh: () => provider.syncFromSms(),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: false,
              floating: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leadingWidth: 0,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  const AppLogo(size: 30),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateLabel, style: AppText.title(context)),
                        Text(
                          '$logCount logs · pull to sync',
                          style: AppText.overline(context),
                        ),
                      ],
                    ),
                  ),
                  Consumer<TransactionProvider>(
                    builder: (_, txProvider, __) {
                      return GestureDetector(
                        onTap: () => SmsImportPrompt.show(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.crimson.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Row(
                            children: [
                              if (txProvider.isSyncing)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.crimson,
                                  ),
                                )
                              else
                                const Icon(Icons.sync_rounded,
                                    size: 14, color: AppColors.crimson),
                              const SizedBox(width: 4),
                              Text(
                                txProvider.lastSynced == null
                                    ? 'Sync'
                                    : DateFormat('hh:mm a')
                                        .format(txProvider.lastSynced!),
                                style: AppText.label(context).copyWith(
                                  fontSize: 11,
                                  color: AppColors.crimson,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ProfileAvatar(
                    imageBytes: auth.profileImageBytes,
                    name: auth.name,
                    radius: 18,
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                4,
                AppSpacing.page,
                AppSpacing.navClearance,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Next salary banner (glass) ──────────────────────────
                  Consumer<PeriodProvider>(
                    builder: (context, periodProvider, child) {
                      if (periodProvider.mode == PeriodMode.custom) {
                        return const SizedBox.shrink();
                      }
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final nextSalaryDate =
                          PeriodProvider.nextSalaryDate(now: today);
                      final daysLeft = nextSalaryDate.difference(today).inDays;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.amber.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_rounded,
                                  color: Color(0xFFB87A00),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text('Next salary drops',
                                    style: AppText.title(context)
                                        .copyWith(fontSize: 14)),
                              ),
                              Text(
                                daysLeft <= 0
                                    ? 'Today'
                                    : daysLeft == 1
                                        ? 'Tomorrow'
                                        : 'in $daysLeft days',
                                style: AppText.amount(context,
                                    size: 14, color: AppColors.crimson),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // ── Hero summary ────────────────────────────────────────
                  Consumer<PeriodProvider>(
                    builder: (context, periodProvider, child) {
                      final cycleExpenses = provider
                          .expensesInPeriod(periodProvider.currentPeriod)
                          .toList();
                      final total = cycleExpenses.fold<double>(
                        0,
                        (sum, transaction) => sum + transaction.amount,
                      );
                      final categories = <String, double>{};
                      for (final transaction in cycleExpenses) {
                        categories[transaction.category] =
                            (categories[transaction.category] ?? 0) +
                                transaction.amount;
                      }
                      final topCategory = categories.isEmpty
                          ? 'None'
                          : categories.entries
                              .reduce((a, b) => a.value > b.value ? a : b)
                              .key;
                      return FadeSlideIn(
                        child: SummaryCard(
                          total: total,
                          count: cycleExpenses.length,
                          topCat: topCategory,
                          budget: provider.monthlyBudget,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // ── Category breakdown ──────────────────────────────────
                  const SectionHeader(title: 'Spending by category'),
                  _CategoryBreakdownCard(expenses: trackedExpenses),

                  const SizedBox(height: AppSpacing.xxl),

                  // ── Daily spend ────────────────────────────────────────
                  const SectionHeader(title: 'Last 7 days'),
                  _DailySpendCard(expenses: trackedExpenses),

                  const SizedBox(height: AppSpacing.xxl),

                  // ── Recent activity ────────────────────────────────────
                  SectionHeader(
                    title: 'Recent activity',
                    actionLabel: '${trackedTransactions.length} total',
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
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.sm),
                      child: Center(
                        child:
                            CircularProgressIndicator(color: AppColors.crimson),
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

// ── Category Breakdown card ──────────────────────────────────────────────────

class _CategoryBreakdownCard extends StatelessWidget {
  final List<TransactionModel> expenses;

  const _CategoryBreakdownCard({required this.expenses});

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final t in expenses) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    final grandTotal = totals.values.fold<double>(0, (s, v) => s + v);
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(4).toList();

    final sections = entries.isEmpty
        ? [
            PieChartSectionData(
              color: AppColors.surfaceAlt(context),
              value: 100,
              radius: 16,
              showTitle: false,
            )
          ]
        : entries.asMap().entries.map((e) {
            return PieChartSectionData(
              color:
                  AppColors.chartPalette[e.key % AppColors.chartPalette.length],
              value: grandTotal > 0 ? e.value.value / grandTotal * 100 : 0,
              radius: 16,
              showTitle: false,
            );
          }).toList();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 116,
                height: 116,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: AppMotion.respect(context, AppMotion.chart),
                      curve: AppMotion.emphasized,
                      builder: (context, t, _) {
                        final animated = sections
                            .map((s) => PieChartSectionData(
                                  color: s.color,
                                  value: s.value * t,
                                  radius: s.radius,
                                  showTitle: s.showTitle,
                                ))
                            .toList();
                        return PieChart(
                          PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 40,
                            startDegreeOffset: -90,
                            sections: animated,
                          ),
                        );
                      },
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _compact(grandTotal),
                          style: AppText.amount(context, size: 16),
                        ),
                        Text('total',
                            style:
                                AppText.label(context).copyWith(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: top.isEmpty
                    ? Text('No spending data yet', style: AppText.body(context))
                    : Column(
                        children: top.map((e) {
                          final pct = grandTotal > 0
                              ? (e.value / grandTotal * 100)
                              : 0.0;
                          final color = AppColors.chartPalette[
                              entries.indexOf(e) %
                                  AppColors.chartPalette.length];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.label(context)
                                        .copyWith(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  '₹${_compact(e.value)}',
                                  style: AppText.amount(context, size: 12),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '${pct.toStringAsFixed(0)}%',
                                    textAlign: TextAlign.right,
                                    style: AppText.label(context)
                                        .copyWith(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _compact(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

// ── Daily Spend bar card ─────────────────────────────────────────────────────

class _DailySpendCard extends StatelessWidget {
  final List<TransactionModel> expenses;

  const _DailySpendCard({required this.expenses});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dailyTotals = List.generate(7, (i) {
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

    final todayTotal = dailyTotals.last.amount;
    final max = dailyTotals
        .map((d) => d.amount)
        .fold<double>(0, (m, v) => v > m ? v : m);
    final barMax = max <= 0 ? 100.0 : max * 1.25;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Today',
                  style: AppText.label(context).copyWith(fontSize: 12)),
              const Spacer(),
              Text(
                '₹${todayTotal.toStringAsFixed(0)}',
                style:
                    AppText.amount(context, size: 18, color: AppColors.crimson),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 92,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.respect(context, AppMotion.chart),
              curve: AppMotion.emphasized,
              builder: (context, t, _) {
                return BarChart(
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
                            if (i < 0 || i >= dailyTotals.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                DateFormat('E')
                                    .format(dailyTotals[i].day)
                                    .substring(0, 1),
                                style: AppText.label(context)
                                    .copyWith(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: dailyTotals.asMap().entries.map((e) {
                      final isToday = e.key == 6;
                      return BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: e.value.amount * t,
                            width: 14,
                            borderRadius: BorderRadius.circular(6),
                            gradient: isToday
                                ? AppColors.flameGradient
                                : LinearGradient(
                                    colors: [
                                      AppColors.orange.withValues(alpha: 0.35),
                                      AppColors.orange.withValues(alpha: 0.18),
                                    ],
                                  ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
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
