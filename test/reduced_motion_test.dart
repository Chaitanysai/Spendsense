import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/insights_screen.dart';
import 'package:spendsense/widgets/app_states.dart';

void _setReducedMotion(WidgetTester tester, {required bool enabled}) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: enabled);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Color _skeletonColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(SkeletonBox),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as BoxDecoration).color!;
}

Future<ScrollController> _openAssistant(
  WidgetTester tester, {
  required bool reducedMotion,
}) async {
  _setReducedMotion(tester, enabled: reducedMotion);
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => TransactionProvider(),
      child: const MaterialApp(home: InsightsScreen()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.text('Ask SpendSense AI'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ask SpendSense AI'));
  await tester.pumpAndSettle();

  for (var i = 0; i < 5; i++) {
    await tester.tap(find.text('Top category?'));
    await tester.pumpAndSettle();
  }

  final messageList = find.byWidgetPredicate(
    (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
  );
  expect(messageList, findsOneWidget);

  final controller = tester.widget<ListView>(messageList).controller!;
  expect(controller.position.maxScrollExtent, greaterThan(0));
  return controller;
}

Future<void> _submitAssistantQuery(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextField),
    'How many transactions do I have?',
  );
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SkeletonBox reduced motion', () {
    testWidgets('renders a stable placeholder when animations are disabled',
        (tester) async {
      _setReducedMotion(tester, enabled: true);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SkeletonBox(height: 24, width: 120)),
        ),
      );

      final initialColor = _skeletonColor(tester);
      await tester.pump(const Duration(milliseconds: 550));
      expect(_skeletonColor(tester), initialColor);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(_skeletonColor(tester), initialColor);
    });

    testWidgets('keeps shimmering when animations are enabled', (tester) async {
      _setReducedMotion(tester, enabled: false);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SkeletonBox(height: 24, width: 120)),
        ),
      );

      final initialColor = _skeletonColor(tester);
      await tester.pump(const Duration(milliseconds: 550));
      expect(_skeletonColor(tester), isNot(initialColor));
    });
  });

  group('assistant auto-scroll reduced motion', () {
    testWidgets('jumps immediately when animations are disabled',
        (tester) async {
      final controller = await _openAssistant(
        tester,
        reducedMotion: true,
      );
      final previousOffset = controller.offset;

      await _submitAssistantQuery(tester);

      expect(controller.position.maxScrollExtent, greaterThan(previousOffset));
      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );
    });

    testWidgets('keeps animated scrolling when animations are enabled',
        (tester) async {
      final controller = await _openAssistant(
        tester,
        reducedMotion: false,
      );
      final previousOffset = controller.offset;

      await _submitAssistantQuery(tester);

      final targetOffset = controller.position.maxScrollExtent;
      expect(targetOffset, greaterThan(previousOffset));
      expect(controller.offset, closeTo(previousOffset, 1));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(controller.offset, greaterThan(previousOffset));

      await tester.pump(const Duration(milliseconds: 125));
      expect(controller.offset, closeTo(targetOffset, 1));
    });
  });
}
