import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/bill_classifier.dart';
import 'package:spendsense/services/bill_detection_service.dart';
import 'package:spendsense/services/smart_parser.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

/// End-to-end checks from a synthetic bank SMS through the real parser to the
/// bill classifier. The messages are invented test fixtures, not user data.
void main() {
  final date = DateTime(2026, 10, 6, 12, 1);

  Future<TransactionModel?> parse(String sms, String id) =>
      SmartParser().parse(sms, id, date);

  Future<void> expectBill(String sms, String id, BillKind kind) async {
    final tx = await parse(sms, id);
    expect(tx, isNotNull, reason: id);
    final result = const BillClassifier().classify(tx!);
    expect(result.kind, kind, reason: id);
    expect(result.evidence, BillEvidence.paidBill, reason: id);
    expect(tx.billKindHint, kind.name, reason: id);
    expect(tx.billReminderHint, isFalse, reason: id);
  }

  Future<void> expectOrdinary(String sms, String id) async {
    final tx = await parse(sms, id);
    expect(tx, isNotNull, reason: id);
    final result = const BillClassifier().classify(tx!);
    expect(result.evidence, BillEvidence.ordinary, reason: id);
    expect(tx.billKindHint, BillKind.none.name, reason: id);
  }

  test('real parser output preserves bill-specific evidence', () async {
    await expectBill(
      'Rs 1,200.00 debited from A/c XX1234 towards BESCOM electricity bill on 05-10-26. Ref 123456789 - HDFC Bank',
      'utility',
      BillKind.utility,
    );
    await expectBill(
      'Rs 999.00 debited from A/c XX1234 for ACT Fibernet broadband bill on 05-10-26 - ICICI Bank',
      'broadband',
      BillKind.broadband,
    );
    await expectBill(
      'Rs 649.00 debited from A/c XX1234 for Airtel postpaid bill on 05-10-26 - Axis Bank',
      'mobile',
      BillKind.mobile,
    );
    await expectBill(
      'Rs 2,500.00 debited from A/c XX1234 towards HDFC home loan EMI on 05-10-26 - HDFC Bank',
      'loan',
      BillKind.loan,
    );
    await expectBill(
      'Rs 3,100.00 debited from A/c XX1234 towards LIC insurance premium on 05-10-26 - SBI',
      'insurance',
      BillKind.insurance,
    );
    await expectBill(
      'Rs 649.00 debited from A/c XX1234 for Netflix subscription on 05-10-26 - HDFC Bank',
      'subscription',
      BillKind.subscription,
    );
    await expectBill(
      'Rs 20,000.00 debited from A/c XX1234 towards house rent on 05-10-26 - HDFC Bank',
      'rent',
      BillKind.rent,
    );
  });

  test('real parser output keeps ordinary spending ordinary', () async {
    await expectOrdinary(
      'Rs 450.00 debited from A/c XX1234 for Swiggy order on 05-10-26 - HDFC Bank',
      'food',
    );
    await expectOrdinary(
      'Rs 2,000.00 debited from A/c XX1234 for HPCL petrol on 05-10-26 - HDFC Bank',
      'fuel',
    );
    await expectOrdinary(
      'Rs 3,000.00 debited from A/c XX1234 for Amazon order on 05-10-26 - HDFC Bank',
      'shopping',
    );
    await expectOrdinary(
      'Rs 500.00 debited from A/c XX1234 via UPI to RAHUL on 05-10-26 - HDFC Bank',
      'upi',
    );
    await expectOrdinary(
      'Rs 239.00 debited from A/c XX1234 for Jio Prepaid Recharges on 06-10-26 - Axis Bank',
      'prepaid',
    );
  });

  test('the non-sensitive bill hint survives a JSON round-trip', () async {
    final tx = await parse(
      'Rs 999.00 debited from A/c XX1234 for ACT Fibernet broadband bill on 05-10-26 - ICICI Bank',
      'round-trip',
    );
    expect(tx, isNotNull);
    final reread = TransactionModel.fromJson(tx!.toJson());
    expect(reread.billKindHint, BillKind.broadband.name);
    expect(reread.billReminderHint, isFalse);
    expect(reread.originalSms, isEmpty);
  });

  test('the hint survives encrypted cache storage and safe export', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = TransactionCacheService();
    await cache.init();
    final tx = await parse(
      'Rs 999.00 debited from A/c XX1234 for ACT Fibernet broadband bill on 05-10-26 - ICICI Bank',
      'cache-hint',
    );
    await cache.put(tx!);

    final loaded = await cache.get(tx.id);
    expect(loaded?.billKindHint, BillKind.broadband.name);
    expect(loaded?.originalSms, isEmpty);

    final safe = await cache.exportToJsonString();
    expect(safe, contains('billKindHint'));
    expect(safe, isNot(contains('ACT Fibernet broadband bill')));
  });

  test('a strong parsed utility payment becomes one paid bill', () async {
    final tx = await parse(
      'Rs 1,200.00 debited from A/c XX1234 towards BESCOM electricity bill on 05-10-26. Ref 123456789 - HDFC Bank',
      'utility-detection',
    );
    final views = const BillDetectionService().detect(
      plans: const [],
      transactions: [tx!],
      today: DateTime(2026, 10, 20),
    );
    expect(views, hasLength(1));
    expect(views.single.state, BillState.paid);
    expect(views.single.confidence, greaterThan(0.8));
  });
}
