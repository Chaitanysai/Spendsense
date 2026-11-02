import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Floating glass navigation bar with one spring-driven selected pill.
///
/// The pill is a single object that travels between destinations:
///
/// `tap → spring → stretch → slide → contract → settle`
///
/// * The spring starts on the same frame as the tap, so there is no perceptible
///   delay before the pill moves.
/// * Its width grows with its own velocity, which is what produces the stretch
///   while it travels and the contraction as it arrives. The amount of stretch
///   also scales with the distance being covered, so a neighbouring tab nudges
///   and a cross-bar jump stretches further.
/// * A second tap mid-flight retargets the same spring from the pill's current
///   position *and* velocity. There is no animation queue, so rapid taps cannot
///   overlap, stutter or leave the pill between slots.
///
/// Selection is never carried by colour alone: the pill, the glyph weight, the
/// label weight and the `selected` semantics flag all change together.
///
/// ## Cost model
///
/// [BackdropFilter] only pays for the pixels it covers, and it is applied to the
/// pill body rather than the whole subtree. The blur is dropped entirely under
/// high contrast, where a translucent surface over scrolling content is exactly
/// the legibility problem that setting exists to remove.
class FloatingNavBar extends StatefulWidget {
  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FloatingNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar>
    with SingleTickerProviderStateMixin {
  /// Selected slot centre, measured in slot units (0.5, 1.5, …).
  ///
  /// Slot units rather than pixels so a rotation or a width change cannot strand
  /// the pill between two destinations.
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.currentIndex + 0.5,
  );

  bool _reduceMotion = false;

  /// Distance of the current travel, in slots. Used to size the stretch so a
  /// one-slot nudge is quieter than a jump across the bar.
  double _travel = 1;

  /// Pill metrics, in logical pixels.
  static const double _pillHeight = 32;
  static const double _iconBoxHeight = 34;
  static const double _maxStretch = 16;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (reduced == _reduceMotion) return;
    _reduceMotion = reduced;
    if (reduced) {
      _position.value = widget.currentIndex + 0.5;
    }
  }

  @override
  void didUpdateWidget(covariant FloatingNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) return;
    _travelTo(widget.currentIndex);
  }

  void _travelTo(int index) {
    final target = index + 0.5;
    if (_reduceMotion) {
      _position.value = target;
      return;
    }
    _travel = (target - _position.value).abs().clamp(1.0, 4.0);
    _position.animateWith(
      SpringSimulation(
        AppSpring.nav,
        _position.value,
        target,
        // Inherit the in-flight velocity: this is what makes a second tap feel
        // like a change of mind rather than a restart.
        _position.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final borderRadius = BorderRadius.circular(AppRadius.pill);
    final highContrast = MediaQuery.highContrastOf(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: highContrast ? 0 : 12,
              sigmaY: highContrast ? 0 : 12,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                gradient: highContrast
                    ? null
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: AppColors.isGlassCanvas(context)
                            ? [
                                AppColors.darkSurfaceAlt
                                    .withValues(alpha: 0.78),
                                AppColors.darkBackground
                                    .withValues(alpha: 0.62),
                              ]
                            : dark
                                ? [
                                    AppColors.darkSurfaceAlt
                                        .withValues(alpha: 0.88),
                                    AppColors.darkSurface
                                        .withValues(alpha: 0.78),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.80),
                                    Colors.white.withValues(alpha: 0.62),
                                  ],
                      ),
                color: highContrast
                    ? (dark ? AppColors.darkSurfaceAlt : Colors.white)
                    : null,
                borderRadius: borderRadius,
                border: Border.all(
                  color: highContrast
                      ? AppColors.textPrimary(context)
                      : dark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.06),
                  width: highContrast ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow(context),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slot = constraints.maxWidth / widget.items.length;
                  return Stack(
                    children: [
                      // Painted first so the glyphs and labels sit on top of it.
                      AnimatedBuilder(
                        animation: _position,
                        builder: (context, _) {
                          final center = _position.value * slot;
                          final base = (slot - 12).clamp(40.0, 54.0);
                          final velocity = _position.isAnimating
                              ? _position.velocity.abs()
                              : 0.0;
                          final stretch = _reduceMotion
                              ? 0
                              : (velocity / 10).clamp(0.0, 1.0) *
                                  (_maxStretch * (0.4 + 0.15 * _travel));
                          final width = base + stretch;
                          final left = (center - width / 2)
                              .clamp(0.0, constraints.maxWidth - width);
                          return Positioned(
                            left: left,
                            top: (_iconBoxHeight - _pillHeight) / 2,
                            width: width,
                            height: _pillHeight,
                            // The pill is decoration: the slot below carries the
                            // label, the selected flag and the action.
                            child: ExcludeSemantics(
                              child: DecoratedBox(
                                key: const Key('nav-selected-pill'),
                                decoration: BoxDecoration(
                                  gradient: AppColors.navPillGradient(context),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.brand.withValues(
                                          alpha: dark ? 0.34 : 0.22),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < widget.items.length; i++)
                            Expanded(
                              child: _NavSlot(
                                item: widget.items[i],
                                selected: i == widget.currentIndex,
                                onTap: () => widget.onTap(i),
                                iconBoxHeight: _iconBoxHeight,
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final double iconBoxHeight;

  const _NavSlot({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.iconBoxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor = AppColors.navSelected(context);
    final idleColor = AppColors.textTertiary(context);
    final duration = AppMotion.respect(context, AppMotion.fast);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // The tap target stays on the untransformed slot, so press feedback can
        // never shrink the 48dp minimum or delay the tab switch.
        child: PressFeedback(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: iconBoxHeight,
                    child: Center(
                      child: Icon(
                        item.icon,
                        size: 21,
                        color:
                            selected ? AppColors.onNavPill(context) : idleColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: AppMotion.easeOut,
                    style: AppText.onGradient(
                      size: 10,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                    ).copyWith(
                      color: selected ? selectedColor : idleColor,
                      letterSpacing: 0.3,
                      height: 1.1,
                    ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
