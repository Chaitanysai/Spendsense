import '../models/recurring_plan.dart';
import '../models/transaction_model.dart';
import '../utils/period_math.dart';
import 'bill_classifier.dart';

/// What a bill row is telling the user. There is deliberately no
/// "needs review" state: ambiguous transactions stay ordinary and never ask the
/// user a question.
enum BillState { paid, overdue, dueSoon, upcoming }

extension BillStateX on BillState {
  String get label => switch (this) {
        BillState.paid => 'Paid',
        BillState.overdue => 'Overdue',
        BillState.dueSoon => 'Due soon',
        BillState.upcoming => 'Upcoming',
      };
}

/// An automatically detected obligation. It is derived from existing
/// transactions and never persisted, so re-running detection is idempotent.
class AutoBill {
  final String billerKey;
  final String title;
  final String category;
  final int expectedAmountMinor;
  final DateTime dueDate;
  final BillState state;
  final double confidence;
  final bool isRecurring;
  final int occurrenceCount;
  final BillKind kind;
  final TransactionModel? lastPayment;
  final List<TransactionModel> history;

  const AutoBill({
    required this.billerKey,
    required this.title,
    required this.category,
    required this.expectedAmountMinor,
    required this.dueDate,
    required this.state,
    required this.confidence,
    required this.isRecurring,
    required this.occurrenceCount,
    required this.kind,
    required this.lastPayment,
    required this.history,
  });
}

/// One row on the Bills screen. A [plan] is user-confirmed and persisted; an
/// [autoBill] is derived automatically from the ledger and never prompts.
class BillView {
  final RecurringPlan? plan;
  final AutoBill? autoBill;
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
    this.autoBill,
    this.dueDate,
    this.matchedPayment,
    this.history = const [],
  });

  bool get isConfirmed => plan != null;
  bool get isAutoDetected => autoBill != null;
  String? get billerKey => autoBill?.billerKey;
  double? get confidence => autoBill?.confidence;
}

/// Conservative bill derivation over data SpendSense already has.
///
/// * Plans remain the persisted, user-confirmed source of truth.
/// * Auto bills are derived deterministically from bill-specific transactions:
///   strong single evidence becomes a paid bill, and a reliable monthly /
///   weekly / quarterly / yearly pattern becomes an upcoming or overdue bill.
/// * Routine groceries, food delivery, fuel, shopping, transfers and cash are
///   excluded by [BillClassifier] before any grouping happens.
/// * Reminder-only text never marks a bill paid.
/// * One payment can be assigned to at most one plan, and each plan to at most
///   one payment.
class BillDetectionService {
  static const int matchDaysAfterDue = 3;
  static const int matchDaysBeforeDue = 10;
  static const double amountTolerance = 0.02;

  const BillDetectionService();

  List<BillView> detect({
    required List<RecurringPlan> plans,
    required List<TransactionModel> transactions,
    required DateTime today,
    Set<String> hiddenBillKeys = const {},
  }) {
    final day = PeriodMath.dateOnly(today);
    final tracked = transactions
        .where((t) => !t.isExcluded && t.type == TransactionType.expense)
        .toList();

    final matches = _matchPlans(plans, tracked, day);
    final views = <BillView>[
      for (final plan in plans)
        _viewForPlan(plan, tracked, day, matches[plan.id]),
    ];

    final planMatchedTxIds = matches.values.map((t) => t.id).toSet();
    final autoViews = _autoBills(
      plans: plans,
      transactions: tracked,
      today: day,
      hiddenBillKeys: hiddenBillKeys,
      planMatchedTxIds: planMatchedTxIds,
    );
    views.addAll(autoViews);

    const order = {
      BillState.overdue: 0,
      BillState.dueSoon: 1,
      BillState.upcoming: 2,
      BillState.paid: 3,
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

  // ── Confirmed plans ───────────────────────────────────────────────────────

  BillView _viewForPlan(
    RecurringPlan plan,
    List<TransactionModel> tracked,
    DateTime day,
    TransactionModel? matched,
  ) {
    final days = plan.daysUntilDue(day);
    final match =
        matched != null && _withinWindow(plan, matched, day) ? matched : null;

    final state = match != null
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
      matchedPayment: match,
      history: _historyForPlan(plan, tracked),
    );
  }

  /// Reassigns at most one strong payment per plan and at most one plan per
  /// payment. A weak category-only coincidence is never enough.
  Map<String, TransactionModel> _matchPlans(
    List<RecurringPlan> plans,
    List<TransactionModel> tracked,
    DateTime day,
  ) {
    final candidates = <_PlanCandidate>[];
    for (final plan in plans) {
      final sourceReference = _sourceReference(plan, tracked);
      for (final tx in tracked) {
        if (BillClassifier.isReminderOnly(tx.originalSms)) continue;
        if (!_withinWindow(plan, tx, day)) continue;
        final amountGap = (tx.amountMinor - plan.amountMinor).abs();
        final tolerance =
            (plan.amountMinor * amountTolerance).round().clamp(100, 1 << 30);
        if (amountGap > tolerance) continue;
        final score = _score(plan, tx, sourceReference, amountGap);
        if (!score.strong) continue;
        candidates.add(_PlanCandidate(plan.id, tx, score.total, amountGap));
      }
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byAmount = a.amountGap.compareTo(b.amountGap);
      if (byAmount != 0) return byAmount;
      return b.payment.date.compareTo(a.payment.date);
    });

    final matchedPlans = <String>{};
    final usedPayments = <String>{};
    final out = <String, TransactionModel>{};
    for (final candidate in candidates) {
      if (matchedPlans.contains(candidate.planId)) continue;
      if (usedPayments.contains(candidate.payment.id)) continue;
      matchedPlans.add(candidate.planId);
      usedPayments.add(candidate.payment.id);
      out[candidate.planId] = candidate.payment;
    }
    return out;
  }

  _MatchScore _score(
    RecurringPlan plan,
    TransactionModel tx,
    String? sourceReference,
    int amountGap,
  ) {
    var identity = 0.0;
    var hasIdentity = false;

    final ref = tx.reference?.trim();
    if (sourceReference != null &&
        sourceReference.isNotEmpty &&
        ref != null &&
        ref.isNotEmpty &&
        _normalize(ref) == _normalize(sourceReference)) {
      identity = 0.45;
      hasIdentity = true;
    }

    final title = _normalize(plan.title);
    final merchant = _normalize(tx.merchant);
    if (!hasIdentity && title.isNotEmpty && merchant.isNotEmpty) {
      if (title == merchant ||
          merchant.contains(title) ||
          title.contains(merchant)) {
        identity = 0.40;
        hasIdentity = true;
      } else {
        final titleTokens = _meaningfulTokens(title);
        final merchantTokens = _meaningfulTokens(merchant);
        final shared = titleTokens.intersection(merchantTokens);
        if (shared.isNotEmpty) {
          identity = shared.length >= 2 ? 0.36 : 0.28;
          hasIdentity = true;
        }
      }
    }

    // Category + amount alone is NOT identity: an unrelated merchant with the
    // same amount inside the window must never mark a plan paid. A manual plan
    // whose title does not resemble the payment remains unmatched (the user can
    // still use Mark paid).
    final tolerance =
        (plan.amountMinor * amountTolerance).round().clamp(100, 1 << 30);
    final amountScore = amountGap == 0
        ? 0.35
        : amountGap <= (plan.amountMinor * 0.005).round().clamp(100, 1 << 30)
            ? 0.30
            : amountGap <= tolerance
                ? 0.22
                : 0.0;

    final due = PeriodMath.dateOnly(plan.nextDue);
    final date = PeriodMath.dateOnly(tx.date);
    final daysFromDue = date.difference(due).inDays.abs();
    final dateScore = daysFromDue == 0
        ? 0.20
        : daysFromDue <= 3
            ? 0.16
            : 0.10;

    final total = identity + amountScore + dateScore;
    return _MatchScore(total: total, strong: hasIdentity && total >= 0.65);
  }

  List<TransactionModel> _historyForPlan(
    RecurringPlan plan,
    List<TransactionModel> tracked,
  ) {
    final sourceReference = _sourceReference(plan, tracked);
    final matches = <TransactionModel>[];
    for (final tx in tracked) {
      if (BillClassifier.isReminderOnly(tx.originalSms)) continue;
      final tolerance =
          (plan.amountMinor * amountTolerance).round().clamp(100, 1 << 30);
      if ((tx.amountMinor - plan.amountMinor).abs() > tolerance) continue;
      if (!_score(plan, tx, sourceReference,
              (tx.amountMinor - plan.amountMinor).abs())
          .strong) {
        continue;
      }
      matches.add(tx);
    }
    return _historyFor(matches);
  }

  String? _sourceReference(RecurringPlan plan, List<TransactionModel> tracked) {
    final id = plan.sourceTransactionId;
    if (id == null) return null;
    return tracked.where((t) => t.id == id).firstOrNull?.reference;
  }

  bool _withinWindow(RecurringPlan plan, TransactionModel t, DateTime day) {
    final due = PeriodMath.dateOnly(plan.nextDue);
    final start = PeriodMath.addDays(due, -matchDaysBeforeDue);
    final end = PeriodMath.addDays(due, matchDaysAfterDue);
    final date = PeriodMath.dateOnly(t.date);
    final cycleStart = _previousDue(plan);
    final earliest = cycleStart.isAfter(start) ? cycleStart : start;
    return !date.isBefore(earliest) && !date.isAfter(end);
  }

  // ── Automatic detection ───────────────────────────────────────────────────

  List<BillView> _autoBills({
    required List<RecurringPlan> plans,
    required List<TransactionModel> transactions,
    required DateTime today,
    required Set<String> hiddenBillKeys,
    required Set<String> planMatchedTxIds,
  }) {
    final groups = <String, _BillGroup>{};
    for (final tx in transactions) {
      if (planMatchedTxIds.contains(tx.id)) continue;
      final classification = const BillClassifier().classify(tx);
      if (classification.isOrdinary || classification.reminderOnly) continue;
      final group = groups.putIfAbsent(
        classification.billerKey,
        () => _BillGroup(
          key: classification.billerKey,
          label: classification.billerLabel,
          kind: classification.kind,
        ),
      );
      group.add(tx, classification);
    }

    final out = <BillView>[];
    for (final group in groups.values) {
      if (hiddenBillKeys.contains(group.key)) continue;
      final entries = group.deduplicated();
      if (entries.isEmpty) continue;
      if (_coveredByPlan(group, plans, entries)) continue;

      final latest = entries.last;
      final pattern = _pattern(entries);
      if (pattern != null) {
        final state = _stateForDue(pattern.nextDue, today);
        out.add(BillView(
          autoBill: AutoBill(
            billerKey: group.key,
            title: latest.classification.billerLabel,
            category: latest.transaction.category,
            expectedAmountMinor: latest.transaction.amountMinor,
            dueDate: pattern.nextDue,
            state: state,
            confidence: pattern.confidence,
            isRecurring: true,
            occurrenceCount: entries.length,
            kind: group.kind,
            lastPayment: latest.transaction,
            history: _historyFor(entries.reversed.map((e) => e.transaction)),
          ),
          title: latest.classification.billerLabel,
          category: latest.transaction.category,
          amountMinor: latest.transaction.amountMinor,
          dueDate: pattern.nextDue,
          state: state,
          matchedPayment: null,
          history: _historyFor(entries.reversed.map((e) => e.transaction)),
        ));
        continue;
      }

      // No reliable recurrence: only strong, bill-specific single evidence is
      // surfaced, and it is shown as an already-paid bill (never recurring).
      // A single generic "bill" mention is not specific enough. It can still
      // become a bill through a reliable recurring pattern above.
      final strong = entries
          .where((e) =>
              e.classification.evidence == BillEvidence.paidBill &&
              (e.classification.kind != BillKind.other ||
                  e.classification.confidence >= 0.8))
          .toList();
      if (strong.isEmpty) continue;
      final paid = strong.last;
      out.add(BillView(
        autoBill: AutoBill(
          billerKey: group.key,
          title: paid.classification.billerLabel,
          category: paid.transaction.category,
          expectedAmountMinor: paid.transaction.amountMinor,
          dueDate: paid.transaction.date,
          state: BillState.paid,
          confidence: paid.classification.confidence,
          isRecurring: false,
          occurrenceCount: entries.length,
          kind: group.kind,
          lastPayment: paid.transaction,
          history: _historyFor(entries.reversed.map((e) => e.transaction)),
        ),
        title: paid.classification.billerLabel,
        category: paid.transaction.category,
        amountMinor: paid.transaction.amountMinor,
        dueDate: paid.transaction.date,
        state: BillState.paid,
        matchedPayment: paid.transaction,
        history: _historyFor(entries.reversed.map((e) => e.transaction)),
      ));
    }
    return out;
  }

  _BillPattern? _pattern(List<_BillEntry> entries) {
    if (entries.length < 2) return null;
    final sorted = [...entries]
      ..sort((a, b) => a.transaction.date.compareTo(b.transaction.date));
    final intervals = <int>[];
    for (var i = 1; i < sorted.length; i++) {
      final days = PeriodMath.dateOnly(sorted[i].transaction.date)
          .difference(PeriodMath.dateOnly(sorted[i - 1].transaction.date))
          .inDays;
      if (days > 0) intervals.add(days);
    }
    if (intervals.isEmpty) return null;

    final sortedIntervals = [...intervals]..sort();
    final median = sortedIntervals[sortedIntervals.length ~/ 2];
    final allowance = median < 10 ? 3 : (median * 0.22).round();
    final consistent = intervals.every((d) => (d - median).abs() <= allowance);
    if (!consistent) return null;

    final int step;
    if (median >= 5 && median <= 9) {
      step = 7;
    } else if (median >= 12 && median <= 17) {
      step = 14;
    } else if (median >= 24 && median <= 38) {
      step = 30;
    } else if (median >= 80 && median <= 100) {
      step = 90;
    } else if (median >= 350 && median <= 380) {
      step = 365;
    } else {
      return null;
    }

    final amounts = sorted.map((e) => e.transaction.amountMinor).toList();
    final minAmount = amounts.reduce((a, b) => a < b ? a : b);
    final maxAmount = amounts.reduce((a, b) => a > b ? a : b);
    final average = amounts.fold<int>(0, (a, b) => a + b) ~/ amounts.length;
    final amountConsistent =
        (maxAmount - minAmount) <= (average * 0.25).round().clamp(100, 1 << 30);
    if (!amountConsistent) return null;

    final last = PeriodMath.dateOnly(sorted.last.transaction.date);
    final nextDue = _advance(last, step);
    final strength = entries
        .map((e) => e.classification.confidence)
        .reduce((a, b) => a > b ? a : b);
    final confidence = (0.72 +
            (sorted.length >= 3 ? 0.12 : 0.0) +
            (amountConsistent ? 0.05 : 0.0) +
            strength * 0.08)
        .clamp(0.0, 0.98)
        .toDouble();
    return _BillPattern(nextDue: nextDue, confidence: confidence);
  }

  BillState _stateForDue(DateTime due, DateTime today) {
    final days = PeriodMath.dateOnly(due).difference(today).inDays;
    if (days < 0) return BillState.overdue;
    if (days <= 3) return BillState.dueSoon;
    return BillState.upcoming;
  }

  bool _coveredByPlan(
    _BillGroup group,
    List<RecurringPlan> plans,
    List<_BillEntry> entries,
  ) {
    final groupLabel = _normalize(group.label);
    final groupTokens = _meaningfulTokens(groupLabel);
    final latestAmount = entries.last.transaction.amountMinor;
    final latestDate = PeriodMath.dateOnly(entries.last.transaction.date);
    for (final plan in plans) {
      final sourceId = plan.sourceTransactionId;
      if (sourceId != null &&
          entries.any((e) => e.transaction.id == sourceId)) {
        return true;
      }
      final title = _normalize(plan.title);
      if (title.isNotEmpty &&
          (title == groupLabel ||
              title.contains(groupLabel) ||
              groupLabel.contains(title))) {
        return true;
      }
      final shared = groupTokens.intersection(_meaningfulTokens(title));
      if (shared.isNotEmpty) return true;
      // Same category, near-identical amount and adjacent cycle: the manual
      // plan is the same obligation under a different label.
      final amountGap = (latestAmount - plan.amountMinor).abs();
      final tolerance = (plan.amountMinor * 0.05).round().clamp(100, 1 << 30);
      final dueGap =
          latestDate.difference(PeriodMath.dateOnly(plan.nextDue)).inDays.abs();
      if (plan.category.toLowerCase() ==
              entries.last.transaction.category.toLowerCase() &&
          amountGap <= tolerance &&
          dueGap <= 45) {
        return true;
      }
    }
    return false;
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  List<TransactionModel> _historyFor(Iterable<TransactionModel> txns) {
    final sorted = [...txns]..sort((a, b) => b.date.compareTo(a.date));
    return sorted.take(6).toList();
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static Set<String> _meaningfulTokens(String value) => {
        for (final token in _normalize(value).split(' '))
          if (token.length >= 4 &&
              !const {
                'bill',
                'bills',
                'payment',
                'payments',
                'paid',
                'autopay',
                'debit',
                'credit',
                'india',
                'bank',
                'limited',
                'services',
                'service',
                'account',
              }.contains(token))
            token,
      };

  DateTime _advance(DateTime from, int days) {
    if (days == 30) return _addMonths(from, 1);
    if (days == 90) return _addMonths(from, 3);
    if (days == 365) return _addMonths(from, 12);
    return PeriodMath.addDays(from, days);
  }

  static DateTime _addMonths(DateTime from, int months) {
    final total = from.year * 12 + (from.month - 1) + months;
    final year = total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = from.day > lastDay ? lastDay : from.day;
    return DateTime(year, month, day);
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
}

// ── Internal value types ────────────────────────────────────────────────────

class _MatchScore {
  final double total;
  final bool strong;
  const _MatchScore({required this.total, required this.strong});
}

class _PlanCandidate {
  final String planId;
  final TransactionModel payment;
  final double score;
  final int amountGap;
  const _PlanCandidate(this.planId, this.payment, this.score, this.amountGap);
}

class _BillEntry {
  final TransactionModel transaction;
  final BillClassification classification;
  const _BillEntry(this.transaction, this.classification);
}

class _BillGroup {
  final String key;
  final String label;
  final BillKind kind;
  final List<_BillEntry> _entries = [];

  _BillGroup({required this.key, required this.label, required this.kind});

  void add(TransactionModel tx, BillClassification classification) =>
      _entries.add(_BillEntry(tx, classification));

  List<_BillEntry> deduplicated() {
    final sorted = [..._entries]
      ..sort((a, b) => a.transaction.date.compareTo(b.transaction.date));
    final ids = <String>{};
    final signatures = <String>{};
    final out = <_BillEntry>[];
    for (final entry in sorted) {
      if (!ids.add(entry.transaction.id)) continue;
      final signature = [
        PeriodMath.dateOnly(entry.transaction.date).toIso8601String(),
        entry.transaction.amountMinor,
        entry.transaction.reference ?? '',
        BillClassifier.normalize(entry.transaction.merchant),
      ].join('|');
      if (!signatures.add(signature)) continue;
      out.add(entry);
    }
    return out;
  }
}

class _BillPattern {
  final DateTime nextDue;
  final double confidence;
  const _BillPattern({required this.nextDue, required this.confidence});
}
