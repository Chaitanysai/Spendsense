import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/assistant/assistant_composer.dart';
import 'package:spendsense/services/assistant/assistant_date_resolver.dart';
import 'package:spendsense/services/assistant/finance_tool_engine.dart';
import 'package:spendsense/services/assistant/local_intent_parser.dart';
import 'package:spendsense/services/assistant/merchant_matcher.dart';

TransactionModel _groww(String id, DateTime date) => TransactionModel(
      id: id,
      amountMinor: 100000,
      type: TransactionType.expense,
      merchant: 'GROWW BROKING LTD',
      category: 'Investments',
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: '',
      isExcluded: false,
    );

void main() {
  final now = DateTime(2026, 10, 30, 12);
  final lastMonth = _groww('groww-sep', DateTime(2026, 9, 12));
  final thisMonth = _groww('groww-oct', DateTime(2026, 10, 12));

  AssistantComposer composer() => AssistantComposer(
        FinanceToolEngine(
          transactions: [lastMonth, thisMonth],
          plans: const [],
          now: now,
        ),
      );

  group('brand deletion respects the requested window', () {
    test('last month selects only that month, not the whole history', () {
      final window = AssistantDateResolver.resolve(
        'delete my groww transactions last month',
        now: now,
      );
      final intent = DeleteBrandsIntent(
        const [MerchantMatcher.groww],
        window: window,
      );
      final reply = composer().compose(intent);

      final pending = reply.pendingAction;
      expect(pending, isNotNull,
          reason: 'one in-window match should produce a preview');
      final ids = pending!.transactionIds;
      expect(ids, contains(lastMonth.id));
      expect(ids, isNot(contains(thisMonth.id)),
          reason: 'the current month is outside "last month"');
    });

    test('an all-time request still sees every transaction', () {
      final window = AssistantDateResolver.resolve(
        'delete my groww transactions',
        now: now,
      );
      expect(window.isAllTime, isTrue);
      final reply = composer().compose(
        DeleteBrandsIntent(const [MerchantMatcher.groww], window: window),
      );

      final ids = reply.pendingAction!.transactionIds;
      expect(ids, containsAll([lastMonth.id, thisMonth.id]));
    });

    test('a window with no matches previews nothing', () {
      final window = AssistantDateResolver.resolve(
        'delete my groww transactions in 2024',
        now: now,
      );
      final reply = composer().compose(
        DeleteBrandsIntent(const [MerchantMatcher.groww], window: window),
      );
      expect(reply.pendingAction, isNull);
    });
  });
}
