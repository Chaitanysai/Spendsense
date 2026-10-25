import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import 'period_math.dart';

/// Pure, immutable transaction filter used by the Activity screen.
///
/// Filtering never mutates or re-stores a transaction, so it cannot affect the
/// encrypted ledger. Amount bounds are integer paise and are compared exactly.
class TransactionFilter {
  /// Free-text query matched against merchant, category, payment method, bank
  /// and the amount (as rupees, e.g. `239.5` matches ₹239.50).
  final String query;
  final String? category;
  final TransactionType? type;

  /// Inclusive on both ends, decided on the local calendar day.
  final DateTimeRange? dateRange;

  /// Inclusive bounds in integer paise.
  final int? minAmountMinor;
  final int? maxAmountMinor;

  const TransactionFilter({
    this.query = '',
    this.category,
    this.type,
    this.dateRange,
    this.minAmountMinor,
    this.maxAmountMinor,
  });

  static const TransactionFilter none = TransactionFilter();

  bool get hasQuery => query.trim().isNotEmpty;

  bool get hasAmountRange => minAmountMinor != null || maxAmountMinor != null;

  /// True when anything narrows the list (so a "Clear" action is meaningful).
  bool get isActive =>
      hasQuery ||
      category != null ||
      type != null ||
      dateRange != null ||
      hasAmountRange;

  /// Copy with explicit clearing: pass `clearX: true` to drop a field (a plain
  /// null argument means "keep").
  TransactionFilter copyWith({
    String? query,
    String? category,
    TransactionType? type,
    DateTimeRange? dateRange,
    int? minAmountMinor,
    int? maxAmountMinor,
    bool clearCategory = false,
    bool clearType = false,
    bool clearDateRange = false,
    bool clearAmountRange = false,
  }) =>
      TransactionFilter(
        query: query ?? this.query,
        category: clearCategory ? null : (category ?? this.category),
        type: clearType ? null : (type ?? this.type),
        dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
        minAmountMinor:
            clearAmountRange ? null : (minAmountMinor ?? this.minAmountMinor),
        maxAmountMinor:
            clearAmountRange ? null : (maxAmountMinor ?? this.maxAmountMinor),
      );

  bool matches(TransactionModel t) {
    if (category != null && t.category != category) return false;
    if (type != null && t.type != type) return false;
    if (dateRange != null &&
        !PeriodMath.containsLocalDate(dateRange!, t.date)) {
      return false;
    }
    if (minAmountMinor != null && t.amountMinor < minAmountMinor!) return false;
    if (maxAmountMinor != null && t.amountMinor > maxAmountMinor!) return false;
    return !hasQuery || _matchesQuery(t);
  }

  List<TransactionModel> apply(Iterable<TransactionModel> all) => [
        for (final t in all)
          if (matches(t)) t
      ];

  bool _matchesQuery(TransactionModel t) {
    final q = query.trim().toLowerCase();
    if (t.merchant.toLowerCase().contains(q) ||
        t.category.toLowerCase().contains(q) ||
        t.paymentMethod.toLowerCase().contains(q) ||
        t.bankName.toLowerCase().contains(q)) {
      return true;
    }
    // Amount search: "₹1,234.5", "1234.5" and "1234" all find ₹1,234.50.
    final amountQuery = q.replaceAll(RegExp(r'[₹,\s]'), '');
    if (amountQuery.isEmpty ||
        !RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(amountQuery)) {
      return false;
    }
    return plainRupees(t.amountMinor).contains(amountQuery);
  }

  /// `12345` paise -> `123.45`; whole rupees have no decimal part.
  static String plainRupees(int amountMinor) {
    final rupees = amountMinor ~/ 100;
    final paise = amountMinor % 100;
    return paise == 0
        ? '$rupees'
        : '$rupees.${paise.toString().padLeft(2, '0')}';
  }
}
