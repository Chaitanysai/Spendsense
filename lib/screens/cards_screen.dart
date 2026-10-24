import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/period_provider.dart';
import '../providers/transaction_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/formatters.dart';
import '../widgets/animated_progress_bar.dart';
import '../widgets/app_states.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/pressable.dart';
import '../widgets/section_header.dart';

/// Payment-instrument roll-ups.
///
/// SpendSense has no card or bank integration, so this screen deliberately
/// reports only what the SMS parser and manual entries already record per
/// transaction: the payment method, the issuing bank, and the account. Nothing
/// here is a live balance and the screen says so.
class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final period = context.watch<PeriodProvider>().currentPeriod;
    final tracked = provider.trackedTransactions.toList();

    if (tracked.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: AppEmptyState(
              icon: Icons.credit_card_off_rounded,
              title: 'No instruments yet',
              message:
                  'Once SpendSense has parsed some transactions, this screen '
                  'groups your spending by payment method, bank and account.',
            ),
          ),
        ),
      );
    }

    // Canonical scope: the same rows and the same filter Home's cycle card
    // uses, so "Total spend" here reconciles with Home by construction rather
    // than by coincidence. See [TransactionProvider.spendingStatsForPeriod].
    final byMethod =
        provider.spendingStatsForPeriod(period, (t) => t.paymentMethod);
    final byBank = provider.spendingStatsForPeriod(period, (t) => t.bank);
    final byAccount = provider.spendingStatsForPeriod(period, (t) => t.account);
    final totalSpent = provider.spendingTotalForPeriod(period);
    final expenseCount = provider.expensesInPeriod(period).length;
    final periodLabel = _periodLabel(period);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
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
                    Text('Payment instruments', style: AppText.h1(context)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Where your money moved, grouped by how you paid',
                      style: AppText.body(context),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _HeroSummary(
                      totalSpent: totalSpent,
                      methodCount: byMethod.length,
                      transactionCount: expenseCount,
                      periodLabel: periodLabel,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xxl,
              AppSpacing.page,
              AppSpacing.tabBottomInset(context),
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (totalSpent == 0)
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No spending in this period',
                            style: AppText.title(context)),
                        const SizedBox(height: 4),
                        Text(
                          'Transactions outside $periodLabel are not included. '
                          'Switch the period in Settings to see another cycle.',
                          style: AppText.body(context),
                        ),
                      ],
                    ),
                  )
                else ...[
                  const SectionHeader(title: 'By payment method'),
                  _InstrumentCard(
                      stats: byMethod, kind: _InstrumentKind.method),
                  const SizedBox(height: AppSpacing.xxl),
                  const SectionHeader(title: 'By bank'),
                  _InstrumentCard(stats: byBank, kind: _InstrumentKind.bank),
                  const SizedBox(height: AppSpacing.xxl),
                  const SectionHeader(title: 'By account'),
                  _InstrumentCard(
                      stats: byAccount, kind: _InstrumentKind.account),
                ],
                const SizedBox(height: AppSpacing.xxl),
                const _SourceNote(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// "1 Oct – 31 Oct" — the exact window every figure on this screen covers.
  static String _periodLabel(DateTimeRange period) {
    final fmt = DateFormat('d MMM');
    return '${fmt.format(period.start)} – ${fmt.format(period.end)}';
  }
}

enum _InstrumentKind { method, bank, account }

class _HeroSummary extends StatelessWidget {
  final int totalSpent;
  final int methodCount;
  final int transactionCount;
  final String periodLabel;

  const _HeroSummary({
    required this.totalSpent,
    required this.methodCount,
    required this.transactionCount,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GradientHeroCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      gradient: AppColors.heroSurfaceGradient(context),
      glow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL SPEND · ${periodLabel.toUpperCase()}',
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
              Formatters.currency.format(totalSpent),
              maxLines: 1,
              style: AppText.onGradient(size: 34, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: methodCount == 1
                      ? 'payment method'
                      : '$methodCount payment methods',
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: _HeroStat(label: '$transactionCount transactions'),
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

class _InstrumentCard extends StatelessWidget {
  final Map<String, InstrumentStat> stats;
  final _InstrumentKind kind;

  const _InstrumentCard({required this.stats, required this.kind});

  @override
  Widget build(BuildContext context) {
    final entries = stats.entries.toList()
      ..sort((a, b) => b.value.spent.compareTo(a.value.spent));

    final grandTotal = entries.fold<int>(0, (s, e) => s + e.value.spent);

    if (entries.isEmpty) {
      return GlassCard(
        child: Text('Nothing recorded yet.', style: AppText.body(context)),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(color: AppColors.border(context), height: AppSpacing.xxl),
            _InstrumentRow(
              name: entries[i].key,
              icon: _iconFor(entries[i].key, kind),
              color: AppColors.chartPalette[i % AppColors.chartPalette.length],
              stat: entries[i].value,
              share: grandTotal > 0 ? entries[i].value.spent / grandTotal : 0,
              index: i,
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(String name, _InstrumentKind kind) {
    final n = name.toLowerCase();
    switch (kind) {
      case _InstrumentKind.method:
        if (n.contains('upi')) return Icons.qr_code_rounded;
        if (n.contains('card') || n.contains('credit')) {
          return Icons.credit_card_rounded;
        }
        if (n.contains('wallet')) return Icons.account_balance_wallet_rounded;
        if (n.contains('net') || n.contains('bank')) {
          return Icons.account_balance_rounded;
        }
        if (n.contains('cash')) return Icons.payments_rounded;
        return Icons.swap_horiz_rounded;
      case _InstrumentKind.bank:
        return Icons.account_balance_rounded;
      case _InstrumentKind.account:
        return Icons.credit_card_rounded;
    }
  }
}

class _InstrumentRow extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final InstrumentStat stat;
  final double share;
  final int index;

  const _InstrumentRow({
    required this.name,
    required this.icon,
    required this.color,
    required this.stat,
    required this.share,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title(context).copyWith(fontSize: 14),
              ),
              const SizedBox(height: 3),
              Text(
                '${stat.count} transaction${stat.count == 1 ? '' : 's'}'
                '${stat.received > 0 ? ' · ${Formatters.currency.format(stat.received)} in' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(context).copyWith(fontSize: 11),
              ),
              const SizedBox(height: 6),
              AnimatedProgressBar(
                fraction: share,
                height: 4,
                color: color,
                trackColor: AppColors.surfaceAlt(context),
                delay: Duration(milliseconds: 30 * (index.clamp(0, 8))),
                semanticLabel: '$name share of spending',
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Formatters.currency.format(stat.spent),
              style: AppText.amount(context, size: 14),
            ),
            const SizedBox(height: 3),
            Text(
              '${(share * 100).toStringAsFixed(1)}%',
              style: AppText.label(context).copyWith(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// States the provenance of these figures so the screen cannot be misread as a
/// bank feed.
class _SourceNote extends StatelessWidget {
  const _SourceNote();

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 17, color: AppColors.textSecondary(context)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'These totals are derived from transactions SpendSense parsed '
                'from your SMS inbox and entries you added manually. SpendSense '
                'does not connect to any bank, card network or UPI directory, so '
                'nothing here is a live balance.',
                style: AppText.body(context).copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
