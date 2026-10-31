import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const AppLogo({
    super.key,
    this.size = 42,
    this.showWordmark = false,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          // The canonical logo asset, so every screen shows the same mark as
          // the launcher icon. Decoded at display size to keep memory small.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBright.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Image.asset(
              'assets/icons/app_icon.png',
              width: size,
              height: size,
              cacheWidth: (size * 3).round(),
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(size * 0.3),
                ),
                child: Icon(
                  Icons.auto_graph_rounded,
                  color: Colors.white,
                  size: size * 0.46,
                ),
              ),
            ),
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SpendSense',
                style: titleStyle ??
                    theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                'Smart money copilot',
                style: subtitleStyle ??
                    theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                      letterSpacing: 0.2,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
