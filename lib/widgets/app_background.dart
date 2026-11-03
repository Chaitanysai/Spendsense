import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Quiet, theme-aware canvas that keeps financial content in focus.
class AppBackground extends StatelessWidget {
  final Widget child;
  final bool showGlow;

  const AppBackground({super.key, required this.child, this.showGlow = true});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: AppColors.scaffold(context)),
        child: child,
      );
}
