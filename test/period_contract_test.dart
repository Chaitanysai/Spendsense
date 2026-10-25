// Contract tests for period boundary logic.
//
//  1. PeriodMath unit tests — the DST-safe, date-only boundary contract.
//  2. PeriodProvider tests for the APPROVED salary-cycle rule
//     (docs/product-readiness/remediation-phase-3.md). The earlier
//     "CURRENT:" characterization pins of the retired last-calendar-day
//     algorithm were removed when the rule was approved; they are superseded by
//     test/salary_cycle_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/utils/period_math.dart';

void main() {
  group('PeriodMath', () {
    group('addDays (calendar arithmetic, DST-safe, drops time-of-day)', () {
      test('across month end: Jan 31 + 1 day = Feb 1', () {
        expect(
          PeriodMath.addDays(DateTime(2026, 1, 31), 1),
          DateTime(2026, 2, 1),
        );
      });

      test('across year end: Dec 31 + 1 day = Jan 1 next year', () {
        expect(
          PeriodMath.addDays(DateTime(2026, 12, 31), 1),
          DateTime(2027, 1, 1),
        );
      });

      test('leap day: Feb 28 2028 + 1 day = Feb 29 2028', () {
        expect(
          PeriodMath.addDays(DateTime(2028, 2, 28), 1),
          DateTime(2028, 2, 29),
        );
      });

      test('leap day: Feb 29 2028 + 1 day = Mar 1 2028', () {
        expect(
          PeriodMath.addDays(DateTime(2028, 2, 29), 1),
          DateTime(2028, 3, 1),
        );
      });

      test('negative: Mar 1 - 1 day = Feb 28 in non-leap 2027', () {
        expect(
          PeriodMath.addDays(DateTime(2027, 3, 1), -1),
          DateTime(2027, 2, 28),
        );
      });

      test('negative: Mar 1 - 1 day = Feb 29 in leap 2028', () {
        expect(
          PeriodMath.addDays(DateTime(2028, 3, 1), -1),
          DateTime(2028, 2, 29),
        );
      });

      test('the result is always midnight', () {
        expect(
            PeriodMath.addDays(DateTime(2026, 10, 12, 18, 45, 30), 1).hour, 0);
        expect(PeriodMath.addDays(DateTime(2026, 10, 12, 18, 45, 30), 1).minute,
            0);
      });

      test('addDays(x, 0) equals dateOnly(x)', () {
        final x = DateTime(2026, 10, 12, 7, 8, 9);
        expect(PeriodMath.addDays(x, 0), PeriodMath.dateOnly(x));
      });
    });

    group('containsLocalDate (start day and end day inclusive)', () {
      final range = DateTimeRange(
        start: DateTime(2026, 10, 31),
        end: DateTime(2026, 11, 29, 23, 59, 59),
      );

      test('first instant of the start day is inside', () {
        expect(PeriodMath.containsLocalDate(range, DateTime(2026, 10, 31)),
            isTrue);
      });

      test('one second before the start day is outside', () {
        expect(
            PeriodMath.containsLocalDate(
                range, DateTime(2026, 10, 30, 23, 59, 59)),
            isFalse);
      });

      test('last second of the end day is inside', () {
        expect(
            PeriodMath.containsLocalDate(
                range, DateTime(2026, 11, 29, 23, 59, 59)),
            isTrue);
      });

      test('midnight after the end day is outside', () {
        expect(PeriodMath.containsLocalDate(range, DateTime(2026, 11, 30)),
            isFalse);
      });

      test('the whole end day is included even when the range end is midnight',
          () {
        final r = DateTimeRange(
            start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31));
        expect(PeriodMath.containsLocalDate(r, DateTime(2026, 10, 31, 18)),
            isTrue);
      });

      test('a UTC instant is judged by its local calendar day', () {
        expect(
          PeriodMath.containsLocalDate(
              range, DateTime(2026, 11, 29, 12).toUtc()),
          isTrue,
        );
      });
    });

    group('clampStartDay', () {
      test('a day that exists in the month is used as-is', () {
        expect(PeriodMath.clampStartDay(2026, 10, 25), DateTime(2026, 10, 25));
      });

      test('a day past the end of the month clamps to the last day', () {
        expect(PeriodMath.clampStartDay(2027, 2, 31), DateTime(2027, 2, 28));
        expect(PeriodMath.clampStartDay(2028, 2, 31), DateTime(2028, 2, 29));
        expect(PeriodMath.clampStartDay(2026, 11, 31), DateTime(2026, 11, 30));
      });

      test('a salary day outside 1..31 throws instead of normalising', () {
        expect(
            () => PeriodMath.clampStartDay(2026, 10, 0), throwsArgumentError);
        expect(
            () => PeriodMath.clampStartDay(2026, 10, 32), throwsArgumentError);
      });
    });

    group('calendarMonth is a separate, explicit period', () {
      test('runs from the 1st to the last day of the month', () {
        final m = PeriodMath.calendarMonth(DateTime(2026, 10, 12));
        expect(m.start, DateTime(2026, 10, 1));
        expect(m.end, DateTime(2026, 10, 31, 23, 59, 59));
        expect(PeriodMath.calendarMonth(DateTime(2027, 2, 3)).end.day, 28);
        expect(PeriodMath.calendarMonth(DateTime(2028, 2, 3)).end.day, 29);
      });
    });
  });

  group('PeriodProvider follows the approved salary-cycle rule', () {
    test('salaryAlignedPeriod defaults to calendar months for salary day 1',
        () {
      final p = PeriodProvider.salaryAlignedPeriod(now: DateTime(2026, 10, 12));
      expect(p.start, DateTime(2026, 10, 1));
      expect(p.end, DateTime(2026, 10, 31, 23, 59, 59));
    });

    test('salaryAlignedPeriod honours an explicit salary day', () {
      final p = PeriodProvider.salaryAlignedPeriod(
          salaryDay: 31, now: DateTime(2027, 2, 28));
      expect(p.start, DateTime(2027, 2, 28));
      expect(p.end, DateTime(2027, 3, 30, 23, 59, 59));
    });

    test('the rule holds for every day 2026-01-01..2028-12-31', () {
      for (var day = DateTime(2026, 1, 1);
          !day.isAfter(DateTime(2028, 12, 31));
          day = PeriodMath.addDays(day, 1)) {
        for (final salaryDay in [1, 15, 28, 29, 30, 31]) {
          final p = PeriodProvider.salaryAlignedPeriod(
              salaryDay: salaryDay, now: day);
          expect(PeriodMath.containsLocalDate(p, day), isTrue,
              reason: 'salary=$salaryDay now=$day -> ${p.start}..${p.end}');
          expect(p.start.isBefore(p.end), isTrue,
              reason: 'salary=$salaryDay now=$day');
        }
      }
    });

    test('changing the salary day changes currentPeriod (audit F1 resolved)',
        () async {
      SharedPreferences.setMockInitialValues({'salary_day': 1});
      final p = PeriodProvider();
      await p.init();
      final dayOne = p.currentPeriod.start;
      await p.setSalaryDay(25);
      expect(p.salaryDay, 25);
      expect(p.currentPeriod.start, isNot(dayOne));
    });

    test('custom mode still wins over the salary cycle', () {
      final custom = DateTimeRange(
          start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 15));
      final p = PeriodProvider.fixedForTest(
        salaryDay: 25,
        now: DateTime(2026, 10, 12),
        mode: PeriodMode.custom,
        custom: custom,
      );
      expect(p.currentPeriod, custom);
      expect(p.previousPeriod, isNull);
    });
  });
}
