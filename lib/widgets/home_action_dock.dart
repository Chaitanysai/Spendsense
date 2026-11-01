import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';
import 'quick_action_tile.dart';

/// The dashboard's floating command dock.
///
/// GO Club's home puts the actions the app exists for in one floating capsule
/// at the thumb, not in four separate outlined boxes. Suno does the same with
/// its composer: one solid surface, one accented primary, everything else quiet.
/// This is that dock. It is the only glass-adjacent surface on the page besides
/// the navigation pill, so it reads as chrome rather than as another card.
class HomeActionDock extends StatelessWidget {
  final List<QuickAction> actions;

  const HomeActionDock({super.key, required this.actions});

  /// The dock's own surface: in dark mode its gradient starts one step above
  /// [AppColors.surfaceColor], so measuring ink against the plain surface would
  /// pick the wrong glyph colour for the top row.
  static Color dockSurface(BuildContext context) {
    final surface = AppColors.surfaceColor(context);
    if (!AppColors.isDark(context)) return surface;
    return Color.alphaBlend(
      Colors.white.withValues(alpha: 0.05),
      surface,
    );
  }

  /// Brand wash applied over the quiet plate for the accented slot.
  ///
  /// Exposed so `home_dock_well_test.dart` asserts against the value the widget
  /// actually paints. The first version of that test carried its own copy, and
  /// when this alpha was tuned the test kept measuring the old constant and
  /// reported numbers that no longer matched the screen.
  static double primaryWashAlpha(bool isDark) => isDark ? 0.12 : 0.16;

  /// One surface step off the dock, behind a quiet glyph.
  static Color quietPlate(BuildContext context, bool isDark) => isDark
      ? Color.alphaBlend(
          Colors.white.withValues(alpha: 0.10),
          dockSurface(context),
        )
      : AppColors.surfaceMuted;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // Four slots only survive a genuinely large text setting as two rows.
    final columns = scale > 1.3 ? 2 : 4;

    final rows = <List<QuickAction>>[
      for (var i = 0; i < actions.length; i += columns)
        actions.sublist(i, (i + columns).clamp(0, actions.length)),
    ];

    final dark = AppColors.isDark(context);

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.05),
                    AppColors.surfaceColor(context),
                  ),
                  AppColors.surfaceColor(context),
                ]
              : [Colors.white, AppColors.surfaceColor(context)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.border(context).withValues(alpha: 0.7),
              ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dividers used to sit *between* the slots, where the paint
                  // order put them above the glyph plates: the lines appeared to
                  // cut straight through the circles. They are painted behind the
                  // plates now, and each slot is opaque only inside its plate, so
                  // the rule reads as a separatrix rather than a slash.
                  for (var c = 0; c < columns; c++)
                    Expanded(
                      child: SizedBox(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: SizedBox(
                                width: 1,
                                child: CustomPaint(
                                  painter: _EdgeRulePainter(
                                    show: c > 0,
                                    color: AppColors.border(context)
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ),
                            c < rows[r].length
                                ? _DockSlot(
                                    action: rows[r][c],
                                    primary: r == 0 && c == 0,
                                  )
                                : const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Paints the one-pixel rule on the leading edge of a slot, if asked.
///
/// A [VerticalDivider] between slots painted *over* the neighbouring glyph
/// plates because the Row's paint order follows child order; drawing the rule
/// as the first (bottom-most) child of the slot's own stack keeps it behind the
/// plate. See [HomeActionDock.build].
class _EdgeRulePainter extends CustomPainter {
  const _EdgeRulePainter({required this.show, required this.color});

  final bool show;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!show) return;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 1, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_EdgeRulePainter old) =>
      old.show != show || old.color != color;
}

class _DockSlot extends StatelessWidget {
  final QuickAction action;
  final bool primary;

  const _DockSlot({required this.action, required this.primary});


  /// Fill behind a glyph. Every slot uses this same construction so the four
  /// read as one control:
  ///
  /// * quiet slots — one published surface step off the dock.
  /// * the primary — the same step, accented, so it is *distinguished* without
  ///   being a different kind of object.
  ///
  /// The primary used to be filled with [AppColors.actionGradient], a saturated
  /// navy disc. Against three pale plates that read as one enabled control and
  /// three disabled ones (light mode measured 0.18x the plate's luminance), which
  /// is exactly what "only Add expense has an icon" was describing.
  ///
  /// It is now accented by pushing the plate *away* from the dock in the theme's
  /// own direction — lighter in dark, brand-tinted in light. Washing the brand
  /// over a dark plate does not work: the brand's dark end pulled the fill down,
  /// leaving the primary (measured `#2F3E49`) marginally darker than its
  /// neighbours (`#33414B`), so the accent was invisible.
  static Color _wellFill(
    BuildContext context,
    bool dark, {
    required bool primary,
  }) {
    final base = HomeActionDock.quietPlate(context, dark);
    if (!primary) return base;
    // Push the plate *away* from the dock surface, in the theme's own direction:
    // dark mode lightens, light mode lays a brand tint down. Washing the brand
    // over a dark plate is what broke this — the brand's dark end pulled the
    // fill below its neighbours, so the accented slot read as the dimmest one.
    return Color.alphaBlend(
      (dark ? Colors.white : AppColors.brand)
          .withValues(alpha: HomeActionDock.primaryWashAlpha(dark)),
      base,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    // One construction for all four slots (see [_wellFill]); the primary differs
    // by brand tint and ink weight, not by being a filled disc. Ink is measured
    // against the plate it actually sits on, because a wash of any hue collapses
    // the glyph's contrast against the plate behind it.
    final wellColor = _wellFill(context, dark, primary: primary);
    final iconColor =
        AppColors.inkOn(AppColors.brand, wellColor, HomeActionDock.dockSurface(context));

    final labelStyle = AppText.label(context).copyWith(
      fontSize: 11,
      height: 1.15,
      fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
      color: primary
          ? AppColors.textPrimary(context)
          : AppColors.textSecondary(context),
    );
    // Both label lines are reserved for every slot. "Add expense" wraps and
    // "Activity" does not, so without a fixed box the two-line slot grew taller
    // than its neighbours and the four icons sat at different heights. The box
    // is measured at the *effective* text scale so it still grows under
    // accessibility font settings instead of clipping.
    final labelHeight =
        (2 * labelStyle.fontSize! * labelStyle.height! *
                MediaQuery.textScalerOf(context).scale(1))
            .ceilToDouble();

    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        sound: SoundEventType.buttonTap,
        child: ConstrainedBox(
          // 40dp well + gap + two label lines is already past 48dp; the floor
          // keeps the target legal before the label box is added.
          constraints: const BoxConstraints(
            minHeight: AppSpacing.wellTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              // Stretch makes the label fill the slot; the icon is centred
              // inside that width. Without this the Column shrink-wrapped to
              // the label and the whole stack sat at the slot's left edge.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: AppSpacing.wellSize,
                    height: AppSpacing.wellSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // The same plate in every slot; the primary's brand wash
                      // comes from [_wellFill], not from a gradient disc.
                      color: wellColor,
                      border: Border.all(
                        color: primary
                            ? AppColors.brand.withValues(alpha: 0.55)
                            : AppColors.border(context).withValues(
                                alpha: dark ? 0.9 : 1.0,
                              ),
                      ),
                    ),
                    child: Icon(
                      action.icon,
                      size: AppSpacing.wellGlyph,
                      color: iconColor,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: labelHeight,
                  // Centre the text inside the reserved box. Every slot reserves
                  // two lines, so a one-line label ("Activity") would otherwise
                  // hang from the top of its box while a wrapped one ("Add
                  // expense") filled it — same box, different optical baseline.
                  child: Center(
                    child: Text(
                      action.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
