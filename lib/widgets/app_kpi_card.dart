import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'app_surface.dart';

// ── AppIconPlate ──────────────────────────────────────────────────────────────

/// Neutral outlined square plate for KPI card headers.
///
/// Translated from PanelUI `Kpi` icon slot: `h-8 w-8 rounded-xl`, surfaceTertiary
/// fill, hairline, dark glyph. 32dp square, radius [AppRadius.plate] (10dp).
///
/// Unlike [IconWell], which tints every plate in the category hue, this plate is
/// intentionally colourless. Colour on a KPI header would compete with the value
/// below it, and the value is the message.
class AppIconPlate extends StatelessWidget {
  final IconData icon;

  /// Size of the plate. Default 32dp (matches the PanelUI KPI icon slot).
  final double size;

  /// Glyph size inside the plate. Default 16dp.
  final double glyphSize;

  const AppIconPlate({
    super.key,
    required this.icon,
    this.size = 32,
    this.glyphSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final fill = AppColors.surfaceTertiary(context);
    final border = AppColors.border(context);
    final ink = AppColors.textSecondary(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.plate),
        border: Border.all(color: border.withValues(alpha: 0.72)),
      ),
      child: Center(
        child: Icon(icon, size: glyphSize, color: ink),
      ),
    );
  }
}

// ── AppTrend ─────────────────────────────────────────────────────────────────

/// Trend indicator: a filled 14dp circle with an arrow, a coloured percentage,
/// and a muted "from last period" caption.
///
/// Translated from PanelUI `Kpi.Trend`: the trend takes a *number* and a
/// `goodDirection`, so colour follows meaning rather than sign. Expenses going
/// down is good; income going down is bad. Null `value` renders nothing (used
/// when there is no previous period to compare against).
///
/// Semantics: "Up 5.1 percent, from last month" (or "Down …") — so a screen
/// reader does not need to infer direction from colour alone.
class AppTrend extends StatelessWidget {
  /// Percentage change. Positive means the tracked figure rose; negative means
  /// it fell. Null suppresses the widget entirely.
  final double? value;

  /// When true, a rise is good (income). When false, a fall is good (expenses).
  final bool goodIsUp;

  /// Short label for the comparison period (e.g. "last month").
  final String periodCaption;

  /// Put the "from …" caption on its own line under the figure. A narrow KPI
  /// card has no room for arrow, percentage and caption side by side without
  /// shrinking all three to an unreadable size, so the caption drops a line and
  /// keeps its own 11sp instead.
  final bool stacked;

  const AppTrend({
    super.key,
    required this.value,
    required this.goodIsUp,
    this.periodCaption = 'last period',
    this.stacked = false,
  });

  /// Whether the trend reading is favourable.
  bool get _good {
    final v = value;
    if (v == null) return true;
    return goodIsUp ? v > 0 : v < 0;
  }

  bool get _rising => (value ?? 0) > 0.05;
  bool get _falling => (value ?? 0) < -0.05;

  IconData get _icon => _rising
      ? Icons.arrow_upward_rounded
      : _falling
          ? Icons.arrow_downward_rounded
          : Icons.remove_rounded;

  String get _label {
    final v = value;
    if (v == null || v.abs() <= 0.05) return 'No change';
    return '${v.abs().toStringAsFixed(1)}%';
  }

  String get _semanticLabel {
    final v = value;
    if (v == null || v.abs() <= 0.05) return 'No change from $periodCaption';
    final dir = _rising ? 'Up' : 'Down';
    return '$dir ${v.abs().toStringAsFixed(1)} percent, from $periodCaption';
  }

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) return const SizedBox.shrink();

    final good = _good;
    final trendColor = good ? AppColors.incomeGreen : AppColors.expenseRed;
    final muted = AppColors.textTertiary(context);

    return Semantics(
      label: _semanticLabel,
      excludeSemantics: true,
      // Scale down rather than overflow: a narrow card at large text keeps the
      // arrow, the figure and the caption together at a slightly smaller size.
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: _figure(context, trendColor),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'from $periodCaption',
                    maxLines: 1,
                    style: AppText.caption(context).copyWith(
                      fontSize: 11,
                      color: muted,
                    ),
                  ),
                ),
              ],
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _figure(context, trendColor),
                  const SizedBox(width: 4),
                  Text(
                    'from $periodCaption',
                    maxLines: 1,
                    style: AppText.caption(context).copyWith(
                      fontSize: 12,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// The filled arrow and the percentage, shared by both layouts.
  Widget _figure(BuildContext context, Color trendColor) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: trendColor,
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, size: 9, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            maxLines: 1,
            style: AppText.caption(context).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: trendColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

// ── AppKpiCard ────────────────────────────────────────────────────────────────

/// A single KPI card: icon plate, label, large value, trend.
///
/// Translated from PanelUI `Kpi` anatomy:
/// - `Kpi.Header` / `Icon` → [AppIconPlate]
/// - `Kpi.Title` → 13sp w500 muted label
/// - `Kpi.Value` → 20sp w600 tabular ink
/// - `Kpi.Trend` → [AppTrend] (number + goodDirection + caption)
///
/// Each card is a [AppSurface.raised] plate. It has a fixed minimum width so a
/// horizontal row of them is consistent, and [IntrinsicHeight] in [AppKpiRow]
/// makes all cards in the same row the same height.
///
/// All values are passed in already formatted — this widget performs no
/// financial calculation.
class AppKpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Percentage trend vs. the previous equivalent period. Null = no trend.
  final double? trendValue;

  /// True when a *rise* in [trendValue] is good (income). False for expenses.
  final bool trendGoodIsUp;

  /// Caption for the trend's "from …" text.
  final String trendPeriodCaption;

  const AppKpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trendValue,
    this.trendGoodIsUp = false,
    this.trendPeriodCaption = 'last period',
  });

  @override
  Widget build(BuildContext context) {
    final inkPrimary = AppColors.textPrimary(context);
    final inkSecondary = AppColors.textSecondary(context);
    // Padding and trend layout come from the row that sizes this card (see
    // [AppKpiRow]); a card used on its own gets the standard 16dp.
    final layout = _KpiLayout.of(context);

    return AppSurface(
      level: AppSurfaceLevel.raised,
      padding: EdgeInsets.all(layout.padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconPlate(icon: icon),
          const SizedBox(height: AppSpacing.sm),
          // Scaled down like the value: a card three-up on a 360dp phone at 1.3x
          // text is narrow enough that "Expenses" would otherwise ellipsize.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              maxLines: 1,
              style: AppText.label(context).copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: inkSecondary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Scale down, never ellipsize: a money figure that loses its last
          // digits reads as a different amount.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: AppText.amount(
                context,
                size: 20,
                weight: FontWeight.w600,
                color: inkPrimary,
              ),
            ),
          ),
          if (trendValue != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppTrend(
              value: trendValue,
              goodIsUp: trendGoodIsUp,
              periodCaption: trendPeriodCaption,
              stacked: layout.stackedTrend,
            ),
          ],
        ],
      ),
    );
  }
}

/// How a row has sized its cards. Handed down instead of measured in the card,
/// because the row equalises heights with an [IntrinsicHeight], which cannot
/// contain a `LayoutBuilder`.
class _KpiLayout extends InheritedWidget {
  final double padding;
  final bool stackedTrend;

  const _KpiLayout({
    required this.padding,
    required this.stackedTrend,
    required super.child,
  });

  static const _standard = _StandardLayout();

  static ({double padding, bool stackedTrend}) of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_KpiLayout>();
    if (scope == null) {
      return (padding: _standard.padding, stackedTrend: _standard.stackedTrend);
    }
    return (padding: scope.padding, stackedTrend: scope.stackedTrend);
  }

  @override
  bool updateShouldNotify(_KpiLayout old) =>
      padding != old.padding || stackedTrend != old.stackedTrend;
}

class _StandardLayout {
  const _StandardLayout();
  double get padding => AppSpacing.cardPadding;
  bool get stackedTrend => false;
}

// ── AppKpiRow ─────────────────────────────────────────────────────────────────

/// A row of [AppKpiCard]s that share one height.
///
/// PanelUI `Kpi.Group` rule: separators go between cards, never after the last.
/// Here separation is by card gap; the surface edges carry the rhythm.
///
/// Three layouts, chosen from the width and text size so a money figure is never
/// clipped:
///
/// * **Fits** (each card at least [minCardWidth] wide): the cards share the row
///   equally and nothing scrolls. A 390dp phone gets three 114dp cards with
///   12dp padding, so "₹1,106" is whole.
/// * **Too narrow** (a 320dp phone): the row scrolls sideways. Two cards are
///   shown in full and the third starts [peek] dp from the edge. The peek is
///   narrower than the card padding, so only the blank edge of the next card
///   shows: it signals "more" without ever painting half of a figure.
/// * **Large text** (1.6x and up): the cards stack full width.
class AppKpiRow extends StatelessWidget {
  final List<Widget> cards;

  const AppKpiRow({super.key, required this.cards});

  /// Narrowest a card may be before the row scrolls instead. 104dp leaves 80dp
  /// of text inside 12dp padding: "₹1,06,000" at 20sp scales to about 0.8.
  static const double minCardWidth = 104;

  /// How much of the next card shows when the row scrolls. Smaller than the
  /// 16dp card padding on purpose (see above).
  static const double peek = 10;

  static const double gap = AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale >= 1.6) {
      // Stacked layout at large text: full-width cards, one below the other.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: gap),
            cards[i],
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final n = cards.length;
        final equal = (available - gap * (n - 1)) / n;

        if (equal >= minCardWidth || n <= 2) {
          return _KpiLayout(
            padding: equal < 120 ? 12 : AppSpacing.cardPadding,
            stackedTrend: equal - 2 * (equal < 120 ? 12 : 16) < 132,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(child: cards[i]),
                  ],
                ],
              ),
            ),
          );
        }

        // Two full cards, the gap after each, and the [peek].
        final cardWidth = (available - gap * 2 - peek) / 2;
        return _KpiLayout(
          padding: AppSpacing.cardPadding,
          stackedTrend: cardWidth - 2 * AppSpacing.cardPadding < 132,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    SizedBox(width: cardWidth, child: cards[i]),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
