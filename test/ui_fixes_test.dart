import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/formatters.dart';
import 'package:spendsense/widgets/amount_input_dialog.dart';
import 'package:spendsense/widgets/pressable.dart';

/// Regression tests for the UI audit fixes.
///
/// Each group pins a behaviour that was previously wrong, so the bug cannot
/// come back silently.

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('relative sync time', () {
    final now = DateTime(2026, 10, 28, 12, 0, 0);

    test('a bare time-of-day could not express staleness; this can', () {
      // The sync pill used to render "hh:mm a", so a sync from four days ago
      // looked identical to one from four minutes ago.
      expect(Formatters.relativeTime(now, now: now), 'just now');
      expect(
        Formatters.relativeTime(now.subtract(const Duration(seconds: 30)),
            now: now),
        'just now',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(minutes: 4)),
            now: now),
        '4m ago',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(hours: 3)),
            now: now),
        '3h ago',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(days: 2)),
            now: now),
        '2d ago',
      );
    });

    test('anything older than a week falls back to a date', () {
      final old = now.subtract(const Duration(days: 30));
      expect(Formatters.relativeTime(old, now: now), Formatters.date(old));
    });

    test('a clock that moved backwards reads as just now, never negative', () {
      expect(
        Formatters.relativeTime(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });
  });

  group('Pressable is reachable without touch', () {
    testWidgets('it takes focus and activates on Enter', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(Pressable(onTap: () => taps++, child: const Text('ACT'))),
      );

      // Regression: Pressable used to be a bare GestureDetector, invisible to
      // keyboard, D-pad and switch control.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(taps, 1, reason: 'focus + Enter must activate the control');
    });

    testWidgets('it paints a visible focus ring when focused', (tester) async {
      await tester.pumpWidget(
        _host(Pressable(onTap: () {}, child: const Text('ACT'))),
      );

      // No ring before focus.
      expect(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(DecoratedBox),
        ),
        findsOneWidget,
        reason: 'a focused control must show where focus is',
      );
    });

    testWidgets('a static Pressable still adds no feedback layer',
        (tester) async {
      await tester.pumpWidget(_host(const Pressable(child: Text('STATIC'))));
      expect(find.byType(FocusableActionDetector), findsNothing);
      expect(find.byType(PressFeedback), findsNothing);
    });

    testWidgets('a tap still fires exactly once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(Pressable(onTap: () => taps++, child: const Text('ACT'))),
      );
      await tester.tap(find.text('ACT'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('amount dialog validates inline and stays open', () {
    /// Pumps a launcher, opens the dialog, and returns a getter for the result
    /// future. The dialog is opened through a real button so the route is a
    /// normal modal, exactly as the app opens it.
    Future<Future<int?> Function()> openDialog(
      WidgetTester tester, {
      String initial = '',
      int? maxMinor,
    }) async {
      Future<int?>? result;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                result = showAmountDialog(
                  context,
                  title: 'Monthly budget',
                  initialText: initial,
                  maxMinor: maxMinor,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result!;
    }

    testWidgets('an empty amount shows an inline error and keeps the dialog',
        (tester) async {
      final result = await openDialog(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Regression: this used to close the dialog and SnackBar the failure,
      // losing the typed text and detaching the message from the field.
      expect(find.text('Enter an amount.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'the dialog must stay open so the amount can be corrected');
      expect(find.byType(SnackBar), findsNothing);

      // Cancel resolves the future with null.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result(), isNull);
    });

    testWidgets('a zero amount is rejected inline', (tester) async {
      final result = await openDialog(tester, initial: '0');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await result();
    });

    testWidgets('an over-limit amount is rejected inline', (tester) async {
      final result =
          await openDialog(tester, initial: '999999999', maxMinor: 100000);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('That amount is too large.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await result();
    });

    testWidgets('editing clears the stale error', (tester) async {
      final result = await openDialog(tester);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '500');
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount.'), findsNothing,
          reason: 'the message must not sit against corrected text');
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await result();
    });

    testWidgets('a valid amount returns integer paise', (tester) async {
      final result = await openDialog(tester, initial: '2500');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(await result(), 250000, reason: '₹2500 is 250000 paise');
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
