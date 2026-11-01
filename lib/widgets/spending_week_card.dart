import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction_model.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/formatters.dart';
import '../utils/period_math.dart';
import 'animated_amount.dart';
import 'glass_card.dart';

/// The "Last 7 days" analytics card.
///
/// One answer at a time: the selected day's total, how it compares with the rest
/// of the week, and the shape of the whole week underneath. Tapping (or dragging
/// across) the plot moves the selection; the card's figure, the delta pill and
/// the value bubble all follow it.
///
/// The chart is drawn by this widget rather than a charting package because the
/// entrance and selection motion are part of the design: the line draws on from
/// the left, the points appear as the head passes them, and the selection marker
/// glides between days instead of jumping.
///
/// Money stays integer paise until it is formatted; only the plotted heights are
/// doubles.
class SpendingWeekCard extends StatefulWidget {
  /// Expenses for the dashboard's current window. Income is deliberately not
  /// passed: this card answers "what did I spend", and mixing the two would make
  /// a refund look like a quiet day.
  final List<TransactionModel> expenses;

  const SpendingWeekCard({super.key, required this.expenses});

  @override
  State<SpendingWeekCard> createState() => _SpendingWeekCardState();
}

class _SpendingWeekCardState extends State<SpendingWeekCard>
    with TickerProviderStateMixin {
  static const int _todayIndex = 6;

  /// Which day the header describes. Survives data updates so a sync landing
  /// mid-inspection does not move the answer.
  int _selected = _todayIndex;

  int _selectionFrom = _todayIndex;
  int _selectionTo = _todayIndex;

  late List<_DaySpend> _days;
  List<double> _from = List<double>.filled(7, 0);
  List<double> _to = List<double>.filled(7, 0);

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.chart,
  );
  late final AnimationController _values = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: AppMotion.base,
    value: 1,
  );

  bool _initialised = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _days = _daysFor(widget.expenses);
    _to = [for (final d in _days) d.amountMinor.toDouble()];
    _from = List<double>.filled(7, 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final changed = reduced != _reduceMotion;
    _reduceMotion = reduced;

    if (!_initialised) {
      _initialised = true;
      if (reduced) {
        _entrance.value = 1;
        _values.value = 1;
      } else {
        _entrance.forward();
        _values.forward();
      }
      return;
    }
    if (changed && reduced) {
      _entrance.value = 1;
      _values.value = 1;
      _selection.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant SpendingWeekCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _daysFor(widget.expenses);
    final nextAmounts = [for (final d in next) d.amountMinor.toDouble()];
    if (_sameAmounts(nextAmounts, _to) && _sameDays(next, _days)) return;

    // Continue from whatever is painted right now, so a value that changes
    // during the entrance does not snap the line back to the baseline.
    final visible = _visibleAmounts();
    _days = next;
    _from = visible;
    _to = nextAmounts;
    if (_reduceMotion) {
      _values.value = 1;
    } else {
      _values.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _values.dispose();
    _selection.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  /// Seven calendar days ending today, aggregated in local time.
  ///
  /// Calendar arithmetic via [PeriodMath.addDays] rather than `Duration(days:)`,
  /// so a DST change cannot shift a row onto the wrong bar.
  List<_DaySpend> _daysFor(List<TransactionModel> expenses) {
    final today = PeriodMath.dateOnly(DateTime.now());
    return List.generate(7, (i) {
      final day = PeriodMath.addDays(today, i - 6);
      var total = 0;
      for (final t in expenses) {
        final local = t.date.toLocal();
        if (local.year == day.year &&
            local.month == day.month &&
            local.day == day.day) {
          total += t.amountMinor;
        }
      }
      return _DaySpend(day: day, amountMinor: total);
    });
  }

  bool _sameAmounts(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _sameDays(List<_DaySpend> a, List<_DaySpend> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].day != b[i].day) return false;
    }
    return true;
  }

  List<double> _visibleAmounts() {
    final t = _values.value;
    return [
      for (var i = 0; i < _to.length; i++) _from[i] + (_to[i] - _from[i]) * t,
    ];
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  void _select(int index) {
    if (index == _selectionTo) return;
    final from = _selection.value >= 1
        ? _selectionTo
        : (_selectionFrom + (_selectionTo - _selectionFrom) * _selection.value)
            .round();
    setState(() {
      _selectionFrom = from;
      _selectionTo = index;
      _selected = index;
    });
    if (_reduceMotion) {
      _selection.value = 1;
    } else {
      _selection.forward(from: 0);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selected.clamp(0, _days.length - 1);
    final selected = _days[selectedIndex];
    final maxAmount = _to.fold<double>(0, (m, v) => v > m ? v : m);
    final hasSpending = maxAmount > 0;
    final weekTotal = _days.fold<int>(0, (s, d) => s + d.amountMinor);
    final isToday = selectedIndex == _todayIndex;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isToday
                              ? 'Today'
                              : DateFormat('EEEE').format(selected.day),
                          style: AppText.label(context).copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          DateFormat('d MMM')
                              .format(selected.day)
                              .toUpperCase(),
                          style: AppText.overline(context).copyWith(
                            fontSize: 9,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedAmount(
                        value: selected.amountMinor.toDouble(),
                        duration: AppMotion.base,
                        format: (v) => Formatters.currency.format(v),
                        style: AppText.amount(
                          context,
                          size: 30,
                          letterSpacing: -1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '7-DAY TOTAL',
                    style: AppText.overline(context).copyWith(fontSize: 9),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    Formatters.currency.format(weekTotal),
                    style: AppText.amount(
                      context,
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasSpending) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: _DeltaLine(
                currentMinor: selected.amountMinor,
                otherDays: [
                  for (var i = 0; i < _days.length; i++)
                    if (i != selectedIndex) _days[i].amountMinor,
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _chart(context, maxAmount),
          ] else
            _emptyChart(context),
          const SizedBox(height: AppSpacing.sm),
          _WeekdayRow(
            days: _days,
            selected: selectedIndex,
            onSelect: _select,
          ),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context, double maxAmount) {
    return SizedBox(
      key: const Key('spending-week-chart'),
      height: 158,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: Listenable.merge([_entrance, _values, _selection]),
            builder: (context, _) {
              final values = _visibleAmounts();
              final entrance = _reduceMotion
                  ? 1.0
                  : AppMotion.emphasized.transform(
                      _entrance.value.clamp(0.0, 1.0),
                    );
              final t = AppMotion.easeOut.transform(
                _selection.value.clamp(0.0, 1.0),
              );
              final geometry = _WeekGeometry(
                size: Size(width, 158),
                values: values,
                maxAmount: maxAmount,
              );
              final from = geometry.pointAt(_selectionFrom);
              final to = geometry.pointAt(_selectionTo);
              final marker = Offset.lerp(from, to, t) ?? to;
              final bubbleValue = values[_selectionFrom] +
                  (values[_selectionTo] - values[_selectionFrom]) * t;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTapDown: (details) => _select(
                        geometry.indexAt(details.localPosition.dx),
                      ),
                      onHorizontalDragStart: (details) => _select(
                        geometry.indexAt(details.localPosition.dx),
                      ),
                      onHorizontalDragUpdate: (details) => _select(
                        geometry.indexAt(details.localPosition.dx),
                      ),
                      child: CustomPaint(
                        painter: _WeekChartPainter(
                          geometry: geometry,
                          progress: entrance,
                          line: AppColors.chartLine(context),
                          area: AppColors.chartArea(context),
                          grid: AppColors.chartGrid(context),
                          surface: AppColors.surfaceColor(context),
                          marker: entrance >= 1 ? marker : null,
                          accent: AppColors.lime,
                        ),
                      ),
                    ),
                  ),
                  // Value bubble above the selected point. Positioned by
                  // translate so its intrinsic width can be anything.
                  Positioned(
                    left: marker.dx.clamp(34.0, width - 34.0),
                    top: (marker.dy - 36).clamp(0.0, 120.0),
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, 0),
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: entrance.clamp(0.0, 1.0),
                          child: _ValueBubble(
                            // The day is part of the bubble on purpose: once the
                            // marker has glided, "₹120" alone is ambiguous.
                            label: '${DateFormat('EEE').format(
                              t < 0.5
                                  ? _days[_selectionFrom].day
                                  : _days[_selectionTo].day,
                            )} · ${Formatters.currency.format(bubbleValue)}',
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Screen-reader targets: one per day, with the same selection
                  // action as a tap. The boxes carry no pointer behaviour, so
                  // the drag gesture above still receives every touch.
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (var i = 0; i < _days.length; i++)
                          Expanded(
                            child: Semantics(
                              container: true,
                              button: true,
                              selected: i == _selected,
                              label: _semanticsLabel(_days[i]),
                              onTap: () => _select(i),
                              child: const SizedBox.expand(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyChart(BuildContext context) {
    return Container(
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        color: AppColors.surfaceAlt(context).withValues(
          alpha: AppColors.isDark(context) ? 0.35 : 0.55,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.show_chart_rounded,
            size: 20,
            color: AppColors.textTertiary(context),
          ),
          const SizedBox(height: 6),
          Text(
            'No spending in the last 7 days',
            style: AppText.bodySmall(context),
          ),
        ],
      ),
    );
  }

  String _semanticsLabel(_DaySpend bar) {
    final weekday = DateFormat('EEEE').format(bar.day);
    final date = DateFormat('d MMM').format(bar.day);
    final amount = Formatters.currency.format(bar.amountMinor);
    return '$weekday, $date, $amount';
  }
}

// ── Header comparison ─────────────────────────────────────────────────────────

/// How the selected day compares with the other six.
///
/// Direction is carried by the word and the icon, not by hue alone. A week with
/// no comparable spend shows a quiet statement rather than a 0%-change pill that
/// would imply a measurement nobody made.
class _DeltaLine extends StatelessWidget {
  final int currentMinor;
  final List<int> otherDays;

  const _DeltaLine({required this.currentMinor, required this.otherDays});

  @override
  Widget build(BuildContext context) {
    final othersTotal = otherDays.fold<int>(0, (s, v) => s + v);
    if (othersTotal <= 0) {
      return Text(
        'First spending this week',
        style: AppText.caption(context).copyWith(fontSize: 10.5),
      );
    }
    if (currentMinor <= 0) {
      return Text(
        'Nothing spent on this day',
        style: AppText.caption(context).copyWith(fontSize: 10.5),
      );
    }
    // A daily average divides by every other *day*, zeros included. Averaging
    // only the days that had spending made a quiet Sunday read "94% below
    // average" against the single big day, which is not what a daily average
    // means.
    final average = othersTotal / otherDays.length;
    final delta = (currentMinor - average) * 100 / average;
    final rising = delta > 3;
    final falling = delta < -3;

    // A week is usually dominated by one or two days, so "x times the average"
    // is either absurd (100×) or meaningless. When the selected day carries
    // more than half the week, its *share* is the useful, bounded fact.
    final weekTotal = othersTotal + currentMinor;
    final share = weekTotal == 0 ? 0.0 : currentMinor / weekTotal;
    final dominant = share >= 0.5;

    final tone = dominant
        ? AppColors.textSecondary(context)
        : rising
            ? AppColors.warning
            : falling
                ? AppColors.incomeGreen
                : AppColors.textSecondary(context);
    // The fixed warning amber and income green are designed for badges on dark
    // glass; as 10px text on a 10% tint over a white card they fall under AA.
    // Light mode deepens the ink while keeping the tint recognisable.
    final ink = AppColors.isDark(context)
        ? tone
        : Color.lerp(tone, AppColors.navyDeep, 0.45) ?? tone;

    final String label;
    final String semantics;
    if (dominant) {
      final pct = (share * 100).round();
      label = '$pct% of this week';
      semantics = '$pct percent of the week\'s spending';
    } else if (!rising && !falling) {
      label = 'About average';
      semantics = 'About average for the week';
    } else {
      // Within half the week the ratio cannot run away, so a percentage is the
      // honest form and matches the word "average".
      label = '${delta.abs().round()}% ${rising ? 'above' : 'below'} average';
      semantics = '${delta.abs().round()} percent '
          '${rising ? 'above' : 'below'} the average of the other days';
    }
    final IconData icon = dominant
        ? Icons.pie_chart_outline_rounded
        : rising
            ? Icons.trending_up_rounded
            : falling
                ? Icons.trending_down_rounded
                : Icons.remove_rounded;

    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:
              tone.withValues(alpha: AppColors.isDark(context) ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: ink,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(context).copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Value bubble ─────────────────────────────────────────────────────────────

class _ValueBubble extends StatelessWidget {
  final String label;

  const _ValueBubble({required this.label});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        // Inverted ink: a tooltip reads as an annotation floating over the card
        // rather than one more surface to decode.
        color: dark ? Colors.white : AppColors.navyDeep,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.36 : 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: AppText.amount(
          context,
          size: 11,
          weight: FontWeight.w700,
          color: dark ? AppColors.navyDeep : Colors.white,
        ),
      ),
    );
  }
}

// ── Weekday labels ───────────────────────────────────────────────────────────

class _WeekdayRow extends StatelessWidget {
  final List<_DaySpend> days;
  final int selected;
  final ValueChanged<int> onSelect;

  const _WeekdayRow({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Semantics(
              label: DateFormat('EEEE').format(days[i].day),
              selected: i == selected,
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onSelect(i),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: AppMotion.respect(
                          context,
                          AppMotion.fast,
                        ),
                        curve: AppMotion.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: i == selected
                              ? AppColors.lime
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          DateFormat('EEEEE')
                              .format(days[i].day)
                              .substring(0, 1),
                          style: AppText.label(context).copyWith(
                            fontSize: 10,
                            color: i == selected
                                ? AppColors.onLime(context)
                                : AppColors.textTertiary(context),
                            fontWeight: i == selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${days[i].day.day}',
                        style: AppText.caption(context).copyWith(
                          fontSize: 9.5,
                          color: i == selected
                              ? AppColors.textSecondary(context)
                              : AppColors.textTertiary(context),
                          fontWeight:
                              i == selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Geometry ─────────────────────────────────────────────────────────────────

/// Pixel positions for one seven-point series.
///
/// Shared by the painter, the bubble and the hit test so a tap always selects
/// the day whose point is under the finger.
class _WeekGeometry {
  static const double _top = 14;
  static const double _bottom = 8;
  static const double _side = 10;

  final Size size;
  final List<double> values;
  final double maxAmount;

  const _WeekGeometry({
    required this.size,
    required this.values,
    required this.maxAmount,
  });

  double get _plotTop => _top;
  double get _plotBottom => size.height - _bottom;
  double get _plotLeft => _side;
  double get _plotRight => size.width - _side;
  double get _plotHeight => _plotBottom - _plotTop;
  double get _step => (_plotRight - _plotLeft) / 6;

  /// Headroom keeps the highest point off the top edge and leaves room for the
  /// selected marker's halo.
  double get _scale => maxAmount <= 0 ? 1 : maxAmount * 1.14;

  Offset pointAt(int index) {
    final i = index.clamp(0, 6);
    final value = i < values.length ? values[i] : 0.0;
    final x = _plotLeft + _step * i;
    final y = _plotBottom - (value / _scale).clamp(0.0, 1.0) * _plotHeight;
    return Offset(x, y);
  }

  int indexAt(double dx) {
    if (_step <= 0) return 0;
    return ((dx - _plotLeft) / _step).round().clamp(0, 6);
  }

  List<Offset> get points => [for (var i = 0; i < 7; i++) pointAt(i)];
}

// ── Painter ──────────────────────────────────────────────────────────────────

class _WeekChartPainter extends CustomPainter {
  final _WeekGeometry geometry;
  final double progress;
  final Color line;
  final LinearGradient area;
  final Color grid;
  final Color surface;
  final Color accent;
  final Offset? marker;

  _WeekChartPainter({
    required this.geometry,
    required this.progress,
    required this.line,
    required this.area,
    required this.grid,
    required this.surface,
    required this.accent,
    required this.marker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      geometry._plotLeft,
      geometry._plotTop,
      geometry._plotRight,
      geometry._plotBottom,
    );

    // Hairline grid. Three rules are enough to read height without turning the
    // card into graph paper.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = rect.bottom - rect.height * i / 3;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    final points = geometry.points;
    final curve = _smooth(points, rect);

    final reveal = (1 - progress).clamp(0.0, 1.0);
    final clipWidth = size.width * (size.width <= 0 ? 1 : progress);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clipWidth, size.height));

    // Area wash.
    final areaPath = Path.from(curve)
      ..lineTo(points.last.dx, rect.bottom)
      ..lineTo(points.first.dx, rect.bottom)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = area.createShader(
          Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom),
        ),
    );

    // The line itself, drawn with a rounded cap and a thin bright core.
    canvas.drawPath(
      curve,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Points appear as the drawing head passes them.
    for (var i = 0; i < points.length; i++) {
      final threshold = i / (points.length - 1);
      if (progress + 1e-6 < threshold) continue;
      _dot(canvas, points[i]);
    }

    canvas.restore();

    // Drawing head: a soft pulse that leads the reveal. Hidden once the line is
    // fully drawn so the card settles to a still image.
    if (reveal > 0.01 && reveal < 1) {
      final headX = rect.left + rect.width * progress;
      final head = _pointOnCurve(points, headX);
      canvas.drawCircle(
        head,
        9,
        Paint()..color = line.withValues(alpha: 0.16),
      );
      canvas.drawCircle(head, 3.2, Paint()..color = line);
    }

    // Selected marker: glides between days, so it is drawn last and on top.
    final selectedPoint = marker;
    if (selectedPoint != null) {
      canvas.drawCircle(
        selectedPoint,
        11,
        Paint()..color = accent.withValues(alpha: 0.20),
      );
      canvas.drawCircle(selectedPoint, 7, Paint()..color = surface);
      canvas.drawCircle(
        selectedPoint,
        7,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(selectedPoint, 3.2, Paint()..color = line);
    }
  }

  void _dot(Canvas canvas, Offset point) {
    canvas.drawCircle(point, 4, Paint()..color = surface);
    canvas.drawCircle(point, 2.4, Paint()..color = line);
  }

  /// Catmull-Rom through the points, flattened to a cubic path.
  ///
  /// Control points are clamped inside the plot so a spike at the edge cannot
  /// bulge the curve over the card padding.
  Path _smooth(List<Offset> points, Rect rect) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[math.min(i + 2, points.length - 1)];
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        (p1.dy + (p2.dy - p0.dy) / 6).clamp(rect.top, rect.bottom),
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        (p2.dy - (p3.dy - p1.dy) / 6).clamp(rect.top, rect.bottom),
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  /// y of the point on the segment that contains [x]. Used only for the head.
  Offset _pointOnCurve(List<Offset> points, double x) {
    // Linear interpolation between the two surrounding data points is accurate
    // enough for a 9px halo and avoids a PathMetrics allocation every frame.
    if (x <= points.first.dx) return points.first;
    for (var i = 0; i < points.length - 1; i++) {
      if (x <= points[i + 1].dx) {
        final t = ((x - points[i].dx) /
                (points[i + 1].dx - points[i].dx).clamp(1, double.infinity))
            .clamp(0.0, 1.0);
        return Offset.lerp(points[i], points[i + 1], t)!;
      }
    }
    return points.last;
  }

  @override
  bool shouldRepaint(covariant _WeekChartPainter old) =>
      old.progress != progress ||
      old.marker != marker ||
      old.line != line ||
      old.grid != grid ||
      old.surface != surface ||
      !identical(old.geometry.values, geometry.values) ||
      old.geometry.maxAmount != geometry.maxAmount;
}

class _DaySpend {
  final DateTime day;
  final int amountMinor;

  const _DaySpend({required this.day, required this.amountMinor});
}
