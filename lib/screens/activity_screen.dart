import 'package:flutter/material.dart';
import '../widgets/app_sheet.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';
import '../services/sound_service.dart';
import '../widgets/transaction_tile.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import '../utils/transaction_filter.dart';
import '../utils/period_math.dart';
import '../widgets/app_button.dart';
import '../widgets/app_chip.dart';
import '../widgets/app_list_row.dart';
import '../widgets/app_states.dart';
import '../widgets/app_surface.dart';
import '../widgets/page_entry.dart';
import '../widgets/sms_import_prompt.dart';

// ─── Date filter presets ───────────────────────────────────────────────────
enum _DatePreset { today, thisWeek, thisMonth, last3Months, custom }

extension _DatePresetLabel on _DatePreset {
  String get label {
    switch (this) {
      case _DatePreset.today:
        return 'Today';
      case _DatePreset.thisWeek:
        return 'This Week';
      case _DatePreset.thisMonth:
        return 'This Month';
      case _DatePreset.last3Months:
        return 'Last 3 Months';
      case _DatePreset.custom:
        return 'Custom Range';
    }
  }

  DateTimeRange? resolve() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case _DatePreset.today:
        return DateTimeRange(start: today, end: now);
      case _DatePreset.thisWeek:
        return DateTimeRange(
          start: PeriodMath.addDays(today, -(today.weekday - 1)),
          end: now,
        );
      case _DatePreset.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case _DatePreset.last3Months:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 2, 1),
          end: now,
        );
      case _DatePreset.custom:
        return null;
    }
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  /// Stable route name. Navigation uses it to dedupe rapid repeated taps so a
  /// double tap cannot stack two Activity screens.
  static const String routeName = '/activity';

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _sortMode = 'Date';
  bool _sortDescending = true;
  String? _selectedCategory;
  TransactionType? _selectedType;
  DateTimeRange? _selectedDateRange;
  _DatePreset? _activePreset;
  String _searchQuery = '';

  /// Inclusive amount bounds, integer paise (null = unbounded).
  int? _minAmountMinor;
  int? _maxAmountMinor;

  /// Whether the tab was visible at the last dependency change. The shell keeps
  /// this screen alive across tab switches, so initState no longer runs on every
  /// visit; the SMS sync that used to happen then is re-triggered here instead.
  bool _tabActive = true;

  /// Route animation the automatic sync is waiting on (null when there is
  /// nothing to wait for).
  Animation<double>? _routeAnimation;

  /// Memoised filter+sort result. Rebuilding for an unrelated reason (theme
  /// change, keyboard, a parent rebuild) must not re-filter and re-sort the
  /// whole ledger.
  List<TransactionModel>? _cachedDisplay;
  List<TransactionModel>? _cachedSource;
  Object? _cachedKey;

  @override
  void initState() {
    super.initState();
    // Defer the automatic SMS scan until the push transition has finished.
    // Starting it in a microtask ran the platform-channel query, ledger writes
    // and listener notifications inside the transition's first frames, which
    // is what made Home -> Activity feel slow. This is not an artificial
    // delay: the scan starts the moment the route's own animation completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation == null || animation.isCompleted) {
        _startAutomaticSync();
        return;
      }
      _routeAnimation = animation;
      animation.addStatusListener(_onRouteStatus);
    });
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
    _startAutomaticSync();
  }

  void _startAutomaticSync() {
    if (!mounted) return;
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    // A sync already in flight is never started twice.
    if (provider.isSyncing) return;
    provider.syncFromSms();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_tabActive) {
      // Deferred like the initState call: sync may notify listeners, which is
      // not allowed while the framework is still building.
      final provider = Provider.of<TransactionProvider>(context, listen: false);
      Future.microtask(() {
        // A sync already in flight is not started a second time, so rapid tab
        // switching cannot stack up overlapping SMS scans.
        if (mounted && !provider.isSyncing) provider.syncFromSms();
      });
    }
    _tabActive = active;
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);
    final displayList = _getProcessedList(provider.transactions);
    final hasFilters = _selectedCategory != null ||
        _selectedType != null ||
        _selectedDateRange != null ||
        _activePreset != null ||
        _minAmountMinor != null ||
        _maxAmountMinor != null ||
        _searchQuery.trim().isNotEmpty;

    final header = _header(provider, displayList, hasFilters);
    final content = AppRefreshIndicator(
      onRefresh: () => provider.syncFromSms(userInitiated: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On a short viewport (a phone in landscape) a pinned header would
          // leave a few lines for the list, so the header scrolls with it. On
          // anything taller it stays put, so search and filters are always at
          // hand. Either way the states below are slivers in the same scroll
          // view, so a tall empty state scrolls instead of overflowing.
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Dragging the results down closes the keyboard, so a search can be
            // read without a separate dismiss tap.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              if (_compactHeader) SliverToBoxAdapter(child: header),
              ..._contentSlivers(provider, displayList, hasFilters),
            ],
          );
        },
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 560;
            if (compact != _compactHeader) {
              // Read by the content above on the next frame; the header moves
              // between a pinned slot and the scroll view without losing the
              // query, which lives in this State.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _compactHeader != compact) {
                  setState(() => _compactHeader = compact);
                }
              });
            }
            return _compactHeader
                ? content
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, Expanded(child: content)],
                  );
          },
        ),
      ),
    );
  }

  /// True while the viewport is too short to pin the header (see [build]).
  bool _compactHeader = false;

  Widget _header(
    TransactionProvider provider,
    List<TransactionModel> displayList,
    bool hasFilters,
  ) {
    return PageEntrance(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The page title, as a heading for screen readers.
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Activity',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.h1(context)
                          .copyWith(fontSize: 24, letterSpacing: -0.4),
                    ),
                  ),
                ),
                if (hasFilters)
                  AppChip(
                    label: 'Clear',
                    leading: Icons.close_rounded,
                    onTap: _clearFilters,
                    semanticLabel: 'Clear search and all filters',
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _SearchField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              onClear: () => setState(() {
                _searchQuery = '';
                _searchController.clear();
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            _filterRow(provider),
            const SizedBox(height: AppSpacing.sm),
            _ResultSummary(transactions: displayList),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  /// One horizontally scrolling row of filter and sort chips.
  ///
  /// Every chip is an [AppChip]: 34dp visual inside a 44dp target, selected
  /// state carried by weight, a check and a stronger hairline as well as tint.
  /// The row bleeds to the screen edge (no clip) so a chip cut by the edge reads
  /// as "more this way" rather than as a bug.
  Widget _filterRow(TransactionProvider provider) {
    final isDateSort = _sortMode == 'Date';
    final typeLabel = switch (_selectedType) {
      TransactionType.expense => 'Expense',
      TransactionType.income => 'Income',
      null => 'Type',
    };
    final dateActive = _activePreset != null || _selectedDateRange != null;
    final amountActive = _minAmountMinor != null || _maxAmountMinor != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          AppChip(
            label: typeLabel,
            leading: Icons.swap_horiz_rounded,
            selected: _selectedType != null,
            onTap: _showTypeSheet,
            semanticLabel: _selectedType == null
                ? 'Filter by type'
                : 'Type filter: $typeLabel',
          ),
          const SizedBox(width: AppSpacing.sm),
          AppChip(
            label: _selectedCategory ?? 'Category',
            leading: Icons.category_rounded,
            selected: _selectedCategory != null,
            onTap: () => _showCategorySheet(provider),
            semanticLabel: _selectedCategory == null
                ? 'Filter by category'
                : 'Category filter: $_selectedCategory',
          ),
          const SizedBox(width: AppSpacing.sm),
          AppChip(
            label: dateActive ? _activeDateLabel() : 'Date',
            leading: Icons.date_range_rounded,
            selected: dateActive,
            onTap: _showDateFilterSheet,
            semanticLabel: dateActive
                ? 'Date filter: ${_activeDateLabel()}'
                : 'Filter by date',
          ),
          const SizedBox(width: AppSpacing.sm),
          AppChip(
            label: amountActive ? _amountLabel() : 'Amount',
            leading: Icons.payments_outlined,
            selected: amountActive,
            onTap: _showAmountSheet,
            semanticLabel: amountActive
                ? 'Amount filter: ${_amountLabel()}'
                : 'Filter by amount',
          ),
          const SizedBox(width: AppSpacing.md),
          // Sorting is a different kind of control from filtering, so it sits
          // after the filters and is never "selected": it always has a value.
          AppChip(
            label: _sortMode == 'Date' ? 'By date' : 'By amount',
            leading: Icons.sort_rounded,
            onTap: () => setState(
                () => _sortMode = _sortMode == 'Date' ? 'Amount' : 'Date'),
            semanticLabel:
                'Sorted by ${_sortMode == 'Date' ? 'date' : 'amount'}. '
                'Tap to sort by ${_sortMode == 'Date' ? 'amount' : 'date'}',
          ),
          const SizedBox(width: AppSpacing.sm),
          AppChip(
            label: _sortDescending
                ? (isDateSort ? 'Newest' : 'Highest')
                : (isDateSort ? 'Oldest' : 'Lowest'),
            leading: _sortDescending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            onTap: () => setState(() => _sortDescending = !_sortDescending),
            semanticLabel:
                'Order: ${_sortDescending ? 'descending' : 'ascending'}. '
                'Tap to reverse',
          ),
        ],
      ),
    );
  }

  /// The list region as slivers: exactly one of ledger error, loading, empty,
  /// no results, or the grouped list. They are different situations with
  /// different next steps, so each has its own copy.
  List<Widget> _contentSlivers(
    TransactionProvider provider,
    List<TransactionModel> displayList,
    bool hasFilters,
  ) {
    // A state that fills what is left and scrolls if it is taller than that.
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);

    // A ledger that failed closed must never look like an empty ledger.
    if (provider.hasLedgerInitError) {
      return [
        fill(AppErrorState(
          title: "Couldn't load your transactions",
          message: 'Your transactions are still saved and encrypted on this '
              'device, but the ledger could not be read '
              '(${provider.ledgerInitErrorCode}). Nothing was deleted.',
          onRetry: provider.retryLedgerInit,
        )),
      ];
    }
    // Unchanged from the original rule: a skeleton only while a sync runs. Home
    // also treats the first cache read as loading, but Activity never did, and
    // its shimmer repeats forever, so widening this would change when the
    // screen settles (it broke `pumpAndSettle` in three navigation tests).
    if (displayList.isEmpty && provider.isSyncing) {
      return const [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: SliverToBoxAdapter(child: _ActivitySkeleton()),
        ),
      ];
    }
    if (displayList.isEmpty) {
      if (hasFilters) {
        return [
          fill(AppEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matching transactions',
            message: _noMatchMessage(),
            actionLabel: 'Clear all filters',
            onAction: _clearFilters,
          )),
        ];
      }
      return [
        fill(provider.hasSmsScanStartDate
            ? const AppEmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'Nothing here yet',
                message:
                    'No transactions were found after your selected SMS start date.',
              )
            : AppEmptyState(
                icon: Icons.sms_rounded,
                title: 'No transactions yet',
                message:
                    'Pick an SMS start date and SpendSense will build your transactions automatically.',
                actionLabel: 'Choose start date',
                onAction: () => SmsImportPrompt.show(context),
              )),
      ];
    }

    final groups = _groupByDay(displayList);
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.tabBottomInset(context),
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final group = groups[index];
              return PageEntrance(
                index: index,
                offset: 0.04,
                child: _DayGroup(
                  title: group.title,
                  total: group.total,
                  transactions: group.transactions,
                ),
              );
            },
            childCount: groups.length,
          ),
        ),
      ),
    ];
  }

  /// Why nothing matched, in words: the active filters, not a generic shrug.
  String _noMatchMessage() {
    final parts = <String>[
      if (_searchQuery.trim().isNotEmpty) 'the search "${_searchQuery.trim()}"',
      if (_selectedType != null)
        _selectedType == TransactionType.expense ? 'Expense' : 'Income',
      if (_selectedCategory != null) _selectedCategory!,
      if (_activePreset != null || _selectedDateRange != null)
        _activeDateLabel(),
      if (_minAmountMinor != null || _maxAmountMinor != null) _amountLabel(),
    ];
    if (parts.isEmpty) return 'Try adjusting your search or filters.';
    // "one of them" is only true with two or more; with a single filter the
    // advice is to remove it.
    return 'Nothing matches ${_joinNatural(parts)}. '
        '${parts.length == 1 ? 'Try removing it.' : 'Try removing one of them.'}';
  }

  String _joinNatural(List<String> parts) {
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  /// Splits the (already sorted) list into runs of one calendar day. Only the
  /// by-date sort groups; sorting by amount is one flat group, because a day
  /// header over an amount-ordered list would repeat and mislead.
  List<_Group> _groupByDay(List<TransactionModel> list) {
    if (_sortMode != 'Date') {
      return [
        _Group(title: null, transactions: list, total: _netMinor(list)),
      ];
    }
    final groups = <_Group>[];
    var run = <TransactionModel>[];
    DateTime? day;
    void flush() {
      if (run.isEmpty) return;
      groups.add(_Group(
        title: _dayTitle(day!),
        transactions: run,
        total: _netMinor(run),
      ));
      run = <TransactionModel>[];
    }

    for (final tx in list) {
      final d = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (day == null || d != day) {
        flush();
        day = d;
      }
      run.add(tx);
    }
    flush();
    return groups;
  }

  /// Net of a run, counting only rows that count (excluded rows do not).
  int _netMinor(List<TransactionModel> rows) {
    var net = 0;
    for (final t in rows) {
      if (t.isExcluded) continue;
      net += t.type == TransactionType.income ? t.amountMinor : -t.amountMinor;
    }
    return net;
  }

  String _dayTitle(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat(d.year == now.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy')
        .format(d);
  }

  // ─── FILTER / SORT LOGIC (unchanged behaviour) ─────────────────────────────

  List<TransactionModel> _getProcessedList(List<TransactionModel> all) {
    // Filter state that can change the result. `_activePreset` is derived
    // storage for `_selectedDateRange`, so it does not need its own slot.
    final key = (
      _searchQuery,
      _selectedCategory,
      _selectedType,
      _selectedDateRange,
      _minAmountMinor,
      _maxAmountMinor,
      _sortMode,
      _sortDescending,
    );
    // The provider hands out its own list instance and replaces it on change,
    // so identity plus the filter key is a sound cache key: an unrelated
    // rebuild (theme, keyboard, parent) reuses the previous result.
    if (identical(all, _cachedSource) && key == _cachedKey) {
      return _cachedDisplay!;
    }

    final list = TransactionFilter(
      query: _searchQuery,
      category: _selectedCategory,
      type: _selectedType,
      dateRange: _selectedDateRange,
      minAmountMinor: _minAmountMinor,
      maxAmountMinor: _maxAmountMinor,
    ).apply(all);
    if (_sortMode == 'Amount') {
      list.sort((a, b) => _sortDescending
          ? b.amountMinor.compareTo(a.amountMinor)
          : a.amountMinor.compareTo(b.amountMinor));
    } else {
      list.sort((a, b) => _sortDescending
          ? b.date.compareTo(a.date)
          : a.date.compareTo(b.date));
    }

    _cachedSource = all;
    _cachedKey = key;
    _cachedDisplay = list;
    return list;
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedType = null;
      _selectedDateRange = null;
      _activePreset = null;
      _minAmountMinor = null;
      _maxAmountMinor = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  String _activeDateLabel() {
    if (_activePreset == _DatePreset.custom && _selectedDateRange != null) {
      return _formatRange(_selectedDateRange!);
    }
    return _activePreset?.label ??
        (_selectedDateRange != null ? _formatRange(_selectedDateRange!) : '');
  }

  // ─── LABELS ────────────────────────────────────────────────────────────────

  String _amountLabel() {
    final lo = _minAmountMinor;
    final hi = _maxAmountMinor;
    if (lo != null && hi != null) {
      return '${Formatters.currency.format(lo)} – ${Formatters.currency.format(hi)}';
    }
    if (lo != null) return '≥ ${Formatters.currency.format(lo)}';
    return '≤ ${Formatters.currency.format(hi ?? 0)}';
  }

  /// Amount bounds are typed in rupees and stored as exact integer paise.
  ///
  /// The sheet owns its text controllers (see [_AmountSheet]). They used to be
  /// created here and disposed the moment the sheet returned, while its closing
  /// animation was still running and its fields were still mounted, which threw
  /// "A TextEditingController was used after being disposed" on every Apply.
  /// The original code did the same; this is a fix, not a regression.
  Future<void> _showAmountSheet() async {
    final result = await showAppSheet<({int? lo, int? hi})>(
      context: context,
      backgroundColor: AppColors.surfaceColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (ctx) => _AmountSheet(
        initialMin: _minAmountMinor,
        initialMax: _maxAmountMinor,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _minAmountMinor = result.lo;
      _maxAmountMinor = result.hi;
    });
  }

  // ─── SHEETS ────────────────────────────────────────────────────────────────

  void _showDateFilterSheet() {
    final hasDate = _activePreset != null || _selectedDateRange != null;
    _showFilterSheet<void>(
      title: 'Filter by date',
      rows: [
        _choiceGroup([
          for (final preset in _DatePreset.values)
            AppListRow(
              title: preset.label,
              subtitle: preset != _DatePreset.custom
                  ? _rangeSubtitle(preset)
                  : (_selectedDateRange != null &&
                          _activePreset == _DatePreset.custom
                      ? _formatRange(_selectedDateRange!)
                      : 'Pick start & end dates'),
              leadingIcon: _presetIcon(preset),
              selected: _activePreset == preset,
              onTap: () async {
                Navigator.pop(context);
                if (preset == _DatePreset.custom) {
                  await _pickCustomRange();
                } else {
                  setState(() {
                    _activePreset = preset;
                    _selectedDateRange = preset.resolve();
                  });
                }
              },
            ),
        ]),
        if (hasDate) ...[
          const SizedBox(height: AppSpacing.md),
          _choiceGroup([
            AppListRow(
              title: 'Clear date filter',
              leadingIcon: Icons.clear_rounded,
              destructive: true,
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _activePreset = null;
                  _selectedDateRange = null;
                });
              },
            ),
          ]),
        ],
      ],
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.input,
      initialDateRange: _selectedDateRange ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      helpText: 'SELECT DATE RANGE',
      saveText: 'APPLY',
      // Follow the app's own brightness: the previous hard-coded light scheme
      // produced a white picker on top of the dark AMOLED canvas.
      builder: (context, child) {
        final dark = AppColors.isDark(context);
        final base = dark ? ColorScheme.dark() : ColorScheme.light();
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: base.copyWith(
              primary: AppColors.brand,
              onPrimary: AppColors.onBrand,
              surface: AppColors.surfaceColor(context),
              onSurface: AppColors.textPrimary(context),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _activePreset = _DatePreset.custom;
      });
    }
  }

  /// A filter sheet: a grabber, a title, and one grouped list of choices.
  ///
  /// Built once so every sheet has the same chrome (PanelUI `bottom-sheet`:
  /// grabber, header, scrolling body). The body scrolls when it is taller than
  /// the sheet allows, so the last choice is always reachable at 2x text. The
  /// surface is the themed opaque sheet colour from `showAppSheet`.
  Future<T?> _showFilterSheet<T>({
    required String title,
    required List<Widget> rows,
    String? hint,
  }) {
    return showAppSheet<T>(
      context: context,
      backgroundColor: AppColors.surfaceColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetGrabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs,
                  AppSpacing.page, AppSpacing.sm),
              child: Semantics(
                header: true,
                child: Text(title, style: AppText.h2(ctx)),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hint != null) ...[
                      Text(hint,
                          style: AppText.bodySmall(ctx)
                              .copyWith(color: AppColors.textSecondary(ctx))),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    ...rows,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rows of one sheet as a single grouped surface with hairlines between them
  /// (PanelUI `Item.Group`), not a column of separate tiles.
  Widget _choiceGroup(List<AppListRow> rows) {
    // Every row goes through the same constructor, the last one included: a row
    // passed through untouched kept its default chevron and the last choice of
    // each sheet looked different from the rest.
    return AppListGroup(rows: [
      for (var i = 0; i < rows.length; i++)
        AppListRow(
          title: rows[i].title,
          subtitle: rows[i].subtitle,
          leadingIcon: rows[i].leadingIcon,
          leadingTone: rows[i].leadingTone,
          selected: rows[i].selected,
          destructive: rows[i].destructive,
          onTap: rows[i].onTap,
          semanticLabel: rows[i].semanticLabel,
          showDivider: i != rows.length - 1,
          showChevron: false,
        ),
    ]);
  }

  void _showCategorySheet(TransactionProvider provider) {
    final categories = provider.availableCategories;
    _showFilterSheet<void>(
      title: 'Filter by category',
      rows: [
        _choiceGroup([
          AppListRow(
            title: 'All categories',
            leadingIcon: Icons.select_all_rounded,
            selected: _selectedCategory == null,
            onTap: () {
              setState(() => _selectedCategory = null);
              Navigator.pop(context);
            },
          ),
          for (final cat in categories)
            AppListRow(
              title: cat,
              leadingIcon: CategoryStyle.icon(cat),
              leadingTone: CategoryStyle.color(cat),
              selected: _selectedCategory == cat,
              onTap: () {
                setState(() => _selectedCategory = cat);
                Navigator.pop(context);
              },
            ),
        ]),
      ],
    );
  }

  void _showTypeSheet() {
    _showFilterSheet<void>(
      title: 'Filter by type',
      rows: [
        _choiceGroup([
          AppListRow(
            title: 'All transactions',
            leadingIcon: Icons.select_all_rounded,
            selected: _selectedType == null,
            onTap: () {
              setState(() => _selectedType = null);
              Navigator.pop(context);
            },
          ),
          AppListRow(
            title: 'Expense',
            leadingIcon: Icons.south_west_rounded,
            leadingTone: AppColors.expenseRed,
            selected: _selectedType == TransactionType.expense,
            onTap: () {
              setState(() => _selectedType = TransactionType.expense);
              Navigator.pop(context);
            },
          ),
          AppListRow(
            title: 'Income',
            leadingIcon: Icons.north_east_rounded,
            leadingTone: AppColors.incomeGreen,
            selected: _selectedType == TransactionType.income,
            onTap: () {
              setState(() => _selectedType = TransactionType.income);
              Navigator.pop(context);
            },
          ),
        ]),
      ],
    );
  }

  String _rangeSubtitle(_DatePreset preset) {
    final range = preset.resolve();
    if (range == null) return '';
    final f = DateFormat('d MMM');
    return '${f.format(range.start)} – ${f.format(range.end)}';
  }

  IconData _presetIcon(_DatePreset preset) {
    switch (preset) {
      case _DatePreset.today:
        return Icons.today_rounded;
      case _DatePreset.thisWeek:
        return Icons.view_week_rounded;
      case _DatePreset.thisMonth:
        return Icons.calendar_month_rounded;
      case _DatePreset.last3Months:
        return Icons.date_range_rounded;
      case _DatePreset.custom:
        return Icons.edit_calendar_rounded;
    }
  }

  String _formatRange(DateTimeRange range) {
    final f = DateFormat('d MMM');
    return '${f.format(range.start)} – ${f.format(range.end)}';
  }
}

// ─── ACTIVITY WIDGETS ───────────────────────────────────────────────────────

/// A run of transactions on one day, or the whole list when it is not grouped.
class _Group {
  /// "Today", "Yesterday", "Mon, 9 Nov"; null for an ungrouped (by amount) list.
  final String? title;
  final List<TransactionModel> transactions;

  /// Net of the rows that count (income minus expenses), integer paise.
  final int total;

  const _Group({
    required this.title,
    required this.transactions,
    required this.total,
  });
}

/// The grabber at the top of a filter sheet. Decorative: a screen reader
/// dismisses a sheet with the platform gesture, so it is hidden from semantics.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          margin:
              const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.border(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// The search field: a 48dp rounded field on a quiet surface, with a clear
/// button that keeps the keyboard up (clearing a query is the start of the next
/// one). Filtering is in-memory and memoised, so there is no debounce: a
/// debounce is for a query that costs something (PanelUI `search-bar`).
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      level: AppSurfaceLevel.raised,
      shadow: false,
      bordered: true,
      radius: AppRadius.md,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.md),
            ExcludeSemantics(
              child: Icon(Icons.search_rounded,
                  size: 20, color: AppColors.textTertiary(context)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                style: AppText.body(context).copyWith(
                    color: AppColors.textPrimary(context), fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Search transactions',
                  hintStyle: AppText.body(context).copyWith(
                      color: AppColors.textTertiary(context), fontSize: 14.5),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox(width: AppSpacing.md)
                  : AppIconButton(
                      icon: Icons.close_rounded,
                      semanticLabel: 'Clear search',
                      variant: AppIconButtonVariant.plain,
                      onPressed: onClear,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "11 transactions · ₹4,500 in · ₹3,394 out" for what is currently listed.
///
/// Sums the list the screen already filtered, in integer paise, and counts only
/// rows that count (an excluded row is listed but is in no total) so the line
/// can never disagree with Home or Insights. Announced as one sentence and as
/// a live region, so applying a filter tells a screen reader what it produced.
class _ResultSummary extends StatelessWidget {
  final List<TransactionModel> transactions;

  const _ResultSummary({required this.transactions});

  @override
  Widget build(BuildContext context) {
    var inMinor = 0;
    var outMinor = 0;
    var counted = 0;
    for (final t in transactions) {
      if (t.isExcluded) continue;
      counted++;
      if (t.type == TransactionType.income) {
        inMinor += t.amountMinor;
      } else {
        outMinor += t.amountMinor;
      }
    }
    final n = transactions.length;
    final excluded = n - counted;
    final countText = '$n transaction${n == 1 ? '' : 's'}';
    final muted = AppText.caption(context)
        .copyWith(fontSize: 12.5, color: AppColors.textSecondary(context));
    final inText = Formatters.currency.format(inMinor);
    final outText = Formatters.currency.format(outMinor);

    final spoken = n == 0
        ? 'No transactions'
        : '$countText. $inText in, $outText out'
            '${excluded > 0 ? '. $excluded excluded from totals' : ''}';

    return Semantics(
      liveRegion: true,
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: n == 0
          ? Text('0 transactions', style: muted)
          : Wrap(
              // No dot separators: when the line wraps (an excluded count, a
              // narrow phone) a "·" is left dangling at the end of line one.
              // The words and the money colours already separate the figures.
              spacing: AppSpacing.md,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(countText, style: muted),
                Text(
                  '$inText in',
                  style: muted.copyWith(
                      color: AppColors.incomeGreen,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                Text(
                  '$outText out',
                  style: muted.copyWith(
                      color: AppColors.expenseRed,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                // Listed but not summed. Without this the line reads as a
                // total over all N rows and quietly disagrees with the list.
                if (excluded > 0) ...[
                  Text('$excluded excluded', style: muted),
                ],
              ],
            ),
    );
  }
}

/// One day's rows on a single surface, under a sentence-case date title.
///
/// The title carries the day's net so a long day is readable without adding
/// every row; the figure is a plain signed amount in the money colours, not a
/// badge. Rows are flat (no card each) with an indented hairline between them:
/// the transactions are the content of the surface, not five more cards.
class _DayGroup extends StatelessWidget {
  final String? title;
  final int total;
  final List<TransactionModel> transactions;

  const _DayGroup({
    required this.title,
    required this.total,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final net = total;
    // A day whose rows are all excluded has no net to show; "₹0" would read as
    // a real zero next to a row that plainly has an amount.
    final allExcluded = transactions.every((t) => t.isExcluded);
    final netText = allExcluded
        ? 'Excluded'
        : '${net < 0 ? '−' : (net > 0 ? '+' : '')} ${Formatters.currency.format(net.abs())}'
            .trim();
    final netColor = allExcluded
        ? AppColors.textTertiary(context)
        : (net < 0
            ? AppColors.expenseRed
            : (net > 0
                ? AppColors.incomeGreen
                : AppColors.textTertiary(context)));

    final rows = <Widget>[
      for (var i = 0; i < transactions.length; i++) ...[
        TransactionTile(
          transaction: transactions[i],
          showDate: title == null,
          flat: true,
        ),
        if (i < transactions.length - 1)
          const AppSeparator(indent: 68, endIndent: AppSpacing.md),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(
                  top: AppSpacing.sm, bottom: AppSpacing.sm),
              child: Semantics(
                header: true,
                label: allExcluded
                    ? '$title, excluded from totals'
                    : '$title, net $netText',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.weight(
                                AppText.title(context), FontWeight.w600)
                            .copyWith(
                                fontSize: 13.5,
                                color: AppColors.textSecondary(context)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      netText,
                      maxLines: 1,
                      style: AppText.amount(
                        context,
                        size: 12.5,
                        weight: FontWeight.w600,
                        color: netColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          AppSurface(
            level: AppSurfaceLevel.raised,
            padding: EdgeInsets.zero,
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder shaped like the grouped list that replaces it: a date
/// title and one surface of rows. The same footprint as the loaded state, so
/// nothing moves when the data lands.
class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: SkeletonBox(height: 12, width: 84),
          ),
          AppSurface(
            level: AppSurfaceLevel.raised,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.md),
                    child: Row(
                      children: [
                        SkeletonBox(height: 44, width: 44, radius: 22),
                        SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(height: 14, width: 140),
                              SizedBox(height: AppSpacing.sm),
                              SkeletonBox(height: 10, width: 90),
                            ],
                          ),
                        ),
                        SkeletonBox(height: 16, width: 56),
                      ],
                    ),
                  ),
                  if (i < 3)
                    const AppSeparator(indent: 68, endIndent: AppSpacing.md),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Filter by amount" sheet. Stateful so it can own, and dispose, its two
/// controllers after its own route has finished leaving.
class _AmountSheet extends StatefulWidget {
  final int? initialMin;
  final int? initialMax;

  const _AmountSheet({required this.initialMin, required this.initialMax});

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final TextEditingController _min = TextEditingController(
      text: widget.initialMin == null
          ? ''
          : formatPaise(widget.initialMin!, trimZeroPaise: true));
  late final TextEditingController _max = TextEditingController(
      text: widget.initialMax == null
          ? ''
          : formatPaise(widget.initialMax!, trimZeroPaise: true));
  String? _error;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    int? parse(String s) {
      final t = s.trim();
      return t.isEmpty ? null : parseRupeesToPaise(t);
    }

    try {
      final lo = parse(_min.text);
      final hi = parse(_max.text);
      if (lo != null && hi != null && lo > hi) {
        setState(() => _error = 'Minimum must not exceed maximum.');
        return;
      }
      Navigator.pop(context, (lo: lo, hi: hi));
    } on MoneyParseException {
      setState(() => _error = 'Enter valid amounts.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetGrabber(),
          Semantics(
            header: true,
            child: Text('Filter by amount', style: AppText.h2(context)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('In rupees. Leave a side empty for no limit.',
              style: AppText.bodySmall(context)
                  .copyWith(color: AppColors.textSecondary(context))),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, controller, last) in [
                ('Minimum', _min, false),
                ('Maximum', _max, true),
              ])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: last ? 0 : AppSpacing.sm),
                    child: TextField(
                      controller: controller,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: const [AmountInputFormatter()],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: InputDecoration(
                        labelText: label,
                        prefixText: '₹ ',
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Announced as it appears: a message that only changes colour is
          // invisible to a screen reader.
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 16, color: AppColors.danger),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(error,
                          style: AppText.label(context)
                              .copyWith(color: AppColors.danger)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, (lo: null, hi: null)),
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: AppPrimaryButton(
                  label: 'Apply',
                  sound: SoundEventType.selectionChanged,
                  onPressed: _apply,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
