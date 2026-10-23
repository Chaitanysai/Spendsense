import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/home_screen.dart';

TransactionModel _tx({
  required String id,
  required int amount,
  required TransactionType type,
  required DateTime date,
  bool excluded = false,
}) {
  return TransactionModel(
    id: id,
    amount: amount,
    type: type,
    merchant: 'Test merchant',
    category: 'Food',
    paymentMethod: 'UPI',
    date: date,
    time: '12:00',
    originalSms: '',
    isExcluded: excluded,
    source: 'Test',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sms_scan_start_date': DateTime(2026, 10, 1).toIso8601String(),
    });
  });

  group('Home financial aggregates', () {
    test('income-only, expense-only, and mixed transactions keep direction',
        () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(
          id: 'income',
          amount: 100000,
          type: TransactionType.income,
          date: DateTime(2026, 10, 10),
        ),
        _tx(
          id: 'expense',
          amount: 342737,
          type: TransactionType.expense,
          date: DateTime(2026, 10, 11),
        ),
      ]);

      expect(provider.totalTrackedIncome, 10000000);
      expect(provider.totalTrackedExpenses, 34273700);
      expect(provider.availableBalance, -24273700);
    });

    test('empty and excluded transactions do not affect totals', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(
          id: 'excluded-income',
          amount: 50000,
          type: TransactionType.income,
          date: DateTime(2026, 10, 10),
          excluded: true,
        ),
      ]);

      expect(provider.totalTrackedIncome, 0);
      expect(provider.totalTrackedExpenses, 0);
      expect(provider.availableBalance, 0);
    });

    test('period spending includes both date boundaries and only expenses', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(
          id: 'start',
          amount: 1000,
          type: TransactionType.expense,
          date: DateTime(2026, 10, 1, 0, 1),
        ),
        _tx(
          id: 'end',
          amount: 2000,
          type: TransactionType.expense,
          date: DateTime(2026, 10, 31, 23, 59),
        ),
        _tx(
          id: 'income',
          amount: 9000,
          type: TransactionType.income,
          date: DateTime(2026, 10, 15),
        ),
        _tx(
          id: 'outside',
          amount: 7000,
          type: TransactionType.expense,
          date: DateTime(2026, 11, 1),
        ),
      ]);

      final range = DateTimeRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      );
      expect(provider.totalExpensesForPeriod(range), 300000);
    });
  });

  testWidgets('Home Activity quick action is present', (tester) async {
    final provider = TransactionProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Activity'), findsWidgets);
  });
}
