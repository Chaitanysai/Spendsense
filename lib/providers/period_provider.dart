import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── PERIOD MODE ────────────────────────────────────────────────────────────

enum PeriodMode {
  oneMonth, // salary-day aligned, 1 month window (default)
  custom, // user-picked start/end
}

// ─── PERIOD PROVIDER ────────────────────────────────────────────────────────

class PeriodProvider with ChangeNotifier {
  static const _keySalaryDay = 'salary_day'; // 1–31
  static const _keySetupDone = 'salary_day_setup'; // bool

  // State
  int _salaryDay = 1;
  PeriodMode _mode = PeriodMode.oneMonth;
  DateTimeRange? _custom;

  // Getters
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
  // "1 month, salary-day aligned" means:
  //   • If today is ON or AFTER the salary day  → period starts this month on
  //     salary day, ends the day before next month's salary day.
  //   • If today is BEFORE the salary day       → period started last month on
  //     salary day, ends yesterday (day before today's salary day).
  //
  // Example — salary day = 25:
  //   Today = Apr 10  → period: Mar 25 00:00 … Apr 24 23:59
  //   Today = Apr 28  → period: Apr 25 00:00 … May 24 23:59

  DateTimeRange get currentPeriod {
    if (_mode == PeriodMode.custom && _custom != null) {
      return _custom!;
    }
    return salaryAlignedPeriod(_salaryDay, months: 1);
  }

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

  static DateTimeRange salaryAlignedPeriod(int salaryDay,
      {required int months}) {
    final today = DateTime.now();

    // Clamp salary day to valid day in a given month
    int clampedDay(int year, int month) {
      final daysInMonth = DateUtils.getDaysInMonth(year, month);
      return salaryDay.clamp(1, daysInMonth);
    }

    final currentMonthSalaryDay = clampedDay(today.year, today.month);

    DateTime periodStart;
    if (today.day >= currentMonthSalaryDay) {
      // We're in or past the salary day this month → current cycle started
      // this month on salary day.
      periodStart = DateTime(
          today.year, today.month, clampedDay(today.year, today.month));
    } else {
      // We haven't reached salary day yet → current cycle started last month.
      final prevMonth = DateTime(today.year, today.month - 1);
      periodStart = DateTime(prevMonth.year, prevMonth.month,
          clampedDay(prevMonth.year, prevMonth.month));
    }

    // End = one day before the NEXT salary day after periodStart
    final nextSalaryMonth =
        DateTime(periodStart.year, periodStart.month + months);
    final nextSalaryDay =
        clampedDay(nextSalaryMonth.year, nextSalaryMonth.month);
    final periodEnd =
        DateTime(nextSalaryMonth.year, nextSalaryMonth.month, nextSalaryDay)
            .subtract(const Duration(days: 1));

    return DateTimeRange(
      start: periodStart,
      end: DateTime(periodEnd.year, periodEnd.month, periodEnd.day, 23, 59, 59),
    );
  }

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
