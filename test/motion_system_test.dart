import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/main.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/app_page_route.dart';
import 'package:spendsense/widgets/app_states.dart';
import 'package:spendsense/widgets/fade_indexed_stack.dart';

/// Stage 2 — the central motion foundation: one clock, and reduced motion
/// honoured by every primitive that owns a ticker.
void main() {
  Widget wrap(Widget child, {bool reduceMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 780),
        disableAnimations: reduceMotion,
      ),
      child: MaterialApp(home: child),
    );
  }

  group('AppMotion tokens', () {
    testWidgets('respect() collapses a duration when motion is reduced',
        (tester) async {
      late Duration normal;
      late Duration reduced;

      await tester.pumpWidget(wrap(Builder(builder: (context) {
        normal = AppMotion.respect(context, AppMotion.base);
        return const SizedBox();
      })));
      await tester.pumpWidget(wrap(
        Builder(builder: (context) {
          reduced = AppMotion.respect(context, AppMotion.base);
          return const SizedBox();
        }),
        reduceMotion: true,
      ));

      expect(normal, AppMotion.base);
      expect(reduced, Duration.zero);
      expect(AppMotion.tab, const Duration(milliseconds: 260));
    });

    testWidgets('reduced() reports the platform request', (tester) async {
      late bool value;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        value = AppMotion.reduced(context);
        return const SizedBox();
      }), reduceMotion: true));
      expect(value, isTrue);
    });
  });

  group('FadeIndexedStack', () {
    testWidgets('keeps every tab alive and settles on the incoming page',
        (tester) async {
      await tester.pumpWidget(wrap(const _StackHost()));

      expect(find.text('page-0'), findsOneWidget);
      // Non-active tabs are offstage but mounted: their state must survive.
      // find.text skips offstage candidates, so ask for them explicitly.
      expect(find.text('page-1', skipOffstage: false), findsOneWidget);

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.text('page-1'), findsOneWidget);
      await tester.pump(AppMotion.tab);
      // The wrapper stays in the tree (it is how the tab was revealed); what
      // matters is that its animation has fully landed.
      final fade = tester.widget<FadeTransition>(_fadesInStack().first);
      expect(fade.opacity.value, 1.0);
    });

    testWidgets('swaps without any motion under reduced motion',
        (tester) async {
      await tester.pumpWidget(wrap(const _StackHost(), reduceMotion: true));

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.text('page-1'), findsOneWidget);
      // The wrapper chain is kept on purpose: giving inactive tabs a different
      // shape rebuilt their subtrees and dropped their State. Reduced motion
      // pins that wrapper to its end value on the first frame instead, so
      // nothing moves while the tree stays stable.
      final fade = tester.widget<FadeTransition>(_fadesInStack().first);
      expect(fade.opacity.value, 1.0);
    });
  });

  group('SkeletonBox shimmer', () {
    testWidgets('stops its ticker under reduced motion', (tester) async {
      await tester.pumpWidget(wrap(
        const Center(child: SkeletonBox(height: 20, width: 120)),
        reduceMotion: true,
      ));

      // This is the assertion the suite cares about: with motion reduced the
      // shimmer no longer repeats forever, so the tree can settle.
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsOneWidget);
    });

    testWidgets('still shimmers when motion is allowed', (tester) async {
      await tester.pumpWidget(wrap(
        const Center(child: SkeletonBox(height: 20, width: 120)),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });

  group('AppStateSwap', () {
    testWidgets('cross-fades to the new state and ends on it', (tester) async {
      await tester.pumpWidget(wrap(const _SwapHost()));

      expect(find.text('loading'), findsOneWidget);
      _swapState(tester).showContent();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(AppMotion.base);

      expect(find.textContaining('content'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
    });

    testWidgets('an unrelated rebuild of the same state does not restart it',
        (tester) async {
      await tester.pumpWidget(wrap(const _SwapHost()));

      _swapState(tester).rebuildSameState();
      await tester.pump();
      // Still the loading state, still one child, no second fade queued.
      expect(find.text('loading'), findsOneWidget);
      expect(find.byType(AppStateSwap), findsOneWidget);
    });

    testWidgets('reduced motion swaps without an animation', (tester) async {
      await tester.pumpWidget(wrap(const _SwapHost(), reduceMotion: true));

      _swapState(tester).showContent();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('content'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
    });
  });

  group('AppPageTransitions', () {
    testWidgets('a dialog appears immediately when motion is reduced',
        (tester) async {
      await tester.pumpWidget(wrap(const _DialogOpener(), reduceMotion: true));

      await tester.tap(find.text('open dialog'));
      await tester.pump();

      expect(find.text('dialog body'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('dialog body'), findsOneWidget);
    });

    testWidgets('the app theme installs the reduced-motion-aware builder',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TransactionProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const SpendSenseApp(),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      final theme = Theme.of(tester.element(find.byType(Scaffold).first));
      for (final platform in TargetPlatform.values) {
        if (platform == TargetPlatform.fuchsia) continue;
        expect(theme.pageTransitionsTheme.builders[platform],
            isA<AppPageTransitions>(),
            reason:
                '$platform still uses a builder that ignores reduced motion');
      }
    });

    testWidgets('every palette and mode keeps the reduced-aware builder',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TransactionProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const SpendSenseApp(),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      final themeProvider = Provider.of<ThemeProvider>(
          tester.element(find.byType(Scaffold).first),
          listen: false);

      for (final palette in AppPalette.all) {
        for (final mode in ThemeMode.values) {
          await themeProvider.setPalette(palette);
          await themeProvider.setThemeMode(mode);
          await tester.pump(AppMotion.slow);
          await tester.pump(AppMotion.slow);

          final theme = Theme.of(tester.element(find.byType(Scaffold).first));
          // Guards against a vacuous loop: the theme really did change.
          final expectedBrightness = switch (mode) {
            ThemeMode.dark => Brightness.dark,
            _ => tester.platformDispatcher.platformBrightness,
          };
          expect(theme.brightness, expectedBrightness,
              reason: '${palette.id} / $mode never reached the widget tree');
          expect(theme.pageTransitionsTheme.builders[TargetPlatform.android],
              isA<AppPageTransitions>(),
              reason: '${palette.id} / $mode dropped the motion builder');
        }
      }
    });
  });
}

Finder _fadesInStack() => find.descendant(
    of: find.byType(FadeIndexedStack), matching: find.byType(FadeTransition));

_SwapHostState _swapState(WidgetTester tester) =>
    tester.state<_SwapHostState>(find.byType(_SwapHost));

class _StackHost extends StatefulWidget {
  const _StackHost();

  @override
  State<_StackHost> createState() => _StackHostState();
}

class _StackHostState extends State<_StackHost> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: FadeIndexedStack(
              index: _index,
              children: const [
                Center(child: Text('page-0')),
                Center(child: Text('page-1')),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _index = 1),
            child: const Text('go'),
          ),
        ],
      ),
    );
  }
}

class _SwapHost extends StatefulWidget {
  const _SwapHost();

  @override
  State<_SwapHost> createState() => _SwapHostState();
}

class _SwapHostState extends State<_SwapHost> {
  bool _loading = true;
  int _tick = 0;

  void showContent() => setState(() => _loading = false);
  void rebuildSameState() => setState(() => _tick++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppStateSwap(
        state: _loading ? 'loading' : 'content',
        child: _loading
            ? const Center(child: Text('loading'))
            : Center(child: Text('content $_tick')),
      ),
    );
  }
}

class _DialogOpener extends StatelessWidget {
  const _DialogOpener();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(
                content: Text('dialog body'), backgroundColor: Colors.white),
          ),
          child: const Text('open dialog'),
        ),
      ),
    );
  }
}
