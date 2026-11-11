import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/app_surface.dart';

/// The surface ladder is the foundation every later screen sits on, so these
/// tests assert the contract rather than a screenshot: which level paints which
/// tone, that elevation is opt-in, that a hairline appears where PanelUI says it
/// must, and that no palette lets a surface dissolve into its own canvas.

Widget _host(Widget child, {bool dark = false}) => MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(body: Center(child: child)),
    );

/// The decorated container inside an [AppSurface].
BoxDecoration _decorationOf(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byType(AppSurface), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  setUp(() => AppColors.applyPalette(AppPalette.defaultPalette));
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  testWidgets('each level paints the tone it claims', (tester) async {
    for (final level in AppSurfaceLevel.values) {
      await tester.pumpWidget(_host(
        AppSurface(level: level, child: const SizedBox(width: 80, height: 20)),
      ));
      await tester.pump();

      final decoration = _decorationOf(tester);
      final context = tester.element(find.byType(AppSurface));
      switch (level) {
        case AppSurfaceLevel.canvas:
          expect(decoration.color, isNull);
        case AppSurfaceLevel.grouped:
          expect(decoration.color, AppColors.surfaceGrouped(context));
        case AppSurfaceLevel.tertiary:
          expect(decoration.color, AppColors.surfaceTertiary(context));
        case AppSurfaceLevel.raised:
          expect(decoration.color, AppColors.glassSurface(context));
      }
    }
  });

  testWidgets('elevation is opt-in: only the raised level shadows',
      (tester) async {
    for (final level in AppSurfaceLevel.values) {
      await tester.pumpWidget(_host(
        AppSurface(level: level, child: const SizedBox(width: 80, height: 20)),
      ));
      await tester.pump();
      final decoration = _decorationOf(tester);
      if (level == AppSurfaceLevel.raised) {
        expect(decoration.boxShadow, isNotNull, reason: 'raised is the focal card');
      } else {
        expect(decoration.boxShadow, isNull,
            reason: '$level must not cast a shadow onto its parent');
      }
    }

    // An explicit override wins in both directions.
    await tester.pumpWidget(_host(
      AppSurface(
        level: AppSurfaceLevel.raised,
        shadow: false,
        child: const SizedBox(width: 80, height: 20),
      ),
    ));
    await tester.pump();
    expect(_decorationOf(tester).boxShadow, isNull);
  });

  testWidgets('a hairline is drawn exactly where a plane needs one',
      (tester) async {
    // Premium Blue light: the white card is 1.07:1 on its page, enough to
    // separate by tone (as in the reference). Orange Milk light is 1.025:1 and
    // keeps the edge. Dark mode always keeps it, because it has no shadow.
    for (final (palette, dark, raisedEdge) in [
      (AppPalette.premiumBlue, false, false),
      (AppPalette.orangeMilk, false, true),
      (AppPalette.premiumBlue, true, true),
    ]) {
      AppColors.applyPalette(palette);
      for (final level in AppSurfaceLevel.values) {
        await tester.pumpWidget(_host(
          AppSurface(
              level: level, child: const SizedBox(width: 80, height: 20)),
          dark: dark,
        ));
        // MaterialApp cross-fades a brightness change; read after it settles.
        await tester.pumpAndSettle();
        final decoration = _decorationOf(tester);
        final expected = switch (level) {
          AppSurfaceLevel.canvas => false,
          AppSurfaceLevel.raised => raisedEdge,
          _ => true,
        };
        expect(decoration.border != null, expected,
            reason: '${palette.id} dark=$dark $level');
      }
    }
    AppColors.applyPalette(AppPalette.defaultPalette);
  });

  testWidgets('default padding is cardPadding and zero is honoured',
      (tester) async {
    // A decorated Container insets its child by the hairline's width, so the
    // measured offset is padding + the edge (0 or 1). Asserting the sum keeps
    // the check honest without pretending the border is or is not there.
    await tester.pumpWidget(_host(
      AppSurface(child: const Text('inside')),
    ));
    await tester.pump();
    final context = tester.element(find.byType(AppSurface));
    final edge = AppColors.needsSurfaceEdge(context) ? 1.0 : 0.0;
    final surface = tester.getRect(find.byType(AppSurface));
    final label = tester.getRect(find.text('inside'));
    expect(AppSpacing.cardPadding, 16, reason: 'spec 11 D6');
    expect(label.left - surface.left,
        closeTo(AppSpacing.cardPadding + edge, 0.01));
    expect(label.top - surface.top,
        closeTo(AppSpacing.cardPadding + edge, 0.01));

    // A surface wrapping a bled chart or list takes no padding at all.
    await tester.pumpWidget(_host(
      AppSurface(
        padding: EdgeInsets.zero,
        child: const SizedBox(width: 40, height: 40),
      ),
    ));
    await tester.pump();
    final bled = tester.getRect(find.byType(AppSurface));
    final inner = tester.getRect(find.byType(SizedBox).first);
    expect(inner.left - bled.left, lessThanOrEqualTo(1.01));
  });

  testWidgets('a labelled surface is announced as one node', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(
      AppSurface(
        semanticLabel: 'Available balance 1,250 rupees',
        child: const Text('1,250'),
      ),
    ));
    await tester.pump();

    expect(
      find.bySemanticsLabel('Available balance 1,250 rupees'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('1,250'), findsNothing);
    handle.dispose();
  });

  testWidgets('every palette keeps every surface distinct from the canvas',
      (tester) async {
    for (final palette in AppPalette.all) {
      AppColors.applyPalette(palette);
      for (final dark in [false, true]) {
        await tester.pumpWidget(_host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final level in [
                AppSurfaceLevel.grouped,
                AppSurfaceLevel.tertiary,
                AppSurfaceLevel.raised,
              ])
                AppSurface(
                  level: level,
                  child: const SizedBox(width: 120, height: 16),
                ),
            ],
          ),
          dark: dark,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: '${palette.id} dark=$dark');

        final context = tester.element(find.byType(AppSurface).first);
        final canvas = AppColors.scaffold(context);
        for (final surface in tester.widgetList<AppSurface>(
          find.byType(AppSurface),
        )) {
          // `tertiary` is a band *inside* a raised surface, so its backdrop is
          // the card, not the canvas; every other level sits on the page.
          final backdrop = surface.level == AppSurfaceLevel.tertiary
              ? AppColors.glassSurface(context)
              : canvas;
          final filled = surface.level == AppSurfaceLevel.raised
              ? AppColors.glassSurface(context)
              : surface.level == AppSurfaceLevel.tertiary
                  ? AppColors.surfaceTertiary(context)
                  : AppColors.surfaceGrouped(context);
          // Every level but `canvas` also draws a hairline (asserted above), so
          // the fill only has to be *a* step, not a strong one — but it must
          // not collapse onto its backdrop, which is what a wrong token does.
          expect(
            AppColors.contrastRatio(filled, backdrop),
            greaterThan(1.0),
            reason: '${palette.id} dark=$dark ${surface.level.name} vanishes',
          );
        }
      }
    }
    AppColors.applyPalette(AppPalette.defaultPalette);
  });
}
