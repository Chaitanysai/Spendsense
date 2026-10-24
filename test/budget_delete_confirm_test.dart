import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/budgets_screen.dart';
import 'package:spendsense/services/ledger_encryption_service.dart';
import 'package:spendsense/utils/app_typography.dart';

class _NoopEncryption extends LedgerEncryptionService {
  @override
  Future<String> decryptText(
    String encoded, {
    String? expectedRecordId,
  }) async =>
      encoded;

  @override
  Future<String> encryptText(String plaintext, {String? recordId}) async =>
      plaintext;
}

Future<(PlannerProvider, TransactionProvider)> _pumpBudgets(
    WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final planner = PlannerProvider(encryption: _NoopEncryption());
  final tx = TransactionProvider();
  final period = PeriodProvider()..init();
  await planner.ready;
  await tx.ready;
  await planner.setCategoryBudget('Food', 100000);
  await planner.setCategoryBudget('Travel', 50000);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: planner),
        ChangeNotifierProvider.value(value: tx),
        ChangeNotifierProvider.value(value: period),
      ],
      child: MaterialApp(home: const BudgetsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (planner, tx);
}

void main() {
  setUp(() => AppTypography.debugSkipFontLoading = true);
  tearDown(() => AppTypography.debugSkipFontLoading = false);

  testWidgets('delete asks for confirmation and Cancel preserves the budget',
      (tester) async {
    final (planner, _) = await _pumpBudgets(tester);
    expect(planner.categoryBudgets.containsKey('Food'), isTrue);
    await tester.tap(find.byTooltip('Remove Food budget'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Food budget?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Food budget?'), findsNothing);
    expect(planner.categoryBudgets.containsKey('Food'), isTrue);
  });

  testWidgets('delete confirmation Remove deletes the category budget',
      (tester) async {
    final (planner, _) = await _pumpBudgets(tester);
    final deleteButton = find.byTooltip('Remove Travel budget');
    await tester.scrollUntilVisible(
      deleteButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    final removeButton = find.widgetWithText(FilledButton, 'Remove');
    expect(removeButton, findsOneWidget);
    await tester.tap(removeButton);
    await tester.pumpAndSettle();
    expect(planner.categoryBudgets.containsKey('Travel'), isFalse);
    expect(planner.categoryBudgets.containsKey('Food'), isTrue);
  });

  testWidgets('dismissing the dialog preserves the budget', (tester) async {
    final (planner, _) = await _pumpBudgets(tester);
    await tester.tap(find.byTooltip('Remove Food budget'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(planner.categoryBudgets.containsKey('Food'), isTrue);
  });
}
