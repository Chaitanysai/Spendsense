import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_tile.dart';
import '../utils/app_colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/profile_avatar.dart';
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
    final dateLabel =
        DateFormat('EEEE, d MMMM').format(now); // e.g. "Wednesday, 8 April"
    final logCount = trackedTransactions.length;

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      body: RefreshIndicator(
        color: AppColors.primaryTeal,
        onRefresh: () => provider.syncFromSms(),
        child: CustomScrollView(
          slivers: [
            // ── Top app-bar ────────────────────────────────────────────────
            SliverAppBar(
              pinned: false,
              floating: true,
              backgroundColor: AppColors.scaffold(context),
              elevation: 0,
              leadingWidth: 0,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  const AppLogo(size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        Text(
                          '$logCount LOGS TODAY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary(context),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Streak / sync pill
                  Consumer<TransactionProvider>(
                    builder: (_, txProvider, __) {
                      return GestureDetector(
                        onTap: () => SmsImportPrompt.show(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceColor(context),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadow(context),
                                blurRadius: 8,
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.sync_rounded,
                                  size: 14,
                                  color: AppColors.primaryTeal),
                              const SizedBox(width: 4),
                              Text(
                                txProvider.lastSynced == null
                                    ? 'Sync'
                                    : DateFormat('hh:mm a')
                                        .format(txProvider.lastSynced!),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // Add button
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.add,
                        color: AppColors.scaffold(context), size: 20),
                  ),
                  const SizedBox(width: 6),
                  ProfileAvatar(
                    imageBytes: auth.profileImageBytes,
                    name: auth.name,
                    radius: 17,
                  ),
                ],
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Budget gauge ─────────────────────────────────────────
                  SummaryCard(
                    total: provider.totalTrackedExpenses,
                    count: trackedExpenses.length,
                    topCat: provider.topTrackedCategory,
                  ),

                  const SizedBox(height: 20),

                  // ── Category breakdown card ───────────────────────────────
                  _CategoryBreakdownCard(expenses: trackedExpenses),

                  const SizedBox(height: 14),

                  // ── Daily spend bar ───────────────────────────────────────
                  _DailySpendCard(expenses: trackedExpenses),

                  const SizedBox(height: 20),

                  // ── Recent transactions header ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Today logs',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      Text(
                        '${trackedTransactions.length} items',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Transaction list ──────────────────────────────────────
                  if (provider.isSyncing)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ))
                  else if (!provider.hasSmsScanStartDate)
                    _emptyMsg(context,
                        'Pick an SMS start date to begin scanning your messages.')
                  else if (trackedTransactions.isEmpty)
                    _emptyMsg(context,
                        'No transactions found after your selected SMS start date.')
                  else
                    ...trackedTransactions
                        .take(20)
                        .map((tx) => TransactionTile(transaction: tx)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyMsg(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary(context)),
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

    final grandTotal =
        totals.values.fold<double>(0, (s, v) => s + v);

    final colors = [
      AppColors.primaryTeal,
      AppColors.accentBlue,
      AppColors.accentOrange,
      AppColors.primaryGreen,
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
    ];

    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top3 = entries.take(3).toList();

    final sections = entries.isEmpty
        ? [
            PieChartSectionData(
              color: Colors.grey[300]!,
              value: 100,
              radius: 22,
              showTitle: false,
            )
          ]
        : entries.asMap().entries.map((e) {
            return PieChartSectionData(
              color: colors[e.key % colors.length],
              value: grandTotal > 0 ? e.value.value / grandTotal * 100 : 0,
              radius: 22,
              showTitle: false,
            );
          }).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryTeal,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Category Breakdown',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: AppColors.textSecondary(context)),
            ],
          ),
          const SizedBox(height: 16),

          // Donut + stats
          Row(
            children: [
              // Top-3 category amounts
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: top3.isEmpty
                      ? [
                          Text('No data',
                              style: TextStyle(
                                  color: AppColors.textSecondary(context)))
                        ]
                      : top3.asMap().entries.map((e) {
                          final pct = grandTotal > 0
                              ? (e.value.value / grandTotal * 100)
                                  .toStringAsFixed(0)
                              : '0';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.value.key,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '₹${e.value.value.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        colors[e.key % colors.length],
                                  ),
                                ),
                                Text(
                                  '$pct%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary(context),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                ),
              ),

              // Donut chart
              SizedBox(
                width: 100,
                height: 100,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 28,
                    sections: sections,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Daily Spend bar card (replaces "Active Calories") ────────────────────────

class _DailySpendCard extends StatelessWidget {
  final List<TransactionModel> expenses;

  const _DailySpendCard({required this.expenses});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Build 7-day totals
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
    final barMax = max <= 0 ? 100.0 : max * 1.3;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentOrange,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Daily Spend',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: AppColors.textSecondary(context)),
            ],
          ),
          const SizedBox(height: 14),

          // Mini bar chart row
          SizedBox(
            height: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: BarChart(
                    BarChartData(
                      maxY: barMax,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      barGroups: dailyTotals.asMap().entries.map((e) {
                        final isToday = e.key == 6;
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.amount,
                              width: 12,
                              borderRadius: BorderRadius.circular(4),
                              color: isToday
                                  ? AppColors.accentOrange
                                  : AppColors.accentOrange
                                      .withValues(alpha: 0.25),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded,
                        color: AppColors.accentOrange, size: 16),
                    const SizedBox(width: 3),
                    Text(
                      '₹${todayTotal.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ],
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
