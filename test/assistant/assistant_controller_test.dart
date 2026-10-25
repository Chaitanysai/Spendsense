import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/assistant_controller.dart';
import 'package:spendsense/services/assistant/gemini_proxy_client.dart';

import 'fakes.dart';

void main() {
  final now = DateTime(2026, 10, 25, 12);
  List<TransactionModel> seed() => [
        tx(
          id: 'groww',
          amountMinor: 100000,
          date: DateTime(2026, 10, 1),
          merchant: 'Groww',
          category: 'Investment',
        ),
      ];

  test('no backend falls back to local capability messaging', () async {
    final controller = AssistantController(
      ledger: MemoryLedger(transactions: seed()),
      audit: MemoryAudit(),
      consentStore: MemoryConsent(allowed: true),
      clock: () => now,
    );
    addTearDown(controller.dispose);

    await controller.send('Do you notice anything unusual in my finances?');
    expect(controller.messages.last.isError, false);
    expect(controller.messages.last.text, contains('not configured'));
    expect(controller.messages.last.text, contains('stays local'));
  });

  test(
      'a failed cloud request can be retried without duplicating the user turn',
      () async {
    final remote = ScriptedRemote(
      error: const AssistantRemoteException(
        'offline',
        'You appear to be offline.',
        retryable: true,
      ),
    );
    final controller = AssistantController(
      ledger: MemoryLedger(transactions: seed()),
      audit: MemoryAudit(),
      consentStore: MemoryConsent(allowed: true),
      remoteClient: remote,
      clock: () => now,
    );
    addTearDown(controller.dispose);

    await controller.send('Do you notice anything unusual in my finances?');
    expect(controller.messages.last.isError, true);
    expect(controller.messages.last.text, contains('offline'));
    final userTurnsBefore =
        controller.messages.where((message) => message.isUser).length;

    remote.error = null;
    remote.turns.add(const RemoteAssistantTurn(
      text: 'Your investments are concentrated in two brands.',
    ));
    await controller.retryLast();

    expect(controller.messages.last.isError, false);
    expect(controller.messages.last.text, contains('concentrated'));
    expect(
      controller.messages.where((message) => message.isUser).length,
      userTurnsBefore,
    );
    expect(remote.calls, hasLength(2));
  });

  test('clearing the conversation discards a pending preview', () async {
    final controller = AssistantController(
      ledger: MemoryLedger(transactions: seed()),
      audit: MemoryAudit(),
      consentStore: MemoryConsent(allowed: false),
      clock: () => now,
    );
    addTearDown(controller.dispose);

    await controller.send('Remove Groww from my spending');
    expect(controller.pendingAction, isNotNull);

    controller.clearConversation();
    expect(controller.pendingAction, isNull);
    expect(controller.messages, hasLength(1));
  });
}
