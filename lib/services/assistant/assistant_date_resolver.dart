import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/period_math.dart';

/// A local-calendar window used by the assistant. Both bounds are inclusive
/// calendar days; [start] and [end] are midnight. [nil] means all time.
class AssistantDateWindow {
  final DateTime? start;
  final DateTime? end;
  final String label;

  const AssistantDateWindow._({
    required this.label,
    this.start,
    this.end,
  });

  const AssistantDateWindow.allTime() : this._(label: 'All time');

  factory AssistantDateWindow.range({
    required DateTime start,
    required DateTime end,
    required String label,
  }) =>
      AssistantDateWindow._(
        start: PeriodMath.dateOnly(start),
        end: PeriodMath.dateOnly(end),
        label: label,
      );

  bool get isAllTime => start == null || end == null;

  bool contains(DateTime instant) {
    if (start == null || end == null) return true;
    return PeriodMath.containsLocalDate(
      DateTimeRange(start: start!, end: end!),
      instant,
    );
  }

  /// ISO dates for tool arguments and summaries.
  String get startIso =>
      start == null ? '' : DateFormat('yyyy-MM-dd').format(start!);
  String get endIso => end == null ? '' : DateFormat('yyyy-MM-dd').format(end!);

  String get preciseLabel => isAllTime
      ? 'All time'
      : '${DateFormat('d MMM yyyy').format(start!)} – ${DateFormat('d MMM yyyy').format(end!)}';
}

/// Deterministic natural-language date parsing for local commands and Gemini
/// arguments.
///
/// "This month" and "last month" are CALENDAR months, matching how people read
/// the phrase. The dashboard's salary cycle is a separate concept and the
/// assistant always states the exact inclusive range it used, so the two cannot
/// silently disagree.
class AssistantDateResolver {
  AssistantDateResolver._();

  static const List<String> _monthNames = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];

  static AssistantDateWindow resolve(String query, {DateTime? now}) {
    final reference = PeriodMath.dateOnly(now ?? DateTime.now());
    final q = query.toLowerCase();

    if (_has(q, 'all time') || _has(q, 'overall') || _has(q, 'lifetime')) {
      return const AssistantDateWindow.allTime();
    }

    if (_has(q, 'today')) {
      return AssistantDateWindow.range(
        start: reference,
        end: reference,
        label: 'Today',
      );
    }
    if (_has(q, 'yesterday')) {
      final day = PeriodMath.addDays(reference, -1);
      return AssistantDateWindow.range(
        start: day,
        end: day,
        label: 'Yesterday',
      );
    }

    final lastDays = RegExp(r'last\s+(\d{1,2})\s+days?').firstMatch(q);
    if (lastDays != null) {
      final days = int.tryParse(lastDays.group(1)!) ?? 0;
      if (days > 0 && days <= 366) {
        return AssistantDateWindow.range(
          start: PeriodMath.addDays(reference, -(days - 1)),
          end: reference,
          label: 'Last $days days',
        );
      }
    }

    if (_has(q, 'last month') || _has(q, 'previous month')) {
      final previous = DateTime(reference.year, reference.month - 1, 1);
      final end = DateTime(reference.year, reference.month, 0);
      return AssistantDateWindow.range(
        start: previous,
        end: end,
        label: 'Last month',
      );
    }
    if (_has(q, 'this month') || _has(q, 'current month')) {
      return AssistantDateWindow.range(
        start: DateTime(reference.year, reference.month, 1),
        end: reference,
        label: 'This month',
      );
    }

    if (_has(q, 'last year') || _has(q, 'previous year')) {
      final year = reference.year - 1;
      return AssistantDateWindow.range(
        start: DateTime(year, 1, 1),
        end: DateTime(year, 12, 31),
        label: 'Last year',
      );
    }
    if (_has(q, 'this year') || _has(q, 'current year')) {
      return AssistantDateWindow.range(
        start: DateTime(reference.year, 1, 1),
        end: reference,
        label: 'This year',
      );
    }

    if (_has(q, 'last week') || _has(q, 'previous week')) {
      final startOfThisWeek =
          PeriodMath.addDays(reference, -(reference.weekday - 1));
      final start = PeriodMath.addDays(startOfThisWeek, -7);
      final end = PeriodMath.addDays(startOfThisWeek, -1);
      return AssistantDateWindow.range(
        start: start,
        end: end,
        label: 'Last week',
      );
    }
    if (_has(q, 'this week') || _has(q, 'current week')) {
      final start = PeriodMath.addDays(reference, -(reference.weekday - 1));
      return AssistantDateWindow.range(
        start: start,
        end: reference,
        label: 'This week',
      );
    }

    // Explicit ISO date or "1 Oct 2026" style bounds.
    final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(q);
    if (iso != null) {
      final date = DateTime.tryParse(iso.group(0)!);
      if (date != null) {
        return AssistantDateWindow.range(
          start: date,
          end: date,
          label: DateFormat('d MMM yyyy').format(date),
        );
      }
    }

    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(q);
    final explicitYear =
        yearMatch == null ? null : int.parse(yearMatch.group(1)!);

    for (var i = 0; i < _monthNames.length; i++) {
      final month = i + 1;
      final name = _monthNames[i];
      if (!_has(q, name)) continue;

      var year = explicitYear ?? reference.year;
      if (explicitYear == null && month > reference.month) {
        year -= 1;
      }
      final start = DateTime(year, month, 1);
      final lastDay = DateTime(year, month + 1, 0).day;
      final isCurrentMonth = year == reference.year && month == reference.month;
      final end = isCurrentMonth ? reference : DateTime(year, month, lastDay);
      return AssistantDateWindow.range(
        start: start,
        end: end,
        label: DateFormat('MMMM yyyy').format(start),
      );
    }

    if (explicitYear != null) {
      return AssistantDateWindow.range(
        start: DateTime(explicitYear, 1, 1),
        end: explicitYear == reference.year
            ? reference
            : DateTime(explicitYear, 12, 31),
        label: '$explicitYear',
      );
    }

    return const AssistantDateWindow.allTime();
  }

  /// True when the query explicitly names a bounded period. Used by the local
  /// intent parser to avoid treating every query as "all time".
  static bool hasExplicitPeriod(String query) {
    final q = query.toLowerCase();
    if (RegExp(r'last\s+\d{1,2}\s+days?').hasMatch(q)) return true;
    for (final term in const [
      'today',
      'yesterday',
      'this month',
      'current month',
      'last month',
      'previous month',
      'this year',
      'current year',
      'last year',
      'previous year',
      'this week',
      'last week',
      'previous week',
      'all time',
      'overall',
      'lifetime',
    ]) {
      if (_has(q, term)) return true;
    }
    if (RegExp(r'\b20\d{2}\b').hasMatch(q)) return true;
    for (final month in _monthNames) {
      if (_has(q, month)) return true;
    }
    return false;
  }

  static bool _has(String normalizedQuery, String phrase) {
    final normalized =
        normalizedQuery.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    final padded = ' ${normalized.replaceAll(RegExp(r'\s+'), ' ').trim()} ';
    return padded.contains(' $phrase ');
  }
}
