import 'package:flutter/material.dart';

import '../utils/app_spacing.dart';

/// Smooth shared page transition: subtle slide-up + fade, matching the
/// reference's "smooth transitions" language. Reduced-motion aware.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;
  final Duration duration;

  AppPageRoute({required this.builder, this.duration = AppMotion.base})
      : super(
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
}
