import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/widgets/pressable.dart';

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('transaction type and category selectors use press feedback',
      (tester) async {
    final provider = TransactionProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<TransactionProvider>.value(
        value: provider,
        child: _host(const AddTransactionScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.ancestor(
        of: find.text('Expense'),
        matching: find.byType(PressFeedback),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Food'),
        matching: find.byType(PressFeedback),
      ),
      findsOneWidget,
    );
  });
}
