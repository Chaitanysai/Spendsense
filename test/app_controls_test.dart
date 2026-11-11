import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/app_button.dart';
import 'package:spendsense/widgets/app_chip.dart';

/// Controls carry state that must survive a palette change, a large text scale
/// and a screen reader. These assert the state contract, not pixels.

Widget _host(Widget child, {bool dark = false, double textScale = 1.0}) =>
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  setUp(() => AppColors.applyPalette(AppPalette.defaultPalette));
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  group('AppChip', () {
    testWidgets('selection is carried by weight and a glyph, not hue alone',
        (tester) async {
      await tester.pumpWidget(_host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppChip(label: 'Food', selected: true, onTap: () {}),
            AppChip(label: 'Travel', onTap: () {}),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final selected = tester.widget<Text>(find.text('Food'));
      final unselected = tester.widget<Text>(find.text('Travel'));
      expect(selected.style!.fontWeight, FontWeight.w700);
      expect(unselected.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('reports its state to the screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final taps = <String>[];
      await tester.pumpWidget(_host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppChip(label: 'Food', selected: true, onTap: () => taps.add('on')),
            AppChip(label: 'Travel', onTap: () => taps.add('off')),
            AppChip(label: 'Rent', enabled: false, onTap: () => taps.add('x')),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      final food = tester.getSemantics(find.byType(AppChip).at(0));
      expect(food.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(food.flagsCollection.isButton, isTrue);

      final rent = tester.getSemantics(find.byType(AppChip).at(2));
      expect(rent.flagsCollection.isEnabled, ui.Tristate.isFalse);

      await tester.tap(find.byType(AppChip).at(1));
      expect(taps, ['off']);
      handle.dispose();
    });

    testWidgets('a disabled chip does not fire and dims', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        AppChip(label: 'Rent', enabled: false, onTap: () => taps++),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppChip), warnIfMissed: false);
      expect(taps, 0);
      final opacity = tester.widget<Opacity>(
        find.descendant(of: find.byType(AppChip), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, 0.45);
    });

    testWidgets('keeps a 44dp target and survives 2x text', (tester) async {
      await tester.pumpWidget(_host(
        Wrap(
          children: [
            for (final label in ['Food', 'Groceries and household', 'Transport'])
              AppChip(label: label, onTap: () {}),
          ],
        ),
        textScale: 2.0,
      ));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(AppChip).first).height,
          greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders on all 19 palettes in both modes', (tester) async {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        for (final dark in [false, true]) {
          await tester.pumpWidget(_host(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppChip(label: 'On', selected: true, onTap: () {}),
                const SizedBox(width: 8),
                AppChip(label: 'Off', onTap: () {}),
              ],
            ),
            dark: dark,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${palette.id} dark=$dark');
        }
      }
      AppColors.applyPalette(AppPalette.defaultPalette);
    });
  });

  group('AppIconButton', () {
    testWidgets('is a labelled 44dp target', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(_host(
        AppIconButton(
          icon: Icons.tune_rounded,
          semanticLabel: 'Edit dashboard',
          onPressed: () => taps++,
        ),
      ));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(AppIconButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Edit dashboard'), findsOneWidget);

      await tester.tap(find.byType(AppIconButton));
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('disabled reports itself and ignores taps', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(_host(
        const AppIconButton(
          icon: Icons.delete_outline,
          semanticLabel: 'Delete',
          onPressed: null,
        ),
      ));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(AppIconButton));
      expect(node.flagsCollection.isEnabled, ui.Tristate.isFalse);
      await tester.tap(find.byType(AppIconButton), warnIfMissed: false);
      expect(taps, 0);
      handle.dispose();
    });
  });

  group('AppDestructiveButton', () {
    testWidgets('is quiet: a danger wash and a hairline, not a red slab',
        (tester) async {
      await tester.pumpWidget(_host(
        SizedBox(
          width: 320,
          child: AppDestructiveButton(
            label: 'Delete transaction',
            icon: Icons.delete_outline,
            onPressed: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppDestructiveButton),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      final context = tester.element(find.byType(AppDestructiveButton));

      expect(decoration.color, AppColors.wash(context, AppColors.danger));
      expect(decoration.border, isNotNull);
      expect(decoration.color, isNot(AppColors.danger),
          reason: 'a solid danger fill belongs in the confirming dialog only');
      expect(find.text('Delete transaction'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading state blocks a second submission', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        SizedBox(
          width: 320,
          child: AppDestructiveButton(
            label: 'Delete',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      ));
      // A spinner never settles; advance one frame instead of waiting for it.
      await tester.pump();
      await tester.tap(find.byType(AppDestructiveButton), warnIfMissed: false);
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
