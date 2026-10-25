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

  /// Standard horizontal page padding for the Galaxy-S24 class width.
  static const double page = 20;

  /// Quick-action tiles: shared metrics so every tile is identical.
  static const double tileGap = sm;
  static const double tileMinHeight = 88;
  static const double tileIconBox = 38;
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

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Returns [duration] unless the platform disables animations.
  static Duration respect(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true
          ? Duration.zero
          : duration;
}
