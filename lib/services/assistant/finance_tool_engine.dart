import 'dart:math';

import 'package:intl/intl.dart';

import '../../models/assistant_models.dart';
import '../../models/recurring_plan.dart';
import '../../models/transaction_model.dart';
import '../bill_detection_service.dart';
import '../../utils/period_math.dart';
import 'assistant_date_resolver.dart';
import 'merchant_matcher.dart';

class FinanceToolException implements Exception {
  final String code;
  final String message;

  const FinanceToolException(this.code, this.message);

  Map<String, dynamic> toJson() => {'error': code, 'message': message};

  @override
  String toString() => 'FinanceToolException($code): $message';
}

class FinanceToolResult {
  final String tool;
  final Map<String, dynamic> data;
  final AssistantPendingAction? pending;

  const FinanceToolResult({
    required this.tool,
    required this.data,
    this.pending,
  });
}

/// Typed, validated finance operations over local records.
///
/// Gemini can only reach the names in [remoteToolNames]; apply and undo are
/// deliberately absent from that set and can only be reached after an explicit
/// in-app confirmation. No tool accepts SQL, paths, code or arbitrary storage
/// access.
class FinanceToolEngine {
  static const Set<String> remoteReadOnlyTools = {
    'search_transactions',
    'get_spending_summary',
    'group_transactions_by_merchant',
    'get_category_summary',
    'get_monthly_comparison',
    'list_bills',
    'get_transaction_details',
    'find_duplicate_transactions',
  };

  static const Set<String> remotePreviewTools = {
    'preview_transaction_exclusion',
    'preview_transaction_deletion',
  };

  static const Set<String> remoteToolNames = {
    ...remoteReadOnlyTools,
    ...remotePreviewTools,
  };

  static const int maxPreviewRecords = AssistantPendingAction.maxRecords;
  static const int maxSearchLimit = 50;
  static const int maxAliases = 10;

  final List<TransactionModel> transactions;
  final List<RecurringPlan> plans;
  final Set<String> hiddenBillKeys;
  final DateTime now;
  final BillDetectionService billDetector;

  const FinanceToolEngine({
    required this.transactions,
    required this.plans,
    required this.now,
    this.hiddenBillKeys = const {},
    this.billDetector = const BillDetectionService(),
  });

  FinanceToolResult execute(String name, Map<String, dynamic> arguments) {
    if (!remoteToolNames.contains(name)) {
      throw FinanceToolException(
        'unknown_tool',
        'That assistant action is not available.',
      );
    }
    switch (name) {
      case 'search_transactions':
        return _search(arguments);
      case 'get_spending_summary':
        return _spendingSummary(arguments);
      case 'group_transactions_by_merchant':
        return _merchantGroups(arguments);
      case 'get_category_summary':
        return _categorySummary(arguments);
      case 'get_monthly_comparison':
        return _monthlyComparison(arguments);
      case 'list_bills':
        return _listBills(arguments);
      case 'get_transaction_details':
        return _details(arguments);
      case 'find_duplicate_transactions':
        return _duplicates(arguments);
      case 'preview_transaction_exclusion':
        return _previewChange(arguments, AssistantChangeType.exclusion);
      case 'preview_transaction_deletion':
        return _previewChange(arguments, AssistantChangeType.deletion);
      default:
        throw FinanceToolException(
          'unknown_tool',
          'That assistant action is not available.',
        );
    }
  }

  // ── Read-only tools ───────────────────────────────────────────────────────

  FinanceToolResult _search(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {
      'query',
      'merchant',
      'merchantAliases',
      'brand',
      'category',
      'type',
      'includeExcluded',
      'startDate',
      'endDate',
      'limit',
      'offset',
      'sort',
    });
    final window = _window(args);
    final limit =
        _intArg(args, 'limit', fallback: 20, min: 1, max: maxSearchLimit);
    final offset = _intArg(args, 'offset', fallback: 0, min: 0, max: 100000);
    final sort = _stringArg(args, 'sort', fallback: 'date_desc');
    if (!const {'date_desc', 'date_asc', 'amount_desc', 'amount_asc'}
        .contains(sort)) {
      throw const FinanceToolException(
          'invalid_argument', 'The sort order is not supported.');
    }
    final matched = _filter(args, window, defaultIncludeExcluded: true);
    final sorted = [...matched]..sort(_comparator(sort));
    final page = sorted.skip(offset).take(limit).toList();
    final totals = _totals(matched);
    return FinanceToolResult(tool: 'search_transactions', data: {
      'range': _windowJson(window),
      'matchedCount': matched.length,
      'returnedCount': page.length,
      'offset': offset,
      'limit': limit,
      'totals': totals,
      'transactions': [
        for (final tx in page)
          AssistantTransactionView.fromTransaction(tx).toToolJson(),
      ],
      if (page.isEmpty) 'empty': true,
    });
  }

  FinanceToolResult _spendingSummary(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {
      'merchant',
      'merchantAliases',
      'brand',
      'category',
      'startDate',
      'endDate',
      'includeIncome',
    });
    final window = _window(args);
    // Summary always excludes excluded rows from spending; the filter is
    // intentionally not user/model controlled.
    final matched = _filter(args, window, defaultIncludeExcluded: true);
    final totals = _totals(matched);
    return FinanceToolResult(tool: 'get_spending_summary', data: {
      'range': _windowJson(window),
      'spendingMinor': totals['expenseMinor'],
      'incomeMinor': totals['incomeMinor'],
      'excludedMinor': totals['excludedMinor'],
      'investmentMinor': totals['investmentMinor'],
      'transferMinor': totals['transferMinor'],
      'expenseCount': totals['expenseCount'],
      'incomeCount': totals['incomeCount'],
      'excludedCount': totals['excludedCount'],
      'transactionCount': totals['totalCount'],
      'transactionsIncludedInSpending': totals['spendingCount'],
      'note':
          'Spending counts non-excluded expense rows only. Investment transfers are shown separately and remain part of spending unless the user excludes them.',
    });
  }

  FinanceToolResult _merchantGroups(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {
      'merchant',
      'merchantAliases',
      'brand',
      'category',
      'startDate',
      'endDate',
      'includeExcluded',
      'limit',
    });
    final window = _window(args);
    final limit =
        _intArg(args, 'limit', fallback: 20, min: 1, max: maxSearchLimit);
    final includeExcluded = _boolArg(args, 'includeExcluded', fallback: false);
    final matched = _filter(
      args,
      window,
      defaultIncludeExcluded: includeExcluded,
    );

    final groups = <String, _MerchantGroup>{};
    for (final tx in matched) {
      final key = MerchantMatcher.normalize(tx.merchant);
      final group = groups.putIfAbsent(
        key.isEmpty ? 'unknown' : key,
        () => _MerchantGroup(tx.merchant.isEmpty ? 'Unknown' : tx.merchant),
      );
      group.add(tx);
    }
    final sorted = groups.values.toList()
      ..sort((a, b) => b.expenseMinor.compareTo(a.expenseMinor));
    final page = sorted.take(limit).toList();
    return FinanceToolResult(tool: 'group_transactions_by_merchant', data: {
      'range': _windowJson(window),
      'matchedCount': matched.length,
      'groupCount': sorted.length,
      'returnedCount': page.length,
      'groups': [
        for (final g in page)
          {
            'merchant': g.label,
            'count': g.count,
            'expenseMinor': g.expenseMinor,
            'incomeMinor': g.incomeMinor,
            'excludedCount': g.excludedCount,
            'excludedMinor': g.excludedMinor,
            'investmentMinor': g.investmentMinor,
            'firstDate': DateFormat('yyyy-MM-dd').format(g.firstDate),
            'lastDate': DateFormat('yyyy-MM-dd').format(g.lastDate),
          },
      ],
    });
  }

  FinanceToolResult _categorySummary(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {
      'merchant',
      'merchantAliases',
      'brand',
      'startDate',
      'endDate',
      'limit',
    });
    final window = _window(args);
    final limit = _intArg(args, 'limit', fallback: 20, min: 1, max: 50);
    final matched = _filter(args, window, defaultIncludeExcluded: false);
    final totals = <String, int>{};
    final counts = <String, int>{};
    for (final tx in matched) {
      if (tx.type != TransactionType.expense) continue;
      totals[tx.category] = (totals[tx.category] ?? 0) + tx.amountMinor;
      counts[tx.category] = (counts[tx.category] ?? 0) + 1;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final allSpending = totals.values.fold<int>(0, (a, b) => a + b);
    return FinanceToolResult(tool: 'get_category_summary', data: {
      'range': _windowJson(window),
      'totalSpendingMinor': allSpending,
      'categories': [
        for (final e in entries.take(limit))
          {
            'category': e.key,
            'amountMinor': e.value,
            'count': counts[e.key] ?? 0,
            'sharePercent': allSpending == 0
                ? 0.0
                : double.parse(
                    ((e.value * 100) / allSpending).toStringAsFixed(1)),
          },
      ],
    });
  }

  FinanceToolResult _monthlyComparison(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {
      'month',
      'merchant',
      'merchantAliases',
      'brand',
      'category',
    });
    final monthArg = _optionalString(args, 'month');
    DateTime currentStart;
    if (monthArg != null) {
      final parsed = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(monthArg);
      final month = parsed == null ? null : int.tryParse(parsed.group(2)!);
      if (parsed == null || month == null || month < 1 || month > 12) {
        throw const FinanceToolException(
            'invalid_argument', 'month must use YYYY-MM.');
      }
      currentStart = DateTime(int.parse(parsed.group(1)!), month, 1);
    } else {
      currentStart = DateTime(now.year, now.month, 1);
    }
    final currentEnd = _monthEnd(currentStart, now);
    final previousStart =
        DateTime(currentStart.year, currentStart.month - 1, 1);
    final previousEnd = DateTime(currentStart.year, currentStart.month, 0);
    final currentWindow = AssistantDateWindow.range(
      start: currentStart,
      end: currentEnd,
      label: DateFormat('MMMM yyyy').format(currentStart),
    );
    final previousWindow = AssistantDateWindow.range(
      start: previousStart,
      end: previousEnd,
      label: DateFormat('MMMM yyyy').format(previousStart),
    );
    final current =
        _totals(_filter(args, currentWindow, defaultIncludeExcluded: false));
    final previous =
        _totals(_filter(args, previousWindow, defaultIncludeExcluded: false));
    final delta =
        (current['expenseMinor'] as int) - (previous['expenseMinor'] as int);
    final percent = (previous['expenseMinor'] as int) == 0
        ? (current['expenseMinor'] as int) == 0
            ? 0.0
            : 100.0
        : (delta * 100.0) / (previous['expenseMinor'] as int);

    final currentByCategory = _categoryTotals(currentWindow);
    final previousByCategory = _categoryTotals(previousWindow);
    final categoryDrivers = _drivers(currentByCategory, previousByCategory);
    final currentByMerchant = _merchantTotals(currentWindow);
    final previousByMerchant = _merchantTotals(previousWindow);
    final merchantDrivers = _drivers(currentByMerchant, previousByMerchant);

    return FinanceToolResult(tool: 'get_monthly_comparison', data: {
      'current': {
        'label': currentWindow.preciseLabel,
        'spendingMinor': current['expenseMinor'],
        'incomeMinor': current['incomeMinor'],
      },
      'previous': {
        'label': previousWindow.preciseLabel,
        'spendingMinor': previous['expenseMinor'],
        'incomeMinor': previous['incomeMinor'],
      },
      'deltaMinor': delta,
      'percentChange': double.parse(percent.toStringAsFixed(2)),
      'categoryDrivers': [
        for (final d in categoryDrivers.take(5))
          {
            'category': d.label,
            'currentMinor': d.currentMinor,
            'previousMinor': d.previousMinor,
            'deltaMinor': d.deltaMinor,
          },
      ],
      'merchantDrivers': [
        for (final d in merchantDrivers.take(5))
          {
            'merchant': d.label,
            'currentMinor': d.currentMinor,
            'previousMinor': d.previousMinor,
            'deltaMinor': d.deltaMinor,
          },
      ],
    });
  }

  FinanceToolResult _listBills(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {'status', 'limit'});
    final status = _stringArg(args, 'status', fallback: 'unpaid');
    if (!const {'unpaid', 'paid', 'all'}.contains(status)) {
      throw const FinanceToolException(
          'invalid_argument', 'status must be unpaid, paid or all.');
    }
    final limit = _intArg(args, 'limit', fallback: 20, min: 1, max: 50);
    final views = billDetector.detect(
      plans: plans,
      transactions: transactions,
      today: now,
      hiddenBillKeys: hiddenBillKeys,
    );
    final filtered = views
        .where((view) {
          if (status == 'all') return true;
          final paid = view.state == BillState.paid;
          return status == 'paid' ? paid : !paid;
        })
        .take(limit)
        .toList();
    return FinanceToolResult(tool: 'list_bills', data: {
      'status': status,
      'count': filtered.length,
      'bills': [
        for (final view in filtered)
          {
            'title': view.title,
            'category': view.category,
            'amountMinor': view.amountMinor,
            'dueDate': view.dueDate == null
                ? null
                : DateFormat('yyyy-MM-dd').format(view.dueDate!),
            'state': view.state.label,
            'isRecurring':
                view.plan != null || (view.autoBill?.isRecurring ?? false),
            'confidence': view.confidence,
          },
      ],
    });
  }

  FinanceToolResult _details(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {'transactionIds'});
    final ids = _stringListArg(args, 'transactionIds', min: 1, max: 50);
    final byId = {for (final tx in transactions) tx.id: tx};
    final found = <TransactionModel>[];
    final missing = <String>[];
    for (final id in ids) {
      final tx = byId[id];
      if (tx == null) {
        missing.add(id);
      } else {
        found.add(tx);
      }
    }
    if (found.isEmpty) {
      throw const FinanceToolException(
          'transaction_not_found', 'No transaction matches those ids.');
    }
    return FinanceToolResult(tool: 'get_transaction_details', data: {
      'transactions': [
        for (final tx in found)
          AssistantTransactionView.fromTransaction(tx).toToolJson(),
      ],
      'missingIds': missing,
    });
  }

  FinanceToolResult _duplicates(Map<String, dynamic> args) {
    _rejectUnknownKeys(args, const {
      'merchant',
      'merchantAliases',
      'brand',
      'category',
      'startDate',
      'endDate',
      'limit',
    });
    final window = _window(args);
    final limit = _intArg(args, 'limit', fallback: 20, min: 1, max: 50);
    final matched = _filter(args, window, defaultIncludeExcluded: true);
    final groups = <String, List<TransactionModel>>{};
    for (final tx in matched) {
      final day = DateFormat('yyyy-MM-dd').format(tx.date.toLocal());
      final merchant = MerchantMatcher.normalize(tx.merchant);
      final key = '${tx.type.name}|${tx.amountMinor}|$day|$merchant';
      groups.putIfAbsent(key, () => []).add(tx);
    }
    final duplicates = groups.values.where((g) => g.length > 1).toList()
      ..sort((a, b) => b.first.amountMinor.compareTo(a.first.amountMinor));
    final extraCopies = duplicates.fold<int>(0, (sum, g) => sum + g.length - 1);
    final extraAmount = duplicates.fold<int>(
      0,
      (sum, g) =>
          sum +
          (g.length - 1) *
              (g.first.type == TransactionType.expense
                  ? g.first.amountMinor
                  : 0),
    );
    return FinanceToolResult(tool: 'find_duplicate_transactions', data: {
      'range': _windowJson(window),
      'groupCount': duplicates.length,
      'extraCopyCount': extraCopies,
      'potentialDuplicateExpenseMinor': extraAmount,
      'groups': [
        for (final group in duplicates.take(limit))
          {
            'merchant': group.first.merchant,
            'date': DateFormat('yyyy-MM-dd').format(group.first.date.toLocal()),
            'amountMinor': group.first.amountMinor,
            'type': group.first.type == TransactionType.income
                ? 'income'
                : 'expense',
            'count': group.length,
            'transactions': [
              for (final tx in group)
                AssistantTransactionView.fromTransaction(tx).toToolJson(),
            ],
          },
      ],
    });
  }

  // ── Preview tools ─────────────────────────────────────────────────────────

  FinanceToolResult _previewChange(
    Map<String, dynamic> args,
    AssistantChangeType type,
  ) {
    _rejectUnknownKeys(args, const {
      'transactionIds',
      'startDate',
      'endDate',
    });
    final ids = _stringListArg(
      args,
      'transactionIds',
      min: 1,
      max: maxPreviewRecords,
    );
    final window = _window(args);
    final byId = {for (final tx in transactions) tx.id: tx};
    final missing = [
      for (final id in ids)
        if (!byId.containsKey(id)) id
    ];
    if (missing.isNotEmpty) {
      throw FinanceToolException(
        'transaction_not_found',
        missing.length == 1
            ? 'One transaction no longer exists. Refresh the preview.'
            : '${missing.length} transactions no longer exist. Refresh the preview.',
      );
    }
    final selected = [for (final id in ids) byId[id]!];
    final effective = type == AssistantChangeType.exclusion
        ? selected.where((tx) => !tx.isExcluded).toList()
        : selected;
    if (effective.isEmpty) {
      throw const FinanceToolException(
        'already_excluded',
        'Those transactions are already excluded from spending.',
      );
    }
    if (effective.length > maxPreviewRecords) {
      throw FinanceToolException(
        'too_many_records',
        'A single change is limited to $maxPreviewRecords transactions.',
      );
    }

    final spendingBefore = _spendingForWindow(window);
    var removedSpending = 0;
    for (final tx in effective) {
      if (tx.type == TransactionType.expense && !tx.isExcluded) {
        removedSpending += tx.amountMinor;
      }
    }
    final spendingAfter = spendingBefore - removedSpending;
    final nowValue = now;
    final pending = AssistantPendingAction(
      id: _newActionId(nowValue),
      type: type,
      transactionIds: [for (final tx in effective) tx.id],
      transactions: [
        for (final tx in effective)
          AssistantTransactionView.fromTransaction(tx),
      ],
      expectedFingerprints: {
        for (final tx in effective) tx.id: _fingerprint(tx),
      },
      expectedCount: effective.length,
      expectedTotalMinor:
          effective.fold<int>(0, (sum, tx) => sum + tx.amountMinor),
      spendingBeforeMinor: spendingBefore,
      spendingAfterMinor: spendingAfter,
      spendingScopeLabel: window.preciseLabel,
      spendingScopeStart: window.start,
      spendingScopeEnd: window.end,
      createdAt: nowValue,
      expiresAt: nowValue.add(AssistantPendingAction.lifetime),
      explanation: type == AssistantChangeType.exclusion
          ? 'Excluded transactions stay in your ledger and can be restored. '
              'They stop counting in spending totals, Insights, budgets and '
              'payment-instrument summaries.'
          : 'Deleting removes these records from the encrypted ledger. It cannot '
              'be undone unless the assistant audit copy is still available.',
    );

    return FinanceToolResult(
      tool: type == AssistantChangeType.exclusion
          ? 'preview_transaction_exclusion'
          : 'preview_transaction_deletion',
      pending: pending,
      data: {
        'previewId': pending.id,
        'action': type.name,
        'requiresExplicitUserConfirmation': true,
        'recordCount': pending.expectedCount,
        'totalMinor': pending.expectedTotalMinor,
        'spendingBeforeMinor': spendingBefore,
        'spendingAfterMinor': spendingAfter,
        'spendingScope': window.preciseLabel,
        'expiresAt': pending.expiresAt.toIso8601String(),
        'records': [
          for (final tx in pending.transactions) tx.toToolJson(),
        ],
      },
    );
  }

  // ── Filtering and totals ──────────────────────────────────────────────────

  List<TransactionModel> _filter(
    Map<String, dynamic> args,
    AssistantDateWindow window, {
    required bool defaultIncludeExcluded,
  }) {
    final merchant = _optionalString(args, 'merchant');
    final aliases = _optionalStringList(args, 'merchantAliases');
    final brandKey = _optionalString(args, 'brand');
    final brand =
        brandKey == null ? null : MerchantMatcher.brandByKey(brandKey);
    if (brandKey != null && brand == null) {
      throw const FinanceToolException(
          'invalid_argument', 'brand must be groww or zerodha.');
    }
    final category = _optionalString(args, 'category');
    final typeFilter = _stringArg(args, 'type', fallback: 'all');
    if (!const {'expense', 'income', 'all'}.contains(typeFilter)) {
      throw const FinanceToolException(
          'invalid_argument', 'type must be expense, income or all.');
    }
    final includeExcluded =
        _boolArg(args, 'includeExcluded', fallback: defaultIncludeExcluded);

    return [
      for (final tx in transactions)
        if (_matches(
          tx,
          window: window,
          merchant: merchant,
          aliases: aliases,
          brand: brand,
          category: category,
          typeFilter: typeFilter,
          includeExcluded: includeExcluded,
        ))
          tx,
    ];
  }

  bool _matches(
    TransactionModel tx, {
    required AssistantDateWindow window,
    required String? merchant,
    required List<String> aliases,
    required MerchantBrand? brand,
    required String? category,
    required String typeFilter,
    required bool includeExcluded,
  }) {
    if (!includeExcluded && tx.isExcluded) return false;
    if (!window.contains(tx.date)) return false;
    if (typeFilter == 'expense' && tx.type != TransactionType.expense) {
      return false;
    }
    if (typeFilter == 'income' && tx.type != TransactionType.income) {
      return false;
    }
    if (category != null &&
        category.isNotEmpty &&
        tx.category.toLowerCase() != category.toLowerCase()) {
      return false;
    }
    if (brand != null && !MerchantMatcher.matchesBrand(tx, brand)) {
      return false;
    }
    if (merchant != null &&
        merchant.isNotEmpty &&
        !MerchantMatcher.matchesFilter(tx, merchant)) {
      return false;
    }
    if (aliases.isNotEmpty &&
        !aliases.any((alias) => MerchantMatcher.matchesAlias(tx, alias))) {
      return false;
    }
    return true;
  }

  int _spendingForWindow(AssistantDateWindow window) {
    var total = 0;
    for (final tx in transactions) {
      if (tx.isExcluded) continue;
      if (tx.type != TransactionType.expense) continue;
      if (!window.contains(tx.date)) continue;
      total += tx.amountMinor;
    }
    return total;
  }

  Map<String, dynamic> _totals(List<TransactionModel> txs) {
    var expense = 0;
    var income = 0;
    var excluded = 0;
    var investment = 0;
    var transfer = 0;
    var expenseCount = 0;
    var incomeCount = 0;
    var excludedCount = 0;
    var spendingCount = 0;
    for (final tx in txs) {
      if (tx.isExcluded) {
        excluded += tx.amountMinor;
        excludedCount++;
        continue;
      }
      if (tx.type == TransactionType.income) {
        income += tx.amountMinor;
        incomeCount++;
        continue;
      }
      final kind = classifyTransaction(tx);
      if (kind == AssistantTransactionKind.investment) {
        investment += tx.amountMinor;
      } else if (kind == AssistantTransactionKind.transfer) {
        transfer += tx.amountMinor;
      }
      expense += tx.amountMinor;
      expenseCount++;
      spendingCount++;
    }
    return {
      'expenseMinor': expense,
      'incomeMinor': income,
      'excludedMinor': excluded,
      'investmentMinor': investment,
      'transferMinor': transfer,
      'expenseCount': expenseCount,
      'incomeCount': incomeCount,
      'excludedCount': excludedCount,
      'spendingCount': spendingCount,
      'totalCount': txs.length,
    };
  }

  Map<String, int> _categoryTotals(AssistantDateWindow window) {
    final totals = <String, int>{};
    for (final tx in _filter({}, window, defaultIncludeExcluded: false)) {
      if (tx.type != TransactionType.expense) continue;
      totals[tx.category] = (totals[tx.category] ?? 0) + tx.amountMinor;
    }
    return totals;
  }

  Map<String, int> _merchantTotals(AssistantDateWindow window) {
    final totals = <String, int>{};
    for (final tx in _filter({}, window, defaultIncludeExcluded: false)) {
      if (tx.type != TransactionType.expense) continue;
      final key = tx.merchant.trim().isEmpty ? 'Unknown' : tx.merchant.trim();
      totals[key] = (totals[key] ?? 0) + tx.amountMinor;
    }
    return totals;
  }

  List<AssistantDriver> _drivers(
    Map<String, int> current,
    Map<String, int> previous,
  ) {
    final keys = {...current.keys, ...previous.keys};
    final drivers = [
      for (final key in keys)
        AssistantDriver(
          label: key,
          currentMinor: current[key] ?? 0,
          previousMinor: previous[key] ?? 0,
          deltaMinor: (current[key] ?? 0) - (previous[key] ?? 0),
        ),
    ]..sort((a, b) => b.deltaMinor.compareTo(a.deltaMinor));
    return drivers;
  }

  // ── Argument validation ───────────────────────────────────────────────────

  AssistantDateWindow _window(Map<String, dynamic> args) {
    final startRaw = _optionalString(args, 'startDate');
    final endRaw = _optionalString(args, 'endDate');
    if (startRaw == null && endRaw == null) {
      return const AssistantDateWindow.allTime();
    }
    if (startRaw == null || endRaw == null) {
      throw const FinanceToolException(
          'invalid_date_range', 'Both startDate and endDate are required.');
    }
    final start = DateTime.tryParse(startRaw);
    final end = DateTime.tryParse(endRaw);
    if (start == null || end == null) {
      throw const FinanceToolException(
          'invalid_date_range', 'Dates must use YYYY-MM-DD.');
    }
    final startDay = PeriodMath.dateOnly(start);
    final endDay = PeriodMath.dateOnly(end);
    if (endDay.isBefore(startDay)) {
      throw const FinanceToolException(
          'invalid_date_range', 'The end date is before the start date.');
    }
    return AssistantDateWindow.range(
      start: startDay,
      end: endDay,
      label: 'Selected period',
    );
  }

  Map<String, dynamic> _windowJson(AssistantDateWindow window) => {
        'label': window.preciseLabel,
        'startDate': window.startIso,
        'endDate': window.endIso,
        'allTime': window.isAllTime,
      };

  Map<String, dynamic> get emptyRangeJson => _windowJson(
        const AssistantDateWindow.allTime(),
      );

  static DateTime _monthEnd(DateTime start, DateTime now) {
    final isCurrent = start.year == now.year && start.month == now.month;
    if (isCurrent) return PeriodMath.dateOnly(now);
    return DateTime(start.year, start.month + 1, 0);
  }

  static String _fingerprint(TransactionModel tx) =>
      '${tx.amountMinor}|${tx.isExcluded ? 1 : 0}|${tx.type.name}|'
      '${tx.date.toIso8601String()}|${tx.merchant}';

  static String _newActionId(DateTime now) {
    final random = Random.secure();
    final suffix =
        List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
    return 'act_${now.microsecondsSinceEpoch}_$suffix';
  }

  static Comparator<TransactionModel> _comparator(String sort) =>
      switch (sort) {
        'date_asc' => (a, b) => a.date.compareTo(b.date),
        'amount_desc' => (a, b) => b.amountMinor.compareTo(a.amountMinor),
        'amount_asc' => (a, b) => a.amountMinor.compareTo(b.amountMinor),
        _ => (a, b) => b.date.compareTo(a.date),
      };

  void _rejectUnknownKeys(Map<String, dynamic> args, Set<String> allowed) {
    for (final key in args.keys) {
      if (!allowed.contains(key)) {
        throw FinanceToolException(
          'invalid_argument',
          'Unsupported argument: ${key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')}.',
        );
      }
    }
  }

  String _stringArg(
    Map<String, dynamic> args,
    String key, {
    required String fallback,
  }) {
    final value = args[key];
    if (value == null) return fallback;
    if (value is! String || value.isEmpty || value.length > 500) {
      throw FinanceToolException('invalid_argument', '$key is invalid.');
    }
    return value;
  }

  String? _optionalString(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is! String || value.length > 500) {
      throw FinanceToolException('invalid_argument', '$key is invalid.');
    }
    return value.trim().isEmpty ? null : value.trim();
  }

  bool _boolArg(
    Map<String, dynamic> args,
    String key, {
    required bool fallback,
  }) {
    final value = args[key];
    if (value == null) return fallback;
    if (value is! bool) {
      throw FinanceToolException(
          'invalid_argument', '$key must be true or false.');
    }
    return value;
  }

  int _intArg(
    Map<String, dynamic> args,
    String key, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value = args[key];
    if (value == null) return fallback;
    if (value is! int || value < min || value > max) {
      throw FinanceToolException(
          'invalid_argument', '$key must be between $min and $max.');
    }
    return value;
  }

  List<String> _stringListArg(
    Map<String, dynamic> args,
    String key, {
    required int min,
    required int max,
  }) {
    final value = args[key];
    if (value is! List ||
        value.length < min ||
        value.length > max ||
        value.any((v) => v is! String || v.isEmpty || v.length > 200)) {
      throw FinanceToolException(
          'invalid_argument', '$key must contain $min–$max transaction ids.');
    }
    final list = value.cast<String>();
    if (list.toSet().length != list.length) {
      throw const FinanceToolException(
          'duplicate_argument', 'The same transaction id was supplied twice.');
    }
    return list;
  }

  List<String> _optionalStringList(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value == null) return const [];
    if (value is! List ||
        value.length > maxAliases ||
        value.any((v) => v is! String || v.isEmpty || v.length > 100)) {
      throw FinanceToolException(
          'invalid_argument', '$key must contain at most $maxAliases aliases.');
    }
    return value.cast<String>();
  }
}

class _MerchantGroup {
  final String label;
  int count = 0;
  int expenseMinor = 0;
  int incomeMinor = 0;
  int excludedMinor = 0;
  int excludedCount = 0;
  int investmentMinor = 0;
  DateTime firstDate = DateTime(9999);
  DateTime lastDate = DateTime(1);

  _MerchantGroup(this.label);

  void add(TransactionModel tx) {
    count++;
    if (tx.date.isBefore(firstDate)) firstDate = tx.date;
    if (tx.date.isAfter(lastDate)) lastDate = tx.date;
    if (tx.isExcluded) {
      excludedMinor += tx.amountMinor;
      excludedCount++;
      return;
    }
    if (tx.type == TransactionType.income) {
      incomeMinor += tx.amountMinor;
    } else {
      expenseMinor += tx.amountMinor;
      if (classifyTransaction(tx) == AssistantTransactionKind.investment) {
        investmentMinor += tx.amountMinor;
      }
    }
  }
}
