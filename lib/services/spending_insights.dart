import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../utils/period_math.dart';

/// A spending total for one period compared with an equally long earlier one.
///
/// Both ranges cover the SAME number of elapsed days (e.g. 1st–12th of this
/// month vs 1st–12th of last month), so a partly finished period is never
/// compared against a whole one.
class PeriodComparison {
  final String label;
  final DateTimeRange current;
  final DateTimeRange previous;
  final int currentMinor;
  final int previousMinor;

  const PeriodComparison({
    required this.label,
    required this.current,
    required this.previous,
    required this.currentMinor,
    required this.previousMinor,
  });

  /// False when there is nothing to compare against (avoids "+∞%").
  bool get hasPrevious => previousMinor > 0;

  int get deltaMinor => currentMinor - previousMinor;

  /// Change in tenths of a percent (123 = 12.3%), rounded half away from zero.
  /// Integer arithmetic only. Null without a previous period.
  int? get changeTenthsOfPercent {
    if (!hasPrevious) return null;
    final numerator = deltaMinor * 1000;
    final half = previousMinor ~/ 2;
    return numerator >= 0
        ? (numerator + half) ~/ previousMinor
        : -((-numerator + half) ~/ previousMinor);
  }
}

class CategoryShare {
  final String category;
  final int amountMinor;

  /// Share of the period's spending in tenths of a percent (rounded half up).
  final int shareTenths;

  const CategoryShare(this.category, this.amountMinor, this.shareTenths);
}

class MonthTotal {
  final DateTime month;
  final int amountMinor;

  /// True for the month in progress (its total is not final).
  final bool isPartial;

  const MonthTotal(this.month, this.amountMinor, {required this.isPartial});
}

/// Pure analytics derived from the existing ledger. Nothing here stores
/// anything: every figure is recomputed from the transactions it is given.
///
/// Spending means non-excluded EXPENSE transactions. Income (including any
/// refund recorded as income) is never subtracted from spending here; it is
/// reported separately by the financial summary as net cash flow.
class SpendingInsights {
  SpendingInsights._();

  static Iterable<TransactionModel> _expenses(
          Iterable<TransactionModel> all, DateTimeRange range) =>
      all.where((t) =>
          t.type == TransactionType.expense &&
          !t.isExcluded &&
          PeriodMath.containsLocalDate(range, t.date));

  static int total(Iterable<TransactionModel> all, DateTimeRange range) =>
      _expenses(all, range).fold<int>(0, (s, t) => s + t.amountMinor);

  /// This week (Monday to today) against last week's same elapsed days.
  static PeriodComparison weekOverWeek(
      Iterable<TransactionModel> all, DateTime now) {
    final today = PeriodMath.dateOnly(now);
    final start = PeriodMath.addDays(today, -(today.weekday - 1));
    final elapsed = today.weekday - 1; // days after Monday
    final prevStart = PeriodMath.addDays(start, -7);
    final current = DateTimeRange(start: start, end: today);
    final previous = DateTimeRange(
        start: prevStart, end: PeriodMath.addDays(prevStart, elapsed));
    return PeriodComparison(
      label: 'Week to date vs last week',
      current: current,
      previous: previous,
      currentMinor: total(all, current),
      previousMinor: total(all, previous),
    );
  }

  /// This month (1st to today) against last month's same elapsed days
  /// (clamped to last month's length, e.g. 31 Mar vs 28 Feb).
  static PeriodComparison monthOverMonth(
      Iterable<TransactionModel> all, DateTime now) {
    final today = PeriodMath.dateOnly(now);
    final start = DateTime(today.year, today.month, 1);
    final prevStart = DateTime(today.year, today.month - 1, 1);
    final prevLast = DateTime(today.year, today.month, 0).day;
    final prevEnd = DateTime(prevStart.year, prevStart.month,
        today.day > prevLast ? prevLast : today.day);
    final current = DateTimeRange(start: start, end: today);
    final previous = DateTimeRange(start: prevStart, end: prevEnd);
    return PeriodComparison(
      label: 'Month to date vs last month',
      current: current,
      previous: previous,
      currentMinor: total(all, current),
      previousMinor: total(all, previous),
    );
  }

  /// Spending by category in [range], largest first, with integer shares.
  static List<CategoryShare> categoryBreakdown(
      Iterable<TransactionModel> all, DateTimeRange range) {
    final totals = <String, int>{};
    for (final t in _expenses(all, range)) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amountMinor;
    }
    final sum = totals.values.fold<int>(0, (a, b) => a + b);
    final entries = totals.entries.toList()
      ..sort((a, b) {
        final byAmount = b.value.compareTo(a.value);
        return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
      });
    return [
      for (final e in entries)
        CategoryShare(
            e.key, e.value, sum == 0 ? 0 : (e.value * 1000 + sum ~/ 2) ~/ sum),
    ];
  }

  /// The [limit] largest single expenses in [range] (ties broken by newest).
  static List<TransactionModel> largestExpenses(
      Iterable<TransactionModel> all, DateTimeRange range,
      {int limit = 5}) {
    final list = _expenses(all, range).toList()
      ..sort((a, b) {
        final byAmount = b.amountMinor.compareTo(a.amountMinor);
        return byAmount != 0 ? byAmount : b.date.compareTo(a.date);
      });
    return list.take(limit).toList();
  }

  /// Calendar-month totals for the last [months] months, oldest first. The
  /// final entry is the month in progress and is flagged partial.
  static List<MonthTotal> monthlyTrend(
      Iterable<TransactionModel> all, DateTime now,
      {int months = 6}) {
    final list = all.toList();
    return [
      for (var i = months - 1; i >= 0; i--)
        () {
          final month = DateTime(now.year, now.month - i, 1);
          return MonthTotal(
            month,
            total(list, PeriodMath.calendarMonth(month)),
            isPartial: i == 0,
          );
        }(),
    ];
  }
}
