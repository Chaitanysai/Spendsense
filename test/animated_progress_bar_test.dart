import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/widgets/animated_progress_bar.dart';

Widget _host(
  Widget child, {
  bool reduceMotion = false,
  double width = 240,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(child: SizedBox(width: width, child: child)),
        ),
      ),
    ),
  );
}

/// The fill currently painted, read from the FractionallySizedBox the bar uses.
double _fill(WidgetTester tester) {
  final box = tester.widget<FractionallySizedBox>(
    find.descendant(
      of: find.byType(AnimatedProgressBar),
      matching: find.byType(FractionallySizedBox),
    ),
  );
  return box.widthFactor ?? 0;
}

void main() {
  testWidgets('grows from zero and settles exactly on the target',
      (tester) async {
    await tester.pumpWidget(_host(
      const AnimatedProgressBar(
        fraction: 0.6,
        duration: Duration(milliseconds: 400),
      ),
    ));

    await tester.pump();
    expect(_fill(tester), 0.0, reason: 'starts empty');

    await tester.pump(const Duration(milliseconds: 120));
    final mid = _fill(tester);
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(0.6), reason: 'still animating');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(_fill(tester), closeTo(0.6, 1e-9),
        reason: 'must settle on the exact target, not near it');
  });

  testWidgets('a data change continues from the painted value', (tester) async {
    await tester.pumpWidget(_host(
      const AnimatedProgressBar(
        fraction: 0.8,
        duration: Duration(milliseconds: 300),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(_fill(tester), closeTo(0.8, 1e-9));

    await tester.pumpWidget(_host(
      const AnimatedProgressBar(
        fraction: 0.4,
        duration: Duration(milliseconds: 300),
      ),
    ));
    await tester.pump();
    // The first frame of the change must start from 0.8, not from zero.
    expect(_fill(tester), closeTo(0.8, 1e-6));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(_fill(tester), closeTo(0.4, 1e-9));
  });

  testWidgets('an unrelated rebuild does not replay the animation',
      (tester) async {
    Widget build(String marker) => _host(
          AnimatedProgressBar(
            key: const ValueKey('bar'),
            fraction: 0.55,
            duration: const Duration(milliseconds: 300),
            semanticLabel: marker,
          ),
        );

    await tester.pumpWidget(build('first'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final settled = _fill(tester);

    await tester.pumpWidget(build('second'));
    await tester.pump();
    expect(_fill(tester), closeTo(settled, 1e-9),
        reason: 'same target, different parent build: value must not reset');
  });

  testWidgets('clamps out-of-range and non-finite values', (tester) async {
    for (final value in <double>[0, -0.5, 2.5, double.nan, double.infinity]) {
      await tester.pumpWidget(_host(
        AnimatedProgressBar(
          key: ValueKey(value),
          fraction: value,
          duration: const Duration(milliseconds: 100),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      final painted = _fill(tester);
      expect(painted.isFinite, isTrue, reason: '$value');
      expect(painted, inInclusiveRange(0.0, 1.0), reason: '$value');
      expect(tester.takeException(), isNull, reason: '$value');
    }
  });

  testWidgets('a zero target paints nothing and never throws', (tester) async {
    await tester.pumpWidget(_host(
      const AnimatedProgressBar(fraction: 0, duration: Duration(milliseconds: 200)),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_fill(tester), 0.0, reason: 'zero paints an empty bar');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion settles immediately', (tester) async {
    await tester.pumpWidget(_host(
      const AnimatedProgressBar(
        fraction: 0.75,
        duration: Duration(milliseconds: 600),
      ),
      reduceMotion: true,
    ));
    await tester.pump();

    expect(_fill(tester), closeTo(0.75, 1e-9));
  });

  testWidgets('a stagger delay postpones the start, then completes',
      (tester) async {
    await tester.pumpWidget(_host(
      const AnimatedProgressBar(
        fraction: 0.5,
        delay: Duration(milliseconds: 120),
        duration: Duration(milliseconds: 200),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_fill(tester), 0.0, reason: 'still waiting for its turn');

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_fill(tester), closeTo(0.5, 1e-9));
  });

  testWidgets('exposes a label and a numeric value to accessibility',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(
      const AnimatedProgressBar(
        fraction: 0.42,
        semanticLabel: 'Food share',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800));

    final node = tester.getSemantics(find.bySemanticsLabel('Food share'));
    expect(node.label, 'Food share');
    expect(node.value, '42%');
    handle.dispose();
  });

  testWidgets('a timer is cancelled when the bar is disposed', (tester) async {
    await tester.pumpWidget(_host(
      const AnimatedProgressBar(
        fraction: 0.9,
        delay: Duration(seconds: 5),
      ),
    ));
    // Replace the tree before the delay fires; no pending-timer failure.
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
}
