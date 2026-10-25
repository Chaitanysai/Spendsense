import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/assistant_models.dart';
import 'package:spendsense/services/assistant/assistant_orchestrator.dart';
import 'package:spendsense/services/assistant/gemini_proxy_client.dart';

import 'fakes.dart';

void main() {
  late DateTime now;
  late MemoryLedger ledger;
  late MemoryAudit audit;
  late MemoryConsent consent;

  final transactions = [
    tx(
      id: 'groww-1',
      amountMinor: 100000,
      date: DateTime(2026, 10, 1),
      merchant: 'Groww',
      category: 'Investment',
    ),
    tx(
      id: 'groww-2',
      amountMinor: 200000,
      date: DateTime(2026, 10, 2),
      merchant: 'GROWW BROKING',
      category: 'Investment',
    ),
    tx(
      id: 'zerodha-1',
      amountMinor: 300000,
      date: DateTime(2026, 10, 3),
      merchant: 'Zerodha',
      category: 'Investment',
    ),
    tx(
      id: 'food-1',
      amountMinor: 50000,
      date: DateTime(2026, 10, 4),
      merchant: 'Swiggy',
      category: 'Food',
    ),
  ];

  setUp(() {
    now = DateTime(2026, 10, 25, 12);
    ledger = MemoryLedger(transactions: transactions);
    audit = MemoryAudit();
    consent = MemoryConsent(allowed: true);
  });

  AssistantOrchestrator build({ScriptedRemote? remote}) =>
      AssistantOrchestrator(
        ledger: ledger,
        audit: audit,
        consent: consent,
        remoteClient: remote,
        clock: () => now,
      );

  group('read-only requests', () {
    test('list Groww and Zerodha returns sections without mutating', () async {
      final orchestrator = build();
      final reply = await orchestrator.handle(
        'List my Groww and Zerodha transactions.',
      );
      expect(reply.sections.length, 2);
      expect(reply.sections[0].title, 'Groww');
      expect(reply.sections[0].matchedCount, 2);
      expect(reply.sections[1].title, 'Zerodha');
      expect(reply.pendingAction, isNull);
      expect(ledger.exclusionWrites, 0);
      expect(ledger.deletionWrites, 0);
      expect(ledger.transactions.length, 4);
      expect(audit.entries, isEmpty);
    });

    test('food last month uses an exact range and deterministic total',
        () async {
      final orchestrator = build();
      final reply = await orchestrator.handle(
        'How much did I spend on food last month?',
      );
      expect(reply.summary, isNotNull);
      expect(reply.summary!.spendingMinor, 0);
      expect(reply.text, contains('₹0'));
      expect(reply.pendingAction, isNull);
    });
  });

  group('exclusion confirmation and undo', () {
    test('preview is mandatory and vague chat cannot apply it', () async {
      final orchestrator = build();
      final preview = await orchestrator.handle(
        'Remove Groww from my spending.',
      );
      expect(preview.pendingAction, isNotNull);
      expect(preview.pendingAction!.expectedCount, 2);
      expect(ledger.exclusionWrites, 0);
      expect(ledger.transactions.every((t) => !t.isExcluded), true);

      final vague = await orchestrator.handle('okay');
      expect(vague.text, contains('not applied from a chat message'));
      expect(ledger.exclusionWrites, 0);

      final wrongId = await orchestrator.confirmPending('not-the-preview');
      expect(wrongId.isError, true);
      expect(ledger.exclusionWrites, 0);
    });

    test('confirm applies exclusion, records audit, and duplicate fails',
        () async {
      final orchestrator = build();
      final preview = await orchestrator.handle(
        'Exclude Groww transactions from my spending calculations.',
      );
      final action = preview.pendingAction!;
      final applied = await orchestrator.confirmPending(action.id);
      expect(applied.isError, false);
      expect(applied.summary!.spendingMinor, 350000);
      expect(ledger.exclusionWrites, 1);
      final groww = ledger.transactions.where((t) => t.id.startsWith('groww'));
      expect(groww.every((t) => t.isExcluded), true);
      expect(audit.entries, hasLength(1));
      expect(audit.entries.single.type, AssistantChangeType.exclusion);
      expect(audit.entries.single.affectedCount, 2);

      final duplicate = await orchestrator.confirmPending(action.id);
      expect(duplicate.isError, true);
      expect(ledger.exclusionWrites, 1);
      expect(audit.entries, hasLength(1));
    });

    test('undo restores the previous exclusion flags and totals', () async {
      final orchestrator = build();
      final preview = await orchestrator.handle(
        'Remove Groww from my spending.',
      );
      await orchestrator.confirmPending(preview.pendingAction!.id);
      expect(ledger.transactions.any((t) => t.isExcluded), true);

      final undo = await orchestrator.undoLast();
      expect(undo.isError, false);
      expect(undo.text, contains('Undone'));
      expect(ledger.transactions.every((t) => !t.isExcluded), true);
      expect(audit.entries.single.undone, true);

      final again = await orchestrator.undoLast();
      expect(again.text, contains('no assistant change available'));
    });

    test('an expired preview cannot be confirmed', () async {
      final orchestrator = build();
      final preview = await orchestrator.handle(
        'Remove Groww from my spending.',
      );
      now = now.add(const Duration(minutes: 6));
      final applied = await orchestrator.confirmPending(
        preview.pendingAction!.id,
      );
      expect(applied.isError, true);
      expect(ledger.exclusionWrites, 0);
    });

    test('audit failure rolls the exclusion back', () async {
      audit.failAppend = true;
      final orchestrator = build();
      final preview = await orchestrator.handle(
        'Remove Groww from my spending.',
      );
      final applied = await orchestrator.confirmPending(
        preview.pendingAction!.id,
      );
      expect(applied.isError, true);
      expect(applied.text, contains('not applied'));
      expect(ledger.transactions.every((t) => !t.isExcluded), true);
      expect(audit.entries, isEmpty);
    });
  });

  group('deletion confirmation and undo', () {
    test('explicit deletion removes exact records and undo restores them',
        () async {
      final orchestrator = build();
      final preview = await orchestrator.handle(
        'Delete my Groww transactions.',
      );
      final action = preview.pendingAction!;
      expect(action.isDeletion, true);
      expect(action.expectedCount, 2);
      expect(ledger.transactions.length, 4);

      final applied = await orchestrator.confirmPending(action.id);
      expect(applied.isError, false);
      expect(ledger.transactions.length, 2);
      expect(ledger.deletionWrites, 1);
      expect(audit.entries.single.deletedSnapshots, hasLength(2));

      final undo = await orchestrator.undoLast();
      expect(undo.isError, false);
      expect(ledger.transactions.length, 4);
      expect(
        ledger.transactions.map((t) => t.id),
        containsAll(['groww-1', 'groww-2']),
      );
    });
  });

  group('remote function calling', () {
    test('cloud is not called without consent', () async {
      consent = MemoryConsent(allowed: false);
      final remote = ScriptedRemote(
        turns: const [RemoteAssistantTurn(text: 'Cloud answer')],
      );
      final orchestrator = build(remote: remote);
      final reply = await orchestrator.handle(
        'What patterns do you notice in my investments?',
      );
      expect(reply.needsCloudConsent, true);
      expect(remote.calls, isEmpty);
    });

    test('read-only Gemini calls execute locally and results are returned',
        () async {
      final remote = ScriptedRemote(turns: const [
        RemoteAssistantTurn(
          text: '',
          functionCalls: [
            RemoteToolCall('search_transactions', {
              'brand': 'groww',
              'includeExcluded': true,
            }),
          ],
        ),
        RemoteAssistantTurn(text: 'You have two Groww transfers.'),
      ]);
      final orchestrator = build(remote: remote);
      final reply = await orchestrator.handle(
        'What patterns do you notice in my investments?',
      );
      expect(reply.text, contains('two Groww'));
      expect(reply.sections, hasLength(1));
      expect(reply.sections.single.matchedCount, 2);
      expect(remote.calls, hasLength(2));
      expect(remote.calls[1].toolExchanges, hasLength(1));
      expect(remote.calls[1].toolExchanges.single.calls.single.name,
          'search_transactions');
      expect(ledger.exclusionWrites, 0);
      expect(ledger.deletionWrites, 0);
    });

    test('identical tool calls are deduplicated within a model turn', () async {
      const call = RemoteToolCall('search_transactions', {'limit': 5});
      final remote = ScriptedRemote(turns: const [
        RemoteAssistantTurn(
          text: '',
          functionCalls: [call, call],
        ),
        RemoteAssistantTurn(text: 'Answer.'),
      ]);
      final orchestrator = build(remote: remote);
      await orchestrator.handle('Give me a pattern summary.');
      final exchange = remote.calls[1].toolExchanges.single;
      expect(exchange.calls, hasLength(2));
      expect(exchange.responses[0], exchange.responses[1]);
    });

    test('malformed tool arguments return an error and do not crash', () async {
      final remote = ScriptedRemote(turns: const [
        RemoteAssistantTurn(
          text: '',
          functionCalls: [
            RemoteToolCall('search_transactions', {'limit': 9999}),
          ],
        ),
        RemoteAssistantTurn(text: 'I could not run that search.'),
      ]);
      final orchestrator = build(remote: remote);
      final reply = await orchestrator.handle('Give me a pattern summary.');
      expect(reply.isError, false);
      expect(reply.text, contains('could not run'));
      final response =
          remote.calls[1].toolExchanges.single.responses.single as Map;
      expect((response['response'] as Map)['error'], 'invalid_argument');
    });

    test('remote preview still requires explicit in-app confirmation',
        () async {
      final remote = ScriptedRemote(turns: const [
        RemoteAssistantTurn(
          text: '',
          functionCalls: [
            RemoteToolCall('search_transactions', {'brand': 'groww'}),
            RemoteToolCall('preview_transaction_exclusion', {
              'transactionIds': ['groww-1', 'groww-2'],
            }),
          ],
        ),
        RemoteAssistantTurn(text: 'Preview prepared. Nothing was applied.'),
      ]);
      final orchestrator = build(remote: remote);
      final reply = await orchestrator.handle(
        'Please prepare a reversible Groww adjustment.',
      );
      expect(reply.pendingAction, isNotNull);
      expect(reply.text, contains('no change has been applied'));
      expect(ledger.exclusionWrites, 0);
      expect(audit.entries, isEmpty);

      final applied = await orchestrator.confirmPending(
        reply.pendingAction!.id,
      );
      expect(applied.isError, false);
      expect(ledger.exclusionWrites, 1);
    });

    test('network/model errors degrade to a clear error with no mutation',
        () async {
      final remote = ScriptedRemote(
        error: const AssistantRemoteException(
          'offline',
          'You appear to be offline.',
          retryable: true,
        ),
      );
      final orchestrator = build(remote: remote);
      final reply = await orchestrator.handle('Give me a pattern summary.');
      expect(reply.isError, true);
      expect(reply.text, contains('offline'));
      expect(ledger.exclusionWrites, 0);
    });
  });

  test('undo with no audit returns a safe message', () async {
    final orchestrator = build();
    final reply = await orchestrator.undoLast();
    expect(reply.isError, false);
    expect(reply.text, contains('no assistant change available'));
  });
}
