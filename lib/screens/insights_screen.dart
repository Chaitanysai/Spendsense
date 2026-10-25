import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/formatters.dart';
import '../utils/period_math.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_page_route.dart';
import '../widgets/category_bubble.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/glass_card.dart';
import '../widgets/insight_cards.dart';
import 'assistant_screen.dart';
import 'summary_screen.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    // The shell keeps this tab mounted, so it no longer rebuilds on every visit.
    // The month totals below are derived from DateTime.now(), so subscribe to
    // the tab's ticker state: the screen rebuilds when the tab is shown again
    // and cannot display a stale month after the clock rolled over.
    TickerMode.valuesOf(context);
    final metrics = _buildMetrics(provider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.tabBottomInset(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const [AppLogo(size: 34, showWordmark: true)]),
              const SizedBox(height: AppSpacing.xl),
              Text('Insights', style: AppText.h1(context)),
              const SizedBox(height: 4),
              Text('Understand your spending at a glance',
                  style: AppText.body(context)),
              const SizedBox(height: AppSpacing.xl),

              // â”€â”€ Stat cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              SizedBox(
                height: 168,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  children: [
                    FadeSlideIn(
                      index: 0,
                      child: _statCard(
                        context,
                        title: 'This month',
                        value: Formatters.currency.format(metrics.currentTotal),
                        subtitle:
                            DateFormat('MMMM yyyy').format(DateTime.now()),
                        gradient: AppColors.heroSurfaceGradient(context),
                        icon: Icons.calendar_month_rounded,
                      ),
                    ),
                    FadeSlideIn(
                      index: 1,
                      child: _statCard(
                        context,
                        title: 'Change',
                        // With no comparable previous month there is no delta to
                        // report, so show a neutral placeholder rather than a
                        // misleading "0.0% up".
                        value: metrics.hasPreviousMonth
                            ? '${metrics.percentChange.toStringAsFixed(1)}%'
                            : 'â€”',
                        subtitle: !metrics.hasPreviousMonth
                            ? 'No prior month data'
                            : metrics.percentChange > 0
                                ? 'Up vs last month'
                                : metrics.percentChange < 0
                                    ? 'Down vs last month'
                                    : 'Same as last month',
                        gradient: metrics.hasPreviousMonth &&
                                metrics.percentChange < 0
                            ? AppColors.successGradient
                            : AppColors.heroSurfaceGradient(context),
                        glowColor: metrics.hasPreviousMonth &&
                                metrics.percentChange < 0
                            ? AppColors.incomeGreen
                            : null,
                        icon: !metrics.hasPreviousMonth
                            ? Icons.timeline_rounded
                            : metrics.percentChange >= 0
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                      ),
                    ),
                    FadeSlideIn(
                      index: 2,
                      child: _statCard(
                        context,
                        title: 'Top category',
                        value: metrics.topCategory,
                        subtitle: 'Highest spend this month',
                        gradient: AppColors.heroGradient,
                        glowColor: AppColors.brand,
                        icon: Icons.auto_awesome_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(
                index: 3,
                child: _buildCategoryBubbles(context, metrics),
              ),
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(
                index: 4,
                child: InsightComparisons(transactions: provider.transactions),
              ),
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(
                index: 5,
                child: GlassCard(
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute(builder: (_) => const SummaryScreen()),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.summarize_rounded,
                          color: AppColors.brandInk(context)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text('Financial summary',
                            style: AppText.title(context)),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: AppColors.textTertiary(context)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(index: 6, child: _buildSmartTip(context, metrics)),
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(
                index: 7,
                child: _buildAssistantLauncherCard(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _InsightMetrics _buildMetrics(TransactionProvider provider) {
    // Calendar-month reporting, deliberately separate from the salary cycle.
    // Both months are derived from ONE captured "now" so the pair can never
    // straddle a midnight rollover, and membership is decided on the LOCAL
    // calendar day.
    final now = DateTime.now();
    final thisMonth = PeriodMath.calendarMonth(now);
    final lastMonth =
        PeriodMath.calendarMonth(DateTime(now.year, now.month - 1));

    bool inMonth(TransactionModel t, DateTimeRange month) =>
        !t.isExcluded &&
        t.type == TransactionType.expense &&
        PeriodMath.containsLocalDate(month, t.date);

    final currentMonthTx =
        provider.transactions.where((t) => inMonth(t, thisMonth)).toList();
    final lastMonthTx =
        provider.transactions.where((t) => inMonth(t, lastMonth)).toList();

    final currentTotal =
        currentMonthTx.fold<int>(0, (sum, t) => sum + t.amountMinor);
    final lastTotal = lastMonthTx.fold<int>(0, (sum, t) => sum + t.amountMinor);

    double percentChange = 0;
    if (lastTotal > 0) {
      percentChange = (currentTotal - lastTotal) * 100.0 / lastTotal;
    }

    final categoryMap = <String, int>{};
    for (final t in currentMonthTx) {
      categoryMap[t.category] = (categoryMap[t.category] ?? 0) + t.amountMinor;
    }

    final sortedCategories = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topCategory =
        sortedCategories.isEmpty ? 'No data' : sortedCategories.first.key;

    return _InsightMetrics(
      currentTotal: currentTotal,
      percentChange: percentChange,
      hasPreviousMonth: lastTotal > 0,
      topCategory: topCategory,
      totalCategories: currentTotal,
      categories: sortedCategories.take(6).toList(),
    );
  }

  Widget _statCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required Gradient gradient,
    required IconData icon,
    Color? glowColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: SizedBox(
        width: 220,
        child: GradientHeroCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          gradient: gradient,
          glowColor: glowColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(title,
                      style: AppText.onGradient(
                          size: 12, weight: FontWeight.w600, opacity: 0.9)),
                  const Spacer(),
                  Icon(icon,
                      color: Colors.white.withValues(alpha: 0.9), size: 20),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    maxLines: 1,
                    style:
                        AppText.onGradient(size: 28, weight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.onGradient(
                      size: 11, weight: FontWeight.w500, opacity: 0.9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBubbles(BuildContext context, _InsightMetrics metrics) {
    final total = metrics.totalCategories;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Top categories',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(context)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('THIS MONTH', style: AppText.overline(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (metrics.categories.isEmpty)
            Text('No spending data yet this month.',
                style: AppText.body(context))
          else
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: metrics.categories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.lg),
                itemBuilder: (context, i) {
                  final entry = metrics.categories[i];
                  final pct = total > 0 ? entry.value / total * 100 : 0.0;
                  return SizedBox(
                    width: 64,
                    child: CategoryBubble(
                      category: entry.key,
                      size: 52,
                      label: entry.key,
                      percentLabel: '${pct.toStringAsFixed(0)}%',
                      highlighted: i == 0,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAssistantLauncherCard(BuildContext context) {
    return GradientHeroCard(
      onTap: () => _openAssistant(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.smart_toy_rounded, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('Tap to open',
                    style:
                        AppText.onGradient(size: 11, weight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Ask SpendSense AI',
              style: AppText.onGradient(size: 24, weight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.sm),
          // `height: 1.4` was the clipping cause: a 1.4x line box over two
          // lines needs 2.8 * fontSize of vertical space, which overran the
          // card's 2-line budget and cut the third line mid-glyph instead of
          // drawing an ellipsis. Dropping `height` (the font's natural metrics
          // fit two lines) keeps the type size and weight intact and lets
          // `maxLines: 2` ellipsize as intended for any future longer copy.
          Text(
            'Ask about transactions, preview exclusions, or undo a change — '
            'calculated on-device, with optional Gemini assistance.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.onGradient(size: 13, opacity: 0.9),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartTip(BuildContext context, _InsightMetrics metrics) {
    String tip = 'Spending is steady. Ask the bot what drove the month.';

    if (metrics.currentTotal > 10000) {
      tip =
          'High spending detected. Ask the bot for top merchants and trim ideas.';
    } else if (metrics.percentChange > 20) {
      tip =
          'This month jumped sharply. A follow-up about categories will help.';
    } else if (metrics.percentChange < -10) {
      tip = 'You are spending less than last month. Ask what improved most.';
    }

    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.amberGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                const Icon(Icons.lightbulb_rounded, color: Color(0xFF5A3B00)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Smart tip', style: AppText.title(context)),
                const SizedBox(height: 6),
                Text(tip, style: AppText.body(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAssistant(BuildContext context) {
    AppPageRoute.pushOnce(
      context,
      name: AssistantScreen.routeName,
      builder: (_) => const AssistantScreen(),
    );
  }
}

class _InsightMetrics {
  final int currentTotal;
  final double percentChange;
  final bool hasPreviousMonth;
  final String topCategory;
  final int totalCategories;
  final List<MapEntry<String, int>> categories;

  const _InsightMetrics({
    required this.currentTotal,
    required this.percentChange,
    required this.hasPreviousMonth,
    required this.topCategory,
    required this.totalCategories,
    required this.categories,
  });
}
