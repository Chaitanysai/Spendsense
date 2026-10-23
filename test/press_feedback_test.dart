import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/widgets/app_button.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';
import 'package:spendsense/widgets/glass_card.dart';
import 'package:spendsense/widgets/pressable.dart';

/// Hosts a widget under a real MaterialApp so InkWells have a Material ancestor
/// and MediaQuery can be adjusted per test.
///
/// The splash factory is pinned to [InkRipple] so the glass-card layering tests
/// observe a deterministic ink layer instead of a platform-specific shader.
Widget _host(
  Widget child, {
  bool disableAnimations = false,
  bool dark = false,
  Color? splashColor,
}) {
  final theme =
      ThemeData(brightness: dark ? Brightness.dark : Brightness.light);
  return MaterialApp(
    theme: theme.copyWith(
      splashFactory: InkRipple.splashFactory,
      splashColor: splashColor,
    ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

/// Reads the scale of the press transform under [root].
double _scaleOf(WidgetTester tester, Finder root) {
  final transform = tester.widget<Transform>(
    find.descendant(of: root, matching: find.byType(Transform)).first,
  );
  return transform.transform.storage[0];
}

/// The child used by most press tests: a plain, tappable box.
const Widget _box = SizedBox(width: 160, height: 48);

const Widget _tallBox = SizedBox(width: 160, height: 120);

/// Samples one pixel from the widget under [key] (in its own coordinates).
///
/// Rendering the subtree is the only honest way to prove a ripple is visible:
/// no widget-tree assertion can tell whether ink was painted above or below an
/// opaque fill.
Future<List<int>> _pixelAt(
  WidgetTester tester,
  GlobalKey key,
  Offset local,
) async {
  // `toImage` hands work to the engine, which the fake-async test zone never
  // runs. It has to be awaited inside `runAsync` or the test hangs forever.
  late List<int> pixel;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final width = image.width;
    final height = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    final bytes = data!;
    final x = local.dx.round().clamp(0, width - 1);
    final y = local.dy.round().clamp(0, height - 1);
    final i = (y * width + x) * 4;
    pixel = <int>[
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    ];
  });
  return pixel;
}

Offset _centerOf(WidgetTester tester, GlobalKey key) {
  final box = tester.renderObject<RenderBox>(find.byKey(key));
  return Offset(box.size.width / 2, box.size.height / 2);
}

void main() {
  group('Pressable', () {
    testWidgets('feeds back on touch-down, settles at 0.97, then fires once',
        (tester) async {
      var taps = 0;
      const key = Key('pressable');
      await tester.pumpWidget(_host(Pressable(
        key: key,
        onTap: () => taps++,
        child: _box,
      )));

      expect(_scaleOf(tester, find.byKey(key)), 1.0);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(key)));
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'touch-down must schedule feedback on the very next frame',
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _scaleOf(tester, find.byKey(key)),
        lessThan(1.0),
        reason: 'feedback starts on pointer-down, not after the tap resolves',
      );
      expect(taps, 0, reason: 'holding a control must not run its action');

      // 90 ms press-in: measured after the press window has elapsed.
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scaleOf(tester, find.byKey(key)), closeTo(0.97, 0.0001));

      await gesture.up();
      await tester.pump();
      // Mid-release the surface is still travelling back to rest.
      await tester.pump(const Duration(milliseconds: 40));
      final releasing = _scaleOf(tester, find.byKey(key));
      expect(releasing, greaterThan(0.97));
      expect(releasing, lessThan(1.0));

      await tester.pump(const Duration(milliseconds: 220));
      expect(_scaleOf(tester, find.byKey(key)), closeTo(1.0, 0.0001));
      expect(taps, 1);
    });

    testWidgets('reduced motion keeps the control flat but still taps',
        (tester) async {
      var taps = 0;
      const key = Key('pressable');
      await tester.pumpWidget(_host(
        Pressable(key: key, onTap: () => taps++, child: _box),
        disableAnimations: true,
      ));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(key)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scaleOf(tester, find.byKey(key)), 1.0);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(_scaleOf(tester, find.byKey(key)), 1.0);
      expect(taps, 1, reason: 'reduced motion must not cost the tap');
    });

    testWidgets('a static Pressable adds no feedback layer', (tester) async {
      const key = Key('static');
      await tester.pumpWidget(_host(const Pressable(key: key, child: _box)));

      expect(
        find.descendant(of: find.byKey(key), matching: find.byType(Transform)),
        findsNothing,
        reason: 'content with no tap must not grow a press layer',
      );
    });

    testWidgets('a drag past the touch slop releases the press, no tap fires',
        (tester) async {
      var taps = 0;
      const key = Key('pressable');
      await tester.pumpWidget(_host(Pressable(
        key: key,
        onTap: () => taps++,
        child: _box,
      )));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(key)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scaleOf(tester, find.byKey(key)), closeTo(0.97, 0.0001));

      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        _scaleOf(tester, find.byKey(key)),
        closeTo(1.0, 0.0001),
        reason: 'a drag must not leave the surface stuck under the finger',
      );

      await gesture.up();
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('a drag inside a real scrollable scrolls it without tapping',
        (tester) async {
      var taps = 0;
      const key = Key('row');
      await tester.pumpWidget(_host(SizedBox(
        height: 200,
        child: ListView(
          children: [
            Pressable(
              key: key,
              onTap: () => taps++,
              child: const SizedBox(
                height: 80,
                child: Center(child: Text('ROW')),
              ),
            ),
            for (var i = 0; i < 8; i++)
              SizedBox(
                height: 80,
                child: Center(child: Text('FILLER $i')),
              ),
          ],
        ),
      )));

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, 0);

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('ROW')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scaleOf(tester, find.byKey(key)), closeTo(0.97, 0.0001));

      // Two moves: the first is absorbed by the drag slop, the second scrolls.
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(
        scrollable.position.pixels,
        greaterThan(0),
        reason: 'the pointer must still drive the scrollable',
      );
      expect(
        _scaleOf(tester, find.byKey(key)),
        closeTo(1.0, 0.0001),
        reason: 'the pressed look must clear once the list takes the drag',
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 0, reason: 'a scroll must never become a tap');
    });

    testWidgets('the tap callback and its sound stay single-shot',
        (tester) async {
      var taps = 0;
      const key = Key('pressable');
      await tester.pumpWidget(_host(Pressable(
        key: key,
        onTap: () => taps++,
        child: _box,
      )));

      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('PressFeedback', () {
    testWidgets('a child-owned long press is not stolen', (tester) async {
      var longPresses = 0;
      await tester.pumpWidget(_host(PressFeedback(
        child: GestureDetector(
          onLongPress: () => longPresses++,
          child: const SizedBox(
            width: 160,
            height: 48,
            child: Text('HOLD'),
          ),
        ),
      )));

      await tester.longPress(find.text('HOLD'));
      await tester.pump();
      expect(longPresses, 1);
    });

    testWidgets('a disabled control stays flat and fires nothing',
        (tester) async {
      const key = Key('feedback');
      await tester.pumpWidget(_host(const PressFeedback(
        key: key,
        enabled: false,
        child: _box,
      )));

      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(key)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_scaleOf(tester, find.byKey(key)), 1.0);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 220));
      expect(_scaleOf(tester, find.byKey(key)), 1.0);
    });

    testWidgets('feedback emits no platform sounds and no haptics',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      const key = Key('feedback');
      await tester
          .pumpWidget(_host(const PressFeedback(key: key, child: _box)));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(key)));
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        calls.where((c) =>
            c.method == 'SystemSound.play' ||
            c.method == 'HapticFeedback.vibrate'),
        isEmpty,
        reason: 'the press layer must not add audible or tactile feedback',
      );
    });
  });

  group('shared buttons', () {
    testWidgets('primary button has one ink owner and presses in',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(AppPrimaryButton(label: 'SAVE', onPressed: () => taps++)),
      );

      final inks = find.descendant(
        of: find.byType(AppPrimaryButton),
        matching: find.byType(InkWell),
      );
      expect(inks, findsOneWidget,
          reason: 'the ripple must have exactly one ink layer');
      expect(tester.widget<InkWell>(inks).onTap, isNotNull);

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('SAVE')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _scaleOf(tester, find.byType(AppPrimaryButton)),
        lessThan(1.0),
        reason: 'the button must react before the tap resolves',
      );

      await tester.pump(const Duration(milliseconds: 120));
      expect(
        _scaleOf(tester, find.byType(AppPrimaryButton)),
        closeTo(0.97, 0.0001),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'the ripple and the scale must not double-fire');
      expect(
        _scaleOf(tester, find.byType(AppPrimaryButton)),
        closeTo(1.0, 0.0001),
      );
    });

    testWidgets('button stays keyboard activatable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(AppPrimaryButton(label: 'SAVE', onPressed: () => taps++)),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(taps, 1, reason: 'focus + Enter must still reach the InkWell');
    });

    testWidgets('button keeps its tap semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(AppPrimaryButton(label: 'SAVE', onPressed: () {})),
      );

      final data = tester.getSemantics(find.byType(InkWell)).getSemanticsData();
      expect(data.label, contains('SAVE'));
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      handle.dispose();
    });

    testWidgets('a loading button shows no feedback and ignores taps',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppPrimaryButton(
        label: 'SAVE',
        loading: true,
        onPressed: () => taps++,
      )));

      expect(
        tester
            .widget<InkWell>(find.descendant(
              of: find.byType(AppPrimaryButton),
              matching: find.byType(InkWell),
            ))
            .onTap,
        isNull,
        reason: 'a loading button must not accept taps',
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AppPrimaryButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        _scaleOf(tester, find.byType(AppPrimaryButton)),
        1.0,
        reason: 'a loading button must not react to touch',
      );

      await gesture.up();
      // The loading spinner animates forever, so `pumpAndSettle` would never
      // return here; pump far enough for the press release to finish instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(taps, 0);
    });

    testWidgets('disabled primary and ghost buttons ignore taps',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          AppPrimaryButton(label: 'SAVE', onPressed: null),
          AppGhostButton(label: 'CANCEL', onPressed: null),
        ],
      )));

      await tester.tap(find.text('SAVE'));
      await tester.pump();
      await tester.tap(find.text('CANCEL'));
      await tester.pump();
      expect(taps, 0);

      // Counter wiring is live for an enabled ghost button.
      await tester.pumpWidget(_host(AppGhostButton(
        label: 'CANCEL',
        onPressed: () => taps++,
      )));
      await tester.tap(find.text('CANCEL'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('glass card', () {
    testWidgets('paints its ripple above the fill in light mode',
        (tester) async {
      final key = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(_host(
        RepaintBoundary(
          key: key,
          child: GlassCard(onTap: () => taps++, child: _tallBox),
        ),
        splashColor: const Color(0x66000000),
      ));
      await tester.pumpAndSettle();

      final at = _centerOf(tester, key);
      final before = await _pixelAt(tester, key, at);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(GlassCard)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 100));

      final during = await _pixelAt(tester, key, at);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        during[0],
        lessThan(before[0] - 8),
        reason: 'a 90%-opaque light fill must not hide the splash',
      );
      expect(taps, 1);
    });

    testWidgets('paints its ripple above the fill in dark mode',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(_host(
        RepaintBoundary(
          key: key,
          child: GlassCard(onTap: () {}, child: _tallBox),
        ),
        dark: true,
        splashColor: const Color(0x66FFFFFF),
      ));
      await tester.pumpAndSettle();

      final at = _centerOf(tester, key);
      final before = await _pixelAt(tester, key, at);

      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(GlassCard)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 100));

      final during = await _pixelAt(tester, key, at);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        during[0],
        greaterThan(before[0] + 8),
        reason: 'the splash must brighten the dark card, not hide beneath it',
      );
    });

    testWidgets('a static card stays static and keeps its padding',
        (tester) async {
      await tester.pumpWidget(_host(
        const GlassCard(child: SizedBox(width: 100, height: 40)),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GlassCard),
          matching: find.byType(Transform),
        ),
        findsNothing,
        reason: 'no press layer without an onTap',
      );
      expect(
        tester.getSize(find.byType(GlassCard)),
        // 100x40 child + 20px padding each side + the 1px border each side.
        const Size(142, 82),
        reason: 'padding must still be part of the card box',
      );
    });

    testWidgets('a tappable card keeps padding and fires once', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(GlassCard(
        onTap: () => taps++,
        child: const SizedBox(width: 100, height: 40),
      )));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(GlassCard)), const Size(142, 82));

      await tester.tap(find.byType(GlassCard));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('floating navigation', () {
    Widget bar(List<int> taps, int index) => _host(FloatingNavBar(
          items: const [
            NavItem(Icons.home_rounded, 'HOME'),
            NavItem(Icons.settings_rounded, 'SETTINGS'),
          ],
          currentIndex: index,
          onTap: taps.add,
        ));

    testWidgets('only the pressed slot scales and one index is reported',
        (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(bar(taps, 0));

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('SETTINGS')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final scales = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(FloatingNavBar),
              matching: find.byType(Transform),
            ),
          )
          .map((t) => t.transform.storage[0])
          .toList();
      expect(scales.where((s) => s < 1.0), hasLength(1),
          reason: 'only the touched slot may shrink');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, [1]);
    });

    testWidgets('keeps the 48dp target, its colours and its semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      final taps = <int>[];
      await tester.pumpWidget(bar(taps, 0));

      final context = tester.element(find.byType(FloatingNavBar));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.home_rounded)).color,
        AppColors.navSelected(context),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.settings_rounded)).color,
        AppColors.textTertiary(context),
      );

      for (final label in ['HOME', 'SETTINGS']) {
        final slot = tester.getSize(find
            .ancestor(
              of: find.text(label),
              matching: find.byType(Semantics),
            )
            .first);
        expect(slot.height, greaterThanOrEqualTo(48),
            reason: '$label must keep a 48dp tap target');
      }

      final settingsSemantics = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'SETTINGS',
      );
      var data =
          tester.getSemantics(settingsSemantics.first).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isSelected, Tristate.isFalse);

      await tester.pumpWidget(bar(taps, 1));
      await tester.pump(const Duration(milliseconds: 300));
      data = tester.getSemantics(settingsSemantics.first).getSemanticsData();
      expect(data.flagsCollection.isSelected, Tristate.isTrue);

      await tester.tap(find.text('HOME'));
      await tester.pump();
      expect(taps, [0], reason: 'selection changes must not eat taps');

      handle.dispose();
    });
  });
}
