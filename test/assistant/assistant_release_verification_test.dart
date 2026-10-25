import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/assistant_models.dart';
import 'package:spendsense/models/recurring_plan.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/assistant/assistant_orchestrator.dart';

import 'fakes.dart';

/// Verification for the exact release conversations, using synthetic local
/// records and deterministic code only.
void main() {
  late DateTime now;
  late MemoryLedger ledger;
  late MemoryAudit audit;
  late AssistantOrchestrator orchestrator;

  setUp(() {
    now = DateTime(2026, 10, 25, 12);
    ledger = MemoryLedger(
      transactions: [
        tx(
          id: 'groww-sep',
          amountMinor: 50000,
          date: DateTime(2026, 9, 10),
          merchant: 'Groww Broking',
          category: 'Investment',
        ),
        tx(
          id: 'groww-oct',
          amountMinor: 100000,
          date: DateTime(2026, 10, 2),
          merchant: 'GROWW',
          category: 'Investment',
        ),
        tx(
          id: 'groww-excluded',
          amountMinor: 25000,
          date: DateTime(2026, 10, 5),
          merchant: 'Groww',
          category: 'Investment',
          excluded: true,
        ),
        tx(
          id: 'zerodha-oct',
          amountMinor: 200000,
          date: DateTime(2026, 10, 3),
          merchant: 'ZERODHA BROKING LTD',
          category: 'Investment',
        ),
        tx(
          id: 'food-oct',
          amountMinor: 30000,
          date: DateTime(2026, 10, 1),
          merchant: 'Swiggy',
          category: 'Food',
        ),
        tx(
          id: 'food-sep',
          amountMinor: 70000,
          date: DateTime(2026, 9, 20),
          merchant: 'Swiggy',
          category: 'Food',
        ),
        tx(
          id: 'salary',
          amountMinor: 1000000,
          date: DateTime(2026, 10, 1),
          merchant: 'Employer',
          category: 'Income',
          type: TransactionType.income,
        ),
      ],
      plans: [
        RecurringPlan.create(
          id: 'netflix-plan',
          title: 'Netflix',
          category: 'Entertainment',
          amountMinor: 64900,
          frequency: PlanFrequency.monthly,
          nextDue: DateTime(2026, 10, 28),
        ),
      ],
    );
    audit = MemoryAudit();
    orchestrator = AssistantOrchestrator(
      ledger: ledger,
      audit: audit,
      consent: MemoryConsent(allowed: false),
      clock: () => now,
    );
  });

  test('1 — lists Groww and Zerodha from real local records', () async {
    final reply = await orchestrator.handle(
      'List all Groww and Zerodha transactions.',
    );
    expect(reply.isError, false);
    expect(reply.sections.map((s) => s.title), ['Groww', 'Zerodha']);
    expect(reply.sections[0].matchedCount, 3);
    expect(reply.sections[0].expenseMinor, 150000);
    expect(reply.sections[0].excludedMinor, 25000);
    expect(reply.sections[0].excludedCount, 1);
    expect(reply.sections[1].matchedCount, 1);
    expect(reply.sections[1].expenseMinor, 200000);
    expect(reply.summary, isNotNull);
    expect(reply.summary!.totalCount, 4);
    expect(ledger.transactions.length, 7);
    expect(ledger.transactions.any((t) => t.isExcluded), true);
    expect(ledger.exclusionWrites, 0);
    expect(ledger.deletionWrites, 0);
    expect(audit.entries, isEmpty);
  });

  test('2 — this month spending uses calendar bounds and non-excluded rows',
      () async {
    final reply = await orchestrator.handle('How much did I spend this month?');
    expect(reply.isError, false);
    expect(reply.summary, isNotNull);
    expect(reply.summary!.spendingMinor, 330000);
    expect(reply.summary!.start, DateTime(2026, 10, 1));
    expect(reply.summary!.end, DateTime(2026, 10, 25));
    expect(reply.summary!.expenseCount, 3);
    expect(reply.summary!.excludedCount, 1);
    expect(ledger.exclusionWrites, 0);
    expect(ledger.deletionWrites, 0);
  });

  test('3 — biggest expenses are ranked deterministically', () async {
    final reply = await orchestrator.handle('Show my biggest expenses.');
    expect(reply.isError, false);
    expect(reply.sections, hasLength(1));
    final rows = reply.sections.single.transactions;
    expect(rows, hasLength(5));
    expect(rows.first.merchant, 'ZERODHA BROKING LTD');
    expect(rows.first.amountMinor, 200000);
    expect(rows[1].amountMinor, 100000);
    expect(rows.every((row) => row.isExcluded == false), true);
    expect(ledger.exclusionWrites, 0);
    expect(ledger.deletionWrites, 0);
  });

  test('4/5 — exclusion requires confirmation; undo restores original state',
      () async {
    final preview =
        await orchestrator.handle('Exclude Groww from my spending.');
    expect(preview.isError, false);
    expect(preview.pendingAction, isNotNull);
    final action = preview.pendingAction!;
    expect(action.type, AssistantChangeType.exclusion);
    expect(action.expectedCount, 2);
    expect(action.expectedTotalMinor, 150000);
    expect(action.spendingBeforeMinor, 450000);
    expect(action.spendingAfterMinor, 300000);
    expect(preview.sections.single.transactions, hasLength(2));
    expect(ledger.transactions.length, 7);
    expect(ledger.exclusionWrites, 0);
    expect(audit.entries, isEmpty);

    final applied = await orchestrator.confirmPending(action.id);
    expect(applied.isError, false);
    expect(applied.summary!.spendingMinor, 300000);
    expect(ledger.exclusionWrites, 1);
    expect(
      ledger.transactions
          .where((t) => t.id == 'groww-sep' || t.id == 'groww-oct')
          .every((t) => t.isExcluded),
      true,
    );
    // Exclusion preserves records, bills/plans and an already-excluded row.
    expect(ledger.transactions.length, 7);
    expect(
      ledger.transactions
          .singleWhere((t) => t.id == 'groww-excluded')
          .isExcluded,
      true,
    );
    expect(ledger.plans, hasLength(1));
    expect(ledger.plans.single.title, 'Netflix');
    expect(ledger.plans.single.amountMinor, 64900);
    expect(audit.entries, hasLength(1));

    final undo = await orchestrator.handle('Undo that change.');
    expect(undo.isError, false);
    expect(undo.text, contains('Undone'));
    expect(ledger.transactions.length, 7);
    expect(
      ledger.transactions
          .where((t) => t.id == 'groww-sep' || t.id == 'groww-oct')
          .every((t) => !t.isExcluded),
      true,
    );
    expect(audit.entries.single.undone, true);
  });

  test('6 — unpaid bills come from the planner and ledger', () async {
    final reply = await orchestrator.handle('Show my unpaid bills.');
    expect(reply.isError, false);
    expect(reply.bills, hasLength(1));
    expect(reply.bills.single.title, 'Netflix');
    expect(reply.bills.single.amountMinor, 64900);
    expect(reply.bills.single.status, 'Due soon');
    expect(audit.entries, isEmpty);
  });

  test('repeated confirmation cannot apply twice', () async {
    final preview =
        await orchestrator.handle('Exclude Groww from my spending.');
    final id = preview.pendingAction!.id;
    final first = await orchestrator.confirmPending(id);
    final second = await orchestrator.confirmPending(id);
    expect(first.isError, false);
    expect(second.isError, true);
    expect(ledger.exclusionWrites, 1);
    expect(audit.entries, hasLength(1));
  });

  test('overlapping confirmations cannot apply twice', () async {
    final preview =
        await orchestrator.handle('Exclude Groww from my spending.');
    final id = preview.pendingAction!.id;
    final results = await Future.wait([
      orchestrator.confirmPending(id),
      orchestrator.confirmPending(id),
    ]);
    expect(results.where((reply) => !reply.isError), hasLength(1));
    expect(results.where((reply) => reply.isError), hasLength(1));
    expect(ledger.exclusionWrites, 1);
    expect(audit.entries, hasLength(1));
  });
}
