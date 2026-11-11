import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/transaction_model.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../../utils/formatters.dart';
import '../../utils/period_math.dart';
import '../animated_amount.dart';
import '../app_surface.dart';

/// The dashboard's spending trend — the replacement for the old radial dial.
///
/// A smooth area chart over a selectable window (7 or 30 days). Dragging or
/// tapping the plot moves a marker; the headline amount, the comparison line
/// and the value bubble all follow it. The window toggle is local state, so
/// changing it never rebuilds the dashboard.
///
/// The chart is drawn by this widget rather than a charting package because the
/// entrance and selection motion are part of the design: the line draws on from
/// the left, the marker glides between points instead of jumping, and a second
/// gesture mid-flight retargets from the value currently on screen.
///
/// Money stays integer paise until it is formatted; only plotted heights are
/// doubles.
class SpendingTrendCard extends StatefulWidget {
  /// Non-excluded expenses. Income is passed separately so the header can show
  /// what came in over the same window without mixing it into the spend line.
  final List<TransactionModel> expenses;
  final List<TransactionModel> income;

  /// Window the card opens on. 7 or 30.
  final int initialDays;

  const SpendingTrendCard({
    super.key,
    required this.expenses,
    this.income = const [],
    this.initialDays = 7,
  });

  @override
  State<SpendingTrendCard> createState() => _SpendingTrendCardState();
}

class _SpendingTrendCardState extends State<SpendingTrendCard>
    with TickerProviderStateMixin {
  static const List<int> _windows = [7, 30];

  late int _windowDays = widget.initialDays;
  late int _selected = _windowDays - 1;
  int _selectionFrom = 0;
  int _selectionTo = 0;

  late List<_DayPoint> _days;
  List<double> _from = const [];
  List<double> _to = const [];

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
    _days = _daysFor(widget.expenses, widget.income, _windowDays);
    _to = [for (final d in _days) d.expenseMinor.toDouble()];
    _from = List<double>.filled(_to.length, 0);
    _selected = _to.length - 1;
    _selectionFrom = _selected;
    _selectionTo = _selected;
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
  void didUpdateWidget(covariant SpendingTrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _daysFor(widget.expenses, widget.income, _windowDays);
    final nextAmounts = [for (final d in next) d.expenseMinor.toDouble()];
    if (_sameAmounts(nextAmounts, _to) && _sameDays(next, _days)) return;

    final visible = _visibleAmounts();
    _days = next;
    _from = visible.length == nextAmounts.length
        ? visible
        : List<double>.filled(nextAmounts.length, 0);
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

  /// [count] calendar days ending today, aggregated in local time.
  ///
  /// Calendar arithmetic via [PeriodMath.addDays] rather than `Duration(days:)`,
  /// so a DST change cannot shift a row onto the wrong point.
  List<_DayPoint> _daysFor(
    List<TransactionModel> expenses,
    List<TransactionModel> income,
    int count,
  ) {
    final today = PeriodMath.dateOnly(DateTime.now());
    final points = List.generate(count, (i) {
      final day = PeriodMath.addDays(today, i - (count - 1));
      return _DayPoint(day: day);
    });
    final index = <int, int>{
      for (var i = 0; i < points.length; i++)
        points[i].day.microsecondsSinceEpoch: i,
    };
    for (final t in expenses) {
      final local = t.date.toLocal();
      final key =
          DateTime(local.year, local.month, local.day).microsecondsSinceEpoch;
      final i = index[key];
      if (i != null) points[i].expenseMinor += t.amountMinor;
    }
    for (final t in income) {
      final local = t.date.toLocal();
      final key =
          DateTime(local.year, local.month, local.day).microsecondsSinceEpoch;
      final i = index[key];
      if (i != null) points[i].incomeMinor += t.amountMinor;
    }
    return points;
  }

  bool _sameAmounts(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _sameDays(List<_DayPoint> a, List<_DayPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].day != b[i].day) return false;
    }
    return true;
  }

  List<double> _visibleAmounts() {
    final t = _values.value;
    return [
      for (var i = 0; i < _to.length; i++)
        (_from.length == _to.length ? _from[i] : 0) +
            (_to[i] - (_from.length == _to.length ? _from[i] : 0)) * t,
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

  void _setWindow(int days) {
    if (days == _windowDays) return;
    final next = _daysFor(widget.expenses, widget.income, days);
    setState(() {
      _windowDays = days;
      _days = next;
      _from = List<double>.filled(next.length, 0);
      _to = [for (final d in next) d.expenseMinor.toDouble()];
      _selected = next.length - 1;
      _selectionFrom = _selected;
      _selectionTo = _selected;
      _selection.value = 1;
    });
    if (_reduceMotion) {
      _values.value = 1;
      _entrance.value = 1;
    } else {
      _values.forward(from: 0);
      _entrance.forward(from: 0);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selected.clamp(0, _days.length - 1);
    final selected = _days[selectedIndex];
    final maxAmount = _to.fold<double>(0, (m, v) => m > v ? m : v);
    final hasSpending = maxAmount > 0;
    final windowTotal = _days.fold<int>(0, (s, d) => s + d.expenseMinor);
    final windowIncome = _days.fold<int>(0, (s, d) => s + d.incomeMinor);
    final isToday = selectedIndex == _days.length - 1;

    return AppSurface(
      level: AppSurfaceLevel.raised,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
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
                    Text(
                      isToday
                          ? 'Today'
                          : DateFormat('EEE d MMM').format(selected.day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.overline(context).copyWith(
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedAmount(
                        value: selected.expenseMinor.toDouble(),
                        duration: AppMotion.base,
                        format: (v) => Formatters.currency.format(v),
                        style: AppText.displayAmount(context, size: 28),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _WindowToggle(
                days: _windowDays,
                options: _windows,
                onChanged: _setWindow,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_windowDays-day total ${Formatters.currency.format(windowTotal)}'
                  '${windowIncome > 0 ? ' · in ${Formatters.currency.format(windowIncome)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasSpending) ...[
            _chart(context, maxAmount),
            const SizedBox(height: AppSpacing.sm),
            _axisLabels(context),
          ] else
            _emptyChart(context),
        ],
      ),
    );
  }

  Widget _chart(BuildContext context, double maxAmount) {
    return SizedBox(
      key: const Key('spending-trend-chart'),
      height: 150,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: Listenable.merge([_entrance, _values, _selection]),
            builder: (context, _) {
              final values = _visibleAmounts();
              final entrance = _reduceMotion
                  ? 1.0
                  : AppMotion.emphasized
                      .transform(_entrance.value.clamp(0.0, 1.0));
              final t =
                  AppMotion.easeOut.transform(_selection.value.clamp(0.0, 1.0));
              final geometry = _TrendGeometry(
                size: Size(width, 150),
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
                      onTapDown: (details) =>
                          _select(geometry.indexAt(details.localPosition.dx)),
                      onHorizontalDragStart: (details) =>
                          _select(geometry.indexAt(details.localPosition.dx)),
                      onHorizontalDragUpdate: (details) =>
                          _select(geometry.indexAt(details.localPosition.dx)),
                      child: CustomPaint(
                        painter: _TrendPainter(
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
                  // The bubble is placed from its *measured* size. It used to be
                  // centred on the point and clamped by its centre to 34dp from
                  // the edge, which only holds for a bubble under 68dp wide. A
                  // wider one (a longer figure, or larger text) had its right
                  // end cut flat by the card's clip; seen in a 360dp / 1.3x
                  // dark capture.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: entrance.clamp(0.0, 1.0),
                        child: CustomSingleChildLayout(
                          delegate: _BubbleLayout(marker: marker),
                          // A figure wider than the whole card (a very large
                          // amount at 2x text) scales down instead of clipping.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _ValueBubble(
                              label: '${DateFormat('d MMM').format(
                                t < 0.5
                                    ? _days[_selectionFrom].day
                                    : _days[_selectionTo].day,
                              )} · ${Formatters.currency.format(bubbleValue)}',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Screen-reader targets. Seven days get one node each; a
                  // 30-day window would be 30 nodes, so it exposes a single
                  // summary node instead (see [_semanticsSummary]).
                  if (_days.length <= 10)
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

  Widget _axisLabels(BuildContext context) {
    final style = AppText.caption(context).copyWith(fontSize: 10);
    if (_days.length <= 10) {
      return Row(
        children: [
          for (var i = 0; i < _days.length; i++)
            Expanded(
              child: Semantics(
                label: DateFormat('EEEE').format(_days[i].day),
                selected: i == _selected,
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => _select(i),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      DateFormat('EEEEE').format(_days[i].day),
                      textAlign: TextAlign.center,
                      style: style.copyWith(
                        color: i == _selected
                            ? AppColors.textPrimary(context)
                            : AppColors.textTertiary(context),
                        fontWeight:
                            i == _selected ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    final first = _days.first.day;
    final middle = _days[_days.length ~/ 2].day;
    final last = _days.last.day;
    final fmt = DateFormat('d MMM');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(fmt.format(first), style: style),
        Text(fmt.format(middle), style: style),
        Text(fmt.format(last), style: style),
      ],
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
            'No spending in the last $_windowDays days',
            style: AppText.bodySmall(context),
          ),
        ],
      ),
    );
  }

  String _semanticsLabel(_DayPoint point) {
    final weekday = DateFormat('EEEE').format(point.day);
    final date = DateFormat('d MMM').format(point.day);
    final amount = Formatters.currency.format(point.expenseMinor);
    return '$weekday, $date, $amount';
  }
}

// ── Window toggle ─────────────────────────────────────────────────────────────

/// A compact segmented control for the chart window.
///
/// The selected segment is a filled pill that animates between positions; the
/// control is local to the card, so switching windows never rebuilds the
/// dashboard. Under reduced motion the pill jumps without travelling.
class _WindowToggle extends StatelessWidget {
  final int days;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const _WindowToggle({
    required this.days,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            Semantics(
              button: true,
              selected: option == days,
              label: '$option day trend',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(option),
                child: AnimatedContainer(
                  duration: AppMotion.respect(context, AppMotion.fast),
                  curve: AppMotion.easeOut,
                  constraints:
                      const BoxConstraints(minHeight: 32, minWidth: 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: option == days
                        ? (dark
                            ? Colors.white.withValues(alpha: 0.12)
                            : AppColors.brand.withValues(alpha: 0.14))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '${option}D',
                    style: AppText.weight(
                      AppText.label(context),
                      option == days ? FontWeight.w800 : FontWeight.w600,
                    ).copyWith(
                      fontSize: 11,
                      color: option == days
                          ? AppColors.textPrimary(context)
                          : AppColors.textTertiary(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Value bubble ─────────────────────────────────────────────────────────────

/// Centres the bubble on [marker], then slides it back inside the card.
///
/// Horizontal: the bubble's own width decides how far it may travel, so the
/// right end of a wide figure can never leave the card. Vertical: 36dp above the
/// point, kept inside the 150dp plot as before.
class _BubbleLayout extends SingleChildLayoutDelegate {
  final Offset marker;

  const _BubbleLayout({required this.marker});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(constraints.maxWidth, constraints.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = (size.width - childSize.width).clamp(0.0, double.infinity);
    final left = (marker.dx - childSize.width / 2).clamp(0.0, maxLeft);
    final top = (marker.dy - 36).clamp(0.0, 112.0);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_BubbleLayout old) => old.marker != marker;
}

class _ValueBubble extends StatelessWidget {
  final String label;

  const _ValueBubble({required this.label});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final bubble = dark ? Colors.white : AppColors.navyDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bubble,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppText.amount(
          context,
          size: 11,
          weight: FontWeight.w700,
          color: AppColors.resolveInk(
            dark ? AppColors.navyDeep : Colors.white,
            bubble,
          ),
        ),
      ),
    );
  }
}

// ── Geometry ─────────────────────────────────────────────────────────────────

/// Pixel positions for one series of [values.length] points.
///
/// Shared by the painter, the bubble and the hit test so a tap always selects
/// the point under the finger.
class _TrendGeometry {
  static const double _top = 14;
  static const double _bottom = 8;
  static const double _side = 10;

  final Size size;
  final List<double> values;
  final double maxAmount;

  const _TrendGeometry({
    required this.size,
    required this.values,
    required this.maxAmount,
  });

  int get count => values.length;

  double get _plotTop => _top;
  double get _plotBottom => size.height - _bottom;
  double get _plotLeft => _side;
  double get _plotRight => size.width - _side;
  double get _plotHeight => _plotBottom - _plotTop;
  double get _step => count <= 1 ? 0 : (_plotRight - _plotLeft) / (count - 1);

  /// Headroom keeps the highest point off the top edge and leaves room for the
  /// selected marker's halo.
  double get _scale => maxAmount <= 0 ? 1 : maxAmount * 1.14;

  Offset pointAt(int index) {
    final i = index.clamp(0, count - 1);
    final value = i < values.length ? values[i] : 0.0;
    final x = _plotLeft + _step * i;
    final y = _plotBottom - (value / _scale).clamp(0.0, 1.0) * _plotHeight;
    return Offset(x, y);
  }

  int indexAt(double dx) {
    if (_step <= 0) return 0;
    return ((dx - _plotLeft) / _step).round().clamp(0, count - 1);
  }

  List<Offset> get points => [for (var i = 0; i < count; i++) pointAt(i)];
}

// ── Painter ──────────────────────────────────────────────────────────────────

class _TrendPainter extends CustomPainter {
  final _TrendGeometry geometry;
  final double progress;
  final Color line;
  final LinearGradient area;
  final Color grid;
  final Color surface;
  final Color accent;
  final Offset? marker;

  _TrendPainter({
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
    if (points.isEmpty) return;
    final curve = _smooth(points, rect);

    final reveal = (1 - progress).clamp(0.0, 1.0);
    final clipWidth = size.width * (size.width <= 0 ? 1 : progress);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clipWidth, size.height));

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

    canvas.drawPath(
      curve,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Points appear as the drawing head passes them. A 30-day window would be
    // 30 dots, so only short windows draw them.
    if (points.length <= 10) {
      for (var i = 0; i < points.length; i++) {
        final threshold = i / (points.length - 1);
        if (progress + 1e-6 < threshold) continue;
        _dot(canvas, points[i]);
      }
    }

    canvas.restore();

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
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.progress != progress ||
      old.marker != marker ||
      old.line != line ||
      old.grid != grid ||
      old.surface != surface ||
      !identical(old.geometry.values, geometry.values) ||
      old.geometry.maxAmount != geometry.maxAmount;
}

class _DayPoint {
  final DateTime day;
  int expenseMinor = 0;
  int incomeMinor = 0;

  _DayPoint({required this.day});
}
