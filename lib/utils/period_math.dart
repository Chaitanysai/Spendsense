import 'package:flutter/material.dart';

/// Shared, DST-safe boundary math for salary-day periods.
///
/// CONTRACT: period ranges are LOCAL-CALENDAR ranges. All comparisons are
/// date-only — the time-of-day of the range bounds is ignored. The start day
/// is inclusive and the end DAY is inclusive (so an instant anywhere on the
/// end day belongs to the range, and nothing on the day after does).
///
/// ## Salary cycle (approved product rule)
///
/// A salary day `N` (1..31) begins a cycle on day `N` of each month:
///
///  * if the month has at least `N` days the cycle starts on day `N`;
///  * otherwise it starts on that month's last day (clamped — Feb 31 -> Feb 28/29);
///  * the next cycle starts on the corresponding clamped day of the next month.
///
/// So with `N = 31`: Jan 31, Feb 28, Mar 31, Apr 30, May 31, ...
/// Each cycle always runs from its start day up to the day before the next
/// start day, which makes consecutive cycles exactly contiguous: no gaps, no
/// overlaps, every calendar day in exactly one cycle.
///
/// ## Timezone
///
/// All arithmetic is calendar arithmetic on local dates. Never use
/// `DateTime.add(Duration(days: n))` for day stepping: a `Duration` is a fixed
/// number of 24-hour blocks, so across a DST change it lands at 23:00 or 01:00
/// of the wrong calendar day.
class PeriodMath {
  PeriodMath._();

  /// Drops the time-of-day from [d], which is treated as already-local.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Adds [days] calendar days to [d]; DST-safe; drops the time-of-day
  /// (result is always 00:00 of the target calendar day).
  ///
  /// WHY calendar arithmetic instead of `d.add(const Duration(days: n))`:
  /// a `Duration` is a fixed number of 24-hour blocks, so on a local
  /// DateTime it shifts the calendar day across a DST change (a 23- or
  /// 25-hour day makes midnight + 24h land at 01:00 or 23:00 of the wrong
  /// day). Constructing `DateTime(y, m, day + n)` instead moves exactly one
  /// calendar day (Dart normalizes day overflow into the next month/year)
  /// and always yields midnight.
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// True iff the local calendar day of [instant] falls within [range]:
  /// `dateOnly(instant.toLocal()) >= dateOnly(range.start)` AND
  /// `dateOnly(instant.toLocal()) < addDays(range.end, 1)` — i.e. the start
  /// day is inclusive, the end DAY is inclusive, and any time-of-day on the
  /// range bounds is ignored.
  static bool containsLocalDate(DateTimeRange range, DateTime instant) {
    final day = dateOnly(instant.toLocal());
    final startDay = dateOnly(range.start);
    final endDayExclusive = addDays(range.end, 1);
    return !day.isBefore(startDay) && day.isBefore(endDayExclusive);
  }

  /// Number of days in the given month.
  static int daysInMonth(int year, int month) =>
      DateUtils.getDaysInMonth(year, month);

  /// The day a cycle actually starts in [year]-[month] for salary day
  /// [salaryDay]: [salaryDay], or the month's last day when it is shorter.
  ///
  /// Throws [ArgumentError] for a salary day outside 1..31 rather than
  /// silently normalising it.
  ///
  /// Implementation note: `DateTime(2027, 2, 31)` would *overflow* into
  /// March 3 (Dart normalises out-of-range days), so the day is clamped
  /// against the month's length first.
  static DateTime clampStartDay(int year, int month, int salaryDay) {
    if (salaryDay < 1 || salaryDay > 31) {
      throw ArgumentError.value(salaryDay, 'salaryDay', 'must be 1..31');
    }
    // Month 13/0 would normalise the year; normalise here so daysInMonth sees
    // the real target month.
    final first = DateTime(year, month, 1);
    final lastDay = daysInMonth(first.year, first.month);
    return DateTime(
      first.year,
      first.month,
      salaryDay > lastDay ? lastDay : salaryDay,
    );
  }

  /// The cycle that contains [now] for salary day [salaryDay].
  ///
  /// `start` is midnight of the cycle's first day; `end` is the end day at
  /// 23:59:59 (kept for callers that render or compare a DateTimeRange).
  /// Comparisons must use [containsLocalDate], which ignores the time-of-day.
  static DateTimeRange salaryCycle({
    required int salaryDay,
    DateTime? now,
  }) {
    final today = dateOnly(now ?? DateTime.now());
    final thisMonthStart = clampStartDay(today.year, today.month, salaryDay);

    final DateTime start;
    if (!today.isBefore(thisMonthStart)) {
      start = thisMonthStart;
    } else {
      final prev = DateTime(today.year, today.month - 1, 1);
      start = clampStartDay(prev.year, prev.month, salaryDay);
    }

    final nextMonth = DateTime(start.year, start.month + 1, 1);
    final nextStart = clampStartDay(nextMonth.year, nextMonth.month, salaryDay);
    final endDay = addDays(nextStart, -1);

    return DateTimeRange(
      start: start,
      end: DateTime(endDay.year, endDay.month, endDay.day, 23, 59, 59),
    );
  }

  /// The cycle immediately before the one containing [now]; contiguous with
  /// [salaryCycle] (its last day is the day before the current cycle starts).
  static DateTimeRange previousSalaryCycle({
    required int salaryDay,
    DateTime? now,
  }) {
    final current = salaryCycle(salaryDay: salaryDay, now: now);
    return salaryCycle(
      salaryDay: salaryDay,
      now: addDays(current.start, -1),
    );
  }

  /// The calendar month containing [day] — a deliberately DIFFERENT period
  /// from the salary cycle, used for reporting labelled "This month".
  static DateTimeRange calendarMonth(DateTime day) => DateTimeRange(
        start: DateTime(day.year, day.month, 1),
        end: DateTime(
            day.year, day.month, daysInMonth(day.year, day.month), 23, 59, 59),
      );

  /// The next calendar date on which salary arrives at or after [now].
  static DateTime nextSalaryDate(int salaryDay, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final thisMonth = clampStartDay(today.year, today.month, salaryDay);
    if (!today.isAfter(thisMonth)) return thisMonth;
    final next = DateTime(today.year, today.month + 1, 1);
    return clampStartDay(next.year, next.month, salaryDay);
  }
}
