import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/app_dialog.dart';

/// Dialogs are where a destructive decision is actually taken, so the contract
/// matters: every exit path resolves explicitly, the destructive variant uses
/// the palette's danger tone, and a long body scrolls instead of overflowing.
///
/// Nineteen hand-rolled `AlertDialog`s existed before Phase 3; these tests are
/// what the later migration is checked against.

Widget _host({bool dark = false, double textScale = 1.0}) => MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(body: SizedBox.expand()),
      ),
    );

void main() {
  setUp(() => AppColors.applyPalette(AppPalette.defaultPalette));
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  testWidgets('confirm resolves true and cancel resolves false',
      (tester) async {
    await tester.pumpWidget(_host());
    final context = tester.element(find.byType(Scaffold));

    bool? confirmed;
    showAppConfirmDialog(
      context,
      title: 'Delete budget?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep',
      destructive: true,
      icon: Icons.delete_outline,
    ).then((value) => confirmed = value);
    await tester.pumpAndSettle();

    expect(find.text('Delete budget?'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    showAppConfirmDialog(context, title: 'Delete budget?', confirmLabel: 'Delete')
        .then((value) => confirmed = value);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('dismissing the barrier is a refusal, never a confirmation',
      (tester) async {
    await tester.pumpWidget(_host());
    final context = tester.element(find.byType(Scaffold));

    bool? confirmed;
    showAppConfirmDialog(
      context,
      title: 'Clear ledger?',
      message: 'Everything will be removed.',
      destructive: true,
    ).then((value) => confirmed = value);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
    expect(find.text('Clear ledger?'), findsNothing);
  });

  testWidgets('the destructive confirm takes the danger tone', (tester) async {
    await tester.pumpWidget(_host());
    final context = tester.element(find.byType(Scaffold));

    showAppConfirmDialog(
      context,
      title: 'Delete account?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    final background = button.style!.backgroundColor!.resolve({});
    expect(background, AppColors.danger);
  });

  testWidgets('a long body scrolls and stays inside the dialog at 2x text',
      (tester) async {
    await tester.pumpWidget(_host(textScale: 2.0));
    final context = tester.element(find.byType(Scaffold));

    showAppAlertDialog(
      context,
      title: 'About this ledger',
      scrollable: true,
      message: List.filled(
        40,
        'Every transaction is encrypted on this device.',
      ).join(' '),
      dismissLabel: 'Close',
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('About this ledger'), findsNothing);
  });

  testWidgets('the dialog surface comes from the theme, on every palette',
      (tester) async {
    for (final palette in AppPalette.all) {
      AppColors.applyPalette(palette);
      for (final dark in [false, true]) {
        await tester.pumpWidget(_host(dark: dark));
        final context = tester.element(find.byType(Scaffold));
        showAppAlertDialog(context, title: 'Confirm', message: 'Body');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: '${palette.id} dark=$dark');
        expect(find.text('Confirm'), findsOneWidget);

        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
    }
    AppColors.applyPalette(AppPalette.defaultPalette);
  });
}
