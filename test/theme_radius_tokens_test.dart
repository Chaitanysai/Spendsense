// Locks the semantic radius scale and the concentric-corner helper.
//
// These tokens exist so a corner can be named by *what it wraps* instead of by
// how round it is. That only pays off if the names stay ordered and keep their
// values, because the plates and cards that adopt them are spread across the
// screens and none of them can see the others.
//
// The scale is deliberately additive: `card` and `plate` predate it and are
// referenced from well over a hundred files, so this test freezes their current
// numbers as hard as the new names. Retuning either is a design decision that
// has to come through here first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/glass_card.dart';
import 'package:spendsense/widgets/icon_well.dart';

void main() {
  group('raw radius steps', () {
    test('keep the values the rest of the app is drawn against', () {
      expect(AppRadius.sm, 8);
      expect(AppRadius.md, 12);
      expect(AppRadius.lg, 16);
      expect(AppRadius.xl, 22);
      expect(AppRadius.pill, 999);
    });

    test('step upwards without gaps or repeats', () {
      final steps = <double>[
        AppRadius.sm,
        AppRadius.md,
        AppRadius.lg,
        AppRadius.xl,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]),
            reason: 'step $i is not larger than the one below it');
      }
    });
  });

  group('semantic radii', () {
    test('name the plane they wrap, not a raw step', () {
      // A glyph plate is the small square well; a tile wraps icon + label; a
      // panel is the same plane as a card; a container is the outermost region.
      expect(AppRadius.icon, AppRadius.plate);
      expect(AppRadius.tile, AppRadius.md);
      expect(AppRadius.panel, AppRadius.card);
      expect(AppRadius.container, AppRadius.xl);
    });

    test('freeze card and plate — 100+ call sites depend on these numbers', () {
      expect(AppRadius.card, 16,
          reason: 'AppSpacing.cardPadding pairs with it');
      expect(AppRadius.plate, 10);
    });

    test('stay ordered from the innermost plate to the outermost container',
        () {
      final scale = <double>[
        AppRadius.icon,
        AppRadius.tile,
        AppRadius.card,
        AppRadius.panel,
        AppRadius.container,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThanOrEqualTo(scale[i - 1]),
            reason: 'a plane cannot be rounder than the one inside it');
      }
    });
  });

  group('nested', () {
    test('subtracts the inset from the parent corner', () {
      expect(AppRadius.nested(26, 10), 16);
      expect(AppRadius.nested(22, 16), 6);
    });

    test('defaults the inset to the card padding', () {
      expect(AppRadius.nested(26), AppRadius.nested(26, AppSpacing.lg));
      expect(AppRadius.nested(22), 6);
    });

    test('clamps at zero when the inset swallows the corner', () {
      // A plate wider than its parent's corner would otherwise go negative,
      // which BorderRadius.circular rejects outright.
      expect(AppRadius.nested(12, 20), 0);
      expect(AppRadius.nested(16, 16), 0);
    });

    test('returns a BorderRadius matching the scalar form', () {
      expect(AppRadius.nestedAll(26, 10).topLeft.x, AppRadius.nested(26, 10));
      expect(
        AppRadius.nestedAll(26, 10),
        const BorderRadius.all(Radius.circular(16)),
      );
    });
  });

  group('IconWell adopts the icon plate', () {
    testWidgets('draws the semantic plate radius by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body:
                IconWell(icon: Icons.receipt_long_rounded, color: Colors.blue),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.icon));
      expect(container.constraints!.maxWidth, AppSpacing.wellSize);
    });

    testWidgets('honours a scaled plate and keeps the glyph proportional',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IconWell(
              icon: Icons.smart_toy_rounded,
              color: Color(0xFF3B82F6),
              size: 48,
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.constraints!.maxWidth, 48);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius,
          const BorderRadius.all(Radius.circular(AppRadius.card)));

      final icon = tester.widget<Icon>(find.byType(Icon));
      // 48 * (20 / 40) — the glyph keeps the standard well's proportion.
      expect(icon.size, 24);
    });

    testWidgets('circular wins over any corner', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IconWell(
              icon: Icons.add_rounded,
              color: Color(0xFF3B82F6),
              circular: true,
            ),
          ),
        ),
      );

      final decoration = tester
          .widget<Container>(find.byType(Container))
          .decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.borderRadius, isNull);
    });
  });

  group('stations that adopt the tokens agree with their container', () {
    testWidgets('the home drag ghost matches the GlassCard it lifts',
        (tester) async {
      // A lifted row is the same card, so a shadow drawn at a different radius
      // reads as the card changing shape mid-drag.
      const card = GlassCard(child: SizedBox.shrink());
      expect(card.radius, AppRadius.card);
    });

    testWidgets('an inner plate can sit concentrically in a card',
        (tester) async {
      final inner = AppRadius.nested(AppRadius.card, AppSpacing.md);
      expect(inner, lessThan(AppRadius.card));
      expect(inner, 4);
    });
  });
}
