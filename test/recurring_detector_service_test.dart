import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/recurring_detector_service.dart';

TransactionModel _tx(
  String id,
  DateTime date,
  int amount,
  TransactionType type,
) {
  return TransactionModel(
    id: id,
    amount: amount,
    type: type,
    merchant: 'Same Merchant',
    category: 'Bills',
    paymentMethod: 'UPI',
    date: date,
    time: '09:00',
    originalSms: '',
    isExcluded: false,
  );
}

void main() {
  final service = RecurringDetectorService();

  test('income rows do not create recurring payments', () {
    final recurring = service.detectRecurring([
      _tx('income-1', DateTime(2026, 1, 1), 5000, TransactionType.income),
      _tx('income-2', DateTime(2026, 2, 1), 5000, TransactionType.income),
    ]);

    expect(recurring, isEmpty);
  });

  test('income rows do not inflate recurring expense costs', () {
    final recurring = service.detectRecurring([
      _tx('expense-1', DateTime(2026, 1, 1), 100, TransactionType.expense),
      _tx('income', DateTime(2026, 1, 15), 9000, TransactionType.income),
      _tx('expense-2', DateTime(2026, 2, 1), 200, TransactionType.expense),
    ]);

    expect(recurring, hasLength(1));
    expect(recurring.single.occurrenceCount, 2);
    expect(recurring.single.averageAmountMinor, 15000);
    expect(
      service.getEstimatedMonthlyCostMinor(recurring),
      15000,
    );
  });
}
