import '../models/recurring_plan.dart';
import '../models/transaction_model.dart';
import '../utils/period_math.dart';
import 'recurring_detector_service.dart';

/// What a bill row is telling the user.
enum BillState {
  /// A payment was found for this cycle.
  paid,

  /// The due date has passed and no payment was matched.
  overdue,

  /// Due within the next few days.
  dueSoon,

  /// Due later, or no date pressure yet.
  upcoming,

  /// A detected pattern the user has not confirmed as a bill yet.
  needsReview,
}

extension BillStateX on BillState {
  String get label => switch (this) {
        BillState.paid => 'Paid',
        BillState.overdue => 'Overdue',
        BillState.dueSoon => 'Due soon',
        BillState.upcoming => 'Upcoming',
        BillState.needsReview => 'Needs review',
      };
}

/// One row on the Bills screen.
///
/// A [plan] is a confirmed, persisted bill. A [suggestion] is a detected
/// recurring pattern that the user has not confirmed; it is never persisted and
/// never counted as a bill until "Track" creates a plan.
class BillView {
  final RecurringPlan? plan;
  final RecurringTransaction? suggestion;
  final String title;
  final String category;
  final int amountMinor;
  final DateTime? dueDate;
  final BillState state;
  final TransactionModel? matchedPayment;
  final List<TransactionModel> history;

  const BillView({
    required this.title,
    required this.category,
    required this.amountMinor,
    required this.state,
    this.plan,
    this.suggestion,
    this.dueDate,
    this.matchedPayment,
    this.history = const [],
  });

  bool get isSuggestion => suggestion != null;
  bool get isConfirmed => plan != null;
}

/// Conservative bill derivation over data SpendSense already has.
///
/// It deliberately does not persist anything: running it twice over the same
/// transactions produces the same rows, so repeated SMS syncs cannot create
/// duplicate bills or duplicate payments.
///
/// A reminder is never treated as a payment. Only stored *expense*
/// transactions (a successful payment the parser already confirmed) can mark a
/// bill paid; there is no code path from reminder text to [BillState.paid].
class BillDetectionService {
  /// Window after a due date in which a transaction still counts as paying it.
  static const int matchDaysAfterDue = 3;

  /// Window before a due date in which a transaction counts as paying early.
  static const int matchDaysBeforeDue = 10;

  /// Amount tolerance: 2%, but at least ₹1, so rounding in an SMS never hides
  /// a match.
  static const double amountTolerance = 0.02;

  const BillDetectionService();

  List<BillView> detect({
    required List<RecurringPlan> plans,
    required List<TransactionModel> transactions,
    required DateTime today,
  }) {
    final day = PeriodMath.dateOnly(today);
    final tracked = transactions.where((t) => !t.isExcluded).toList();

    final views = <BillView>[];
    for (final plan in plans) {
      views.add(_viewForPlan(plan, tracked, day));
    }

    // Suggestions are only offered for patterns that already look recurring and
    // are not represented by a confirmed plan.
    final covered = plans
        .map((p) => _normalize('${p.title} ${p.category}'))
        .toSet();
    final detected = RecurringDetectorService()
        .detectRecurring(tracked)
        .where((r) => r.frequency != RecurrenceFrequency.irregular)
        .where((r) => r.occurrenceCount >= 2)
        .where((r) => !covered.contains(_normalize('${r.merchant} ${r.category}')))
        .toList();

    for (final r in detected) {
      final due = estimateNextDue(r);
      if (due == null) continue;
      views.add(BillView(
        suggestion: r,
        title: r.merchant.isEmpty ? r.category : r.merchant,
        category: r.category,
        amountMinor: r.averageAmountMinor,
        dueDate: due,
        state: BillState.needsReview,
        history: _historyFor(r.transactions),
      ));
    }

    // Actionable bills first, then suggestions, then paid/quiet ones.
    const order = {
      BillState.overdue: 0,
      BillState.dueSoon: 1,
      BillState.upcoming: 2,
      BillState.needsReview: 3,
      BillState.paid: 4,
    };
    views.sort((a, b) {
      final byState = order[a.state]!.compareTo(order[b.state]!);
      if (byState != 0) return byState;
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad == null && bd == null) return a.title.compareTo(b.title);
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return views;
  }

  BillView _viewForPlan(
    RecurringPlan plan,
    List<TransactionModel> tracked,
    DateTime day,
  ) {
    final matches = tracked
        .where((t) => t.type == TransactionType.expense)
        .where((t) => _matches(plan, t))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final days = plan.daysUntilDue(day);
    final match = matches.isEmpty ? null : matches.first;

    // Only a matched payment inside this cycle's window marks the bill paid.
    // "Inside" is deliberately asymmetric: a payment may arrive a little early
    // or shortly after the due date, never months away.
    final cycleMatch = match != null && _withinWindow(plan, match, day);

    final state = cycleMatch
        ? BillState.paid
        : days < 0
            ? BillState.overdue
            : days <= 3
                ? BillState.dueSoon
                : BillState.upcoming;

    return BillView(
      plan: plan,
      title: plan.title,
      category: plan.category,
      amountMinor: plan.amountMinor,
      dueDate: plan.nextDue,
      state: state,
      matchedPayment: cycleMatch ? match : null,
      history: _historyFor(matches),
    );
  }

  bool _matches(RecurringPlan plan, TransactionModel t) {
    if (t.category.toLowerCase() != plan.category.toLowerCase()) return false;
    final tolerance =
        (plan.amountMinor * amountTolerance).round().clamp(100, 1 << 30);
    if ((t.amountMinor - plan.amountMinor).abs() > tolerance) return false;
    // Merchant/title overlap is a second, cheap signal; an empty plan title
    // cannot veto a category+amount match.
    final title = plan.title.toLowerCase().trim();
    if (title.isEmpty) return true;
    final merchant = t.merchant.toLowerCase();
    return merchant.contains(title) ||
        title.contains(merchant) ||
        _normalize(merchant) == _normalize(title);
  }

  bool _withinWindow(RecurringPlan plan, TransactionModel t, DateTime day) {
    final due = PeriodMath.dateOnly(plan.nextDue);
    final start = PeriodMath.addDays(due, -matchDaysBeforeDue);
    final end = PeriodMath.addDays(due, matchDaysAfterDue);
    final date = PeriodMath.dateOnly(t.date);
    // A payment must not be older than one full cycle before this due date,
    // otherwise last month's payment would keep marking this one paid.
    final cycleStart = _previousDue(plan);
    final earliest = cycleStart.isAfter(start) ? cycleStart : start;
    return !date.isBefore(earliest) && !date.isAfter(end);
  }

  DateTime _previousDue(RecurringPlan plan) {
    switch (plan.frequency) {
      case PlanFrequency.weekly:
        return PeriodMath.addDays(plan.nextDue, -7);
      case PlanFrequency.biWeekly:
        return PeriodMath.addDays(plan.nextDue, -14);
      case PlanFrequency.monthly:
        return _addMonths(plan.nextDue, -1);
      case PlanFrequency.quarterly:
        return _addMonths(plan.nextDue, -3);
      case PlanFrequency.yearly:
        return _addMonths(plan.nextDue, -12);
    }
  }

  DateTime? estimateNextDue(RecurringTransaction r) {
    final last = PeriodMath.dateOnly(r.lastOccurrence);
    switch (r.frequency) {
      case RecurrenceFrequency.daily:
        return PeriodMath.addDays(last, 1);
      case RecurrenceFrequency.weekly:
        return PeriodMath.addDays(last, 7);
      case RecurrenceFrequency.biWeekly:
        return PeriodMath.addDays(last, 14);
      case RecurrenceFrequency.monthly:
        return _addMonths(last, 1);
      case RecurrenceFrequency.irregular:
        return null;
    }
  }

  List<TransactionModel> _historyFor(List<TransactionModel> txns) {
    final sorted = [...txns]..sort((a, b) => b.date.compareTo(a.date));
    return sorted.take(6).toList();
  }

  /// A stable id for the plan created from a suggestion, so tracking the same
  /// pattern twice is a no-op instead of a duplicate bill.
  static String planIdFor(RecurringTransaction r) =>
      'auto:${_normalize('${r.merchant}|${r.category}')}';

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static DateTime _addMonths(DateTime from, int months) {
    final total = from.year * 12 + (from.month - 1) + months;
    final year = total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = from.day > lastDay ? lastDay : from.day;
    return DateTime(year, month, day);
  }
}
