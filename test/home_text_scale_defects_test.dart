import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/widgets/category_spending_bars.dart';
import 'package:spendsense/widgets/section_header.dart';

/// Two large-text defects, both seen in the 411dp / 2.0x captures of Home and
/// neither caught by an existing test:
///
///  * "Monthly budget" next to "Manage" was cut to "Monthly bud...".
///  * the category percentage lost its sign: "39%" is 48dp wide at 2x text and
///    its box is 32dp, so the % was clipped and the row read "39".
///
/// Checked with Inter loaded so the glyphs have their real width.
void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await inter.load();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(411 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('a dashboard section title is not cut off at 2x text',
      (tester) async {
    await pump(
      tester,
      SectionHeader(
        title: 'Monthly budget',
        large: true,
        actionLabel: 'Manage',
        actionIcon: Icons.chevron_right_rounded,
        onAction: () {},
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Monthly budget'),
    );
    expect(paragraph.didExceedMaxLines, isFalse,
        reason: 'the title was truncated with an ellipsis');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the category percentage keeps its % sign inside its box at 2x',
      (tester) async {
    await pump(
      tester,
      const CategorySpendingBars(
        totalsMinor: {'Shopping': 132000, 'Food': 88400, 'Groceries': 86000},
        maxRows: 3,
      ),
    );
    var checked = 0;
    for (final e in find.byType(RichText).evaluate()) {
      final ro = e.renderObject;
      if (ro is! RenderParagraph || !ro.text.toPlainText().endsWith('%')) {
        continue;
      }
      // Only the row labels sit in a 32dp box; the composition legend also ends
      // in "%" but has its own layout, so skip anything without that box.
      RenderBox? box;
      e.visitAncestorElements((a) {
        final w = a.widget;
        if (w is SizedBox && w.width == 32) {
          box = a.renderObject as RenderBox;
          return false;
        }
        return true;
      });
      if (box == null) continue;
      checked++;
      // Clipped text is glyphs wider than the box they are painted in. Two
      // layouts to tell apart: a plain Text in a 32dp box is laid out 32dp wide
      // and its 48dp of glyphs spill out (size.width reads 32, the glyphs do
      // not); under a FittedBox the paragraph is laid out at its natural width
      // and the whole thing is scaled down. So measure the glyph width
      // (intrinsic) times the scale actually applied (painted / laid-out).
      final painted = MatrixUtils.transformRect(
        ro.getTransformTo(null),
        Offset.zero & ro.size,
      );
      final applied = painted.width / ro.size.width;
      final glyphs = ro.getMaxIntrinsicWidth(double.infinity) * applied;
      final slotWidth = box!.size.width;
      expect(glyphs, lessThanOrEqualTo(slotWidth + 0.5),
          reason: '${ro.text.toPlainText()} paints '
              '${glyphs.toStringAsFixed(1)}dp of glyphs in a '
              '${slotWidth.toStringAsFixed(0)}dp box and is clipped');
    }
    expect(checked, 3, reason: 'expected three percentage labels');
    expect(tester.takeException(), isNull);
  });
}
