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
import '../widgets/app_states.dart';
import '../widgets/glossy_pill.dart';
import '../widgets/pressable.dart';
import '../widgets/sms_import_prompt.dart';
import '../widgets/sound_scope.dart';

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
          start: today.subtract(Duration(days: today.weekday - 1)),
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

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      Provider.of<TransactionProvider>(context, listen: false).syncFromSms();
    });
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
        _activePreset != null;

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
                          sound: SoundEventType.buttonTap,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
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
                                    color: AppColors.brand,
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
              // Syncing, the empty variants and the populated list cross-fade
              // into each other instead of popping. The key is the state itself,
              // so editing a filter inside one state does not restart the fade.
              child: AppStateSwap(
                state: _bodyKey(displayList, hasFilters, provider),
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
                                message:
                                    'Try adjusting your search or filters.',
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
                                    onAction: () =>
                                        SmsImportPrompt.show(context),
                                  ))
                        : AppRefreshIndicator(
                            onRefresh: () => Provider.of<TransactionProvider>(
                                    context,
                                    listen: false)
                                .syncFromSms(),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.page,
                                0,
                                AppSpacing.page,
                                AppSpacing.fabClearance,
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
                                      heroScope: 'activity',
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── FILTER / SORT LOGIC (unchanged behaviour) ─────────────────────────────

  /// Which body state the list area is in, used as the [AppStateSwap] key. Each
  /// empty variant gets its own value so switching between them still fades.
  String _bodyKey(List<TransactionModel> displayList, bool hasFilters,
      TransactionProvider provider) {
    if (displayList.isNotEmpty) return 'list';
    if (provider.isSyncing) return 'syncing';
    if (hasFilters) return 'empty-filtered';
    return provider.hasSmsScanStartDate ? 'empty-none' : 'empty-no-start-date';
  }

  List<TransactionModel> _getProcessedList(List<TransactionModel> all) {
    List<TransactionModel> list = all.where((t) {
      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          t.merchant.toLowerCase().contains(query) ||
          t.category.toLowerCase().contains(query) ||
          t.paymentMethod.toLowerCase().contains(query) ||
          t.bankName.toLowerCase().contains(query) ||
          t.amount.toString().contains(query);

      final matchesCategory =
          _selectedCategory == null || t.category == _selectedCategory;
      final matchesType = _selectedType == null || t.type == _selectedType;

      final matchesDate = _selectedDateRange == null ||
          _isWithinRange(t.date, _selectedDateRange!);

      return matchesSearch && matchesCategory && matchesType && matchesDate;
    }).toList();

    if (_sortMode == 'Amount') {
      list.sort((a, b) => _sortDescending
          ? b.amount.compareTo(a.amount)
          : a.amount.compareTo(b.amount));
    } else {
      list.sort((a, b) => _sortDescending
          ? b.date.compareTo(a.date)
          : a.date.compareTo(b.date));
    }

    return list;
  }

  bool _isWithinRange(DateTime date, DateTimeRange range) {
    final s = DateTime(range.start.year, range.start.month, range.start.day);
    final e = DateTime(range.end.year, range.end.month, range.end.day)
        .add(const Duration(days: 1));
    final local = date.toLocal();
    return !local.isBefore(s) && local.isBefore(e);
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedType = null;
      _selectedDateRange = null;
      _activePreset = null;
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: GlossyPill.chip(
          label: label,
          icon: icon,
          trailing: trailing,
          selected: active,
          onTap: onTap,
          sound: SoundEventType.selectionChanged,
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
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.brand,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
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
    final color = danger ? AppColors.danger : (iconColor ?? AppColors.brand);
    return ListTile(
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
          style: AppText.title(context)
              .copyWith(fontSize: 14, color: danger ? AppColors.danger : null)),
      subtitle: subtitle != null
          ? Text(subtitle, style: AppText.body(context).copyWith(fontSize: 11))
          : null,
      trailing:
          selected ? Icon(Icons.check_circle_rounded, color: color) : null,
      onTap: () {
        SoundScope.play(context, SoundEventType.selectionChanged);
        onTap();
      },
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
    // Rendered as the same frosted pill the filter chips use, so the applied
    // filters and the controls that set them read as one family.
    return Semantics(
      button: true,
      label: 'Remove $label filter',
      excludeSemantics: true,
      child: GlossyPill(
        onTap: onRemove,
        sound: SoundEventType.buttonTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.brand),
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
