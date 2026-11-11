import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/home_action_dock.dart';

/// The dock's plates must read as shapes, and their glyphs must be legible.
///
/// History: two device reports ("only Add expense has an icon", then "Add
/// expense has a dark icon and the rest do not") came from quiet plates that
/// were a brand tint 1.1 to 1.3:1 off the dock and a primary that was a
/// different kind of object. The V2 dock removes both causes: quiet plates are
/// neutral outlined squares that all share one construction, and the single
/// primary (Add) is a solid ink disc on purpose, the same object as the active
/// navigation pill.
///
/// Every value is resolved through the widget's own helpers inside a real build
/// context, never through a copy of the maths.
void main() {
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  double contrast(Color a, Color b) => AppColors.contrastRatio(a, b);

  /// The dock surface and plate fills exactly as the widget resolves them.
  Future<({Color surface, Color quiet, Color primary, Color primaryInk})>
      resolve(WidgetTester tester, bool dark) async {
    late Color surface, quiet;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Builder(builder: (c) {
        surface = HomeActionDock.dockSurface(c);
        quiet = HomeActionDock.quietPlate(c, dark);
        return const SizedBox();
      }),
    ));
    return (
      surface: surface,
      quiet: quiet,
      primary: HomeActionDock.primaryPlate(dark),
      primaryInk: HomeActionDock.primaryInk(dark),
    );
  }

  for (final palette in AppPalette.all) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('dock plates and glyphs hold up (${palette.id} $mode)',
          (tester) async {
        AppColors.applyPalette(palette);
        final p = await resolve(tester, dark);
        final reason = '${palette.label} $mode';

        // The primary is a solid ink disc: it must stand off the card clearly
        // and its glyph must clear the same 7:1 the navigation pill does.
        expect(contrast(p.primary, p.surface), greaterThanOrEqualTo(7),
            reason: '$reason: primary disc vs dock');
        expect(contrast(p.primaryInk, p.primary), greaterThanOrEqualTo(7),
            reason: '$reason: primary glyph vs disc');

        // A quiet plate is a faint step in tone; the hairline around it carries
        // the shape. Opaque, and never the same colour as the card.
        expect(p.quiet.a, 1.0, reason: '$reason: quiet plate is opaque');
        expect(p.quiet, isNot(p.surface), reason: '$reason: plate = card');

        // Its glyph is the primary text ink, measured on the plate it sits on.
        final ink = AppColors.textPrimaryFor(dark);
        expect(contrast(ink, p.quiet), greaterThanOrEqualTo(4.5),
            reason: '$reason: quiet glyph vs plate');
      });
    }
  }
}
