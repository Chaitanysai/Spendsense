import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// Smooth shared page transition: subtle slide-up + fade, matching the
/// reference's "smooth transitions" language. Reduced-motion aware.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;
  final Duration duration;

  AppPageRoute({
    required this.builder,
    this.duration = AppMotion.base,
    super.settings,
  }) : super(
          transitionDuration: duration,
          reverseTransitionDuration: AppMotion.fast,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final reduced =
                MediaQuery.maybeDisableAnimationsOf(context) == true;
            if (reduced) return child;

            final curved = CurvedAnimation(
              parent: animation,
              curve: AppMotion.emphasized,
              reverseCurve: Curves.easeIn,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );

  static Route<T> push<T>(WidgetBuilder builder) =>
      AppPageRoute<T>(builder: builder);

  /// Route names whose push is still in flight. A second tap while the first
  /// route is opening would otherwise stack a duplicate screen (and build its
  /// subtree twice during the transition).
  static final Set<String> _inFlight = <String>{};

  /// Pushes at most one route named [name] at a time.
  ///
  /// The guard is released when the pushed route is popped, so the next tap
  /// works normally. Returns `null` when a push was already in flight.
  static Future<T?>? pushOnce<T>(
    BuildContext context, {
    required String name,
    required WidgetBuilder builder,
  }) {
    if (!_inFlight.add(name)) return null;
    return Navigator.of(context)
        .push<T>(AppPageRoute<T>(
          builder: builder,
          settings: RouteSettings(name: name),
        ))
        .whenComplete(() => _inFlight.remove(name));
  }

  /// Test seam: forget every in-flight route (a widget test starts a fresh
  /// navigator and must not inherit a stale guard).
  @visibleForTesting
  static void debugResetInFlight() => _inFlight.clear();
}
