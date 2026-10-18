// Cupertino, not Material: this is where CupertinoPageTransitionsBuilder lives.
import 'package:flutter/cupertino.dart';

import '../utils/app_spacing.dart';

/// Smooth shared page transition: subtle slide-up + fade, matching the
/// reference's "smooth transitions" language. Reduced-motion aware.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;
  final Duration duration;

  AppPageRoute({required this.builder, this.duration = AppMotion.base})
      : super(
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (AppMotion.reduced(context)) return child;

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
}

/// The theme-level fallback for routes the app does not push through
/// [AppPageRoute] — dialogs, bottom sheets, and anything a plugin navigates to.
/// Delegates to the platform's Cupertino slide, but returns the page already in
/// place when reduced motion is on, since [CupertinoPageTransitionsBuilder]
/// ignores that setting.
class AppPageTransitions extends PageTransitionsBuilder {
  const AppPageTransitions();

  static final _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _cupertino.transitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _cupertino.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    return _cupertino.buildTransitions<T>(
        route, context, animation, secondaryAnimation, child);
  }
}
