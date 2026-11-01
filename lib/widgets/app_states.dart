import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'app_button.dart';
import 'glass_card.dart';
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
                color: AppColors.brand.withValues(alpha: 0.09),
                border: Border.all(
                  color: AppColors.brand.withValues(alpha: 0.16),
                ),
              ),
              child: Icon(
                icon,
                size: 36,
                color: AppColors.brandInk(context),
              ),
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
///
/// The sheen travels across the block while the base colour breathes very
/// slightly, so a stack of placeholders reads as one loading surface rather than
/// a set of grey rectangles. Both stop when the platform requests reduced
/// motion — the placeholder then renders as a flat, stable surface.
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
    duration: AppMotion.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.skeletonBase(context);
    final highlight = AppColors.skeletonHighlight(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // A slow breath on the base so the block is alive between sheen passes,
        // and a bright band that sweeps left to right.
        final breathe = 0.06 + 0.06 * (1 - (2 * t - 1).abs());
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, breathe),
            gradient: LinearGradient(
              begin: Alignment(-1.8 + 3.6 * t, 0),
              end: Alignment(-0.8 + 3.6 * t, 0),
              colors: [
                Colors.transparent,
                highlight.withValues(alpha: 0.55),
                Colors.transparent,
              ],
            ),
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

/// Contextual placeholder that mirrors the "Last 7 days" card.
///
/// Same block structure as the real card — header pair, plot, seven day marks —
/// so the content swap does not move anything on the page.
class SpendingWeekSkeleton extends StatelessWidget {
  const SpendingWeekSkeleton({super.key});

  static const List<double> _heights = [34, 52, 22, 66, 40, 58, 30];

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 10, width: 64),
                    SizedBox(height: AppSpacing.sm),
                    SkeletonBox(height: 26, width: 132, radius: AppRadius.sm),
                  ],
                ),
              ),
              SkeletonBox(height: 10, width: 54),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 122,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _heights.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: SkeletonBox(
                          height: _heights[i],
                          width: 18,
                          radius: 9,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                const Expanded(
                  child: Center(
                    child: SkeletonBox(height: 16, width: 16, radius: 8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Contextual placeholder that mirrors the category breakdown card.
class CategoryBreakdownSkeleton extends StatelessWidget {
  const CategoryBreakdownSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SkeletonBox(height: 22, width: 118, radius: AppRadius.sm),
              Spacer(),
              SkeletonBox(height: 20, width: 72, radius: AppRadius.pill),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SkeletonBox(height: 10, radius: AppRadius.pill),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: [
                  const SkeletonBox(height: 26, width: 26, radius: 13),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(child: SkeletonBox(height: 12, width: 96)),
                  const SizedBox(width: AppSpacing.sm),
                  const SkeletonBox(height: 12, width: 54),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Reveals freshly loaded content after its skeleton is removed.
///
/// A hard swap from placeholder to data is the one moment a dashboard can feel
/// like it flickered. This fades the real content in while a small blur resolves,
/// over the same duration as the skeleton's own 300 ms exit, and does nothing at
/// all when the platform asks for reduced motion.
class ContentReveal extends StatefulWidget {
  final Widget child;

  const ContentReveal({super.key, required this.child});

  @override
  State<ContentReveal> createState() => _ContentRevealState();
}

class _ContentRevealState extends State<ContentReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return widget.child;
    }
    final curved = CurvedAnimation(parent: _c, curve: AppMotion.emphasized);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: (1 - t) * 4,
              sigmaY: (1 - t) * 4,
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
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
      color: AppColors.brandInk(context),
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
