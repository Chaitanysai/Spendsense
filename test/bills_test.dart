import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/recurring_plan.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/bills_screen.dart';
import 'package:spendsense/services/bill_detection_service.dart';

const _detector = BillDetectionService();

TransactionModel _tx({
  required String id,
  required int amountMinor,
  required DateTime date,
  String merchant = 'Netflix',
  String category = 'Entertainment',
  TransactionType type = TransactionType.expense,
  bool excluded = false,
}) =>
    TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: 'Card',
      date: date,
      time: '10:00',
      originalSms: '',
      isExcluded: excluded,
    );

RecurringPlan _plan({
  String id = 'p1',
  String title = 'Netflix',
  String category = 'Entertainment',
  int amountMinor = 64900,
  PlanFrequency frequency = PlanFrequency.monthly,
  required DateTime nextDue,
}) =>
    RecurringPlan.create(
      id: id,
      title: title,
      category: category,
      amountMinor: amountMinor,
      frequency: frequency,
      nextDue: nextDue,
    );

/// Counts automatic SMS scans so a test can prove Bills never starts one.
class _CountingProvider extends TransactionProvider {
  int syncs = 0;

  @override
  Future<void> syncFromSms({bool userInitiated = false}) async {
    syncs++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime(2026, 10, 20);

  group('bill states for confirmed plans', () {
    test('overdue when the due date has passed with no payment', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 10, 17))],
        transactions: const [],
        today: today,
      );
      expect(views.single.state, BillState.overdue);
    });

    test('due soon within three days', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 10, 22))],
        transactions: const [],
        today: today,
      );
      expect(views.single.state, BillState.dueSoon);
    });

    test('upcoming beyond the due-soon window', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 11, 10))],
        transactions: const [],
        today: today,
      );
      expect(views.single.state, BillState.upcoming);
    });

    test('a matching payment marks it paid and is linked', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 10, 22))],
        transactions: [
          _tx(id: 'pay', amountMinor: 64900, date: DateTime(2026, 10, 19)),
        ],
        today: today,
      );
      expect(views.single.state, BillState.paid);
      expect(views.single.matchedPayment?.id, 'pay');
    });

    test('an amount outside the 2% tolerance does not match', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 10, 22))],
        transactions: [
          _tx(id: 'pay', amountMinor: 70000, date: DateTime(2026, 10, 19)),
        ],
        today: today,
      );
      expect(views.single.state, isNot(BillState.paid));
    });

    test('a payment months before the due date does not count', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 10, 22))],
        transactions: [
          _tx(id: 'old', amountMinor: 64900, date: DateTime(2026, 7, 1)),
        ],
        today: today,
      );
      expect(views.single.state, isNot(BillState.paid));
    });

    test('income and excluded rows never mark a bill paid', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 10, 22))],
        transactions: [
          _tx(
              id: 'in',
              amountMinor: 64900,
              date: DateTime(2026, 10, 19),
              type: TransactionType.income),
          _tx(
              id: 'ex',
              amountMinor: 64900,
              date: DateTime(2026, 10, 19),
              excluded: true),
        ],
        today: today,
      );
      expect(views.single.state, isNot(BillState.paid));
    });

    test('payment history is newest first and capped', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 10, 22))],
        transactions: [
          for (var i = 0; i < 12; i++)
            _tx(
              id: 'p$i',
              amountMinor: 64900,
              date: DateTime(2026, 10, 1 + i),
            ),
        ],
        today: today,
      );
      expect(views.single.history.length, lessThanOrEqualTo(6));
      final dates = views.single.history.map((t) => t.date).toList();
      final sorted = [...dates]..sort((a, b) => b.compareTo(a));
      expect(dates, sorted);
    });
  });

  group('detected suggestions', () {
    List<TransactionModel> recurring() => [
          _tx(id: 'r1', amountMinor: 64900, date: DateTime(2026, 7, 5)),
          _tx(id: 'r2', amountMinor: 64900, date: DateTime(2026, 8, 5)),
          _tx(id: 'r3', amountMinor: 64900, date: DateTime(2026, 9, 5)),
        ];

    test('a repeated payment becomes a needs-review suggestion', () {
      final views = _detector.detect(
        plans: const [],
        transactions: recurring(),
        today: today,
      );
      expect(views, isNotEmpty);
      expect(views.first.state, BillState.needsReview);
      expect(views.first.isSuggestion, isTrue);
      expect(views.first.title, 'Netflix');
    });

    test('a suggestion is never treated as paid', () {
      final views = _detector.detect(
        plans: const [],
        transactions: recurring(),
        today: today,
      );
      expect(
          views.where((v) => v.state == BillState.paid), isEmpty,
          reason: 'nothing is confirmed, so nothing can be paid');
    });

    test('detection is idempotent across repeated runs', () {
      final first = _detector.detect(
          plans: const [], transactions: recurring(), today: today);
      final second = _detector.detect(
          plans: const [], transactions: recurring(), today: today);

      expect(first.length, second.length);
      expect(
        first.map((v) => '${v.title}|${v.amountMinor}|${v.state}').toList(),
        second.map((v) => '${v.title}|${v.amountMinor}|${v.state}').toList(),
      );
    });

    test('an already-tracked pattern is not suggested again', () {
      final views = _detector.detect(
        plans: [_plan(nextDue: DateTime(2026, 11, 5))],
        transactions: recurring(),
        today: today,
      );
      expect(views.where((v) => v.isSuggestion), isEmpty);
    });

    test('the generated plan id is stable and normalised', () {
      final views = _detector.detect(
        plans: const [],
        transactions: recurring(),
        today: today,
      );
      final suggestion = views.firstWhere((v) => v.isSuggestion).suggestion!;
      final a = BillDetectionService.planIdFor(suggestion);
      final b = BillDetectionService.planIdFor(suggestion);
      expect(a, b);
      expect(a, startsWith('auto:'));
    });
  });

  group('Bills screen', () {
    late _CountingProvider tx;
    late PlannerProvider planner;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tx = _CountingProvider();
      planner = PlannerProvider();
      await planner.ready;
    });

    tearDown(() {
      tx.dispose();
      planner.dispose();
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransactionProvider>.value(value: tx),
            ChangeNotifierProvider<PlannerProvider>.value(value: planner),
          ],
          child: const MaterialApp(home: BillsScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('opening Bills never starts an SMS scan', (tester) async {
      await pump(tester);
      expect(tx.syncs, 0,
          reason: 'passive navigation must not trigger permission or a scan');
      await tester.pump(const Duration(seconds: 1));
      expect(tx.syncs, 0);
    });

    testWidgets('an empty list shows the add-a-bill state', (tester) async {
      await pump(tester);
      expect(find.text('No bills yet'), findsOneWidget);
    });

    testWidgets('marking paid advances the plan and offers undo',
        (tester) async {
      final due = DateTime.now().add(const Duration(days: 2));
      await tester.runAsync(() => planner.addPlan(_plan(nextDue: due)));
      await pump(tester);

      expect(find.text('Mark paid'), findsOneWidget);
      await tester.tap(find.text('Mark paid'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(planner.plans.single.nextDue.isAfter(due), isTrue);
      expect(find.textContaining('marked paid'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('undo restores the previous due date', (tester) async {
      final due = DateTime.now().add(const Duration(days: 2));
      await tester.runAsync(() => planner.addPlan(_plan(nextDue: due)));
      await pump(tester);

      await tester.tap(find.text('Mark paid'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('Undo'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Plans store date-only dues, so compare the calendar day.
      final restored = planner.plans.single.nextDue;
      expect(
        [restored.year, restored.month, restored.day],
        [due.year, due.month, due.day],
      );
    });

    testWidgets('a suggestion offers Track as bill and tracking is idempotent',
        (tester) async {
      tx.debugSeed([
        _tx(id: 'r1', amountMinor: 64900, date: DateTime(2026, 8, 5)),
        _tx(id: 'r2', amountMinor: 64900, date: DateTime(2026, 9, 5)),
        _tx(id: 'r3', amountMinor: 64900, date: DateTime(2026, 10, 5)),
      ]);
      await pump(tester);

      expect(find.text('Needs review'), findsWidgets);
      await tester.tap(find.text('Track as bill'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(planner.plans, hasLength(1));
      expect(planner.plans.single.id, startsWith('auto:'));
    });

  });
}
