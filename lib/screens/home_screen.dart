import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/period_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/budget_math.dart';
import '../utils/category_style.dart';
import '../utils/dashboard_sections.dart';
import '../utils/formatters.dart';
import '../utils/period_math.dart';
import '../widgets/animated_amount.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_states.dart';
import '../widgets/budget_gauge.dart';
import '../widgets/category_bubble_cluster.dart';
import '../widgets/glass_card.dart';
import '../widgets/pressable.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/quick_action_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/sms_import_prompt.dart';
import '../widgets/transaction_tile.dart';
import 'activity_screen.dart';
import 'add_transaction_screen.dart';
import 'budgets_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _didCheckSmsStartDate = false;

  /// Whether the Home tab was visible at the last dependency change. The shell
  /// keeps this screen alive across tab switches, so it is no longer rebuilt on
  /// every visit. The start-date check used to run on each return as a side
  /// effect of that rebuild, so it is re-armed here when the tab reappears.
  bool _tabActive = true;

  /// Local privacy toggle for the headline figure. Deliberately not persisted:
  /// it is a "hide it while someone is looking" affordance, not a preference.
  bool _balanceVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    // This runs just before build in the same frame, so build picks up the
    // re-armed check immediately.
    if (active && !_tabActive) _didCheckSmsStartDate = false;
    _tabActive = active;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);
    final auth = context.watch<AuthProvider>();

    if (!_didCheckSmsStartDate &&
        !provider.isLoadingCache &&
        !provider.hasLedgerInitError) {
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

    // Section visibility is a display preference only. Absent provider (e.g.
    // an embedded preview) means "show everything".
    final prefs = context.watch<ThemeProvider?>();
    bool show(String id) => prefs?.isSectionVisible(id) ?? true;
    // Clears the floating navigation bar *and* the Add button stacked above
    // it, using the bar's real height rather than a fixed guess.
    final scrollBottomInset = AppSpacing.tabBottomInset(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: AppRefreshIndicator(
        onRefresh: () => provider.syncFromSms(userInitiated: true),
        child: CustomScrollView(
          slivers: [
            // Greeting row + balance card. The balance card is the single
            // saturated surface on the screen; everything below it is a calm
            // white/near-black card.
            SliverToBoxAdapter(
              child: _HeaderSection(
                auth: auth,
                provider: provider,
                balanceVisible: _balanceVisible,
                onToggleBalance: () =>
                    setState(() => _balanceVisible = !_balanceVisible),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                scrollBottomInset,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const _QuickActions(),
                  const SizedBox(height: AppSpacing.xxl),
                  if (show(DashboardSection.budget)) ...[
                    SectionHeader(
                      title: 'Monthly budget',
                      actionLabel: 'Manage',
                      actionIcon: Icons.chevron_right_rounded,
                      onAction: () => Navigator.of(context).push(
                        AppPageRoute(builder: (_) => const BudgetsScreen()),
                      ),
                    ),
                    const _BudgetCard(),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                  if (show(DashboardSection.categories)) ...[
                    const SectionHeader(title: 'Spending by category'),
                    _CategoryCard(expenses: trackedExpenses),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                  if (show(DashboardSection.weekly)) ...[
                    const SectionHeader(title: 'Last 7 days'),
                    _DailySpendCard(expenses: trackedExpenses),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                  if (show(DashboardSection.recent)) ...[
                    SectionHeader(
                      title: 'Recent transactions',
                      actionLabel: 'See all',
                      actionIcon: Icons.chevron_right_rounded,
                      onAction: () => Navigator.of(context).push(
                        AppPageRoute(builder: (_) => const ActivityScreen()),
                      ),
                    ),
                    ..._recentSection(context, provider, trackedTransactions),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _recentSection(
    BuildContext context,
    TransactionProvider provider,
    List<TransactionModel> trackedTransactions,
  ) {
    return [
      // A ledger that failed closed must never look like a successfully loaded
      // empty ledger — this branch is what makes the two states
      // distinguishable.
      if (provider.hasLedgerInitError)
        AppEmptyState(
          icon: Icons.gpp_maybe_rounded,
          title: "Couldn't load your ledger",
          message: 'Your transactions are still saved and encrypted on '
              'this device, but the ledger could not be read '
              '(${provider.ledgerInitError.runtimeType}). '
              'Nothing was deleted.',
          actionLabel: 'Try again',
          onAction: () => provider.retryLedgerInit(),
        )
      else if (trackedTransactions.isEmpty && provider.isSyncing)
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
          icon: Icons.receipt_long_rounded,
          title: 'Nothing found',
          message:
              'No transactions were detected after your selected SMS start date.',
          actionLabel: 'Sync now',
          onAction: () => provider.syncFromSms(userInitiated: true),
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
              color: AppColors.brandInk(context),
            ),
          ),
        ),
    ];
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

/// Greeting row and the balance hero. Kept together because they share the same
/// page gutter and read as one header block, but the balance card is a real card
/// rather than a full-bleed banner: it gives the layout the reference's "floating
/// balance panel" shape and keeps the canvas visible on both sides.
class _HeaderSection extends StatelessWidget {
  final AuthProvider auth;
  final TransactionProvider provider;
  final bool balanceVisible;
  final VoidCallback onToggleBalance;

  const _HeaderSection({
    required this.auth,
    required this.provider,
    required this.balanceVisible,
    required this.onToggleBalance,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _greetingRow(context),
            const SizedBox(height: AppSpacing.lg),
            _BalanceCard(
              provider: provider,
              visible: balanceVisible,
              onToggle: onToggleBalance,
            ),
          ],
        ),
      ),
    );
  }

  Widget _greetingRow(BuildContext context) {
    final name = auth.greetingName;
    final greeting = Formatters.greeting(DateTime.now());

    return Row(
      children: [
        ProfileAvatar(
          imageBytes: auth.profileImageBytes,
          name: auth.name,
          radius: 22,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(context).copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary(context),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                name.isEmpty ? '$greeting there' : '$greeting, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.h2(context).copyWith(fontSize: 19),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const _SyncButton(),
      ],
    );
  }
}

/// Sync affordance: shows a spinner while a scan runs, otherwise the last sync
/// time. Uses the existing SMS import prompt rather than a new surface.
class _SyncButton extends StatelessWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final label = provider.lastSynced == null
            ? 'Sync'
            : DateFormat('hh:mm a').format(provider.lastSynced!);

        return Semantics(
          button: true,
          label: provider.isSyncing ? 'Syncing messages' : 'Sync messages',
          excludeSemantics: true,
          child: Pressable(
            onTap: () => SmsImportPrompt.show(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            sound: SoundEventType.buttonTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor(context),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.isSyncing)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandInk(context),
                      ),
                    )
                  else
                    Icon(
                      Icons.sync_rounded,
                      size: 15,
                      color: AppColors.brandInk(context),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppText.label(context).copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Balance hero ─────────────────────────────────────────────────────────────

/// The Home hero prioritizes current salary-cycle spending. Income and the
/// all-time balance remain supporting data rather than the primary metric.
class _BalanceCard extends StatelessWidget {
  final TransactionProvider provider;
  final bool visible;
  final VoidCallback onToggle;

  const _BalanceCard({
    required this.provider,
    required this.visible,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tracked = provider.trackedTransactions;
    final income = provider.totalTrackedIncome;
    final expenses = provider.totalTrackedExpenses;

    return Consumer<PeriodProvider>(
      builder: (context, period, _) {
        final cycleSpent =
            provider.totalExpensesForPeriod(period.currentPeriod);
        return _buildCard(
          context,
          tracked: tracked,
          income: income,
          expenses: expenses,
          cycleSpent: cycleSpent,
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required Iterable<TransactionModel> tracked,
    required int income,
    required int expenses,
    required int cycleSpent,
  }) {
    final dark = AppColors.isDark(context);
    final radius = BorderRadius.circular(AppRadius.lg);

    // Dark mode keeps the green as a focal accent: the gradient is pulled toward
    // the near-black surface so the card does not glow against the black canvas.
    final gradient = AppColors.heroSurfaceGradient(context);

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: radius,
        // A hairline defines the card edge against pure black.
        border: dark ? Border.all(color: AppColors.borderDark) : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: dark ? 0.12 : 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Controlled decorative rings: one clipped crescent top-right, one
            // broad low-contrast disc bottom-left. Static, so no paint cost
            // beyond the card itself.
            Positioned(
              top: -70,
              right: -50,
              child: _Ring(size: 200, opacity: 0.10),
            ),
            Positioned(
              bottom: -80,
              left: -40,
              child: _Ring(size: 180, opacity: 0.07),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total spent this cycle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.onGradient(
                            size: 12,
                            weight: FontWeight.w600,
                            opacity: 0.82,
                          ),
                        ),
                      ),
                      _VisibilityToggle(
                        visible: visible,
                        onToggle: onToggle,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: visible
                              ? AnimatedAmount(
                                  value: cycleSpent.toDouble(),
                                  format: (v) => Formatters.currency.format(v),
                                  style: AppText.onGradient(
                                    size: 36,
                                    weight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                  ),
                                )
                              : Text(
                                  '••••••',
                                  style: AppText.onGradient(
                                    size: 34,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    provider.hasLedgerInitError
                        ? 'Couldn\'t load your ledger'
                        : tracked.isEmpty
                            ? 'Add or sync transactions to see spending'
                            : 'Income ${Formatters.currency.format(income)} · '
                                'Spent ${Formatters.currency.format(expenses)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.onGradient(
                      size: 11,
                      weight: FontWeight.w500,
                      opacity: 0.78,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _CyclePill(provider: provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double size;
  final double opacity;

  const _Ring({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: opacity),
            width: size * 0.14,
          ),
        ),
      ),
    );
  }
}

class _VisibilityToggle extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggle;

  const _VisibilityToggle({required this.visible, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: visible ? 'Hide balance' : 'Show balance',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onToggle,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 19,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

/// Cycle-over-cycle spending change, shown as the reference's lime pill. Only
/// rendered when a comparable previous window exists — never as a fabricated
/// "up this month".
class _CyclePill extends StatelessWidget {
  final TransactionProvider provider;

  const _CyclePill({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Consumer<PeriodProvider>(
      builder: (context, period, _) {
        final previous = period.previousPeriod;
        if (previous == null) return const SizedBox.shrink();

        final current = provider
            .expensesInPeriod(period.currentPeriod)
            .fold<int>(0, (sum, t) => sum + t.amountMinor);
        final before = provider
            .expensesInPeriod(previous)
            .fold<int>(0, (sum, t) => sum + t.amountMinor);
        if (before <= 0) return const SizedBox.shrink();

        final delta = (current - before) * 100.0 / before;
        final rising = delta > 0.05;
        final falling = delta < -0.05;
        final label = !rising && !falling
            ? 'Same as last cycle'
            : '${delta.abs().toStringAsFixed(1)}% '
                '${rising ? 'more' : 'less'} than last cycle';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.lime,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                rising
                    ? Icons.trending_up_rounded
                    : falling
                        ? Icons.trending_down_rounded
                        : Icons.remove_rounded,
                size: 13,
                color: AppColors.onLime(context),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.onGradient(
                    size: 11,
                    weight: FontWeight.w700,
                  ).copyWith(color: AppColors.onLime(context)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Quick actions ────────────────────────────────────────────────────────────

/// Four real actions: money out, money in, an SMS sync, and a jump to the full
/// activity list. Every destination already existed; none is a placeholder.
/// Layout (equal tiles, 4-across or 2 x 2) lives in [QuickActionGrid].
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return QuickActionGrid(
      actions: [
        QuickAction(
          label: 'Add expense',
          icon: Icons.south_west_rounded,
          onTap: () => _open(context, TransactionType.expense),
        ),
        QuickAction(
          label: 'Add income',
          icon: Icons.north_east_rounded,
          onTap: () => _open(context, TransactionType.income),
        ),
        QuickAction(
          label: 'Sync SMS',
          icon: Icons.sync_rounded,
          onTap: () => SmsImportPrompt.show(context),
        ),
        QuickAction(
          label: 'Activity',
          icon: Icons.receipt_long_rounded,
          onTap: () => Navigator.of(context).push(
            AppPageRoute(builder: (_) => const ActivityScreen()),
          ),
        ),
      ],
    );
  }

  /// Both entry points land on the same shared form, so validation, category
  /// rules and persistence stay in one place.
  void _open(BuildContext context, TransactionType type) {
    showAddTransactionSheet(context, initialType: type);
  }
}
// ── Budget card ──────────────────────────────────────────────────────────────

class _BudgetCard extends StatelessWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Consumer2<TransactionProvider, PeriodProvider>(
        builder: (context, txProvider, period, _) {
          final progress = BudgetProgress(
            spentMinor: txProvider.totalExpensesForPeriod(period.currentPeriod),
            budgetMinor: txProvider.monthlyBudgetMinor,
          );
          final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;

          // The gauge and the figures sit side by side on a normal phone, but
          // at very narrow widths or large text sizes they stack instead of
          // squeezing the figures to nothing.
          return LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 260 || textScale > 1.6;
              final gaugeSize = constraints.maxWidth < 300 ? 92.0 : 108.0;
              final gauge = BudgetGauge(
                spent: progress.spentMinor,
                budget: progress.budgetMinor,
                size: gaugeSize,
              );
              final figures = _BudgetFigures(progress: progress);

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: gauge),
                    const SizedBox(height: AppSpacing.md),
                    figures,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  gauge,
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: figures),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Budget amount, spent amount and a status pill. The pill is always drawn (in
/// both themes) so the block keeps the same proportions in every state.
class _BudgetFigures extends StatelessWidget {
  final BudgetProgress progress;

  const _BudgetFigures({required this.progress});

  @override
  Widget build(BuildContext context) {
    final hasBudget = progress.hasBudget;
    final over = progress.isOver;
    final nearLimit = hasBudget && !over && progress.percentUsed >= 80;

    final Color tone = !hasBudget
        ? AppColors.textTertiary(context)
        : over
            ? AppColors.expenseRed
            : nearLimit
                ? AppColors.amber
                : AppColors.incomeGreen;
    final IconData icon = !hasBudget
        ? Icons.tune_rounded
        : over
            ? Icons.error_outline_rounded
            : nearLimit
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded;
    final String status = !hasBudget
        ? 'Set a budget'
        : over
            ? '${Formatters.currency.format(progress.overMinor)} over '
                '(+${progress.overPercent}%)'
            : '${Formatters.currency.format(progress.remainingMinor)} left';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('BUDGET', style: AppText.overline(context)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            hasBudget
                ? Formatters.currency.format(progress.budgetMinor)
                : 'No budget set',
            maxLines: 1,
            style: AppText.amount(context, size: 22),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hasBudget
              ? 'Spent ${Formatters.currency.format(progress.spentMinor)} '
                  '· ${progress.percentUsed}% used'
              : 'Spent ${Formatters.currency.format(progress.spentMinor)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.label(context).copyWith(fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: tone),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(context).copyWith(
                      fontSize: 12.5,
                      color: tone,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
// ── Category card ────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final List<TransactionModel> expenses;

  const _CategoryCard({required this.expenses});

  @override
  Widget build(BuildContext context) {
    final totals = <String, int>{};
    for (final t in expenses) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amountMinor;
    }
    final hasData = totals.values.any((v) => v > 0);
    final chartTotals = <String, double>{
      for (final entry in totals.entries) entry.key: entry.value.toDouble(),
    };

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasData) ...[
            CategoryBubbleCluster(totals: chartTotals),
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, color: AppColors.border(context)),
            const SizedBox(height: AppSpacing.md),
            _TopCategories(totals: totals),
          ] else
            _CategoryEmpty(),
        ],
      ),
    );
  }
}

/// Polished, non-decorative empty state: one line of guidance, no gradients
/// competing with the balance card.
class _CategoryEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(context),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              Icons.pie_chart_outline_rounded,
              size: 21,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No spending this cycle',
                    style: AppText.title(context).copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  'Add a transaction and the breakdown fills in automatically.',
                  style: AppText.body(context).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Exact figures for the leading categories — the bubbles convey share, but a
/// bubble alone cannot be read for an amount.
class _TopCategories extends StatelessWidget {
  final Map<String, int> totals;

  const _TopCategories({required this.totals});

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return Text('No spending recorded yet.', style: AppText.body(context));
    }

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
                      style: AppText.label(context).copyWith(fontSize: 12.5),
                    ),
                  ),
                  Text(
                    Formatters.currency.format(e.value),
                    style: AppText.amount(context, size: 13),
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
    final today = PeriodMath.dateOnly(now);
    final days = List.generate(7, (i) {
      // Calendar arithmetic: stepping back 6..0 days must stay on the same
      // wall-clock day across a DST change (Duration would shift it).
      final day = PeriodMath.addDays(today, i - 6);
      final totalMinor = expenses
          .where((t) =>
              t.date.year == day.year &&
              t.date.month == day.month &&
              t.date.day == day.day)
          .fold<int>(0, (s, t) => s + t.amountMinor);
      return _DayBar(day: day, amount: totalMinor.toDouble());
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
              Text(
                Formatters.currency.format(todayTotal),
                style: AppText.amount(context, size: 17),
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
                                    ? AppColors.brandInk(context)
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
                      tooltipBgColor: AppColors.isDark(context)
                          ? AppColors.darkSurfaceAlt
                          : AppColors.navyDeep,
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
                              ? LinearGradient(
                                  colors: [
                                    AppColors.brandBright,
                                    AppColors.brand,
                                  ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                )
                              : LinearGradient(
                                  colors: [
                                    AppColors.brand.withValues(alpha: 0.30),
                                    AppColors.brand.withValues(alpha: 0.12),
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
