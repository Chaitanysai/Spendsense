import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/providers/assistant_controller.dart';
import 'package:spendsense/screens/assistant_screen.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assistant chat renders a preview and requires an explicit tap',
      (tester) async {
    final ledger = MemoryLedger(transactions: [
      tx(
        id: 'groww-1',
        amountMinor: 100000,
        date: DateTime(2026, 10, 1),
        merchant: 'Groww',
        category: 'Investment',
      ),
      tx(
        id: 'groww-2',
        amountMinor: 250000,
        date: DateTime(2026, 10, 2),
        merchant: 'Groww Broking',
        category: 'Investment',
      ),
      tx(
        id: 'food',
        amountMinor: 50000,
        date: DateTime(2026, 10, 3),
        merchant: 'Swiggy',
        category: 'Food',
      ),
    ]);
    final audit = MemoryAudit();
    final controller = AssistantController(
      ledger: ledger,
      audit: audit,
      consentStore: MemoryConsent(allowed: false),
      clock: () => DateTime(2026, 10, 25, 12),
    );

    await tester.pumpWidget(MaterialApp(
      home: AssistantScreen(controller: controller),
    ));
    await tester.pumpAndSettle();
    expect(find.text('SpendSense Assistant'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Remove Groww from my spending',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(controller.pendingAction, isNotNull,
        reason: controller.messages.last.text);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.textContaining('Confirm exclusion'), findsOneWidget);
    expect(find.textContaining('NOT APPLIED'), findsOneWidget);
    expect(ledger.exclusionWrites, 0);
    expect(ledger.transactions.every((t) => !t.isExcluded), true);

    // A typed acknowledgement must not apply the preview.
    await tester.enterText(find.byType(TextField), 'okay');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(ledger.exclusionWrites, 0);
    expect(find.textContaining('tap Review & confirm'), findsOneWidget);

    await tester.tap(find.text('Review & confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Exclude from spending?'), findsOneWidget);
    expect(find.text('Exact records'), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Exclude from spending'));
    await tester.pumpAndSettle();

    expect(ledger.exclusionWrites, 1);
    expect(audit.entries, hasLength(1));
    expect(
      ledger.transactions
          .where((t) => t.id.startsWith('groww'))
          .every((t) => t.isExcluded),
      true,
    );
    expect(find.textContaining('Excluded 2 transactions'), findsOneWidget);
  });

  testWidgets('assistant cards survive 2x text on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final ledger = MemoryLedger(transactions: [
      tx(
        id: 'groww-long',
        amountMinor: 123456789,
        date: DateTime(2026, 10, 1),
        merchant: 'A Very Long Groww Broking Narration That Must Wrap Safely',
        category: 'Investment',
      ),
      tx(
        id: 'food-long',
        amountMinor: 98765,
        date: DateTime(2026, 10, 2),
        merchant: 'A Very Long Restaurant Name That Must Ellipsize',
        category: 'Food',
      ),
    ]);
    final controller = AssistantController(
      ledger: ledger,
      audit: MemoryAudit(),
      consentStore: MemoryConsent(allowed: false),
      clock: () => DateTime(2026, 10, 25, 12),
    );

    await tester.pumpWidget(MaterialApp(
      home: AssistantScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), 'Remove Groww from spending');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Confirm exclusion'), findsOneWidget);

    // Clear the preview so its expiry timer does not outlive the test tree.
    await controller.cancelPending(controller.pendingAction!.id);
    await tester.pump();
  });
}
