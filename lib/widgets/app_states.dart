import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'app_button.dart';
import 'pressable.dart';

/// Illustrated empty state with an optional call-to-action.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.brand.withValues(alpha: 0.18),
                    AppColors.cyan.withValues(alpha: 0.10),
                  ],
                ),
              ),
              child: Icon(icon, size: 38, color: AppColors.brand),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.title(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body(context),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: 220,
                child:
                    AppPrimaryButton(label: actionLabel!, onPressed: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state with retry.
class AppErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const AppErrorState({
    super.key,
    this.title = 'Something went wrong',
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 44, color: AppColors.textTertiary(context)),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: AppText.title(context)),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                textAlign: TextAlign.center, style: AppText.body(context)),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: 180,
                child: AppGhostButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single shimmering placeholder block.
class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = AppRadius.sm,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 0.5,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The shimmer is decoration, not information, so under reduced motion the
    // block stays at its mid tone instead of pulsing forever. This also lets a
    // reduced-motion test settle, which an always-repeating ticker prevents.
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.surfaceAlt(context);
    final highlight = AppColors.border(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Placeholder list shown while the local cache loads.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.border(context).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                const SkeletonBox(height: 46, width: 46, radius: 23),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonBox(height: 14, width: 140),
                      SizedBox(height: AppSpacing.sm),
                      SkeletonBox(height: 10, width: 90),
                    ],
                  ),
                ),
                const SkeletonBox(height: 18, width: 56),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Cross-fades between the mutually exclusive states a screen can be in
/// (loading, empty, error, content) instead of swapping them hard.
///
/// [state] is the switch key: it must change when — and only when — the visible
/// state changes, otherwise the fade fires on ordinary data updates. Under
/// reduced motion the swap is instant.
class AppStateSwap extends StatelessWidget {
  final Object state;
  final Widget child;

  const AppStateSwap({
    super.key,
    required this.state,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.respect(context, AppMotion.base),
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut.flipped,
      child: KeyedSubtree(key: ValueKey(state), child: child),
    );
  }
}

/// Reusable pull-to-refresh progress wrapper keeping brand colour.
class AppRefreshIndicator extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.brand,
      backgroundColor: AppColors.surfaceColor(context),
      onRefresh: onRefresh,
      child: child,
    );
  }
}

/// Small helper re-exported so screens can make tappable rows consistent.
class AppTappable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const AppTappable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        borderRadius: borderRadius,
        child: child,
      );
}
