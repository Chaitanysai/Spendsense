import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// The Add sheet must stay entirely above the keyboard.
///
/// On device (1.3 scale, dark) the keyboard left the sheet pinned to the screen
/// bottom: capping its height shrank it from the top while the bottom stayed
/// behind the IME, so the amount field was sliced in half and Merchant,
/// Category and the submit row were unreachable.
///
/// This mounts the sheet through `showAppSheet`, which is how the app opens it,
/// so the assertions observe the geometry the user actually gets. An earlier
/// version of this file pumped `AddTransactionScreen` as a bare `Scaffold` body:
/// `getRect` then measured the unconstrained widget and reported the keyboard
/// boundary as satisfied even with the fix reverted — a vacuous pass.
void main() {
  setUp(() => AppColors.applyPalette(AppPalette.premiumBlue));
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  const screen = Size(411, 914); // OnePlus 7T logical size
  const keyboard = 420.0;
  final keyboardTop = screen.height - keyboard; // 494

  Future<void> pumpSheet(WidgetTester tester, {required double scale}) async {
    tester.view.physicalSize = screen * 3.0;
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 24 * 3.0);
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3.0);
    addTearDown(tester.view.reset);

    late BuildContext hostContext;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: screen,
          padding: const EdgeInsets.only(top: 24),
          viewInsets: const EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(scale),
        ),
        child: MaterialApp(
          home: Builder(builder: (c) {
            hostContext = c;
            return const Scaffold(body: SizedBox());
          }),
        ),
      ),
    );
    // ignore: unawaited_futures
    showAddTransactionSheet(hostContext);
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('lowest content clears the keyboard at ${scale}x',
        (tester) async {
      await pumpSheet(tester, scale: scale);
      // `AddTransactionScreen` fills the sheet *route*, which itself runs to the
      // screen bottom. What must clear the IME is the painted surface and the
      // last interactive element, so those are what is measured here.
      final submit = tester.getRect(find.text('Add expense').last);
      // ignore: avoid_print
      print('scale $scale submit=${submit.top.toStringAsFixed(1)}..'
          '${submit.bottom.toStringAsFixed(1)} keyboardTop=$keyboardTop');
      expect(submit.bottom, lessThanOrEqualTo(keyboardTop + 0.5),
          reason: 'submit label sits ${(submit.bottom - keyboardTop).toStringAsFixed(1)}dp '
              'behind the keyboard at ${scale}x');
    });


    testWidgets('fields are scrollable, not clipped at ${scale}x',
        (tester) async {
      await pumpSheet(tester, scale: scale);
      // Merchant and Category are below the amount card; with the keyboard up
      // they must be reachable by scrolling rather than cut off.
      final scrollable = find.byType(SingleChildScrollView);
      expect(scrollable, findsWidgets);
      await tester.drag(scrollable.first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Merchant'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
    });
  }
}
