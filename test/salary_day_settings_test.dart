// Regression coverage for R9: salary day must be reachable from the UI and the
// value the user picks must be the value the cycle math consumes.
//
// The bug this file guards against: `SalaryDayPrompt` was fully built but
// `SalaryDayPrompt.show()` had ZERO call sites, and Settings had no salary row,
// so `salary_day` silently stayed at its default of 1 for every user while the
// budget copy still said "per cycle".
//
// Two layers are covered separately so a failure points at the right one:
//   * provider persistence  — setSalaryDay -> prefs -> init() round trip
//   * the UI entry point     — Settings shows a Salary day row that opens the
//                             prompt and writes the chosen day
//
// These are automated tests. They do NOT prove the shipping APK behaves this
// way on a device; see the release-gate document.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/settings_screen.dart';
import 'package:spendsense/utils/period_math.dart';

String _r(DateTimeRange r) =>
    '${PeriodMath.dateOnly(r.start).toIso8601String().substring(0, 10)}|'
    '${PeriodMath.dateOnly(r.end).toIso8601String().substring(0, 10)}';

/// Pumps the app shell and settles the Settings screen.
///
/// The shell's floating nav bar runs a continuous animation, so
/// `pumpAndSettle` never returns and a tap can land mid-transition. The tests
/// below therefore mount `SettingsScreen` directly — the same widget the
/// shell hosts (`main.dart` `_screens[4]`) — which isolates the behaviour
/// under test (the salary-day row) from the nav-bar animation.
Future<PeriodProvider> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final period = PeriodProvider();
  await period.init();
  final transactions = TransactionProvider();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: transactions),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: period),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  return period;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('R9 — salary day is persisted and consumed', () {
    test('defaults to 1 when nothing was ever saved', () async {
      SharedPreferences.setMockInitialValues({});
      final p = PeriodProvider();
      await p.init();
      expect(p.salaryDay, 1);
      expect(p.isSetupDone, isFalse,
          reason: 'nothing saved means setup was never completed');
    });

    test('setSalaryDay persists across a fresh provider (app restart)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final first = PeriodProvider();
      await first.init();
      await first.setSalaryDay(25);

      final second = PeriodProvider();
      await second.init();
      expect(second.salaryDay, 25);
      expect(second.isSetupDone, isTrue);
    });

    test('a persisted salary day drives currentPeriod, not just the field',
        () async {
      SharedPreferences.setMockInitialValues({'salary_day': 25});
      final p = PeriodProvider.fixedForTest(
        salaryDay: 25,
        now: DateTime.parse('2026-10-24T12:00:00'),
      );
      await p.init();
      expect(_r(p.currentPeriod), '2026-09-25|2026-10-24');
    });

    test('setSalaryDay resets custom mode so the cycle rule applies again',
        () async {
      SharedPreferences.setMockInitialValues({});
      final p = PeriodProvider();
      await p.init();
      p.setMode(
        PeriodMode.custom,
        custom: DateTimeRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );
      expect(p.mode, PeriodMode.custom);

      await p.setSalaryDay(10);
      expect(p.mode, PeriodMode.oneMonth);
      expect(p.customRange, isNull);
    });

    test('rejects an impossible salary day instead of normalising it',
        () async {
      SharedPreferences.setMockInitialValues({});
      final p = PeriodProvider();
      await p.init();
      expect(() => p.setSalaryDay(0), throwsA(isA<AssertionError>()));
      expect(() => p.setSalaryDay(32), throwsA(isA<AssertionError>()));
    });
  });

  group('R9 — the release-gate D1..D5 matrix (salary day 25 and 31)', () {
    // These are the exact rows from the gate document, so the executable
    // contract and the release checklist cannot drift apart.
    final cases = <String, ({int day, String now, String expected})>{
      'D1 salary 25 on 2026-10-24 is still the September cycle': (
        day: 25,
        now: '2026-10-24',
        expected: '2026-09-25|2026-10-24',
      ),
      'D2 salary 25 on 2026-10-25 resets to the October cycle': (
        day: 25,
        now: '2026-10-25',
        expected: '2026-10-25|2026-11-24',
      ),
      'D3 salary 31 on 2027-02-27 runs from the clamped January start': (
        day: 31,
        now: '2027-02-27',
        expected: '2027-01-31|2027-02-27',
      ),
      'D4 salary 31 on 2027-02-28 starts on the clamped Feb 28': (
        day: 31,
        now: '2027-02-28',
        expected: '2027-02-28|2027-03-30',
      ),
      'D5 salary 31 on 2027-03-31 restores day 31 after clamping': (
        day: 31,
        now: '2027-03-31',
        expected: '2027-03-31|2027-04-29',
      ),
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final c = entry.value;
        final range = PeriodMath.salaryCycle(
          salaryDay: c.day,
          now: DateTime.parse(c.now),
        );
        expect(_r(range), c.expected);
      });
    }

    test('both cycle boundaries are inclusive and the next day is not', () {
      final range = PeriodMath.salaryCycle(
        salaryDay: 25,
        now: DateTime.parse('2026-10-20'),
      );
      expect(PeriodMath.containsLocalDate(range, DateTime(2026, 9, 25)), isTrue,
          reason: 'the cycle start day belongs to the cycle');
      expect(
          PeriodMath.containsLocalDate(range, DateTime(2026, 10, 24)), isTrue,
          reason: 'the cycle end day belongs to the cycle');
      expect(
          PeriodMath.containsLocalDate(range, DateTime(2026, 10, 25)), isFalse,
          reason: 'the day after the cycle end must not count');
    });
  });

  group('R9 — short-month clamping', () {
    test('Feb 31 clamps to Feb 28 in a non-leap year', () {
      expect(PeriodMath.clampStartDay(2027, 2, 31), DateTime(2027, 2, 28));
    });

    test('Feb 31 clamps to Feb 29 in a leap year', () {
      expect(PeriodMath.clampStartDay(2028, 2, 31), DateTime(2028, 2, 29));
    });

    test('day 31 clamps in 30-day months but restores in 31-day months', () {
      expect(PeriodMath.clampStartDay(2027, 4, 31), DateTime(2027, 4, 30));
      expect(PeriodMath.clampStartDay(2027, 5, 31), DateTime(2027, 5, 31));
    });

    test('Feb 31 does not overflow into March (the DateTime trap)', () {
      final clamped = PeriodMath.clampStartDay(2027, 2, 31);
      expect(clamped.month, 2);
      expect(clamped.day, 28);
    });
  });

  group('R9 — Settings exposes the salary-day entry point', () {
    testWidgets('Settings shows a Salary day row with the active day',
        (tester) async {
      SharedPreferences.setMockInitialValues({'salary_day': 25});
      final period = await _pumpSettings(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(period.salaryDay, 25);
      expect(find.text('Salary day'), findsOneWidget);
      expect(find.text('Cycle starts on day 25'), findsOneWidget);
    });

    testWidgets('tapping the row opens the prompt, which persists the choice',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final period = await _pumpSettings(tester);
      expect(period.salaryDay, 1);

      await tester.ensureVisible(find.text('Salary day'));
      await tester.pump();
      await tester.tap(find.text('Salary day'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // The prompt is the only place these strings appear.
      expect(find.text('When do you get your salary?'), findsOneWidget);

      // Pick day 25 in the 1..31 grid, then confirm.
      await tester.tap(find.descendant(
        of: find.byType(GridView),
        matching: find.text('25'),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Set salary day'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(period.salaryDay, 25);
      expect(period.isSetupDone, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('salary_day'), 25,
          reason: 'the choice must survive an app restart');

      // The row reflects the new value once the sheet closes.
      expect(find.text('Cycle starts on day 25'), findsOneWidget);
    });
  });
}
