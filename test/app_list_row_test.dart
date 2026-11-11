import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/app_list_row.dart';
import 'package:spendsense/widgets/app_surface.dart';
import 'package:spendsense/widgets/icon_well.dart';

/// The list row is the shared anatomy for settings groups, bills, budgets and
/// pickers. What must hold: one leading well, one title, one muted line, a
/// trailing slot that never crowds the title, and no overflow with a long
/// merchant or a 2x text scale.

Widget _host(Widget child, {bool dark = false, double textScale = 1.0}) =>
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
      ),
    );

void main() {
  setUp(() => AppColors.applyPalette(AppPalette.defaultPalette));
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  testWidgets('renders a well, a title, a subtitle and a chevron',
      (tester) async {
    await tester.pumpWidget(_host(
      AppListRow(
        leadingIcon: Icons.settings_outlined,
        title: 'Notifications',
        subtitle: 'Budget alerts and bill reminders',
        onTap: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(IconWell), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Budget alerts and bill reminders'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('a trailing value replaces the chevron', (tester) async {
    await tester.pumpWidget(_host(
      const AppListRow(
        title: 'Currency',
        trailingText: 'INR',
        onTap: _noop,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('INR'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('a custom trailing widget is honoured', (tester) async {
    await tester.pumpWidget(_host(
      AppListRow(
        title: 'Sound effects',
        trailing: Switch(value: true, onChanged: (value) {}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('the destructive variant tones the title', (tester) async {
    await tester.pumpWidget(_host(
      AppListRow(
        leadingIcon: Icons.delete_outline,
        title: 'Delete account',
        destructive: true,
        onTap: () {},
      ),
    ));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Delete account'));
    expect(title.style!.color, AppColors.danger);
  });

  testWidgets('a tappable row fires once and announces itself', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(_host(
      AppListRow(
        leadingIcon: Icons.receipt_long_outlined,
        title: 'Export data',
        subtitle: 'Save a CSV to this device',
        onTap: () => taps++,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Export data, Save a CSV to this device'),
        findsOneWidget);
    await tester.tap(find.byType(AppListRow));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a divider is indented past the leading well', (tester) async {
    await tester.pumpWidget(_host(
      const AppListRow(
        leadingIcon: Icons.settings_outlined,
        title: 'Appearance',
        showDivider: true,
      ),
    ));
    await tester.pumpAndSettle();

    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.indent, greaterThan(40));
    expect(divider.height, 1);
  });

  testWidgets('a long title ellipsises and never overflows at 2x text',
      (tester) async {
    await tester.pumpWidget(_host(
      AppListRow(
        leadingIcon: Icons.storefront_outlined,
        title: 'A Very Long Merchant Name That Stresses Line Wrapping 42',
        subtitle: 'Food · Others · Nov 09, 2026',
        trailingText: '₹1,32,000',
        onTap: () {},
      ),
      textScale: 2.0,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.text(
      'A Very Long Merchant Name That Stresses Line Wrapping 42',
    ));
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.maxLines, 1);
  });

  testWidgets('a group is one surface with hairline-separated rows',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(
      AppListGroup(
        semanticLabel: 'Appearance',
        rows: [
          AppListRow(
            leadingIcon: Icons.palette_outlined,
            title: 'Theme colours',
            showDivider: true,
            onTap: () {},
          ),
          AppListRow(
            leadingIcon: Icons.text_fields_rounded,
            title: 'Font style',
            showDivider: true,
            onTap: () {},
          ),
          AppListRow(
            leadingIcon: Icons.restart_alt_rounded,
            title: 'Reset appearance',
            destructive: true,
            onTap: () {},
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    // One raised surface for the whole section, not one per row.
    expect(find.byType(AppSurface), findsOneWidget);
    expect(find.byType(AppListDivider), findsNWidgets(2));
    expect(find.byType(AppListRow), findsNWidgets(3));
    expect(find.bySemanticsLabel('Appearance'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('holds its minimum height on every palette', (tester) async {
    for (final palette in AppPalette.all) {
      AppColors.applyPalette(palette);
      for (final dark in [false, true]) {
        await tester.pumpWidget(_host(
          const AppListRow(title: 'Row'),
          dark: dark,
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: '${palette.id} dark=$dark');
        expect(tester.getSize(find.byType(AppListRow)).height,
            greaterThanOrEqualTo(56));
      }
    }
    AppColors.applyPalette(AppPalette.defaultPalette);
  });
}

void _noop() {}
