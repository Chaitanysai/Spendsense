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
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(size * 0.3),
            boxShadow: [
              BoxShadow(
                // FIX: replaced withOpacity() with withValues(alpha:)
                color: AppColors.brand.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: size * 0.18,
                left: size * 0.18,
                child: Container(
                  width: size * 0.28,
                  height: size * 0.28,
                  decoration: BoxDecoration(
                    // FIX: replaced withOpacity() with withValues(alpha:)
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(size),
                  ),
                ),
              ),
              Positioned(
                bottom: size * 0.16,
                right: size * 0.16,
                child: Container(
                  width: size * 0.34,
                  height: size * 0.34,
                  decoration: BoxDecoration(
                    // FIX: replaced withOpacity() with withValues(alpha:)
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(size * 0.12),
                  ),
                ),
              ),
              Icon(
                Icons.auto_graph_rounded,
                color: Colors.white,
                size: size * 0.46,
              ),
            ],
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
