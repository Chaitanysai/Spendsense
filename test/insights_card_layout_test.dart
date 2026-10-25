// Regression coverage for R10: the Insights "Ask SpendSense AI" card clipped
// its subtitle mid-word ("…compares — a") instead of ellipsising.
//
// Cause: `height: 1.4` on a 13px style needs 2.8 * 13 of vertical space for two
// lines, which overran the card's 2-line budget; the overflow strategy never
// got a chance to draw an ellipsis because the last line was cut by the clip.
//
// These assertions are about LAYOUT, not about a screenshot: a RenderFlex
// overflow would surface as a caught Flutter error, and the ellipsis contract
// is checked on the widget itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/main.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';

const _subtitle =
    'Ask about transactions, preview exclusions, or undo a change — '
    'calculated on-device, with optional Gemini assistance.';

Future<void> _pumpInsights(WidgetTester tester) async {
  // Galaxy S24 is the design target, and the device the bug was seen on is
  // narrower still (1080x2400 @ 420dpi ≈ 411 wide), so test at 360 logical.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime.now().toIso8601String(),
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const SpendSenseApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));

  await tester.tap(find.text('INSIGHTS'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _subtitleFinder() => find.text(_subtitle);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('R10 — Insights AI card subtitle', () {
    testWidgets('renders without a layout overflow', (tester) async {
      await _pumpInsights(tester);

      // A RenderFlex/painting overflow throws into `takeException()`; any
      // non-null value here is the regression.
      expect(tester.takeException(), isNull);
      expect(_subtitleFinder(), findsOneWidget);
    });

    testWidgets('keeps the two-line ellipsis contract', (tester) async {
      await _pumpInsights(tester);

      final text = tester.widget<Text>(_subtitleFinder());
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('does not set a line height that overruns the line budget',
        (tester) async {
      await _pumpInsights(tester);

      final text = tester.widget<Text>(_subtitleFinder());
      final style = text.style;
      expect(style, isNotNull);

      // The bug was an explicit `height: 1.4`, which needs 2.8 * fontSize of
      // vertical space for two lines and overran the card. The shared
      // `AppText.onGradient` default is 1.2; anything tighter than that default
      // is drift, and 1.4 is the specific value that regressed.
      expect(style!.height, lessThanOrEqualTo(1.2),
          reason: 'a line height above the type default overran the card');
      expect(style.height, isNot(1.4), reason: 'the exact regressing value');
      expect(style.fontSize, 13,
          reason: 'the intended type size must not change');
    });

    testWidgets('the whole card fits inside the viewport width',
        (tester) async {
      await _pumpInsights(tester);

      final card = _subtitleFinder();
      final box = tester.getRect(card);
      final screen =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      // The subtitle must not be allowed to paint past the right edge of the
      // screen, which is what a mis-measured line box effectively did.
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(screen + 0.5));
    });

    testWidgets('the title above it is still the full, unordered headline',
        (tester) async {
      await _pumpInsights(tester);
      expect(find.text('Ask SpendSense AI'), findsOneWidget);
      expect(find.text('Tap to open'), findsOneWidget);
    });
  });
}
