import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';
import 'quick_action_tile.dart';

/// The dashboard's action dock: one solid card holding the actions the app
/// exists for.
///
/// Anatomy, from the reference screenshots (Quick Payment / Others card):
///
/// * One white surface, not a tinted strip and not a gradient. Same tone,
///   hairline rule and shadow as every other card on the page.
/// * Quiet actions are small outlined rounded squares with a neutral glyph.
///   Colour is not used here; the glyph and label carry the meaning.
/// * The leading action ([QuickAction.primary], Home's **Add**) is a solid ink
///   circle, the same object as the active navigation pill. It replaces the
///   old floating button, so adding a transaction is one tap from the top of
///   Home and nothing floats over the figures below.
///
/// The dock lives in the page flow, so it scrolls with the content and can never
/// cover financial information.
class HomeActionDock extends StatelessWidget {
  final List<QuickAction> actions;

  const HomeActionDock({super.key, required this.actions});

  /// The dock's own tone. A plain card, so ink measured against it is ink
  /// measured against what is actually behind the plates.
  static Color dockSurface(BuildContext context) =>
      AppColors.glassSurface(context);

  /// Plate behind a quiet glyph: one tertiary step off the card (the palette's
  /// own ink at 5% / 8%). The hairline around it carries the shape; the tone
  /// step only keeps it from reading as a hole in the card.
  static Color quietPlate(BuildContext context, bool isDark) =>
      AppColors.surfaceTertiary(context);

  /// Solid ink disc of the primary action: the active-navigation pill's fill.
  static Color primaryPlate(bool isDark) => AppColors.fabFillFor(isDark);

  /// Glyph on the primary disc.
  static Color primaryInk(bool isDark) => AppColors.fabInkFor(isDark);

  /// Plate edge length. 44dp, so every plate is also a legal touch target.
  static const double plateSize = 44;

  /// Narrowest a slot may get before its two-line label would clip. The dock
  /// folds to fewer columns instead of shrinking a label or a target.
  static const double minSlotWidth = 54;

  /// Columns for [count] actions in [width] dp at [textScale].
  ///
  /// One row when every slot keeps [minSlotWidth] at the effective text size;
  /// otherwise two rows. Visible for tests.
  static int columnsFor({
    required double width,
    required double textScale,
    required int count,
  }) {
    if (count <= 0) return 1;
    final fits = width / count >= minSlotWidth * (textScale > 1 ? textScale : 1);
    return fits && textScale <= 1.3 ? count : (count / 2).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;

    // The dock is a panel like every other card on the page: same tone, same
    // hairline, same shadow.
    final panel = AppColors.panelDecoration(
      context,
      borderRadius: BorderRadius.circular(AppRadius.card),
    );
    const inset = 5.0;

    return Container(
      padding: const EdgeInsets.all(inset),
      decoration: panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = columnsFor(
            width: constraints.maxWidth,
            textScale: scale,
            count: actions.length,
          );
          final rows = <List<QuickAction>>[
            for (var i = 0; i < actions.length; i += columns)
              actions.sublist(i, (i + columns).clamp(0, actions.length)),
          ];
          return Column(
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
                      // The rule between slots is the first (bottom-most) child
                      // of each slot's own stack, so it is painted behind the
                      // plate and can never slice through one.
                      for (var c = 0; c < columns; c++)
                        Expanded(
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
                                  ? _DockSlot(action: rows[r][c])
                                  : const SizedBox.shrink(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Paints the one-pixel rule on the leading edge of a slot, if asked.
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

  const _DockSlot({required this.action});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final primary = action.primary;

    final labelStyle = AppText.label(context).copyWith(
      fontSize: 11,
      height: 1.15,
      fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
      color: primary
          ? AppColors.textPrimary(context)
          : AppColors.textSecondary(context),
    );
    // Both label lines are reserved for every slot. "Add expense" wraps and
    // "Activity" does not, so without a fixed box the two-line slot grew taller
    // than its neighbours and the icons sat at different heights. The box is
    // measured at the *effective* text scale so it still grows under
    // accessibility font settings instead of clipping.
    final labelHeight = (2 *
            labelStyle.fontSize! *
            labelStyle.height! *
            MediaQuery.textScalerOf(context).scale(1))
        .ceilToDouble();

    final plate = primary
        ? Container(
            width: HomeActionDock.plateSize,
            height: HomeActionDock.plateSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HomeActionDock.primaryPlate(dark),
            ),
            child: Icon(
              action.icon,
              size: 24,
              color: HomeActionDock.primaryInk(dark),
            ),
          )
        : Container(
            // 44 wide, 40 tall: the reference's outlined tile. The slot is
            // 44dp tall either way, so the touch target is unchanged.
            width: HomeActionDock.plateSize,
            height: HomeActionDock.plateSize - 4,
            decoration: BoxDecoration(
              color: HomeActionDock.quietPlate(context, dark),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Icon(
              action.icon,
              size: AppSpacing.wellGlyph,
              color: AppColors.textPrimary(context),
            ),
          );

    return Semantics(
      key: ValueKey('dock:${action.label}'),
      button: true,
      label: action.semanticLabel ?? action.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        sound: SoundEventType.buttonTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.wellTouchTarget,
          ),
          child: Padding(
            // 4dp each side, not 8: with five actions a 320dp phone gives a slot
            // 55dp, and a 44dp plate needs the room.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              // Stretch makes the label fill the slot; the plate is centred
              // inside that width. Without this the Column shrink-wrapped to
              // the label and the whole stack sat at the slot's left edge.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: HomeActionDock.plateSize,
                  child: Center(child: plate),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: labelHeight,
                  // Centre the text inside the reserved box so a one-line label
                  // ("Activity") and a wrapped one ("Add expense") share a
                  // baseline region.
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
