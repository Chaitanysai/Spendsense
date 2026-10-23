import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/period_math.dart';

// ─── PERIOD MODE ────────────────────────────────────────────────────────────

enum PeriodMode {
  oneMonth, // salary-day aligned, 1 month window (default)
  custom, // user-picked start/end
}

// ─── PERIOD PROVIDER ────────────────────────────────────────────────────────

/// Amounts are whole rupees and are not touched by any period logic.
class PeriodProvider with ChangeNotifier {
  static const _keySalaryDay = 'salary_day'; // 1–31
  static const _keySetupDone = 'salary_day_setup'; // bool
  static const _keyNow =
      'period_debug_now'; // test-only override, never set in production

  // State
  int _salaryDay = 1;
  PeriodMode _mode = PeriodMode.oneMonth;
  DateTimeRange? _custom;

  /// Optional fixed "today" for tests. Null in production, where the system
  /// clock is used. Never persisted by normal code paths.
  DateTime? _fixedNow;

  PeriodProvider();

  /// A provider with a fixed clock and salary day, for deterministic tests.
  @visibleForTesting
  factory PeriodProvider.fixedForTest({
    required int salaryDay,
    required DateTime now,
    PeriodMode mode = PeriodMode.oneMonth,
    DateTimeRange? custom,
  }) {
    final p = PeriodProvider()
      .._salaryDay = salaryDay
      .._fixedNow = now
      .._setupDone = true
      .._mode = mode;
    if (mode == PeriodMode.custom) p._custom = custom;
    return p;
  }

  DateTime get _now => _fixedNow ?? DateTime.now();
  int get salaryDay => _salaryDay;
  PeriodMode get mode => _mode;
  DateTimeRange? get customRange => _custom;
  bool get isSetupDone => _setupDone;
  bool _setupDone = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _salaryDay = prefs.getInt(_keySalaryDay) ?? 1;
    _setupDone = prefs.getBool(_keySetupDone) ?? false;
    final debugNow = prefs.getString(_keyNow);
    if (debugNow != null) _fixedNow = DateTime.tryParse(debugNow);
    notifyListeners();
  }

  // ── Salary-day setup (called from first-launch prompt + settings) ─────────

  Future<void> setSalaryDay(int day) async {
    assert(day >= 1 && day <= 31);
    _salaryDay = day;
    _mode = PeriodMode.oneMonth; // reset to default mode after change
    _custom = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySalaryDay, day);
    await prefs.setBool(_keySetupDone, true);
    _setupDone = true;
    notifyListeners();
  }

  // ── Mode switching ────────────────────────────────────────────────────────

  void setMode(PeriodMode mode, {DateTimeRange? custom}) {
    _mode = mode;
    _custom = (mode == PeriodMode.custom) ? custom : null;
    notifyListeners();
  }

  // ── Core: the active DateTimeRange ───────────────────────────────────────
  //
  // "1 month, salary-day aligned" (approved product rule):
  //   * Salary arrives on day N of each month; in a month with fewer than N
  //     days it arrives on that month's last day.
  //   * The cycle starts on that day. If today is on or after it, the cycle
  //     started this month; otherwise it started last month.
  //   * The cycle ends the day before the next cycle starts, so consecutive
  //     cycles are exactly contiguous: no gaps, no overlaps.

  DateTimeRange get currentPeriod {
    if (_mode == PeriodMode.custom && _custom != null) {
      return _custom!;
    }
    return PeriodMath.salaryCycle(salaryDay: _salaryDay, now: _now);
  }

  /// The salary-aligned window immediately before [currentPeriod], used for the
  /// dashboard's cycle-over-cycle delta. Null in custom mode, where the user's
  /// arbitrary window has no well-defined predecessor.
  DateTimeRange? get previousPeriod {
    if (_mode == PeriodMode.custom) return null;
    return PeriodMath.previousSalaryCycle(salaryDay: _salaryDay, now: _now);
  }

  /// The calendar month containing today. Reporting that is labelled
  /// "This month" uses this — deliberately NOT the salary cycle.
  DateTimeRange get currentCalendarMonth => PeriodMath.calendarMonth(_now);

  /// The calendar month before [currentCalendarMonth] (for month-over-month).
  DateTimeRange get previousCalendarMonth =>
      PeriodMath.calendarMonth(DateTime(_now.year, _now.month - 1, 1));

  // ── Human-readable label for the chip ────────────────────────────────────

  String get periodLabel {
    switch (_mode) {
      case PeriodMode.oneMonth:
        final p = currentPeriod;
        final s = p.start;
        final e = p.end;
        // e.g.  "25 Mar – 24 Apr"
        return '${s.day} ${_mon(s.month)} – ${e.day} ${_mon(e.month)}';
      case PeriodMode.custom:
        if (_custom == null) return 'Custom';
        final s = _custom!.start;
        final e = _custom!.end;
        return '${s.day} ${_mon(s.month)} – ${e.day} ${_mon(e.month)}';
    }
  }

  // ── Helper: build a salary-aligned range ─────────────────────────────────

  /// Salary cycle for an explicit salary day. Delegates to [PeriodMath] so the
  /// rule lives in exactly one place.
  static DateTimeRange salaryAlignedPeriod({
    int months = 1,
    int salaryDay = 1,
    DateTime? now,
  }) {
    assert(months == 1, 'only one-month salary cycles are supported');
    return PeriodMath.salaryCycle(salaryDay: salaryDay, now: now);
  }

  static DateTime nextSalaryDate({int salaryDay = 1, DateTime? now}) =>
      PeriodMath.nextSalaryDate(salaryDay, now: now);

  // ── Month abbreviation ────────────────────────────────────────────────────

  static const _months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  String _mon(int m) => _months[m];
}
