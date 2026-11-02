import 'package:flutter/material.dart';

/// Spacing, radius, elevation and motion tokens (4-pt base grid).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// The single horizontal page inset. Every screen — the dashboard included —
  /// starts and ends here. Home used to run a 16dp gutter of its own, which put
  /// the dock 4dp inside the section headers below it and read as a
  /// misalignment rather than as a tighter rhythm.
  static const double page = 20;

  /// Kept as an alias so existing call sites resolve to the one inset. Do not
  /// introduce a second value; a screen that wants more space nests a [lg].
  static const double homePage = page;
  static const double homeSectionGap = 20;
  static const double homeHeaderGap = 10;

  /// Icon wells: one well, one glyph, one touch target, everywhere.
  ///
  /// The well is the tinted plate a glyph sits on; the glyph is the icon inside
  /// it. [wellTouchTarget] is the *interactive* size around a well — a 40dp
  /// plate is smaller than the 48dp minimum, so any tappable row must reserve
  /// at least this much height. Plates can sit closer than 8dp because the
  /// separation rule applies to the targets, not the artwork.
  static const double wellSize = 40;
  static const double wellGlyph = 20;
  static const double wellTouchTarget = 48;

  /// Quick-action tiles: shared metrics so every tile is identical.
  static const double tileGap = sm;
  static const double tileMinHeight = 88;
  static const double tileIconBox = wellSize;
  static const double tileMinWidth = 72;

  /// Bottom gutter that clears the floating navigation bar.
  static const double navClearance = 108;

  /// Bottom gutter that clears both the floating navigation bar *and* the
  /// end-floated Add button stacked above it. Every tab that scrolls to the
  /// bottom must use this so the last row is never hidden behind the FAB.
  static const double fabClearance = navClearance + 56;

  /// Adaptive version of [fabClearance] for the five shell tabs.
  ///
  /// The shell's Scaffold extends the body under the floating navigation bar
  /// and reports the bar's real height (device inset and large-text growth
  /// included) as bottom padding, so the gutter below follows the actual bar
  /// instead of a fixed guess. [fabClearance] is kept as the lower bound for
  /// hosts that have no bar (tests, embedded previews).
  static double tabBottomInset(BuildContext context) {
    final bar = MediaQuery.paddingOf(context).bottom;
    // Add button (58) + the gap above the bar (16) + breathing room (8).
    final dynamicInset = bar + 58 + lg + sm;
    return dynamicInset > fabClearance ? dynamicInset : fabClearance;
  }
}

/// Corner radii.
class AppRadius {
  AppRadius._();

  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 30;
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// Motion tokens. Durations collapse to zero when the OS requests reduced
/// motion (checked at the widget via [AppMotion.of]).
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);

  /// Press feedback halves. Touch-down must read as immediate, so it is shorter
  /// than a normal micro-interaction; the release settles a little slower so
  /// the surface never snaps back.
  static const Duration pressIn = Duration(milliseconds: 90);
  static const Duration pressOut = Duration(milliseconds: 160);

  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration counter = Duration(milliseconds: 650);
  static const Duration chart = Duration(milliseconds: 600);

  /// One full pass of the skeleton sheen. Slower than a transition on purpose:
  /// a loading placeholder is ambient, not something the user is waiting to
  /// watch, so it must not read as a progress bar racing to finish.
  static const Duration shimmer = Duration(milliseconds: 1500);

  /// Value bubble / chart detail reveal.
  static const Duration tooltip = Duration(milliseconds: 180);

  /// Longer cross-fade used when the whole app re-themes under the user.
  static const Duration theme = Duration(milliseconds: 320);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Returns [duration] unless the platform disables animations.
  static Duration respect(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true
          ? Duration.zero
          : duration;
}

/// Spring descriptions for motion that has to feel physical rather than timed.
///
/// A spring is specified instead of a duration because the interesting part is
/// how it *arrives*: the navigation pill overshoots by a couple of pixels and
/// settles, and a second tap mid-flight inherits the current velocity instead of
/// restarting a tween. [nav] is tuned to settle in roughly 450 ms from rest while
/// staying responsive to a tap (no visible lag before the pill starts moving).
class AppSpring {
  AppSpring._();

  /// Selected-navigation-pill travel. Slightly under-damped: one small
  /// overshoot, no wobble.
  static const SpringDescription nav = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 30,
  );

  /// Theme-switch thumb. Stiffer and more damped so the small control feels
  /// crisp at its scale.
  static const SpringDescription thumb = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 34,
  );
}
