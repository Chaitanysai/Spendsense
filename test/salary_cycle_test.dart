// Salary-cycle contract, per the APPROVED product rules (docs/product-
// readiness/remediation-phase-3.md):
//
//  1. Salary day N begins a cycle on day N of each month.
//  2. If a month has fewer than N days, the cycle starts on that month's last day.
//  3. The next cycle begins on the corresponding clamped day of the next month.
//  4. Home's "this cycle" total and cycle insights use the salary cycle.
//  5. Calendar-month reporting stays separate and is labelled "This month".
//  6. The monthly budget applies to the salary cycle.
//
// Everything here is pure (explicit `now`, explicit salary day) so it is
// deterministic and independent of the machine's clock or timezone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/utils/period_math.dart';

/// The range as "yyyy-MM-dd|yyyy-MM-dd" for readable assertions.
String _r(DateTimeRange r) =>
    '${PeriodMath.dateOnly(r.start).toIso8601String().substring(0, 10)}|'
    '${PeriodMath.dateOnly(r.end).toIso8601String().substring(0, 10)}';

DateTimeRange _cycle(int salaryDay, String now) =>
    PeriodMath.salaryCycle(salaryDay: salaryDay, now: DateTime.parse(now));

void main() {
  group('salary day 1', () {
    test('mid-month sits in the cycle that began this month', () {
      expect(_r(_cycle(1, '2026-10-12')), '2026-10-01|2026-10-31');
    });

    test('the start day itself is included', () {
      expect(_r(_cycle(1, '2026-10-01')), '2026-10-01|2026-10-31');
    });

    test('the last day of the cycle is still that cycle', () {
      expect(_r(_cycle(1, '2026-10-31')), '2026-10-01|2026-10-31');
    });

    test('February in a non-leap year ends on the 28th', () {
      expect(_r(_cycle(1, '2027-02-15')), '2027-02-01|2027-02-28');
    });

    test('February in a leap year ends on the 29th', () {
      expect(_r(_cycle(1, '2028-02-15')), '2028-02-01|2028-02-29');
    });
  });

  group('salary day 28, 29, 30 and 31 in a 31-day month', () {
    for (final day in [28, 29, 30]) {
      test('salary day $day: before it, the cycle began last month', () {
        expect(
            _r(_cycle(day, '2026-10-01')), '2026-09-$day|2026-10-${day - 1}');
      });

      test('salary day $day: on it, a new cycle begins', () {
        final end = PeriodMath.addDays(DateTime(2026, 11, day), -1);
        expect(
            _r(_cycle(day, '2026-10-${day.toString().padLeft(2, '0')}')),
            '2026-10-${day.toString().padLeft(2, '0')}|'
            '${end.toIso8601String().substring(0, 10)}');
      });
    }

    test('salary day 31: before it, the cycle began Sept 30 (clamped)', () {
      // September has only 30 days, so a salary day of 31 clamps to Sept 30,
      // and the cycle runs to the day before Oct 31.
      expect(_r(_cycle(31, '2026-10-01')), '2026-09-30|2026-10-30');
    });

    test('salary day 31: on Oct 31 a new cycle begins', () {
      expect(_r(_cycle(31, '2026-10-31')), '2026-10-31|2026-11-29');
    });
  });

  group('months shorter than the selected salary day (clamping)', () {
    test('salary day 31 in February: the cycle starts on the 28th/29th', () {
      // Feb 2027 has 28 days; a salary day of 31 clamps to the 28th.
      expect(_r(_cycle(31, '2027-02-10')), '2027-01-31|2027-02-27');
      expect(_r(_cycle(31, '2027-02-28')), '2027-02-28|2027-03-30');
      // Leap February clamps to the 29th.
      expect(_r(_cycle(31, '2028-02-29')), '2028-02-29|2028-03-30');
    });

    test('salary day 30 in a 28-day February', () {
      expect(_r(_cycle(30, '2027-02-10')), '2027-01-30|2027-02-27');
      expect(_r(_cycle(30, '2027-02-28')), '2027-02-28|2027-03-29');
    });

    test('next cycle begins on the CLAMPED day of the next month', () {
      // From the clamped February start, the following cycle starts on
      // March 31 (a 31-day month restores the requested day).
      final feb = _cycle(31, '2027-02-28');
      final next = PeriodMath.salaryCycle(
        salaryDay: 31,
        now: PeriodMath.addDays(feb.end, 1),
      );
      expect(_r(next), '2027-03-31|2027-04-29');
      expect(_r(feb), '2027-02-28|2027-03-30');
      // Rule 3: next.start == the day after this cycle's end.
      expect(next.start, PeriodMath.addDays(feb.end, 1));
    });

    test('salary day 31 in a 30-day month starts on the 30th', () {
      expect(_r(_cycle(31, '2026-11-15')), '2026-10-31|2026-11-29');
      expect(_r(_cycle(31, '2026-12-15')), '2026-11-30|2026-12-30');
    });
  });

  group('year boundaries', () {
    test('a cycle that began in December crosses into January', () {
      expect(_r(_cycle(31, '2026-12-31')), '2026-12-31|2027-01-30');
      expect(_r(_cycle(25, '2027-01-10')), '2026-12-25|2027-01-24');
    });

    test('a cycle that ends in the next January', () {
      expect(_r(_cycle(1, '2026-12-15')), '2026-12-01|2026-12-31');
      expect(_r(_cycle(5, '2026-12-20')), '2026-12-05|2027-01-04');
    });
  });

  group('exact boundaries', () {
    test('start is inclusive and the day after the end is excluded', () {
      final r = _cycle(15, '2026-10-20'); // 2026-10-15 .. 2026-11-14
      expect(_r(r), '2026-10-15|2026-11-14');
      expect(
          PeriodMath.containsLocalDate(r, DateTime(2026, 10, 14, 23, 59, 59)),
          isFalse);
      expect(PeriodMath.containsLocalDate(r, DateTime(2026, 10, 15, 0, 0, 0)),
          isTrue);
      expect(
          PeriodMath.containsLocalDate(r, DateTime(2026, 11, 14, 23, 59, 59)),
          isTrue);
      expect(PeriodMath.containsLocalDate(r, DateTime(2026, 11, 15, 0, 0, 0)),
          isFalse);
    });

    test('a transaction timestamped at the last second of the cycle counts',
        () {
      final r = _cycle(15, '2026-10-20');
      final lastInstant = r.end; // 2359:59 on the end day
      expect(PeriodMath.containsLocalDate(r, lastInstant), isTrue);
      final firstInstantOfNext =
          DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59)
              .add(const Duration(seconds: 1));
      expect(PeriodMath.containsLocalDate(r, firstInstantOfNext), isFalse);
    });

    test('a UTC instant is compared by its LOCAL calendar day', () {
      final r = _cycle(15, '2026-10-20'); // 2026-10-15 .. 2026-11-14
      final utcOnEndDay = DateTime(2026, 11, 14, 12).toUtc();
      expect(PeriodMath.containsLocalDate(r, utcOnEndDay), isTrue);
    });
  });

  group('no gaps and no overlaps across a long range', () {
    for (final salaryDay in [1, 15, 28, 29, 30, 31]) {
      test('salary day $salaryDay, every day from 2025-01-01 to 2030-12-31',
          () {
        var day = DateTime(2025, 1, 1);
        final lastDay = DateTime(2030, 12, 31);
        var r = PeriodMath.salaryCycle(salaryDay: salaryDay, now: day);
        var cycles = 0;

        while (!PeriodMath.addDays(r.end, 1).isAfter(lastDay)) {
          // This cycle contains its own start and end days...
          expect(PeriodMath.containsLocalDate(r, r.start), isTrue);
          expect(PeriodMath.containsLocalDate(r, r.end), isTrue);
          // ...and every day inside it. Every day belongs to exactly one cycle.
          var d = r.start;
          while (!PeriodMath.addDays(d, 1).isAfter(r.end)) {
            expect(
              PeriodMath.containsLocalDate(r, d),
              isTrue,
              reason: 'salary day $salaryDay: $d missing from ${_r(r)}',
            );
            d = PeriodMath.addDays(d, 1);
          }

          // Contiguity: the next cycle starts the very next day (no gap),
          // and does not contain the previous cycle's last day (no overlap).
          final next = PeriodMath.salaryCycle(
              salaryDay: salaryDay, now: PeriodMath.addDays(r.end, 1));
          expect(next.start, PeriodMath.addDays(r.end, 1),
              reason: 'salary day $salaryDay: gap or overlap after ${_r(r)}');
          expect(PeriodMath.containsLocalDate(next, r.end), isFalse);

          r = next;
          cycles++;
        }
        expect(cycles, greaterThan(60));
      });
    }
  });

  group('timezone transitions', () {
    test('a cycle spanning a DST change keeps whole calendar days', () {
      // In a DST zone (e.g. Europe/London, 2026-03-29) a Duration-based
      // calculation shifts the day; calendar arithmetic must not.
      final r = _cycle(5, '2026-03-10'); // 2026-03-05 .. 2026-04-04
      expect(_r(r), '2026-03-05|2026-04-04');
      expect(r.start.hour, 0);
      expect(PeriodMath.dateOnly(r.end).hour, 0);
      // Every day in the range is reachable by calendar stepping.
      var d = r.start;
      var n = 0;
      while (!d.isAfter(PeriodMath.dateOnly(r.end))) {
        expect(PeriodMath.containsLocalDate(r, d), isTrue);
        d = PeriodMath.addDays(d, 1);
        n++;
      }
      expect(n, 31);
    });

    test('addDays never lands off midnight across a DST boundary', () {
      for (final date in [
        DateTime(2026, 3, 28),
        DateTime(2026, 3, 29),
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 25),
      ]) {
        expect(PeriodMath.addDays(date, 1).hour, 0);
        expect(PeriodMath.addDays(date, -1).hour, 0);
      }
    });
  });

  group('PeriodProvider uses the approved rule', () {
    test('currentPeriod follows the stored salary day', () {
      final p = PeriodProvider.fixedForTest(
        salaryDay: 25,
        now: DateTime(2026, 10, 12),
      );
      expect(_r(p.currentPeriod), '2026-09-25|2026-10-24');
    });

    test('previousPeriod is the cycle before, contiguous with current', () {
      final p = PeriodProvider.fixedForTest(
        salaryDay: 25,
        now: DateTime(2026, 10, 12),
      );
      expect(_r(p.previousPeriod!), '2026-08-25|2026-09-24');
      expect(p.previousPeriod!.end.isBefore(p.currentPeriod.start), isTrue);
      expect(PeriodMath.addDays(p.previousPeriod!.end, 1),
          PeriodMath.dateOnly(p.currentPeriod.start));
    });

    test('salary day 31: previous cycle picks up the clamped January start',
        () {
      final p = PeriodProvider.fixedForTest(
        salaryDay: 31,
        now: DateTime(2027, 3, 10),
      );
      expect(_r(p.currentPeriod), '2027-02-28|2027-03-30');
      expect(_r(p.previousPeriod!), '2027-01-31|2027-02-27');
    });

    test('nextSalaryDate honours the salary day, clamped', () {
      expect(PeriodMath.nextSalaryDate(25, now: DateTime(2026, 10, 20)),
          DateTime(2026, 10, 25));
      expect(PeriodMath.nextSalaryDate(25, now: DateTime(2026, 10, 25)),
          DateTime(2026, 10, 25));
      expect(PeriodMath.nextSalaryDate(25, now: DateTime(2026, 10, 26)),
          DateTime(2026, 11, 25));
      expect(PeriodMath.nextSalaryDate(31, now: DateTime(2027, 2, 27)),
          DateTime(2027, 2, 28));
    });

    test('an out-of-range salary day is rejected rather than normalised', () {
      expect(() => PeriodMath.clampStartDay(2026, 10, 0), throwsArgumentError);
      expect(() => PeriodMath.clampStartDay(2026, 10, 32), throwsArgumentError);
    });
  });

  group('calendar month is a separate, explicitly named period', () {
    test('calendar month is the 1st through the last day', () {
      expect(_r(PeriodMath.calendarMonth(DateTime(2026, 10, 12))),
          '2026-10-01|2026-10-31');
      expect(_r(PeriodMath.calendarMonth(DateTime(2027, 2, 10))),
          '2027-02-01|2027-02-28');
    });

    test('with salary day 25 the calendar month differs from the cycle', () {
      final p = PeriodProvider.fixedForTest(
        salaryDay: 25,
        now: DateTime(2026, 10, 12),
      );
      final month = PeriodMath.calendarMonth(DateTime(2026, 10, 12));
      expect(_r(month), '2026-10-01|2026-10-31');
      expect(_r(p.currentPeriod), '2026-09-25|2026-10-24');
      expect(month, isNot(equals(p.currentPeriod)));
    });
  });
}
