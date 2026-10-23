import 'package:flutter/material.dart';
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
import '../widgets/app_states.dart';
import '../widgets/pressable.dart';
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

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      Provider.of<TransactionProvider>(context, listen: false).syncFromSms();
    });
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Activity', style: AppText.h1(context)),
                      const Spacer(),
                      if (hasFilters)
                        Pressable(
                          onTap: _clearFilters,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          sound: SoundEventType.selectionChanged,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: AppColors.brand.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text('Clear',
                                style: AppText.label(context).copyWith(
                                    color: AppColors.brandInk(context),
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Track every penny across your accounts',
                      style: AppText.body(context)),
                  const SizedBox(height: AppSpacing.lg),

                  // Search
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceColor(context),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border(context)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        icon: Icon(Icons.search_rounded,
                            color: AppColors.textTertiary(context)),
                        hintText: 'Search merchant, category, amount…',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      ),
                      style: AppText.body(context).copyWith(
                          color: AppColors.textPrimary(context), fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Sort / filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip(
                          icon: Icons.calendar_today_rounded,
                          label: 'Date',
                          active: _sortMode == 'Date',
                          onTap: () => setState(() => _sortMode = 'Date'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _chip(
                          icon: Icons.payments_rounded,
                          label: 'Amount',
                          active: _sortMode == 'Amount',
                          onTap: () => setState(() => _sortMode = 'Amount'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _typeFilterChip(),
                        const SizedBox(width: AppSpacing.sm),
                        _sortDirectionChip(),
                        const SizedBox(width: AppSpacing.sm),
                        _categoryFilterChip(provider),
                        const SizedBox(width: AppSpacing.sm),
                        _dateRangeChip(),
                        const SizedBox(width: AppSpacing.sm),
                        _amountChip(),
                      ],
                    ),
                  ),

                  if (hasFilters)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          if (_selectedCategory != null)
                            _activeBadge(
                              Icons.category_rounded,
                              _selectedCategory!,
                              () => setState(() => _selectedCategory = null),
                            ),
                          if (_selectedType != null)
                            _activeBadge(
                              Icons.swap_horiz_rounded,
                              _selectedType == TransactionType.expense
                                  ? 'Expense'
                                  : 'Income',
                              () => setState(() => _selectedType = null),
                            ),
                          if (_minAmountMinor != null ||
                              _maxAmountMinor != null)
                            _activeBadge(
                              Icons.payments_rounded,
                              _amountLabel(),
                              () => setState(() {
                                _minAmountMinor = null;
                                _maxAmountMinor = null;
                              }),
                            ),
                          if (_activePreset != null ||
                              _selectedDateRange != null)
                            _activeBadge(
                              Icons.date_range_rounded,
                              _activeDateLabel(),
                              () => setState(() {
                                _activePreset = null;
                                _selectedDateRange = null;
                              }),
                            ),
                        ],
                      ),
                    ),

                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '${displayList.length} transaction${displayList.length == 1 ? '' : 's'}',
                    style: AppText.overline(context),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
            Expanded(
              child: displayList.isEmpty && provider.isSyncing
                  ? const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: AppSpacing.page),
                      child: SkeletonList(count: 5),
                    )
                  : displayList.isEmpty
                      ? (hasFilters
                          ? AppEmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No transactions found',
                              message: 'Try adjusting your search or filters.',
                              actionLabel: 'Clear all filters',
                              onAction: _clearFilters,
                            )
                          : provider.hasSmsScanStartDate
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
                                ))
                      : AppRefreshIndicator(
                          onRefresh: () => Provider.of<TransactionProvider>(
                                  context,
                                  listen: false)
                              .syncFromSms(),
                          child: ListView.builder(
                            padding: EdgeInsets.fromLTRB(
                              AppSpacing.page,
                              0,
                              AppSpacing.page,
                              AppSpacing.tabBottomInset(context),
                            ),
                            itemCount: displayList.length,
                            itemBuilder: (context, index) {
                              final tx = displayList[index];

                              bool showHeader = false;
                              if (_sortMode == 'Date') {
                                if (index == 0) {
                                  showHeader = true;
                                } else {
                                  final prev = displayList[index - 1];
                                  showHeader = Formatters.date(prev.date) !=
                                      Formatters.date(tx.date);
                                }
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showHeader)
                                    _sectionHeader(DateFormat('EEE, d MMM')
                                        .format(tx.date)),
                                  TransactionTile(
                                    transaction: tx,
                                    showDate: false,
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── FILTER / SORT LOGIC (unchanged behaviour) ─────────────────────────────

  List<TransactionModel> _getProcessedList(List<TransactionModel> all) {
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

  // ─── CHIPS ─────────────────────────────────────────────────────────────────

  Widget _chip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    IconData? trailing,
  }) {
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      // Chips change a filter, so they report a selection rather than a tap.
      sound: SoundEventType.selectionChanged,
      child: AnimatedContainer(
        duration: AppMotion.respect(context, AppMotion.fast),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? AppColors.brand.withValues(alpha: 0.14)
              : AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: active
                ? AppColors.brand.withValues(alpha: 0.4)
                : AppColors.border(context),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: active
                    ? AppColors.brandInk(context)
                    : AppColors.textSecondary(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.label(context).copyWith(
                fontSize: 12,
                color: active
                    ? AppColors.brandInk(context)
                    : AppColors.textSecondary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              Icon(trailing,
                  size: 15,
                  color: active
                      ? AppColors.brandInk(context)
                      : AppColors.textSecondary(context)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeFilterChip() {
    final label = switch (_selectedType) {
      TransactionType.expense => 'Expense',
      TransactionType.income => 'Income',
      null => 'Type',
    };
    return _chip(
      icon: Icons.swap_horiz_rounded,
      label: label,
      active: _selectedType != null,
      onTap: _showTypeSheet,
      trailing: Icons.arrow_drop_down,
    );
  }

  Widget _sortDirectionChip() {
    final isDateSort = _sortMode == 'Date';
    final label = _sortDescending
        ? (isDateSort ? 'Newest' : 'Highest')
        : (isDateSort ? 'Oldest' : 'Lowest');
    return _chip(
      icon: _sortDescending
          ? Icons.arrow_downward_rounded
          : Icons.arrow_upward_rounded,
      label: label,
      active: false,
      onTap: () => setState(() => _sortDescending = !_sortDescending),
    );
  }

  Widget _categoryFilterChip(TransactionProvider provider) {
    return _chip(
      icon: Icons.category_rounded,
      label: _selectedCategory ?? 'Category',
      active: _selectedCategory != null,
      onTap: () => _showCategorySheet(provider),
      trailing: Icons.arrow_drop_down,
    );
  }

  Widget _dateRangeChip() {
    final active = _activePreset != null || _selectedDateRange != null;
    return _chip(
      icon: Icons.date_range_rounded,
      label: active ? _activeDateLabel() : 'Date Range',
      active: active,
      onTap: _showDateFilterSheet,
      trailing: Icons.arrow_drop_down,
    );
  }

  Widget _amountChip() {
    final active = _minAmountMinor != null || _maxAmountMinor != null;
    return _chip(
      icon: Icons.payments_outlined,
      label: active ? _amountLabel() : 'Amount range',
      active: active,
      onTap: _showAmountSheet,
      trailing: Icons.arrow_drop_down,
    );
  }

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
  Future<void> _showAmountSheet() async {
    final minCtrl = TextEditingController(
        text: _minAmountMinor == null
            ? ''
            : formatPaise(_minAmountMinor!, trimZeroPaise: true));
    final maxCtrl = TextEditingController(
        text: _maxAmountMinor == null
            ? ''
            : formatPaise(_maxAmountMinor!, trimZeroPaise: true));
    final result = await showModalBottomSheet<({int? lo, int? hi})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              MediaQuery.viewInsetsOf(ctx).bottom + AppSpacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                Text('Filter by amount', style: AppText.h2(ctx)),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    for (final entry in [
                      ('Min ₹', minCtrl),
                      ('Max ₹', maxCtrl)
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: TextField(
                            controller: entry.$2,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(labelText: entry.$1),
                          ),
                        ),
                      ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(error!,
                        style: AppText.label(ctx)
                            .copyWith(color: AppColors.expenseRed)),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, (lo: null, hi: null)),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        int? parse(String s) {
                          final t = s.trim();
                          return t.isEmpty ? null : parseRupeesToPaise(t);
                        }

                        try {
                          final lo = parse(minCtrl.text);
                          final hi = parse(maxCtrl.text);
                          if (lo != null && hi != null && lo > hi) {
                            setSheet(() => error = 'Min must not exceed max.');
                            return;
                          }
                          Navigator.pop(ctx, (lo: lo, hi: hi));
                        } on MoneyParseException {
                          setSheet(() => error = 'Enter valid amounts.');
                        }
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    minCtrl.dispose();
    maxCtrl.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _minAmountMinor = result.lo;
      _maxAmountMinor = result.hi;
    });
  }
  // ─── SHEETS ────────────────────────────────────────────────────────────────

  void _showDateFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) {
        // Scrollable so every preset stays reachable even when the clear
        // action is appended and the sheet is height-capped.
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              Text('Filter by date', style: AppText.h2(context)),
              const SizedBox(height: AppSpacing.lg),
              ..._DatePreset.values.map((preset) {
                final isSelected = _activePreset == preset;
                return _sheetTile(
                  icon: _presetIcon(preset),
                  title: preset.label,
                  subtitle: preset != _DatePreset.custom
                      ? _rangeSubtitle(preset)
                      : (_selectedDateRange != null &&
                              _activePreset == _DatePreset.custom
                          ? _formatRange(_selectedDateRange!)
                          : 'Pick start & end dates'),
                  selected: isSelected,
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (preset == _DatePreset.custom) {
                      await _pickCustomRange();
                    } else {
                      setState(() {
                        _activePreset = preset;
                        _selectedDateRange = preset.resolve();
                      });
                    }
                  },
                );
              }),
              if (_activePreset != null || _selectedDateRange != null) ...[
                const Divider(),
                _sheetTile(
                  icon: Icons.clear_rounded,
                  title: 'Clear date filter',
                  selected: false,
                  danger: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _activePreset = null;
                      _selectedDateRange = null;
                    });
                  },
                ),
              ],
            ],
          ),
        );
      },
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
              onPrimary: Colors.white,
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

  void _showCategorySheet(TransactionProvider provider) {
    final categories = provider.availableCategories;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            Text('Filter by category', style: AppText.h2(context)),
            const SizedBox(height: AppSpacing.md),
            _sheetTile(
              icon: Icons.select_all_rounded,
              title: 'All categories',
              selected: _selectedCategory == null,
              onTap: () {
                setState(() => _selectedCategory = null);
                Navigator.pop(ctx);
              },
            ),
            ...categories.map((cat) => _sheetTile(
                  icon: CategoryStyle.icon(cat),
                  iconColor: CategoryStyle.color(cat),
                  title: cat,
                  selected: _selectedCategory == cat,
                  onTap: () {
                    setState(() => _selectedCategory = cat);
                    Navigator.pop(ctx);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showTypeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            Text('Filter by type', style: AppText.h2(context)),
            const SizedBox(height: AppSpacing.md),
            _sheetTile(
              icon: Icons.select_all_rounded,
              title: 'All transactions',
              selected: _selectedType == null,
              onTap: () {
                setState(() => _selectedType = null);
                Navigator.pop(ctx);
              },
            ),
            _sheetTile(
              icon: Icons.arrow_upward_rounded,
              iconColor: AppColors.expenseRed,
              title: 'Expense',
              selected: _selectedType == TransactionType.expense,
              onTap: () {
                setState(() => _selectedType = TransactionType.expense);
                Navigator.pop(ctx);
              },
            ),
            _sheetTile(
              icon: Icons.arrow_downward_rounded,
              iconColor: AppColors.incomeGreen,
              title: 'Income',
              selected: _selectedType == TransactionType.income,
              onTap: () {
                setState(() => _selectedType = TransactionType.income);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
    Color? iconColor,
    bool danger = false,
  }) {
    final color =
        danger ? AppColors.danger : (iconColor ?? AppColors.brandInk(context));
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        sound: SoundEventType.selectionChanged,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          title: Text(title,
              style: AppText.title(context).copyWith(
                  fontSize: 14, color: danger ? AppColors.danger : null)),
          subtitle: subtitle != null
              ? Text(subtitle,
                  style: AppText.body(context).copyWith(fontSize: 11))
              : null,
          trailing:
              selected ? Icon(Icons.check_circle_rounded, color: color) : null,
          onTap: null,
        ),
      ),
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

  // ─── SMALL WIDGETS ───────────────────────────────────────────────────────

  Widget _activeBadge(IconData icon, String label, VoidCallback onRemove) {
    // The whole chip removes the filter: the close icon alone was a ~23px
    // target, far under the 48dp guideline, and it carried no semantics.
    return Pressable(
      onTap: onRemove,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Semantics(
        button: true,
        label: 'Remove $label filter',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceColor(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.brandInk(context)),
              const SizedBox(width: 6),
              Text(label,
                  style: AppText.label(context).copyWith(
                      fontSize: 12, color: AppColors.textPrimary(context))),
              const SizedBox(width: 6),
              Icon(Icons.close_rounded,
                  size: 15, color: AppColors.textTertiary(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: AppText.overline(context)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Divider(
                color: AppColors.border(context).withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

/// Small drag handle used by the filter bottom sheets.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.border(context),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
