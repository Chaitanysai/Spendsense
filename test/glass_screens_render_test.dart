import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendsense/main.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/providers/update_provider.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';

/// Renders the real app shell (real [ThemeProvider], seeded ledger, no stubbed
/// business logic) for the reworked palettes and writes PNGs for review.
///
/// Output: `docs/design-review/glass-refine/screens/{palette}-{screen}.png`
///
/// It also pins the theme-switch path: Home rendered on palette A and then
/// switched to B through `ThemeProvider.setPalette` must be pixel-identical to
/// Home rendered fresh on B. Any widget that cached A's colours would differ.

TransactionModel _tx(
  String id,
  int rupees,
  String merchant,
  String category,
  int daysAgo, {
  TransactionType type = TransactionType.expense,
}) =>
    TransactionModel(
      id: id,
      amountMinor: rupees * 100,
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: 'UPI',
      date: DateTime.now().subtract(Duration(days: daysAgo)),
      time: '18:30',
      originalSms: '',
      isExcluded: false,
      source: 'Test',
      bank: 'HDFC Bank',
    );

List<TransactionModel> _ledger() => [
      _tx('1', 420, 'Blue Tokai', 'Food', 0),
      _tx('2', 78, 'Metro Card', 'Travel', 0),
      _tx('3', 649, 'Netflix', 'Entertainment', 1),
      _tx('4', 1240, 'Nature Basket', 'Food', 2),
      _tx('5', 2199, 'FabIndia', 'Shopping', 3),
      _tx('6', 500, 'HP Petrol', 'Fuel', 4),
      _tx('7', 2850, 'Airtel Broadband', 'Bills', 6),
      _tx('8', 12000, 'Rent', 'Bills', 9),
      _tx('9', 4500, 'Zara', 'Shopping', 12),
      _tx('10', 65000, 'Salary', 'Income', 2, type: TransactionType.income),
    ];

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
  await inter.load();
  final poppins = FontLoader('Poppins');
  for (final f in const [
    'Poppins-Regular.ttf',
    'Poppins-Medium.ttf',
    'Poppins-SemiBold.ttf',
    'Poppins-Bold.ttf',
  ]) {
    poppins.addFont(rootBundle.load('assets/fonts/$f'));
  }
  await poppins.load();
  // flutter_test does not load the icon font; without it every glyph is a box.
  final root = Platform.environment['FLUTTER_ROOT'];
  final file = root == null
      ? null
      : File('$root/bin/cache/artifacts/material_fonts/'
          'materialicons-regular.otf');
  if (file != null && file.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await icons.load();
  }
}

class _Harness {
  final TransactionProvider transactions;
  final ThemeProvider theme;
  final GlobalKey boundary = GlobalKey();
  _Harness(this.transactions, this.theme);
}

Future<_Harness> _pumpApp(
  WidgetTester tester,
  AppPalette palette, {
  required bool dark,
}) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime.now().toIso8601String(),
    'theme_mode': dark ? 'dark' : 'light',
    'palette_id': palette.id,
    'salary_day_setup': true,
    'salary_day': 1,
    'name': 'Asha',
    'email': 'asha@example.com',
  });

  final transactions = TransactionProvider();
  await transactions.ready;
  transactions.debugSeed(_ledger());
  await transactions.setMonthlyBudgetMinor(4000000);
  final planner = PlannerProvider();
  await planner.ready;
  final theme = ThemeProvider();
  final harness = _Harness(transactions, theme);

  await tester.pumpWidget(
    RepaintBoundary(
      key: harness.boundary,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: transactions),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: planner),
          ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ],
        child: const SpendSenseApp(),
      ),
    ),
  );
  await _settle(tester);
  return harness;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 900));
}

Future<ui.Image> _capture(WidgetTester tester, _Harness h) async {
  late ui.Image image;
  await tester.runAsync(() async {
    final object =
        h.boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    image = await object.toImage(pixelRatio: 2);
  });
  return image;
}

Future<void> _savePng(WidgetTester tester, ui.Image image, String name) async {
  await tester.runAsync(() async {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('docs/design-review/glass-refine/screens/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
  });
}

Future<Uint8List> _rgba(WidgetTester tester, ui.Image image) async {
  late Uint8List out;
  await tester.runAsync(() async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    out = data.buffer.asUint8List();
  });
  return out;
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadFonts();
  });

  // Platform channels the app reads at startup. Same mocks as
  // premium_palette_pages_test: they answer the OS, not the business logic.
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
  const secureStorage =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissions, (call) async => <int, int>{});
    messenger.setMockMethodCallHandler(connectivity, (call) async => 'wifi');
    messenger.setMockMethodCallHandler(secureStorage, (call) async {
      return switch (call.method) {
        'read' => null,
        'readAll' => <String, String>{},
        'containsKey' => false,
        _ => null,
      };
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(connectivity, null);
    messenger.setMockMethodCallHandler(secureStorage, null);
    AppColors.applyPalette(AppPalette.defaultPalette);
  });

  final cases = <String, (AppPalette, bool)>{
    'midnight': (AppPalette.midnight, true),
    'plum-blush': (AppPalette.plumBlush, true),
    'deep-navy': (AppPalette.deepNavy, true),
    'premium-blue-light': (AppPalette.premiumBlue, false),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key}: every tab renders', (tester) async {
      final (palette, dark) = entry.value;
      final h = await _pumpApp(tester, palette, dark: dark);

      // Home, then scrolled so content runs under the bar and the add button.
      await _savePng(tester, await _capture(tester, h), '${entry.key}-home');
      await tester.fling(
          find.byType(Scrollable).first, const Offset(0, -600), 1500);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 300));
      await _savePng(
          tester, await _capture(tester, h), '${entry.key}-home-scrolled');

      for (final tab in const [
        ('BILLS', 'bills'),
        ('INSIGHTS', 'insights'),
        ('CARDS', 'cards'),
        ('SETTINGS', 'settings'),
      ]) {
        await _openTab(tester, tab.$1);
        expect(tester.takeException(), isNull,
            reason: '${entry.key} ${tab.$2} threw');
        await _savePng(
            tester, await _capture(tester, h), '${entry.key}-${tab.$2}');
      }
    });
  }

  testWidgets('add button never overlaps the navigation bar', (tester) async {
    final h = await _pumpApp(tester, AppPalette.midnight, dark: true);
    expect(h.theme.palette.id, 'midnight');
    final fab = tester.getRect(find.byType(FloatingActionButton));
    final bar = tester.getRect(find.byType(FloatingNavBar));
    expect(fab.bottom, lessThanOrEqualTo(bar.top),
        reason: 'FAB $fab overlaps the bar $bar');
  });

  for (final bottomInset in [0.0, 34.0, 48.0]) {
    testWidgets(
        'Home scroll inset clears the nav pill and the add button '
        '(system inset $bottomInset)', (tester) async {
      tester.view.padding = FakeViewPadding(bottom: bottomInset * 2);
      tester.view.viewPadding = FakeViewPadding(bottom: bottomInset * 2);
      addTearDown(tester.view.resetPadding);
      await _pumpApp(tester, AppPalette.midnight, dark: true);

      // The widget's own rect includes its SafeArea, so measure the pill.
      final bar = tester.getRect(find
          .descendant(
              of: find.byType(FloatingNavBar), matching: find.byType(ClipRRect))
          .first);
      final fab = tester.getRect(find.byType(FloatingActionButton));
      // Read the inset from inside the shell body, exactly where HomeScreen
      // does. The add button lives in the Scaffold's floating slot, outside the
      // body's MediaQuery, so its context never sees the nav bar height.
      final context = tester.element(find.byType(HomeScreen));
      final inset = AppSpacing.tabBottomInset(context);

      // The gutter under the last row must reach above the pill and the add
      // button stacked on it, measured from the screen bottom.
      final screenBottom = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final clearance = screenBottom - fab.top;
      expect(inset, greaterThanOrEqualTo(clearance),
          reason: 'inset $inset does not clear the add button (needs '
              '$clearance, bar ${bar.height}, system $bottomInset)');
      expect(fab.bottom, lessThanOrEqualTo(bar.top));
      expect(bar.bottom, lessThanOrEqualTo(screenBottom - bottomInset),
          reason: 'the pill must sit above the system gesture inset');
    });
  }

  testWidgets('theme switch leaves no widget on the old palette',
      (tester) async {
    // A → B through the real provider path.
    final h = await _pumpApp(tester, AppPalette.midnight, dark: true);
    await h.theme.setPalette(AppPalette.plumBlush);
    await _settle(tester);
    final switched = await _capture(tester, h);
    await _savePng(tester, switched, 'switch-midnight-to-plum-home');
    final switchedBytes = await _rgba(tester, switched);

    // Fresh B, same pump schedule.
    await tester.pumpWidget(const SizedBox());
    final fresh = await _pumpApp(tester, AppPalette.plumBlush, dark: true);
    final freshImage = await _capture(tester, fresh);
    final freshBytes = await _rgba(tester, freshImage);

    expect(switchedBytes.length, freshBytes.length);
    var differing = 0;
    for (var i = 0; i < freshBytes.length; i += 4) {
      if ((freshBytes[i] - switchedBytes[i]).abs() > 2 ||
          (freshBytes[i + 1] - switchedBytes[i + 1]).abs() > 2 ||
          (freshBytes[i + 2] - switchedBytes[i + 2]).abs() > 2) {
        differing++;
      }
    }
    final pixels = freshBytes.length ~/ 4;
    // ignore: avoid_print
    print('theme switch: $differing of $pixels pixels differ '
        '(${(differing / pixels * 100).toStringAsFixed(3)}%)');
    if (differing > 0) {
      await _savePng(tester, freshImage, 'switch-fresh-plum-home');
    }
    // Entrance and sync animations may differ by a handful of anti-aliased
    // pixels; a stale colour would repaint whole cards.
    expect(differing / pixels, lessThan(0.002));
  });
}
