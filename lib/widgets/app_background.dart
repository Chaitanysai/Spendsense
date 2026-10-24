import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Screen background: the scaffold colour plus three soft ambient radial glows
/// (brand top-left, accent upper-right, warm lower-left). Static and cheap — no
/// blur, so it does not tax scroll performance.
///
/// The dark canvas is pure black (`#000000`) for every palette, Midnight
/// included: broad colour washes would light up the panel and defeat the point
/// of black, so dark mode paints no glow at all. Navy and blue belong on the
/// cards, hero cards, borders and the selected navigation chip, never on the
/// canvas. Light mode keeps the airy tinted wash.
class AppBackground extends StatelessWidget {
  final Widget child;
  final bool showGlow;

  const AppBackground({super.key, required this.child, this.showGlow = true});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final glow = dark ? 0.10 : 0.16;
    // Pure-black canvas: no accent wash at all, so the palette never tints the
    // background. Light mode keeps its airy glow.
    final paintGlow = showGlow && !(dark && AppColors.isAmoledCanvas);

    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.scaffold(context)),
      child: Stack(
        children: [
          if (paintGlow) ...[
            Positioned(
              top: -120,
              left: -90,
              child: _Glow(
                color: AppColors.brand,
                size: 340,
                opacity: glow,
              ),
            ),
            Positioned(
              top: 180,
              right: -120,
              child: _Glow(
                color: AppColors.cyan,
                size: 300,
                opacity: glow * 0.85,
              ),
            ),
            Positioned(
              bottom: -140,
              left: -60,
              child: _Glow(
                color: AppColors.amber,
                size: 280,
                opacity: glow * 0.6,
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _Glow({
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
