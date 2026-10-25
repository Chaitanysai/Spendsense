import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/models/recurring_plan.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/bill_classification_advisor.dart';
import 'package:spendsense/services/bill_classifier.dart';
import 'package:spendsense/services/bill_detection_service.dart';

const _classifier = BillClassifier();
const _detector = BillDetectionService();
final _today = DateTime(2026, 10, 20);

TransactionModel _tx({
  required String id,
  required int amountMinor,
  required DateTime date,
  required String merchant,
  required String category,
  String sms = '',
  String? reference,
  TransactionType type = TransactionType.expense,
  bool excluded = false,
  String? sourceTransactionId,
  String? billKindHint,
  bool billReminderHint = false,
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
      originalSms: sms,
      isExcluded: excluded,
      reference: reference,
      source: sourceTransactionId ?? 'SMS-Parser',
      billKindHint: billKindHint,
      billReminderHint: billReminderHint,
    );

RecurringPlan _plan({
  String id = 'p1',
  String title = 'Airtel Postpaid',
  String category = 'Bills',
  int amountMinor = 64900,
  DateTime? nextDue,
  String? sourceTransactionId,
}) =>
    RecurringPlan.create(
      id: id,
      title: title,
      category: category,
      amountMinor: amountMinor,
      frequency: PlanFrequency.monthly,
      nextDue: nextDue ?? DateTime(2026, 10, 22),
      sourceTransactionId: sourceTransactionId,
    );

void main() {
  group('reminder vs payment', () {
    test('a utility reminder is ambiguous and never a payment', () {
      final result = _classifier.classifyText(
        'Your electricity bill of Rs 1,200 is due on 25 Oct. Pay before 25 Oct.',
        merchant: 'BESCOM',
        category: 'Bills',
        amountMinor: 120000,
      );
      expect(result.kind, BillKind.utility);
      expect(result.reminderOnly, isTrue);
      expect(result.evidence, BillEvidence.ambiguous);
      expect(result.evidence, isNot(BillEvidence.paidBill));
    });

    test('a utility payment confirmation is a strong paid bill', () {
      final result = _classifier.classifyText(
        'Rs 1,200 debited from A/c for BESCOM electricity bill. Payment successful.',
        merchant: 'BESCOM',
        category: 'Bills',
        amountMinor: 120000,
      );
      expect(result.kind, BillKind.utility);
      expect(result.reminderOnly, isFalse);
      expect(result.evidence, BillEvidence.paidBill);
      expect(result.confidence, greaterThan(0.8));
    });
  });

  group('supported bill kinds', () {
    test('broadband and postpaid mobile bills are classified', () {
      final broadband = _classifier.classifyText(
        'Rs 999 debited for ACT Fibernet broadband bill',
        merchant: 'ACT Fibernet',
        category: 'Bills',
        amountMinor: 99900,
      );
      final mobile = _classifier.classifyText(
        'Rs 649 debited for Airtel postpaid bill',
        merchant: 'Airtel',
        category: 'Bills',
        amountMinor: 64900,
      );
      expect(broadband.kind, BillKind.broadband);
      expect(mobile.kind, BillKind.mobile);
      expect(broadband.evidence, BillEvidence.paidBill);
      expect(mobile.evidence, BillEvidence.paidBill);
    });

    test('loan / EMI reminders and payments are separated', () {
      final reminder = _classifier.classifyText(
        'Your EMI of Rs 2,500 is due on 5 Nov.',
        merchant: 'HDFC Bank',
        category: 'Bills',
        amountMinor: 250000,
      );
      final paid = _classifier.classifyText(
        'Rs 2,500 debited towards EMI repayment',
        merchant: 'HDFC Bank',
        category: 'Bills',
        amountMinor: 250000,
      );
      expect(reminder.kind, BillKind.loan);
      expect(reminder.evidence, BillEvidence.ambiguous);
      expect(paid.kind, BillKind.loan);
      expect(paid.evidence, BillEvidence.paidBill);
    });

    test('insurance premiums and subscriptions are classified', () {
      final insurance = _classifier.classifyText(
        'LIC premium of Rs 3,100 debited. Policy no 123.',
        merchant: 'LIC',
        category: 'Bills',
        amountMinor: 310000,
        reference: 'POL123',
      );
      final subscription = _classifier.classifyText(
        'Rs 649 debited for Netflix subscription renewal',
        merchant: 'Netflix',
        category: 'Entertainment',
        amountMinor: 64900,
      );
      expect(insurance.kind, BillKind.insurance);
      expect(insurance.evidence, BillEvidence.paidBill);
      expect(subscription.kind, BillKind.subscription);
      expect(subscription.evidence, BillEvidence.paidBill);
    });
  });

  group('stored bill hints', () {
    test('a broadband hint survives a lost merchant label', () {
      final tx = _tx(
        id: 'hint-broadband',
        amountMinor: 99900,
        date: DateTime(2026, 10, 5),
        merchant: 'Bank Debit',
        category: 'Bills',
        billKindHint: BillKind.broadband.name,
      );
      final result = _classifier.classify(tx);
      expect(result.kind, BillKind.broadband);
      expect(result.evidence, BillEvidence.paidBill);
    });

    test('an explicit ordinary hint overrides a bill-like merchant', () {
      final tx = _tx(
        id: 'hint-none',
        amountMinor: 23900,
        date: DateTime(2026, 10, 5),
        merchant: 'Jio',
        category: 'Bills',
        billKindHint: BillKind.none.name,
      );
      expect(_classifier.classify(tx).evidence, BillEvidence.ordinary);
    });

    test('a reminder hint never becomes a paid bill', () {
      final tx = _tx(
        id: 'hint-reminder',
        amountMinor: 64900,
        date: DateTime(2026, 10, 5),
        merchant: 'Airtel',
        category: 'Bills',
        billKindHint: BillKind.mobile.name,
        billReminderHint: true,
      );
      final result = _classifier.classify(tx);
      expect(result.evidence, BillEvidence.ambiguous);
      final views = _detector.detect(
        plans: const [],
        transactions: [tx],
        today: _today,
      );
      expect(views, isEmpty);
    });
  });

  group('false-positive safeguards', () {
    final cases = <String, TransactionModel>{
      'grocery': _tx(
        id: 'g',
        amountMinor: 45000,
        date: DateTime(2026, 10, 1),
        merchant: 'BigBasket',
        category: 'Food',
        sms: 'Rs 450 debited for grocery order',
      ),
      'restaurant': _tx(
        id: 'r',
        amountMinor: 90000,
        date: DateTime(2026, 10, 2),
        merchant: 'Swiggy',
        category: 'Food',
        sms: 'Rs 900 debited for restaurant order',
      ),
      'fuel': _tx(
        id: 'f',
        amountMinor: 200000,
        date: DateTime(2026, 10, 3),
        merchant: 'HPCL',
        category: 'Fuel',
        sms: 'Rs 2,000 debited for petrol',
      ),
      'shopping with bill wording': _tx(
        id: 's',
        amountMinor: 300000,
        date: DateTime(2026, 10, 4),
        merchant: 'Amazon',
        category: 'Shopping',
        sms: 'Rs 3,000 debited for Amazon bill payment',
      ),
      'generic UPI': _tx(
        id: 'u',
        amountMinor: 50000,
        date: DateTime(2026, 10, 5),
        merchant: 'Rahul',
        category: 'UPI',
        sms: 'Rs 500 debited via UPI transfer',
      ),
      'cash withdrawal': _tx(
        id: 'c',
        amountMinor: 200000,
        date: DateTime(2026, 10, 6),
        merchant: 'ATM',
        category: 'Cash',
        sms: 'Rs 2,000 cash withdrawal',
      ),
      'person to person': _tx(
        id: 'p',
        amountMinor: 100000,
        date: DateTime(2026, 10, 7),
        merchant: 'Priya',
        category: 'Transfer',
        sms: 'Rs 1,000 sent to Priya',
      ),
      'prepaid recharge': _tx(
        id: 'pre',
        amountMinor: 23900,
        date: DateTime(2026, 10, 8),
        merchant: 'Jio',
        category: 'Bills',
        sms: 'Rs 239 debited for Jio prepaid recharge',
      ),
    };

    for (final entry in cases.entries) {
      test('${entry.key} is never a bill candidate', () {
        final result = _classifier.classify(entry.value);
        expect(result.evidence, BillEvidence.ordinary, reason: entry.key);
        final views = _detector.detect(
          plans: const [],
          transactions: [entry.value],
          today: _today,
        );
        expect(views, isEmpty, reason: entry.key);
      });
    }

    test('a repeated grocery pattern never becomes a bill', () {
      final views = _detector.detect(
        plans: const [],
        transactions: [
          for (var i = 0; i < 4; i++)
            _tx(
              id: 'g$i',
              amountMinor: 45000,
              date: DateTime(2026, 7 + i, 5),
              merchant: 'BigBasket',
              category: 'Food',
              sms: 'Rs 450 debited for grocery order',
            ),
        ],
        today: _today,
      );
      expect(views, isEmpty);
    });
  });

  group('single transaction vs reliable recurrence', () {
    test('one strong utility payment is a paid bill, not a recurring bill', () {
      final views = _detector.detect(
        plans: const [],
        transactions: [
          _tx(
            id: 'u1',
            amountMinor: 120000,
            date: DateTime(2026, 10, 5),
            merchant: 'BESCOM',
            category: 'Bills',
            sms: 'Rs 1,200 debited for electricity bill',
          ),
        ],
        today: _today,
      );
      expect(views, hasLength(1));
      expect(views.single.state, BillState.paid);
      expect(views.single.autoBill!.isRecurring, isFalse);
      expect(views.single.autoBill!.occurrenceCount, 1);
    });

    test('a reliable monthly pattern becomes an automatic recurring bill', () {
      final views = _detector.detect(
        plans: const [],
        transactions: [
          _tx(
            id: 'e1',
            amountMinor: 120000,
            date: DateTime(2026, 7, 5),
            merchant: 'BESCOM',
            category: 'Bills',
            sms: 'Rs 1,200 debited for electricity bill',
          ),
          _tx(
            id: 'e2',
            amountMinor: 125000,
            date: DateTime(2026, 8, 5),
            merchant: 'BESCOM',
            category: 'Bills',
            sms: 'Rs 1,250 debited for electricity bill',
          ),
          _tx(
            id: 'e3',
            amountMinor: 118000,
            date: DateTime(2026, 9, 5),
            merchant: 'BESCOM',
            category: 'Bills',
            sms: 'Rs 1,180 debited for electricity bill',
          ),
        ],
        today: _today,
      );
      expect(views, hasLength(1));
      final bill = views.single;
      expect(bill.isAutoDetected, isTrue);
      expect(bill.autoBill!.isRecurring, isTrue);
      expect(bill.autoBill!.occurrenceCount, 3);
      expect(bill.state, BillState.overdue);
      expect(bill.dueDate, DateTime(2026, 10, 5));
    });

    test('a single generic bill mention stays ordinary', () {
      final views = _detector.detect(
        plans: const [],
        transactions: [
          _tx(
            id: 'generic',
            amountMinor: 50000,
            date: DateTime(2026, 10, 5),
            merchant: 'PhonePe',
            category: 'Bills',
            sms: 'Rs 500 bill payment debited',
          ),
        ],
        today: _today,
      );
      expect(views, isEmpty);
    });

    test('a reminder-only transaction cannot create a paid bill', () {
      final views = _detector.detect(
        plans: const [],
        transactions: [
          _tx(
            id: 'reminder-only',
            amountMinor: 120000,
            date: DateTime(2026, 10, 5),
            merchant: 'BESCOM',
            category: 'Bills',
            sms: 'Your electricity bill of Rs 1,200 is due on 10 Oct.',
          ),
        ],
        today: _today,
      );
      expect(views, isEmpty);
    });

    test('duplicate SMS content cannot create duplicate bills', () {
      final views = _detector.detect(
        plans: const [],
        transactions: [
          _tx(
            id: 'one',
            amountMinor: 120000,
            date: DateTime(2026, 10, 5),
            merchant: 'BESCOM',
            category: 'Bills',
            sms: 'Rs 1,200 debited for electricity bill',
            reference: 'REF1',
          ),
          _tx(
            id: 'two',
            amountMinor: 120000,
            date: DateTime(2026, 10, 5),
            merchant: 'BESCOM',
            category: 'Bills',
            sms: 'Rs 1,200 debited for electricity bill',
            reference: 'REF1',
          ),
        ],
        today: _today,
      );
      expect(views, hasLength(1));
    });

    test('a hidden bill key suppresses the derived row', () {
      final tx = _tx(
        id: 'u1',
        amountMinor: 120000,
        date: DateTime(2026, 10, 5),
        merchant: 'BESCOM',
        category: 'Bills',
        sms: 'Rs 1,200 debited for electricity bill',
      );
      final key = _classifier.classify(tx).billerKey;
      final views = _detector.detect(
        plans: const [],
        transactions: [tx],
        today: _today,
        hiddenBillKeys: {key},
      );
      expect(views, isEmpty);
    });
  });

  group('plan payment matching', () {
    test('a strong biller + amount + window match marks the plan paid', () {
      final views = _detector.detect(
        plans: [_plan()],
        transactions: [
          _tx(
            id: 'pay',
            amountMinor: 64900,
            date: DateTime(2026, 10, 19),
            merchant: 'Airtel Postpaid',
            category: 'Bills',
            sms: 'Rs 649 debited for Airtel postpaid bill',
          ),
        ],
        today: _today,
      );
      expect(views.single.state, BillState.paid);
      expect(views.single.matchedPayment?.id, 'pay');
    });

    test('a weak same-category merchant does not mark the plan paid', () {
      final views = _detector.detect(
        plans: [_plan(title: 'Monthly bill')],
        transactions: [
          _tx(
            id: 'pay',
            amountMinor: 64900,
            date: DateTime(2026, 10, 19),
            merchant: 'Some Shop',
            category: 'Bills',
            sms: 'Rs 649 debited',
          ),
        ],
        today: _today,
      );
      expect(views.single.state, isNot(BillState.paid));
      expect(views.single.matchedPayment, isNull);
    });

    test('a reference match can identify an otherwise different payee', () {
      final source = _tx(
        id: 'source',
        amountMinor: 310000,
        date: DateTime(2026, 7, 5),
        merchant: 'LIC',
        category: 'Bills',
        sms: 'LIC premium debited',
        reference: 'POL123',
      );
      final payment = _tx(
        id: 'pay',
        amountMinor: 310000,
        date: DateTime(2026, 10, 19),
        merchant: 'Bank Debit',
        category: 'Bills',
        sms: 'Rs 3,100 debited',
        reference: 'POL123',
      );
      final views = _detector.detect(
        plans: [
          _plan(
            title: 'Life insurance',
            amountMinor: 310000,
            sourceTransactionId: 'source',
          ),
        ],
        transactions: [source, payment],
        today: _today,
      );
      expect(views.single.state, BillState.paid);
      expect(views.single.matchedPayment?.id, 'pay');
    });

    test('partial or incorrect amounts do not match', () {
      final views = _detector.detect(
        plans: [_plan(amountMinor: 100000)],
        transactions: [
          _tx(
            id: 'partial',
            amountMinor: 80000,
            date: DateTime(2026, 10, 19),
            merchant: 'Airtel Postpaid',
            category: 'Bills',
            sms: 'Rs 800 debited for Airtel bill',
          ),
        ],
        today: _today,
      );
      expect(views.single.state, isNot(BillState.paid));
      expect(views.single.matchedPayment, isNull);
    });

    test('reminder text never marks a plan paid', () {
      final views = _detector.detect(
        plans: [_plan()],
        transactions: [
          _tx(
            id: 'reminder',
            amountMinor: 64900,
            date: DateTime(2026, 10, 19),
            merchant: 'Airtel Postpaid',
            category: 'Bills',
            sms: 'Your Airtel bill of Rs 649 is due on 22 Oct. Please pay.',
          ),
        ],
        today: _today,
      );
      expect(views.single.state, isNot(BillState.paid));
      expect(views.single.matchedPayment, isNull);
    });

    test('one payment cannot pay two plans', () {
      final views = _detector.detect(
        plans: [
          _plan(id: 'p1', title: 'Airtel'),
          _plan(id: 'p2', title: 'Airtel Postpaid'),
        ],
        transactions: [
          _tx(
            id: 'pay',
            amountMinor: 64900,
            date: DateTime(2026, 10, 19),
            merchant: 'Airtel Postpaid',
            category: 'Bills',
            sms: 'Rs 649 debited for Airtel postpaid bill',
          ),
        ],
        today: _today,
      );
      expect(views.where((v) => v.state == BillState.paid), hasLength(1));
      final paidIds = views
          .where((v) => v.matchedPayment != null)
          .map((v) => v.matchedPayment!.id)
          .toSet();
      expect(paidIds, {'pay'});
    });

    test('a payment outside the due window does not match', () {
      final views = _detector.detect(
        plans: [_plan()],
        transactions: [
          _tx(
            id: 'old',
            amountMinor: 64900,
            date: DateTime(2026, 7, 1),
            merchant: 'Airtel Postpaid',
            category: 'Bills',
            sms: 'Rs 649 debited for Airtel postpaid bill',
          ),
        ],
        today: _today,
      );
      expect(views.single.state, isNot(BillState.paid));
    });
  });

  group('optional advisor boundary', () {
    test('the local-only advisor performs no work and returns nothing',
        () async {
      final result = await const LocalOnlyBillAdvisor().advise(
        const BillAdvisoryRequest(
          redactedText: 'electricity bill',
          localKind: BillKind.utility,
          localConfidence: 0.8,
        ),
      );
      expect(result, isNull);
    });

    test('redaction removes account, phone, OTP and balance data', () {
      final redacted = BillTextRedactor.redact(
        'A/c 123456789012 debited Rs 649. OTP 4321. Call 9876543210. '
        'Avl bal 5000. Airtel bill.',
      );
      expect(redacted, isNot(contains('123456789012')));
      expect(redacted, isNot(contains('9876543210')));
      expect(redacted, isNot(contains('4321')));
      expect(redacted, isNot(contains('5000')));
      expect(redacted, contains('Airtel bill'));
    });
  });
}
