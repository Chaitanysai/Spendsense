import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import 'animated_progress_bar.dart';

/// Proportional category spending, as one composition plus ranked rows.
///
/// The strip at the top answers "how is the whole made up?" in a single glance;
/// the rows answer "which category, and how much?" for every category. They are
/// one widget because they are one reading: tapping a row selects it in both
/// places, and the unselected segments dim so a thin slice stays findable.
///
/// Input is integer paise — the widget never receives or produces a money
/// double. Only the shares are doubles, computed for display.
class CategorySpendingBars extends StatefulWidget {
  /// Category name → spending in paise.
  final Map<String, int> totalsMinor;

  /// How many rows to draw before the remainder is summarised.
  final int maxRows;

  /// Currently emphasised category, or null.
  final String? selectedCategory;

  /// Called with the tapped category, or null when the tap clears the
  /// selection. When null, rows are not interactive.
  final ValueChanged<String?>? onSelect;

  /// Reveals the categories beyond [maxRows]. When null, the remainder is
  /// summarised in plain text only.
  final VoidCallback? onShowAll;

  /// Draws the proportional strip above the rows.
  final bool showComposition;

  const CategorySpendingBars({
    super.key,
    required this.totalsMinor,
    this.maxRows = 6,
    this.selectedCategory,
    this.onSelect,
    this.onShowAll,
    this.showComposition = true,
  });

  @override
  State<CategorySpendingBars> createState() => _CategorySpendingBarsState();
}

class _CategorySpendingBarsState extends State<CategorySpendingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _strip = AnimationController(
    vsync: this,
    duration: AppMotion.chart,
  );

  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (_started) return;
    _started = true;
    if (_reduceMotion) {
      _strip.value = 1;
    } else {
      _strip.forward();
    }
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.totalsMinor.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) return const _EmptyBars();

    // Denominator is every category, not just the visible rows, so a percentage
    // is always a share of real spending and never of an arbitrary subset.
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    if (total <= 0) return const _EmptyBars();

    final shown = entries.take(widget.maxRows).toList();
    final hidden = entries.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showComposition) ...[
          _CompositionStrip(
            entries: entries,
            total: total,
            progress: _strip,
            reduceMotion: _reduceMotion,
            selectedCategory: widget.selectedCategory,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        for (var i = 0; i < shown.length; i++)
          _CategoryBarRow(
            category: shown[i].key,
            amountMinor: shown[i].value,
            share: shown[i].value / total,
            delay: Duration(milliseconds: 40 * i),
            selected: shown[i].key == widget.selectedCategory,
            onTap: widget.onSelect == null
                ? null
                : () => widget.onSelect!(
                      shown[i].key == widget.selectedCategory
                          ? null
                          : shown[i].key,
                    ),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '+$hidden more ${hidden == 1 ? 'category' : 'categories'}',
                    style: AppText.label(context).copyWith(
                      fontSize: 11.5,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
                if (widget.onShowAll != null)
                  TextButton(
                    onPressed: widget.onShowAll,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.brandInk(context),
                    ),
                    child: Text(
                      'Show all',
                      style: AppText.weight(
                              AppText.label(context), FontWeight.w700)
                          .copyWith(
                        fontSize: 11.5,
                        color: AppColors.brandInk(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One stacked bar: every category, in ranked order, sharing one rounded track.
///
/// A segment is never narrower than [_minSegment] so a 0.4% category is still a
/// visible mark rather than a hairline; the widths are normalised back to the
/// available space so the strip always fills its track exactly.
class _CompositionStrip extends StatelessWidget {
  static const double _height = 10;
  static const double _minSegment = 3;
  static const double _gap = 2;

  final List<MapEntry<String, int>> entries;
  final int total;
  final Animation<double> progress;
  final bool reduceMotion;
  final String? selectedCategory;

  const _CompositionStrip({
    required this.entries,
    required this.total,
    required this.progress,
    required this.reduceMotion,
    required this.selectedCategory,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - _gap * (entries.length - 1);
        final raw = [
          for (final e in entries)
            math.max(_minSegment, available * e.value / total),
        ];
        final rawTotal = raw.fold<double>(0, (s, v) => s + v);
        final factor = rawTotal > available ? available / rawTotal : 1.0;

        final segments = <Widget>[];
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final color = CategoryStyle.color(entry.key);
          final dimmed =
              selectedCategory != null && selectedCategory != entry.key;
          if (i > 0) segments.add(const SizedBox(width: _gap));
          segments.add(
            SizedBox(
              width: raw[i] * factor,
              child: Semantics(
                label: '${entry.key}, '
                    '${(entry.value * 100 / total).round()} percent',
                child: Opacity(
                  opacity: dimmed ? 0.45 : 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(_height / 2),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: _height,
            child: AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                final t = reduceMotion
                    ? 1.0
                    : AppMotion.emphasized.transform(
                        progress.value.clamp(0.0, 1.0),
                      );
                return ClipRect(
                  clipper: _RevealClipper(t),
                  child: Row(children: segments),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Reveals a child from the left edge without resizing it, so the segments keep
/// their final widths (and therefore their true proportions) while they appear.
class _RevealClipper extends CustomClipper<Rect> {
  final double t;

  const _RevealClipper(this.t);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);

  @override
  bool shouldReclip(covariant _RevealClipper oldClipper) => oldClipper.t != t;
}

class _CategoryBarRow extends StatelessWidget {
  final String category;
  final int amountMinor;
  final double share;
  final Duration delay;
  final bool selected;
  final VoidCallback? onTap;

  const _CategoryBarRow({
    required this.category,
    required this.amountMinor,
    required this.share,
    required this.delay,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.color(category);
    final percent = (share * 100).round();
    final dark = AppColors.isDark(context);

    final content = AnimatedContainer(
      duration: AppMotion.respect(context, AppMotion.fast),
      curve: AppMotion.easeOut,
      padding: EdgeInsets.fromLTRB(
        selected ? AppSpacing.sm : 0,
        AppSpacing.sm,
        selected ? AppSpacing.sm : 0,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: selected
            ? color.withValues(alpha: dark ? 0.14 : 0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: selected
              ? color.withValues(alpha: dark ? 0.36 : 0.26)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CategoryStyle.icon(category), size: 15, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 3,
                child: Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(context).copyWith(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    Formatters.currency.format(amountMinor),
                    maxLines: 1,
                    style: AppText.amount(
                      context,
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 32,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: AppText.amount(
                    context,
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: AppColors.textTertiary(context),
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          AnimatedProgressBar(
            fraction: share,
            height: 7,
            color: color,
            trackColor: AppColors.categoryTrack(color, context),
            delay: delay,
            semanticLabel: '$category, $percent percent of spending',
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: content,
      ),
    );
  }
}

class _EmptyBars extends StatelessWidget {
  const _EmptyBars();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.pie_chart_outline_rounded,
              size: 18, color: AppColors.textTertiary(context)),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'No spending to chart yet',
              style: AppText.body(context),
            ),
          ),
        ],
      ),
    );
  }
}
