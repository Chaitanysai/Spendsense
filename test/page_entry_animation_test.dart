import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/widgets/animated_progress_bar.dart';
import 'package:spendsense/widgets/app_page_route.dart';
import 'package:spendsense/widgets/fade_indexed_stack.dart';
import 'package:spendsense/widgets/fade_slide_in.dart';
import 'package:spendsense/widgets/page_entry.dart';

Widget _app(Widget home) => MaterialApp(
      navigatorObservers: [PageEntryRouteObserver.instance],
      home: home,
    );

double _pageOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find
        .descendant(
          of: find.byType(PageEntryHost),
          matching: find.byType(FadeTransition),
        )
        .first)
    .opacity
    .value;

/// Smallest opacity among the entrance transitions wrapping [content].
/// Using the minimum keeps the assertion independent of layer order.
double _opacityAround(WidgetTester tester, Finder content) {
  final opacities = tester
      .widgetList<FadeTransition>(
        find.ancestor(of: content, matching: find.byType(FadeTransition)),
      )
      .map((t) => t.opacity.value);
  return opacities.reduce((a, b) => a < b ? a : b);
}

double _fill(WidgetTester tester) =>
    tester
        .widget<FractionallySizedBox>(
          find.descendant(
            of: find.byType(AnimatedProgressBar),
            matching: find.byType(FractionallySizedBox),
          ),
        )
        .widthFactor ??
    0;

Widget _barHost(PageEntryController controller, double fraction) => _app(
      PageEntryHost(
        controller: controller,
        child: Center(
          child: SizedBox(
            width: 240,
            child: AnimatedProgressBar(
              fraction: fraction,
              duration: const Duration(milliseconds: 300),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a page entrance runs on first entry and settles at rest',
      (tester) async {
    await tester.pumpWidget(
      _app(const PageEntryHost(child: Text('page content'))),
    );
    await tester.pump();

    expect(_pageOpacity(tester), lessThan(1.0),
        reason: 'the first frame must start the entrance, not paint at rest');

    await tester.pump(const Duration(milliseconds: 500));
    expect(_pageOpacity(tester), 1.0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a pushed page replays when the route above it is popped',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [PageEntryRouteObserver.instance],
        home: PageEntryHost(
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    AppPageRoute(
                      builder: (_) => const Scaffold(body: Text('details')),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('details'), findsOneWidget);

    navigator.currentState!.pop();
    await tester.pump(); // start the pop; didPopNext schedules the replay
    await tester.pump(); // run the post-frame replay

    expect(_opacityAround(tester, find.text('open')), lessThan(1.0),
        reason: 'returning to the page must restart its entrance');

    await tester.pump(const Duration(milliseconds: 500));
    expect(_opacityAround(tester, find.text('open')), 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained tabs replay their entrance when selected again',
      (tester) async {
    Widget host(int index) => _app(
          FadeIndexedStack(
            index: index,
            children: const [
              Text('first'),
              FadeSlideIn(child: Text('second')),
            ],
          ),
        );

    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(1));
    await tester.pumpAndSettle();
    expect(_opacityAround(tester, find.text('second')), 1.0);

    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(1));
    await tester.pump();
    await tester.pump();

    expect(_opacityAround(tester, find.text('second')), lessThan(1.0),
        reason: 'a retained tab must animate on every selection');
    await tester.pump(const Duration(milliseconds: 500));
    expect(_opacityAround(tester, find.text('second')), 1.0);

    // No remount, no duplicate state, and a plain rebuild stays settled.
    await tester.pumpWidget(host(1));
    await tester.pump();
    expect(_opacityAround(tester, find.text('second')), 1.0,
        reason: 'an unrelated rebuild must not restart the entrance');
  });

  testWidgets('progress bars replay from zero and finish on the exact target',
      (tester) async {
    final controller = PageEntryController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_barHost(controller, 0.6));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(_fill(tester), closeTo(0.6, 1e-9));

    controller.replay();
    await tester.pump();
    expect(_fill(tester), 0.0, reason: 'a page entry restarts the fill');

    await tester.pump(const Duration(milliseconds: 120));
    final mid = _fill(tester);
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(0.6));

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_fill(tester), closeTo(0.6, 1e-9),
        reason: 'the fill must stop precisely on the target');
  });

  testWidgets('an unrelated rebuild does not restart a finished bar',
      (tester) async {
    final controller = PageEntryController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_barHost(controller, 0.55));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(_fill(tester), closeTo(0.55, 1e-9));

    await tester.pumpWidget(_barHost(controller, 0.55));
    await tester.pump();
    expect(_fill(tester), closeTo(0.55, 1e-9),
        reason: 'same generation and same target: keep the painted value');
  });

  testWidgets('a target update animates from the painted value to the new one',
      (tester) async {
    final controller = PageEntryController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_barHost(controller, 0.25));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(_fill(tester), closeTo(0.25, 1e-9));

    await tester.pumpWidget(_barHost(controller, 0.75));
    await tester.pump();
    expect(_fill(tester), closeTo(0.25, 1e-6),
        reason: 'a data update continues from what is on screen');

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(_fill(tester), closeTo(0.75, 1e-9));
  });

  testWidgets('zero, full and over-target values clamp and settle cleanly',
      (tester) async {
    final controller = PageEntryController();
    addTearDown(controller.dispose);

    for (final (i, value) in <double>[0, 1, 1.5, -0.25].indexed) {
      await tester.pumpWidget(
        _app(
          PageEntryHost(
            key: ValueKey('host-$i'),
            controller: controller,
            child: Center(
              child: SizedBox(
                width: 240,
                child: AnimatedProgressBar(
                  fraction: value,
                  duration: const Duration(milliseconds: 200),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final painted = _fill(tester);
      expect(painted, inInclusiveRange(0.0, 1.0), reason: 'value $value');
      expect(painted, closeTo(value.clamp(0.0, 1.0), 1e-9),
          reason: 'value $value must settle on its clamp');
      expect(tester.takeException(), isNull);
    }

    // Zero must stay empty even after a replay.
    controller.replay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_fill(tester), 0.0);
  });

  testWidgets('controllers and timers are disposed without exceptions',
      (tester) async {
    final controller = PageEntryController();
    await tester.pumpWidget(_barHost(controller, 0.9));
    await tester.pump(const Duration(milliseconds: 20));

    // Remove the whole subtree mid-animation.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
    controller.dispose();
    // A replay after disposal is a no-op, not a crash.
    controller.replay();
    expect(controller.generation, 0);
  });
}
