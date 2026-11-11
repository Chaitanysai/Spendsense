import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/recurring_plan.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/bill_detection_service.dart';

/// Output-equivalence lock for BillDetectionService.
///
/// The P1 performance refactor hoists per-transaction classification out of
/// the per-plan loop and precomputes normalizations. This test pins the
/// SERVICE OUTPUT on a deterministic fixture so the refactor cannot change
/// what the Bills screen shows — the expected projection below was captured
/// from the pre-refactor implementation and must keep passing byte-for-byte.

TransactionModel _tx(
  String id,
  int amountMinor,
  DateTime date, {
  String merchant = 'Merchant',
  String category = 'Utilities',
  String method = 'UPI',
  String sms = 'paid successfully',
  bool excluded = false,
  TransactionType type = TransactionType.expense,
  String? reference,
  String? source,
}) {
  return TransactionModel(
    id: id,
    amountMinor: amountMinor,
    type: type,
    merchant: merchant,
    category: category,
    paymentMethod: method,
    date: date,
    time: '10:00',
    originalSms: sms,
    isExcluded: excluded,
    bank: 'HDFC',
    account: 'XX1',
    reference: reference,
    source: source ?? 'SMS-Parser',
  );
}

RecurringPlan _plan(
  String id,
  String title,
  int amountMinor,
  DateTime nextDue, {
  String? sourceTransactionId,
}) {
  return RecurringPlan.create(
    id: id,
    title: title,
    category: 'Utilities',
    amountMinor: amountMinor,
    frequency: PlanFrequency.monthly,
    nextDue: nextDue,
    sourceTransactionId: sourceTransactionId,
  );
}

/// A fixture that exercises every filter branch: strong plan matches
/// (reference + merchant identity), amount out of tolerance, outside the
/// match window, reminder-only messages, excluded rows, income rows,
/// merchants that normalize to empty, and bill-like auto-bill candidates.
List<TransactionModel> fixtureTransactions() => [
      // Plan A (Electricity, 120000) — strong match via reference + amount.
      _tx('a1', 120000, DateTime(2026, 10, 14),
          merchant: 'Electricity Board',
          sms: 'INR 1200 paid successfully to Electricity Board',
          reference: 'REF-A1'),
      // Same amount, but a reminder (must never match as a payment).
      _tx('a2', 120000, DateTime(2026, 10, 15),
          merchant: 'Electricity Board',
          sms: 'Your electricity bill of Rs 1200 is due on 20 Oct'),
      // Plan B (Airtel, 59900) — matched by merchant identity.
      _tx('b1', 59900, DateTime(2026, 10, 12),
          merchant: 'Airtel Payments',
          sms: 'INR 599 paid successfully to Airtel'),
      // Amount beyond tolerance for plan B — must not match anything.
      _tx('b2', 99900, DateTime(2026, 10, 12),
          merchant: 'Airtel Payments',
          sms: 'INR 999 paid successfully to Airtel'),
      // Outside every plan window (old row) — history candidate only.
      _tx('old1', 120000, DateTime(2026, 8, 14),
          merchant: 'Electricity Board',
          sms: 'INR 1200 paid successfully to Electricity Board',
          reference: 'REF-OLD'),
      // Excluded and income rows never match or group.
      _tx('ex1', 120000, DateTime(2026, 10, 14),
          merchant: 'Electricity Board', excluded: true),
      _tx('in1', 120000, DateTime(2026, 10, 14),
          merchant: 'Electricity Board', type: TransactionType.income),
      // Merchant that normalizes to nothing.
      _tx('blank1', 120000, DateTime(2026, 10, 14),
          merchant: '   ', sms: 'INR 1200 paid successfully'),
      // Auto-bill candidates: recurring utility payments the plans do not
      // cover, plus an ordinary grocery row that must stay out.
      _tx('u1', 45000, DateTime(2026, 7, 10),
          merchant: 'Jharkhand Bijli Vitran',
          sms: 'INR 450 paid successfully Jharkhand Bijli Vitran bill'),
      _tx('u2', 45000, DateTime(2026, 8, 10),
          merchant: 'Jharkhand Bijli Vitran',
          sms: 'INR 450 paid successfully Jharkhand Bijli Vitran bill'),
      _tx('u3', 45000, DateTime(2026, 9, 10),
          merchant: 'Jharkhand Bijli Vitran',
          sms: 'INR 450 paid successfully Jharkhand Bijli Vitran bill'),
      _tx('g1', 30000, DateTime(2026, 10, 3),
          merchant: 'Big Bazaar',
          category: 'Groceries',
          sms: 'INR 300 spent at Big Bazaar'),
    ];

List<RecurringPlan> fixturePlans() => [
      _plan('pA', 'Electricity', 120000, DateTime(2026, 10, 20),
          sourceTransactionId: 'old1'),
      _plan('pB', 'Airtel', 59900, DateTime(2026, 10, 25)),
      _plan('pC', 'Unknown Plan', 77700, DateTime(2026, 11, 1)),
    ];

/// Compact, deterministic projection of the detect() output.
List<Map<String, Object?>> project(List<BillView> views) => [
      for (final v in views)
        {
          'title': v.title,
          'state': v.state.name,
          'due': v.dueDate?.toIso8601String(),
          'amount': v.amountMinor,
          'matched': v.matchedPayment?.id,
          'historyCount': v.history.length,
          if (v.autoBill != null) 'occurrences': v.autoBill!.occurrenceCount,
        },
    ];

void main() {
  test('detect output is identical to the pre-refactor implementation',
      () async {
    final views = const BillDetectionService().detect(
      plans: fixturePlans(),
      transactions: fixtureTransactions(),
      today: DateTime(2026, 10, 16),
      hiddenBillKeys: const {'some:other-biller'},
    );

    final actual = const JsonEncoder.withIndent('  ').convert(project(views));

    // Captured from the pre-refactor implementation on 2026-11-07. The
    // refactor must reproduce it exactly.
    const expected = r'''
[
  {
    "title": "Jharkhand Bijli Vitran",
    "state": "overdue",
    "due": "2026-10-10T00:00:00.000",
    "amount": 45000,
    "matched": null,
    "historyCount": 3,
    "occurrences": 3
  },
  {
    "title": "Airtel",
    "state": "upcoming",
    "due": "2026-10-25T00:00:00.000",
    "amount": 59900,
    "matched": null,
    "historyCount": 1
  },
  {
    "title": "Unknown Plan",
    "state": "upcoming",
    "due": "2026-11-01T00:00:00.000",
    "amount": 77700,
    "matched": null,
    "historyCount": 0
  },
  {
    "title": "Electricity",
    "state": "paid",
    "due": "2026-10-20T00:00:00.000",
    "amount": 120000,
    "matched": "a1",
    "historyCount": 2
  }
]''';

    // ignore: avoid_print
    print('ACTUAL-BILL-PROJECTION:\n$actual');
    expect(actual, expected);
  });
}
