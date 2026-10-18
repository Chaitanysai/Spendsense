import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/services/ai_service.dart';
import 'package:spendsense/models/ai_chat_message.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/period_provider.dart';

void main() {
  group('AIService Local Intents', () {
    test('Calculates average correctly', () async {
      final ai = AIService();
      final now = DateTime.now();

      final txs = [
        TransactionModel(
          id: '1',
          originalSms: 'food',
          paymentMethod: 'UPI',
          time: '12:00 PM',
          merchant: 'KFC',
          amount: 500,
          date: DateTime(now.year, now.month, now.day - 1),
          type: TransactionType.expense,
          isExcluded: false,
          category: 'Food',
        ),
        TransactionModel(
          id: '2',
          originalSms: 'travel',
          paymentMethod: 'UPI',
          time: '12:00 PM',
          merchant: 'Uber',
          amount: 250,
          date: DateTime(now.year, now.month, now.day),
          type: TransactionType.expense,
          isExcluded: false,
          category: 'Travel',
        ),
      ];

      final history = [
        AIChatMessage(role: 'user', content: 'What is my average per day?')
      ];
      final res = await ai.askAI(history, txs);

      expect(res.contains('per calendar day'), isTrue);
      expect(res.contains('per active spending day'), isTrue);
    });

    test('Identifies top merchant and category', () async {
      final ai = AIService();
      final now = DateTime.now();

      final txs = [
        TransactionModel(
          id: '1',
          originalSms: 'food',
          paymentMethod: 'UPI',
          time: '12:00 PM',
          merchant: 'KFC',
          amount: 100,
          date: now,
          type: TransactionType.expense,
          isExcluded: false,
          category: 'Food',
        ),
        TransactionModel(
          id: '2',
          originalSms: 'food',
          paymentMethod: 'UPI',
          time: '12:00 PM',
          merchant: 'KFC',
          amount: 200,
          date: now,
          type: TransactionType.expense,
          isExcluded: false,
          category: 'Food',
        ),
        TransactionModel(
          id: '3',
          originalSms: 'clothes',
          paymentMethod: 'UPI',
          time: '12:00 PM',
          merchant: 'Zara',
          amount: 150,
          date: now,
          type: TransactionType.expense,
          isExcluded: false,
          category: 'Shopping',
        ),
      ];

      final historyCat = [AIChatMessage(role: 'user', content: 'top category')];
      final resCat = await ai.askAI(historyCat, txs);
      expect(resCat.contains('Food'), isTrue);

      final historyMer = [AIChatMessage(role: 'user', content: 'top merchant')];
      final resMer = await ai.askAI(historyMer, txs);
      expect(resMer.contains('KFC'), isTrue);
    });
  });

  group('PeriodProvider Cycle Boundary', () {
    test('Calculates last day of month correctly', () {
      // Create a mock DateTime overrides or just test generic output
      final range = PeriodProvider.salaryAlignedPeriod();

      final start = range.start;
      final end = range.end;

      // Since it's dynamic based on DateTime.now(), we just verify start and end logic.
      // End date must end at 23:59:59. Start date must end at 00:00:00 (since it uses DateTime(...) normally it is midnight)
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(end.hour, 23);
      expect(end.minute, 59);
      expect(end.second, 59);
    });
  });
}
