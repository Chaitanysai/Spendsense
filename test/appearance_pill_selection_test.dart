import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/screens/appearance_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// A selected pill must look *more* present than an unselected one.
///
/// Measured on device (dark, Appearance screen): selected fill `#1F2E38` against
/// unselected `#23313D`, i.e. the selected pill was darker than its neighbours,
/// so selection read inverted. The cause was a 12%-brand wash over an
/// already-dark card — the brand's own dark end pulled the fill *down*.
///
/// This reads the `BoxDecoration` the pill actually paints inside a real
/// [AppearanceScreen]. An earlier version re-implemented the fill in the test
/// file, so it passed against the *old* inverted widget: it was asserting on its
/// own mirror rather than on the screen.
void main() {
  setUp(() => AppColors.applyPalette(AppPalette.emerald));
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  Future<ThemeProvider> pumpAppearance(WidgetTester tester, {required bool dark}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final theme = ThemeProvider();
    // `AppColors.isDark` reads `ThemeData.brightness`, so the harness must set
    // it — driving only `ThemeProvider` leaves every widget believing it is in
    // light mode and silently measures the wrong branch.
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: const AppearanceScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return theme;
  }

  /// The fill of the pill that contains [label], straight off the widget tree.
  Color? fillOf(WidgetTester tester, String label) {
    final box = find
        .ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        )
        .first;
    return (tester.widget<Container>(box).decoration as BoxDecoration).color;
  }

  for (final dark in [true, false]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('$mode selected pill has a fill, neighbours do not',
        (tester) async {
      await pumpAppearance(tester, dark: dark);
      final theme = Provider.of<ThemeProvider>(
        tester.element(find.byType(AppearanceScreen)),
        listen: false,
      );
      theme.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      final selected = fillOf(tester, 'Dark');
      final unselected = fillOf(tester, 'System');
      // ignore: avoid_print
      print('$mode selected=${selected?.toARGB32().toRadixString(16)} '
          'unselected=${unselected?.toARGB32().toRadixString(16)}');

      expect(selected, isNotNull);
      expect(unselected, isNotNull);
      expect(selected!.a, greaterThan(0.0),
          reason: '$mode selected pill has no fill');
      expect(unselected!.a, 0.0,
          reason: '$mode unselected pill must stay transparent');

      if (dark) {
        // On a dark card the selected fill must lift, so it has to be a
        // neutral white overlay rather than a brand tint.
        expect(selected.r, closeTo(selected.b, 0.02),
            reason: 'dark selected fill is tinted, which pulls it below the '
                'card: r=${selected.r} b=${selected.b}');
        expect(selected.r, greaterThan(0.5),
            reason: 'dark selected fill should be near-white');
      }
    });
  }
}
