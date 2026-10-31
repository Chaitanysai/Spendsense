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
import '../utils/dashboard_sections.dart';
import '../utils/formatters.dart';
import '../utils/period_math.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_states.dart';
import '../widgets/budget_summary.dart';
import '../widgets/category_rail.dart';
import '../widgets/cycle_hero.dart';
import '../widgets/glass_card.dart';
import '../widgets/home_action_dock.dart';
import '../widgets/page_entry.dart';
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
            // Greeting + one ring. The ring is the only loud object on the
            // page; every surface below it is neutral and quiet.
            SliverToBoxAdapter(
              child: PageEntrance(
                child: _HeaderSection(
                  auth: auth,
                  provider: provider,
                  balanceVisible: _balanceVisible,
                  onToggleBalance: () =>
                      setState(() => _balanceVisible = !_balanceVisible),
                  onEditDashboard:
                      prefs == null ? null : () => _startEditing(prefs),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.lg,
                AppSpacing.page,
                scrollBottomInset,
              ),
              sliver: _editing
                  ? _editSliver(context)
                  : SliverList(
                      delegate: SliverChildListDelegate([
                        const PageEntrance(child: _QuickActions()),
                        // The edit affordance lives in the header, beside the
                        // avatar. A separate "Edit dashboard" row here pushed
                        // the first section header under the floating Add
                        // button on 411dp-wide phones.
                        const SizedBox(height: AppSpacing.xxxl),
                        for (final (sectionIndex, id)
                            in (prefs?.visibleSectionOrder ??
                                    DashboardSection.ids)
                                .indexed)
                          ..._section(
                            context,
                            id,
                            provider,
                            trackedTransactions,
                            trackedExpenses,
                          ).map(
                            (widget) => PageEntrance(
                              index: sectionIndex + 1,
                              child: widget,
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

  // ── Dashboard editing ──────────────────────────────────────────────────────

  /// Full order being edited. Held locally so Cancel can discard it; only Done
  /// writes it to preferences.
  List<String> _draftOrder = const [];
  Set<String> _draftHidden = const {};
  bool _editing = false;

  void _startEditing(ThemeProvider prefs) {
    setState(() {
      _draftOrder = prefs.sectionOrder;
      _draftHidden = prefs.hiddenSections;
      _editing = true;
    });
  }

  void _cancelEditing() => setState(() => _editing = false);

  Future<void> _finishEditing() async {
    final prefs = context.read<ThemeProvider?>();
    final order = _draftOrder;
    setState(() => _editing = false);
    await prefs?.setSectionOrder(order);
  }

  Widget _editSliver(BuildContext context) {
    final visible = DashboardSection.visibleInOrder(_draftOrder, _draftHidden);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) == true;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: GlassCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edit dashboard', style: AppText.title(context)),
                  const SizedBox(height: 2),
                  Text(
                    'Drag the handle to reorder. Hidden sections stay hidden; '
                    'show them in Settings → Appearance.',
                    style: AppText.body(context),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _cancelEditing,
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton(
                          onPressed: _finishEditing,
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverReorderableList(
          itemCount: visible.length,
          onReorderItem: (oldIndex, newIndex) => setState(() {
            // onReorderItem already accounts for the removed item; the helper
            // expects the pre-removal index (ReorderableList.onReorder form).
            _draftOrder = DashboardSection.reorderVisible(
                _draftOrder,
                _draftHidden,
                oldIndex,
                newIndex > oldIndex ? newIndex + 1 : newIndex);
          }),
          proxyDecorator: (child, index, animation) => Material(
            color: Colors.transparent,
            elevation: reduce ? 0 : 6,
            shadowColor: Colors.black54,
            borderRadius: AppRadius.lgAll,
            child: child,
          ),
          itemBuilder: (context, index) {
            final id = visible[index];
            return Padding(
              key: ValueKey(id),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        DashboardSection.label(id),
                        style: AppText.title(context),
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Semantics(
                        label: 'Reorder ${DashboardSection.label(id)}',
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// One dashboard section, keyed by its stable id.
  List<Widget> _section(
    BuildContext context,
    String id,
    TransactionProvider provider,
    List<TransactionModel> trackedTransactions,
    List<TransactionModel> trackedExpenses,
  ) {
    switch (id) {
      case DashboardSection.budget:
        return [
          SectionHeader(
            title: 'Monthly budget',
            large: true,
            actionLabel: 'Manage',
            actionIcon: Icons.chevron_right_rounded,
            onAction: () => Navigator.of(context).push(
              AppPageRoute(builder: (_) => const BudgetsScreen()),
            ),
          ),
          const _BudgetCard(),
          const SizedBox(height: AppSpacing.xxxl),
        ];
      case DashboardSection.categories:
        final totals = <String, int>{};
        for (final t in trackedExpenses) {
          totals[t.category] = (totals[t.category] ?? 0) + t.amountMinor;
        }
        return [
          const SectionHeader(
            title: 'Spending by category',
            large: true,
          ),
          CategoryRail(totalsMinor: totals),
          const SizedBox(height: AppSpacing.xxxl),
        ];
      case DashboardSection.weekly:
        return [
          const SectionHeader(title: 'Last 7 days', large: true),
          _DailySpendCard(
            key: const Key('daily-spend-card'),
            expenses: trackedExpenses,
          ),
          const SizedBox(height: AppSpacing.xxxl),
        ];
      case DashboardSection.recent:
        return [
          SectionHeader(
            title: 'Recent transactions',
            large: true,
            actionLabel: 'See all',
            actionIcon: Icons.chevron_right_rounded,
            onAction: () => AppPageRoute.pushOnce(
              context,
              name: ActivityScreen.routeName,
              builder: (_) => const ActivityScreen(),
            ),
          ),
          ..._recentSection(context, provider, trackedTransactions),
        ];
      default:
        return const [];
    }
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
              '(${provider.ledgerInitErrorCode}). '
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
        PageEntrance(
          offset: 0.03,
          child: _RecentFeed(
            transactions: trackedTransactions.take(20).toList(),
          ),
        ),
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

/// Recent transactions as one flat feed rather than a stack of separate tiles.
///
/// The transactions are the content of this surface, not five more cards: hair-
/// line dividers carry the rhythm and the amounts line up in one column. This
/// is the Suno track-list move; it also removes four borders and four shadows
/// per screen from the scroll path.
class _RecentFeed extends StatelessWidget {
  final List<TransactionModel> transactions;

  const _RecentFeed({required this.transactions});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) return const SizedBox.shrink();
    final border = AppColors.border(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < transactions.length; i++) ...[
            TransactionTile(transaction: transactions[i], flat: true),
            if (i < transactions.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 68,
                endIndent: AppSpacing.md,
                color: border.withValues(alpha: 0.72),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

/// Editorial greeting, a quiet sync status, and the one instrument.
///
/// Suno's home opens with a huge line of type and almost nothing else above the
/// fold; GO Club's opens with the number you came for. This block is both: the
/// name is the headline, the ring underneath is the answer.
class _HeaderSection extends StatelessWidget {
  final AuthProvider auth;
  final TransactionProvider provider;
  final bool balanceVisible;
  final VoidCallback onToggleBalance;
  final VoidCallback? onEditDashboard;

  const _HeaderSection({
    required this.auth,
    required this.provider,
    required this.balanceVisible,
    required this.onToggleBalance,
    this.onEditDashboard,
  });

  @override
  Widget build(BuildContext context) {
    final greeting = Formatters.greeting(DateTime.now());
    final name = auth.greetingName;
    final today = DateFormat('EEE d MMM').format(DateTime.now()).toUpperCase();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting,',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.h2(context).copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary(context),
                          height: 1.2,
                        ),
                      ),
                      Text(
                        name.isEmpty ? 'there.' : '$name.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.display(context).copyWith(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.1,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (onEditDashboard != null) ...[
                  Tooltip(
                    message: 'Edit dashboard',
                    child: Semantics(
                      button: true,
                      label: 'Edit dashboard',
                      // A Semantics wrapper with excludeSemantics drops the
                      // Pressable's tap action, so expose it explicitly for
                      // TalkBack and switch access.
                      onTap: onEditDashboard,
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: onEditDashboard,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.tune_rounded,
                            size: 17,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.brandBright,
                        AppColors.lime,
                      ],
                    ),
                  ),
                  child: ProfileAvatar(
                    imageBytes: auth.profileImageBytes,
                    name: auth.name,
                    radius: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Status metadata, not an eyebrow above the headline: the greeting
            // itself carries the top of the hierarchy. A Wrap lets the sync
            // line and the date fall to a second run at large text sizes
            // instead of truncating or overflowing.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _SyncButton(),
                Text(
                  'Welcome back',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.overline(context).copyWith(
                    fontSize: 9,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  today,
                  style: AppText.overline(context)
                      .copyWith(fontSize: 9, letterSpacing: 1.1),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const _SyncStatusStrip(),
            _CycleSection(
              provider: provider,
              visible: balanceVisible,
              onToggleVisibility: onToggleBalance,
            ),
          ],
        ),
      ),
    );
  }
}

/// Wires the provider values into the presentational [CycleHero].
class _CycleSection extends StatelessWidget {
  final TransactionProvider provider;
  final bool visible;
  final VoidCallback onToggleVisibility;

  const _CycleSection({
    required this.provider,
    required this.visible,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PeriodProvider>(
      builder: (context, period, _) {
        final current = period.currentPeriod;
        final previous = period.previousPeriod;
        return CycleHero(
          spentMinor: provider.totalExpensesForPeriod(current),
          budgetMinor: provider.monthlyBudgetMinor,
          transactionCount: provider.trackedTransactions.length,
          topCategory: provider.topTrackedCategory,
          periodLabel: period.periodLabel,
          periodEnd: current.end,
          previousSpentMinor: previous == null
              ? null
              : provider.totalExpensesForPeriod(previous),
          visible: visible,
          onToggleVisibility: onToggleVisibility,
          ledgerError: provider.hasLedgerInitError,
          onSetBudget: () => Navigator.of(context).push(
            AppPageRoute(builder: (_) => const BudgetsScreen()),
          ),
        );
      },
    );
  }
}

/// Actionable status for a sync that did not complete.
///
/// Renders nothing when the last attempt succeeded, so a healthy app stays
/// quiet. When it does appear it names the cause and offers the one action that
/// can fix it: open Android settings for a denied permission, retry for a scan
/// that threw. Collapsing both into "sync failed" would tell the user nothing.
class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final failure = provider.syncFailure;
        if (failure == null) return const SizedBox.shrink();

        final denied = failure == SyncFailure.permissionDenied;
        final message = denied
            ? 'SMS permission is off, so new transactions cannot be imported.'
            : 'The last sync did not finish. Your saved transactions are '
                'unchanged.';

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.amber.withValues(alpha: 0.38),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  denied
                      ? Icons.sms_failed_outlined
                      : Icons.sync_problem_rounded,
                  size: 18,
                  color: AppColors.textPrimary(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: AppText.bodySmall(context).copyWith(
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Pressable(
                  onTap: () {
                    // `userInitiated: true` is what allows a permanently denied
                    // permission to open Android settings, and it is correct
                    // here because the user just tapped Retry/Fix themselves.
                    // A failed scan simply runs again.
                    provider.syncFromSms(userInitiated: true);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      denied ? 'Fix' : 'Retry',
                      style: AppText.label(context).copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandInk(context),
                      ),
                    ),
                  ),
                ),
                Pressable(
                  onTap: provider.dismissSyncFailure,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Sync affordance: shows a spinner while a scan runs, otherwise how long ago
/// the last successful sync was.
///
/// Tapping it syncs. It only opens the "check SMS from when?" sheet when no
/// scan start date has been chosen yet, because that sheet is first-run setup,
/// not a refresh. Previously the pill always opened the date sheet, so a button
/// that displayed a sync time never actually synced — the label and the action
/// disagreed.
class _SyncButton extends StatelessWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, _) {
        final last = provider.lastSynced;
        final label = provider.isSyncing
            ? 'Syncing…'
            : last == null
                ? 'Sync messages'
                : 'Synced ${Formatters.relativeTime(last)}';

        return Semantics(
          button: true,
          label: provider.isSyncing
              ? 'Syncing messages'
              : last == null
                  ? 'Sync messages'
                  : 'Synced ${Formatters.relativeTime(last)}. Sync again',
          excludeSemantics: true,
          child: Pressable(
            onTap: () => _onTap(context, provider),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            sound: SoundEventType.buttonTap,
            child: ConstrainedBox(
              // The visual is a quiet line of caption text; the target is still
              // a full 44dp high row.
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.isSyncing)
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: AppColors.brandInk(context),
                      ),
                    )
                  else
                    Icon(
                      Icons.sync_rounded,
                      size: 13,
                      color: AppColors.textTertiary(context),
                    ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(context).copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
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

  /// First run asks for the scan window; every run after that is a real sync.
  ///
  /// `userInitiated: true` is what allows a permanently denied SMS permission
  /// to open Android settings — the user just asked for this, so sending them
  /// to the fix is the actionable response rather than a silent no-op.
  ///
  /// This deliberately does NOT consult [TransactionProvider.autoSyncCooldown]:
  /// the cooldown exists to stop background triggers from re-scanning, and a
  /// user tapping Sync is asking for a refresh right now. In-flight
  /// deduplication still applies, so a double tap cannot start two scans.
  static void _onTap(BuildContext context, TransactionProvider provider) {
    if (!provider.hasSmsScanStartDate) {
      SmsImportPrompt.show(context);
      return;
    }
    if (provider.isSyncing) return;
    provider.syncFromSms(userInitiated: true);
  }
}

// ── Quick actions ────────────────────────────────────────────────────────────

/// Four real actions: money out, money in, an SMS sync, and a jump to the full
/// activity list. Every destination already existed; none is a placeholder.
/// They live in one floating dock so the dashboard has a command surface, not
/// another grid of cards to read.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return HomeActionDock(
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
          // First run only: the start date is a one-time question. Once it is
          // stored, this action is a plain sync and never re-prompts.
          onTap: () => _SyncButton._onTap(
            context,
            context.read<TransactionProvider>(),
          ),
        ),
        QuickAction(
          label: 'Activity',
          icon: Icons.receipt_long_rounded,
          onTap: () => AppPageRoute.pushOnce(
            context,
            name: ActivityScreen.routeName,
            builder: (_) => const ActivityScreen(),
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
      radius: AppRadius.lg,
      child: Consumer2<TransactionProvider, PeriodProvider>(
        builder: (context, txProvider, period, _) {
          final range = period.currentPeriod;
          final progress = BudgetProgress(
            spentMinor: txProvider.totalExpensesForPeriod(range),
            budgetMinor: txProvider.monthlyBudgetMinor,
          );
          final fmt = DateFormat('d MMM');
          return SizedBox(
            width: double.infinity,
            child: BudgetSummary(
              progress: progress,
              periodLabel:
                  '${fmt.format(range.start)} – ${fmt.format(range.end)}',
            ),
          );
        },
      ),
    );
  }
}
// ── Daily spend ──────────────────────────────────────────────────────────────

class _DailySpendCard extends StatefulWidget {
  final List<TransactionModel> expenses;

  const _DailySpendCard({super.key, required this.expenses});

  @override
  State<_DailySpendCard> createState() => _DailySpendCardState();
}

class _DailySpendCardState extends State<_DailySpendCard> {
  static const int _todayIndex = 6;

  /// Which bar the header describes. Defaults to today and survives parent
  /// rebuilds, so a sync landing mid-inspection does not move the answer.
  int _selected = _todayIndex;

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
  }

  /// Compares calendar days in local time, matching how the provider draws
  /// period boundaries. A stored offset must not move a row to another bar.
  bool _isSameDay(DateTime value, DateTime day) {
    final local = value.toLocal();
    return local.year == day.year &&
        local.month == day.month &&
        local.day == day.day;
  }

  @override
  Widget build(BuildContext context) {
    final today = PeriodMath.dateOnly(DateTime.now());
    final days = List.generate(7, (i) {
      // Calendar arithmetic: stepping back 6..0 days must stay on the same
      // wall-clock day across a DST change (Duration would shift it).
      final day = PeriodMath.addDays(today, i - 6);
      final totalMinor = widget.expenses
          .where((t) => _isSameDay(t.date, day))
          .fold<int>(0, (s, t) => s + t.amountMinor);
      return _DayBar(day: day, amount: totalMinor.toDouble());
    });

    final selectedIndex = _selected.clamp(0, days.length - 1);
    final selected = days[selectedIndex];
    final maxAmount =
        days.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    final barMax = maxAmount <= 0 ? 100.0 : maxAmount * 1.25;
    final hasSpending = maxAmount > 0;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedIndex == _todayIndex
                        ? 'Today'
                        : DateFormat('EEEE').format(selected.day),
                    style: AppText.label(context).copyWith(
                      fontSize: 11,
                      letterSpacing: 0.3,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    DateFormat('d MMM').format(selected.day),
                    style: AppText.caption(context).copyWith(fontSize: 10.5),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      Formatters.currency.format(selected.amount),
                      style: AppText.amount(context, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasSpending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text(
                  'No spending in the last 7 days',
                  style: AppText.bodySmall(context),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 104,
              child: TweenAnimationBuilder<double>(
                // Replays the seven-day bars when the dashboard is entered
                // again; a normal rebuild keeps the same key and does not
                // restart a finished chart.
                key: ValueKey(
                  'daily-spend-entry-'
                  '${PageEntryScope.maybeOf(context)?.generation ?? 0}',
                ),
                tween: Tween(begin: 0, end: 1),
                duration: AppMotion.respect(context, AppMotion.chart),
                curve: AppMotion.emphasized,
                builder: (context, t, _) => Stack(
                  children: [
                    Positioned.fill(
                      child: BarChart(
                        BarChartData(
                          maxY: barMax,
                          alignment: BarChartAlignment.spaceAround,
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          // Selection is persistent, so the transient
                          // fl_chart tooltip would only compete with it.
                          barTouchData: BarTouchData(enabled: false),
                          barGroups: days.asMap().entries.map((e) {
                            final isSelected = e.key == selectedIndex;
                            return BarChartGroupData(
                              x: e.key,
                              barRods: [
                                BarChartRodData(
                                  toY: e.value.amount * t,
                                  width: 16,
                                  borderRadius: BorderRadius.circular(8),
                                  gradient: LinearGradient(
                                    colors: isSelected
                                        ? [
                                            AppColors.lime,
                                            AppColors.brandBright,
                                          ]
                                        : [
                                            AppColors.brand
                                                .withValues(alpha: 0.32),
                                            AppColors.brand
                                                .withValues(alpha: 0.10),
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
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (var i = 0; i < days.length; i++)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: i == selectedIndex,
                                label: _semanticsLabel(days[i]),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _select(i),
                                  // A child is required: without one the
                                  // column collapses to zero height and only
                                  // its centre line stays tappable.
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < days.length; i++)
                    _WeekdayLabel(
                      label: DateFormat('EEEEE')
                          .format(days[i].day)
                          .substring(0, 1),
                      selected: i == selectedIndex,
                      onTap: () => _select(i),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _semanticsLabel(_DayBar bar) {
    final weekday = DateFormat('EEEE').format(bar.day);
    final date = DateFormat('d MMM').format(bar.day);
    final amount = Formatters.currency.format(bar.amount);
    return '$weekday, $date, $amount';
  }
}

/// One weekday initial under the chart. Tappable as a second, larger target
/// for the same selection the chart columns offer.
class _WeekdayLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WeekdayLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.respect(context, AppMotion.fast),
              curve: AppMotion.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? AppColors.lime : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                label,
                style: AppText.label(context).copyWith(
                  fontSize: 10,
                  color: selected
                      ? AppColors.onLime(context)
                      : AppColors.textTertiary(context),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayBar {
  final DateTime day;
  final double amount;
  const _DayBar({required this.day, required this.amount});
}
