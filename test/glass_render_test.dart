import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';
import 'package:spendsense/widgets/glass_card.dart';

/// Renders the glass card and the floating nav over scrolling content for the
/// three reworked palettes and writes PNGs for visual review.
///
/// Output: `docs/design-review/glass-refine/{palette}-tab{n}.png`
const _items = [
  NavItem(Icons.home_rounded, 'Home'),
  NavItem(Icons.receipt_long_rounded, 'Activity'),
  NavItem(Icons.pie_chart_rounded, 'Insights'),
  NavItem(Icons.account_balance_wallet_rounded, 'Budgets'),
  NavItem(Icons.settings_rounded, 'Settings'),
];

Widget _scene(AppPalette palette, int selected) {
  AppColors.applyPalette(palette);
  final text = TextStyle(
    fontFamily: 'Inter',
    color: AppColors.textPrimaryFor(true),
    fontSize: 15,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter'),
    home: Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          // Scrolling content: rows of cards, deliberately running right under
          // the nav so the see-through fill and blur are visible.
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 120),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              Text('This month', style: text.copyWith(fontSize: 22)),
              const SizedBox(height: 12),
              for (var i = 0; i < 7; i++) ...[
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: i.isEven
                              ? AppPalette.expenseRed
                              : AppPalette.incomeGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Transaction ${i + 1}',
                          style: text,
                        ),
                      ),
                      Text('₹${(i + 1) * 420}', style: text),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNavBar(
              items: _items,
              currentIndex: selected,
              onTap: (_) {},
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await loader.load();
    // flutter_test does not load the icon font on its own; without it every
    // glyph renders as a placeholder square.
    final root = Platform.environment['FLUTTER_ROOT'];
    final iconFile = root == null
        ? null
        : File('$root/bin/cache/artifacts/material_fonts/'
            'materialicons-regular.otf');
    if (iconFile != null && iconFile.existsSync()) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())));
      await icons.load();
    }
  });

  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  final cases = {
    'midnight': AppPalette.midnight,
    'plum-blush': AppPalette.plumBlush,
    'deep-navy': AppPalette.deepNavy,
  };

  for (final entry in cases.entries) {
    for (final selected in [0, 2]) {
      testWidgets('${entry.key} · tab $selected renders', (tester) async {
        tester.view.physicalSize = const Size(390 * 2, 560 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: key, child: _scene(entry.value, selected)),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File(
            'docs/design-review/glass-refine/${entry.key}-tab$selected.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes.buffer.asUint8List());
        });
      });
    }
  }
}
