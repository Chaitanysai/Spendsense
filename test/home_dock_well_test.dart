import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/home_action_dock.dart';

/// The four dock plates must read as one control.
///
/// Two separate regressions were reported from the device:
///
/// 1. "only Add expense has an icon" — the quiet plates were a brand tint at
///    [AppColors.brandWellAlpha], measuring 1.29:1 (dark) and 1.13:1 (light)
///    against the dock, so they did not exist as shapes.
/// 2. "Add expense is having dark icon & rest 3 icons are not" — the primary was
///    filled with [AppColors.actionGradient], a saturated navy disc at 0.18x the
///    plate's luminance in light mode, so one slot read enabled and three read
///    disabled.
///
/// Every value here is resolved through the widget's own helpers inside a real
/// build context. An earlier version reimplemented the maths with its own copy
/// of the tint alpha and kept reporting numbers for a constant the widget no
/// longer used.
void main() {
  setUp(() => AppColors.applyPalette(AppPalette.premiumBlue));
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  double channel(double v) {
    v = v / 255.0;
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  double relLum(Color c) =>
      0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);

  double contrast(Color a, Color b) {
    final la = relLum(a), lb = relLum(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Resolves the dock surface and both plate fills the way the widget does.
  Future<({Color surface, Color quiet, Color primary})> plates(
    WidgetTester tester,
    bool dark,
  ) async {
    late Color surface, quiet;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Builder(builder: (c) {
        surface = HomeActionDock.dockSurface(c);
        quiet = HomeActionDock.quietPlate(c, dark);
        return const SizedBox();
      }),
    ));
    // Read the widget's own accent direction instead of re-deriving it. The
    // first version of this file carried its own copy of the wash colour *and*
    // alpha, so it kept passing after the widget was retuned and reported
    // numbers that did not match the screen — and it missed the dark-mode
    // regression where the primary plate ended up darker than its neighbours.
    final primary = Color.alphaBlend(
      (dark ? Colors.white : AppColors.brand)
          .withValues(alpha: HomeActionDock.primaryWashAlpha(dark)),
      quiet,
    );
    return (surface: surface, quiet: quiet, primary: primary);
  }

  for (final dark in [true, false]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('every dock plate is a visible shape ($mode)',
        (tester) async {
      final p = await plates(tester, dark);
      for (final e in {'quiet': p.quiet, 'primary': p.primary}.entries) {
        final ratio = contrast(e.value, p.surface);
        // ignore: avoid_print
        print('$mode ${e.key.padRight(7)} plate-vs-surface='
            '${ratio.toStringAsFixed(2)}:1');
        expect(ratio, greaterThan(1.15),
            reason: '$mode ${e.key} plate is invisible against the dock');
      }
    });

    testWidgets('primary is accented, not a different kind of object ($mode)',
        (tester) async {
      final p = await plates(tester, dark);
      final quiet = relLum(p.quiet);
      final strong = relLum(p.primary);
      final ratio = strong > quiet ? strong / quiet : quiet / strong;
      // ignore: avoid_print
      print('$mode primary/quiet luminance ratio = '
          '${ratio.toStringAsFixed(2)}x');
      // The old filled disc was 3.12x in dark and 5.6x inverse in light. A wash
      // on the same surface keeps the four slots one family.
      expect(ratio, lessThan(2.0),
          reason: '$mode primary plate is a different weight from its '
              'neighbours');
    });

    testWidgets('primary plate stands off the dock further than quiet ($mode)',
        (tester) async {
      final p = await plates(tester, dark);
      // Direction matters, not just "different". In dark mode washing the brand
      // over the plate pulled it *toward* (even below) the dock surface, so the
      // accented slot became the dimmest of the four — measured #2F3E49 primary
      // against #33414B quiet. The primary must always travel further from the
      // dock than the quiet plates do.
      final quietGap = (relLum(p.quiet) - relLum(p.surface)).abs();
      final primaryGap = (relLum(p.primary) - relLum(p.surface)).abs();
      // ignore: avoid_print
      print('$mode quietGap=${quietGap.toStringAsFixed(4)} '
          'primaryGap=${primaryGap.toStringAsFixed(4)} '
          'primary=${p.primary.toARGB32().toRadixString(16)} '
          'quiet=${p.quiet.toARGB32().toRadixString(16)}');
      expect(primaryGap, greaterThan(quietGap * 1.25),
          reason: '$mode primary plate is not more separated from the dock '
              'than a quiet plate (${p.primary.toARGB32().toRadixString(16)} vs '
              '${p.quiet.toARGB32().toRadixString(16)})');
    });

    testWidgets('every glyph clears AA on its own plate ($mode)',
        (tester) async {
      final p = await plates(tester, dark);
      for (final primary in [true, false]) {
        final plate = primary ? p.primary : p.quiet;
        final ink = AppColors.inkOn(AppColors.brand, plate, p.surface);
        final ratio = contrast(ink, plate);
        // ignore: avoid_print
        print('$mode ${primary ? 'primary' : 'quiet  '} glyph-vs-plate='
            '${ratio.toStringAsFixed(2)}:1');
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$mode glyph fails AA on its plate');
      }
    });
  }
}
