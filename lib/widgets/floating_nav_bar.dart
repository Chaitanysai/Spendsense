import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Floating navigation: a row of solid circles, one of which is open.
///
/// Translated from PanelUI's `Tabs variant="expanding"`
/// (`packages/panelui/src/components/tabs/index.tsx`) and the reference
/// screenshots: one solid floating bar holds the destinations; idle ones are
/// quiet circular plates with only a glyph, and the active one is a solid ink
/// pill that widens to let its label out. Nothing is translucent and nothing
/// blurs: content scrolls under an opaque bar.
///
/// Rules carried over from PanelUI, with the reason each one exists:
///
/// * **Each destination draws its own pill.** There is no indicator sliding
///   underneath, because an indicator under pills that already have a fill
///   would be invisible. The shape that moves is the open tab itself.
/// * **The label is never unmounted, only closed over.** A screen reader
///   walking a row of glyphs needs every label, and a label that mounts on
///   selection has no width to animate from.
/// * **Width moves on a curve, not a spring.** Every frame of a width change
///   is a layout pass and the row re-centres with it; a spring's overshoot
///   would slide the clipped label in, out and in again and wobble the row.
///   `Cubic(0.2, 0, 0, 1)` leaves quickly and arrives once.
/// * **Label opacity trails the width** (0.35 → 0.9 of the travel), so text is
///   never drawn into a box narrower than itself.
///
/// Selection is never carried by colour alone: fill, glyph ink, the visible
/// label and the `selected` semantics flag all change together. Every slot is
/// at least 48dp tall, and the press feedback scales only the touched slot.
class FloatingNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FloatingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  /// Diameter of a closed destination and height of the open one.
  static const double itemExtent = 48;

  /// Gap between destinations, and the bar's inner padding.
  static const double gap = 6;

  /// How far the label is pulled back toward the glyph. The glyph box is the
  /// full closed circle, so its 13dp of side bearing would otherwise sit
  /// between glyph and label; this leaves a 7dp gap, as in the reference.
  static const double labelPull = 6;

  /// Padding inside the open pill, after the label.
  static const double labelTrailing = 14;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    // At very large text the open label would push five destinations past a
    // narrow screen. The label then stays in the semantics tree but is not
    // drawn, and the active pill keeps its solid fill so selection still
    // reads without colour alone (the shape is filled, the rest are not).
    final showLabel = textScale < 1.6;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Center(
          heightFactor: 1,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.navBarFillFor(dark),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.border(context)),
                boxShadow: AppColors.surfaceShadowFor(dark, floating: true),
              ),
              child: Padding(
                padding: const EdgeInsets.all(gap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      _NavSlot(
                        item: items[i],
                        selected: i == currentIndex,
                        showLabel: showLabel,
                        onTap: () => onTap(i),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatefulWidget {
  final NavItem item;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  const _NavSlot({
    required this.item,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  @override
  State<_NavSlot> createState() => _NavSlotState();
}

class _NavSlotState extends State<_NavSlot>
    with SingleTickerProviderStateMixin {
  /// 0 = closed circle, 1 = open pill. One controller per slot, so a second
  /// tap mid-flight simply retargets from the current value: no queue, and a
  /// closing pill reverses from wherever it got to.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: _expand,
    value: widget.selected ? 1 : 0,
  );

  /// PanelUI `EXPAND_DURATION`.
  static const Duration _expand = Duration(milliseconds: 260);

  /// PanelUI `Easing.bezier(0.2, 0, 0, 1)`.
  static const Curve _curve = Cubic(0.2, 0, 0, 1);

  /// Measured width of the label at the current text style.
  double _labelWidth = 0;

  @override
  void didUpdateWidget(covariant _NavSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    final target = widget.selected ? 1.0 : 0.0;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _open.value = target;
    } else {
      _open.animateTo(target, curve: _curve);
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  TextStyle _labelStyle(Color color) => AppText.onGradient(
        size: 13,
        weight: FontWeight.w600,
      ).copyWith(color: color, letterSpacing: -0.1, height: 1.1);

  /// The label's intrinsic width, measured once per style and text scale.
  ///
  /// PanelUI measures a hidden ghost copy because the box the label sits in is
  /// the box being resized. A [TextPainter] does the same job without an extra
  /// layout pass, rounded up and given 2dp of slack so a fractional rounding
  /// difference between measurement and layout can never truncate the label.
  double _measure(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: widget.item.label, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble() + 2;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final activeFill = AppColors.navActiveFillFor(dark);
    final activeInk = AppColors.navActiveInkFor(dark);
    final idleFill = AppColors.navFillFor(dark);
    final idleInk = AppColors.navIdleInkFor(dark);

    final style = _labelStyle(activeInk);
    _labelWidth = widget.showLabel ? _measure(context, style) : 0;
    final openExtra = widget.showLabel
        ? _labelWidth - FloatingNavBar.labelPull + FloatingNavBar.labelTrailing
        : 0.0;
    final pull = Directionality.of(context) == TextDirection.rtl
        ? FloatingNavBar.labelPull
        : -FloatingNavBar.labelPull;

    return Semantics(
      // A stable handle for tests and integration drivers. Labels are copy and
      // a closed slot clips its label, so neither is a reliable finder.
      key: ValueKey('nav:${widget.item.label}'),
      button: true,
      selected: widget.selected,
      label: widget.item.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        // The tap target is the untransformed slot, so press feedback can never
        // shrink the 48dp minimum or delay the tab switch.
        child: PressFeedback(
          child: AnimatedBuilder(
            animation: _open,
            builder: (context, _) {
              final t = _open.value;
              final width = FloatingNavBar.itemExtent + openExtra * t;
              // Colour follows the same progress as the width, so the fill and
              // the shape arrive together and a reversal reverses both.
              final fill = Color.lerp(idleFill, activeFill, t)!;
              final ink = Color.lerp(idleInk, activeInk, t)!;
              final labelOpacity = ((t - 0.35) / 0.55).clamp(0.0, 1.0);
              return Container(
                key: widget.selected ? const Key('nav-selected-pill') : null,
                width: width,
                height: FloatingNavBar.itemExtent,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                clipBehavior: Clip.antiAlias,
                child: OverflowBox(
                  alignment: AlignmentDirectional.centerStart,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: FloatingNavBar.itemExtent - 2,
                        child: Icon(widget.item.icon, size: 22, color: ink),
                      ),
                      if (widget.showLabel)
                        Opacity(
                          opacity: labelOpacity,
                          // Paint-only offset: layout keeps the label where the
                          // width was measured for, so nothing reflows.
                          child: Transform.translate(
                            offset: Offset(pull, 0),
                            child: SizedBox(
                              width: _labelWidth,
                              child: Text(
                                widget.item.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: style,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
