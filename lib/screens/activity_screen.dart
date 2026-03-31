import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';
import '../widgets/transaction_tile.dart';
import '../utils/app_colors.dart';
import '../utils/formatters.dart';

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

  /// Returns the DateTimeRange for a given preset.
  /// Returns null for [_DatePreset.custom] — caller must provide a range.
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
        return null; // caller opens date picker
    }
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _sortMode = 'Date'; // Date | Amount
  String? _selectedCategory;
  DateTimeRange? _selectedDateRange;
  _DatePreset? _activePreset; // tracks which preset chip is active
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      Provider.of<TransactionProvider>(context, listen: false).syncFromSms();
    });
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);
    final displayList = _getProcessedList(provider.transactions);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'SpendSense',
          style: TextStyle(
              color: AppColors.primaryPink, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedCategory != null ||
              _selectedDateRange != null ||
              _activePreset != null)
            TextButton(
              onPressed: _clearFilters,
              child: Text(
                'Clear filters',
                style: TextStyle(color: AppColors.primaryPurple, fontSize: 12),
              ),
            ),
          IconButton(
            icon: Icon(Icons.notifications_none, color: Colors.blueGrey),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Activity',
                    style:
                        TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                Text('Track every penny across your accounts',
                    style: TextStyle(color: Colors.grey)),
                SizedBox(height: 20),

                // ── SEARCH ────────────────────────────────────────────────
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Color(0xFFF1F3F6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      icon: Icon(Icons.search, color: Colors.grey),
                      hintText: 'Search transactions...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                SizedBox(height: 16),

                // ── SORT CHIPS ────────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _sortChip(
                        icon: Icons.calendar_today_rounded,
                        label: 'Date',
                        isSelected: _sortMode == 'Date',
                        onTap: () => setState(() => _sortMode = 'Date'),
                      ),
                      SizedBox(width: 10),
                      _sortChip(
                        icon: Icons.payments_rounded,
                        label: 'Amount',
                        isSelected: _sortMode == 'Amount',
                        onTap: () => setState(() => _sortMode = 'Amount'),
                      ),
                      SizedBox(width: 10),
                      _categoryFilterChip(provider),
                      SizedBox(width: 10),
                      // ── DATE RANGE CHIP ──────────────────────────────────
                      // FIX: was a single static chip — now opens a rich
                      // bottom-sheet with presets + custom date picker
                      _dateRangeChip(),
                    ],
                  ),
                ),

                // ── ACTIVE FILTER BADGES ──────────────────────────────────
                if (_selectedCategory != null ||
                    _selectedDateRange != null ||
                    _activePreset != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (_selectedCategory != null)
                          _activeBadge(
                            '📂 $_selectedCategory',
                            () => setState(() => _selectedCategory = null),
                          ),
                        if (_activePreset != null || _selectedDateRange != null)
                          _activeBadge(
                            '📅 ${_activeDateLabel()}',
                            () => setState(() {
                              _activePreset = null;
                              _selectedDateRange = null;
                            }),
                          ),
                      ],
                    ),
                  ),

                SizedBox(height: 12),
              ],
            ),
          ),

          // ── RESULTS COUNT ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '${displayList.length} transaction${displayList.length == 1 ? '' : 's'}',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(height: 8),

          // ── TRANSACTION LIST ─────────────────────────────────────────────
          Expanded(
            child: provider.isSyncing
                ? Center(child: CircularProgressIndicator())
                : displayList.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: () => Provider.of<TransactionProvider>(
                                context,
                                listen: false)
                            .syncFromSms(),
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 20),
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
                                  _sectionHeader(
                                      Formatters.date(tx.date).toUpperCase()),
                                TransactionTile(transaction: tx),
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── FILTER / SORT LOGIC ──────────────────────────────────────────────────

  List<TransactionModel> _getProcessedList(List<TransactionModel> all) {
    List<TransactionModel> list = all.where((t) {
      final matchesSearch =
          t.merchant.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              t.category.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesCategory =
          _selectedCategory == null || t.category == _selectedCategory;

      // FIX: compare only date components (ignore time) to avoid off-by-one
      // on the end-date boundary. Previously "end + 1 day" was a workaround
      // that could accidentally include transactions from the next day.
      final matchesDate = _selectedDateRange == null ||
          _isWithinRange(t.date, _selectedDateRange!);

      return matchesSearch && matchesCategory && matchesDate;
    }).toList();

    if (_sortMode == 'Amount') {
      list.sort((a, b) => b.amount.compareTo(a.amount));
    } else {
      list.sort((a, b) => b.date.compareTo(a.date));
    }

    return list;
  }

  /// Inclusive date-only range check.
  bool _isWithinRange(DateTime date, DateTimeRange range) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(range.start.year, range.start.month, range.start.day);
    final e = DateTime(range.end.year, range.end.month, range.end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = null;
      _selectedDateRange = null;
      _activePreset = null;
    });
  }

  String _activeDateLabel() {
    if (_activePreset == _DatePreset.custom && _selectedDateRange != null) {
      return _formatRange(_selectedDateRange!);
    }
    return _activePreset?.label ??
        (_selectedDateRange != null ? _formatRange(_selectedDateRange!) : '');
  }

  // ─── DATE RANGE CHIP & SHEET ──────────────────────────────────────────────

  Widget _dateRangeChip() {
    final isActive = _activePreset != null || _selectedDateRange != null;

    return GestureDetector(
      onTap:
          _showDateFilterSheet, // FIX: was calling showDateRangePicker directly
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Color(0xFFE8F5E9) : Color(0xFFE8ECEF),
          borderRadius: BorderRadius.circular(20),
          border: isActive ? Border.all(color: Colors.green, width: 1.5) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.date_range_rounded,
                size: 16, color: isActive ? Colors.green[700] : Colors.black54),
            SizedBox(width: 6),
            Text(
              isActive ? _activeDateLabel() : 'Date Range',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isActive ? Colors.green[700] : Colors.black54,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 16, color: isActive ? Colors.green[700] : Colors.black54),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet with preset periods + a "Custom Range" tile that opens
  /// Flutter's date range picker.
  ///
  /// ROOT CAUSE OF BUG #2:
  /// The original _pickDateRange() called showDateRangePicker() directly,
  /// which on some devices/Flutter versions renders without the "Custom"
  /// entry-point because the Material date picker needs an initialEntryMode
  /// override. More critically, there was no way to pick named periods like
  /// "This Month". This sheet solves both issues.
  void _showDateFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Filter by Date',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),

              // Preset options
              ..._DatePreset.values.map((preset) {
                final isSelected = _activePreset == preset;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        isSelected ? AppColors.primaryPurple : Colors.grey[100],
                    child: Icon(
                      _presetIcon(preset),
                      size: 18,
                      color: isSelected ? Colors.white : Colors.grey[600],
                    ),
                  ),
                  title: Text(preset.label,
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: preset != _DatePreset.custom
                      ? Text(
                          _rangeSubtitle(preset),
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        )
                      : Text(
                          _selectedDateRange != null &&
                                  _activePreset == _DatePreset.custom
                              ? _formatRange(_selectedDateRange!)
                              : 'Pick start & end dates',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: AppColors.primaryPurple)
                      : null,
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
              }).toList(),

              // Clear option if something is active
              if (_activePreset != null || _selectedDateRange != null) ...[
                Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.red[50],
                    child: Icon(Icons.clear, size: 18, color: Colors.red),
                  ),
                  title: Text('Clear date filter',
                      style: TextStyle(color: Colors.red)),
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

  /// Opens Flutter's date range picker with initialEntryMode forced to
  /// [DatePickerEntryMode.input] so the custom date fields are always visible.
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      // FIX: force input mode so the text fields are always shown —
      // calendar-only mode hides them on some screen sizes/locales.
      initialEntryMode: DatePickerEntryMode.input,
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      helpText: 'SELECT DATE RANGE',
      saveText: 'APPLY',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.primaryPurple,
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

  String _rangeSubtitle(_DatePreset preset) {
    final range = preset.resolve();
    if (range == null) return '';
    final f = DateFormat('d MMM');
    return '${f.format(range.start)} – ${f.format(range.end)}';
  }

  IconData _presetIcon(_DatePreset preset) {
    switch (preset) {
      case _DatePreset.today:
        return Icons.today;
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

  // ─── WIDGETS ──────────────────────────────────────────────────────────────

  Widget _sortChip({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFE0E0FF) : Color(0xFFE8ECEF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? AppColors.primaryPurple : Colors.black54),
            SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isSelected ? AppColors.primaryPurple : Colors.black54,
                )),
          ],
        ),
      ),
    );
  }

  Widget _categoryFilterChip(TransactionProvider provider) {
    final isActive = _selectedCategory != null;
    return GestureDetector(
      onTap: () => _showCategorySheet(provider),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Color(0xFFFFE0F0) : Color(0xFFE8ECEF),
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? Border.all(color: AppColors.primaryPink, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(Icons.category_rounded,
                size: 16,
                color: isActive ? AppColors.primaryPink : Colors.black54),
            SizedBox(width: 6),
            Text(
              isActive ? _selectedCategory! : 'Category',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isActive ? AppColors.primaryPink : Colors.black54,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 16,
                color: isActive ? AppColors.primaryPink : Colors.black54),
          ],
        ),
      ),
    );
  }

  void _showCategorySheet(TransactionProvider provider) {
    final categories = provider.availableCategories;
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter by Category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: _selectedCategory == null
                    ? AppColors.primaryPurple
                    : Colors.grey[200],
                child: Icon(Icons.select_all,
                    color:
                        _selectedCategory == null ? Colors.white : Colors.grey,
                    size: 18),
              ),
              title: Text('All Categories',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                setState(() => _selectedCategory = null);
                Navigator.pop(ctx);
              },
            ),
            ...categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      isSelected ? AppColors.primaryPink : Color(0xFFE8ECEF),
                  child:
                      Text(_categoryEmoji(cat), style: TextStyle(fontSize: 16)),
                ),
                title: Text(cat, style: TextStyle(fontWeight: FontWeight.w500)),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: AppColors.primaryPink)
                    : null,
                onTap: () {
                  setState(() => _selectedCategory = cat);
                  Navigator.pop(ctx);
                },
              );
            }).toList(),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _activeBadge(String label, VoidCallback onRemove) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12)),
          SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          SizedBox(width: 10),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
            SizedBox(height: 12),
            Text('No transactions found',
                style:
                    TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Try adjusting your filters',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            if (_selectedCategory != null ||
                _selectedDateRange != null ||
                _activePreset != null) ...[
              SizedBox(height: 16),
              TextButton(
                onPressed: _clearFilters,
                child: Text('Clear all filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _categoryEmoji(String cat) {
    const map = {
      'Food': '🍔',
      'Shopping': '🛍',
      'Fuel': '⛽',
      'Travel': '🚗',
      'Bills': '💡',
      'Transfer': '💸',
      'Cash': '💵',
      'Entertainment': '🎬',
      'Health': '🏥',
      'Other': '📦',
      'Others': '📦',
    };
    return map[cat] ?? '📦';
  }
}
