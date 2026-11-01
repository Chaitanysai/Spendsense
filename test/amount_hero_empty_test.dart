import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/amount_hero_field.dart';

/// The hero amount must not claim a figure the user has not typed.
///
/// On device (1.3 scale, dark) an empty Add sheet rendered a large `₹0` as the
/// live amount *above* a field whose hint read "Enter amount". The preview was
/// formatting an empty parse result through the currency formatter, so "nothing
/// entered" and "zero rupees entered" were the same string, and the empty form
/// looked like it already held a committed amount.
void main() {
  setUp(() => AppColors.applyPalette(AppPalette.premiumBlue));
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  Future<List<String>> texts(WidgetTester tester, String initial) async {
    final controller = TextEditingController(text: initial);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AmountHeroField(controller: controller, isIncome: false),
      ),
    ));
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
  }

  testWidgets('empty amount shows no rupee figure', (tester) async {
    final shown = await texts(tester, '');
    expect(shown.any((t) => t.contains('₹')), isFalse,
        reason: 'empty input rendered a rupee amount: $shown');
  });

  testWidgets('typed amount is formatted', (tester) async {
    final shown = await texts(tester, '250');
    expect(shown, contains('₹250'));
  });

  testWidgets('a typed zero is still shown', (tester) async {
    final shown = await texts(tester, '0');
    expect(shown, contains('₹0'),
        reason: 'zero is real input, unlike emptiness');
  });
}
