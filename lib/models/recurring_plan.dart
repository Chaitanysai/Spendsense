import '../utils/money_parser.dart';
import '../utils/period_math.dart';

/// How often a planned bill repeats.
enum PlanFrequency { weekly, biWeekly, monthly, quarterly, yearly }

extension PlanFrequencyX on PlanFrequency {
  String get label => switch (this) {
        PlanFrequency.weekly => 'Weekly',
        PlanFrequency.biWeekly => 'Every 2 weeks',
        PlanFrequency.monthly => 'Monthly',
        PlanFrequency.quarterly => 'Every 3 months',
        PlanFrequency.yearly => 'Yearly',
      };

  /// This plan's amount expressed per month, in integer paise, rounded to the
  /// nearest paise (half up). Conversion factors are exact fractions:
  /// weekly = 52/12 = 13/3, bi-weekly = 26/12 = 13/6, quarterly = 1/3,
  /// yearly = 1/12.
  int monthlyEquivalentMinor(int amountMinor) {
    if (amountMinor <= 0) return 0;
    switch (this) {
      case PlanFrequency.weekly:
        return roundPaiseDivision(amountMinor * 13, 3);
      case PlanFrequency.biWeekly:
        return roundPaiseDivision(amountMinor * 13, 6);
      case PlanFrequency.monthly:
        return amountMinor;
      case PlanFrequency.quarterly:
        return roundPaiseDivision(amountMinor, 3);
      case PlanFrequency.yearly:
        return roundPaiseDivision(amountMinor, 12);
    }
  }
}

/// A user-planned repeating payment. It is a *plan*, not a transaction:
/// creating, editing or "marking paid" never writes to the ledger, so a plan
/// can never produce a duplicate real transaction.
class RecurringPlan {
  /// Largest accepted planned amount (₹100 crore) — a sanity bound that also
  /// keeps every derived multiplication far from integer overflow.
  static const int maxAmountMinor = 100000000000;

  final String id;
  final String title;
  final String category;
  final int amountMinor;
  final PlanFrequency frequency;

  /// Next due date, date-only (local calendar day).
  final DateTime nextDue;

  /// Day of month the plan is anchored to, so a Jan 31 bill returns to the 31st
  /// after a short month instead of drifting to the 28th forever.
  final int anchorDay;

  /// Transaction this plan was created from, if any (reference only).
  final String? sourceTransactionId;

  const RecurringPlan({
    required this.id,
    required this.title,
    required this.category,
    required this.amountMinor,
    required this.frequency,
    required this.nextDue,
    required this.anchorDay,
    this.sourceTransactionId,
  });

  factory RecurringPlan.create({
    required String id,
    required String title,
    required String category,
    required int amountMinor,
    required PlanFrequency frequency,
    required DateTime nextDue,
    String? sourceTransactionId,
  }) {
    final due = PeriodMath.dateOnly(nextDue);
    return RecurringPlan(
      id: id,
      title: title.trim(),
      category: category.trim(),
      amountMinor: amountMinor,
      frequency: frequency,
      nextDue: due,
      anchorDay: due.day,
      sourceTransactionId: sourceTransactionId,
    );
  }

  /// Throws [FormatException] for an invalid plan.
  void validate() {
    if (id.isEmpty) throw const FormatException('Plan id is empty.');
    if (title.trim().isEmpty || title.length > 80) {
      throw const FormatException('Plan name must be 1-80 characters.');
    }
    if (category.trim().isEmpty) {
      throw const FormatException('Plan category is empty.');
    }
    if (amountMinor <= 0 || amountMinor > maxAmountMinor) {
      throw const FormatException('Plan amount is out of range.');
    }
    if (anchorDay < 1 || anchorDay > 31) {
      throw const FormatException('Plan anchor day is invalid.');
    }
  }

  int get monthlyEquivalentMinor =>
      frequency.monthlyEquivalentMinor(amountMinor);

  /// Whole days from [today] to [nextDue]; negative when overdue.
  int daysUntilDue(DateTime today) {
    final a = DateTime.utc(today.year, today.month, today.day);
    final b = DateTime.utc(nextDue.year, nextDue.month, nextDue.day);
    return b.difference(a).inDays;
  }

  /// The due date following [nextDue]. Does not touch any transaction.
  DateTime get followingDue {
    switch (frequency) {
      case PlanFrequency.weekly:
        return PeriodMath.addDays(nextDue, 7);
      case PlanFrequency.biWeekly:
        return PeriodMath.addDays(nextDue, 14);
      case PlanFrequency.monthly:
        return _addMonths(nextDue, 1, anchorDay);
      case PlanFrequency.quarterly:
        return _addMonths(nextDue, 3, anchorDay);
      case PlanFrequency.yearly:
        return _addMonths(nextDue, 12, anchorDay);
    }
  }

  /// The plan moved to its following due date, keeping its anchor day so a
  /// month-end bill returns to the 31st after a short month. Only reschedules;
  /// never touches the ledger.
  RecurringPlan advanced() => RecurringPlan(
        id: id,
        title: title,
        category: category,
        amountMinor: amountMinor,
        frequency: frequency,
        nextDue: followingDue,
        anchorDay: anchorDay,
        sourceTransactionId: sourceTransactionId,
      );

  /// The same plan rolled forward to its first due date on or after [today].
  /// Used to prefill a plan made from an old transaction. Bounded so a corrupt
  /// date can never loop forever.
  RecurringPlan rolledForwardTo(DateTime today) {
    var plan = this;
    final floor = PeriodMath.dateOnly(today);
    for (var i = 0; i < 5000 && plan.nextDue.isBefore(floor); i++) {
      plan = plan.advanced();
    }
    return plan;
  }

  RecurringPlan copyWith({
    String? title,
    String? category,
    int? amountMinor,
    PlanFrequency? frequency,
    DateTime? nextDue,
  }) {
    final due = nextDue == null ? this.nextDue : PeriodMath.dateOnly(nextDue);
    return RecurringPlan(
      id: id,
      title: (title ?? this.title).trim(),
      category: (category ?? this.category).trim(),
      amountMinor: amountMinor ?? this.amountMinor,
      frequency: frequency ?? this.frequency,
      nextDue: due,
      anchorDay: nextDue == null ? anchorDay : due.day,
      sourceTransactionId: sourceTransactionId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'amountMinor': amountMinor,
        'frequency': frequency.name,
        'nextDue': _ymd(nextDue),
        'anchorDay': anchorDay,
        if (sourceTransactionId != null)
          'sourceTransactionId': sourceTransactionId,
      };

  /// Strict decoder: any missing or ill-typed field throws [FormatException]
  /// instead of being replaced by a guess.
  factory RecurringPlan.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('Plan is not an object.');
    final id = raw['id'];
    final title = raw['title'];
    final category = raw['category'];
    final amount = raw['amountMinor'];
    final frequency = raw['frequency'];
    final due = raw['nextDue'];
    final anchor = raw['anchorDay'];
    final source = raw['sourceTransactionId'];
    if (id is! String ||
        title is! String ||
        category is! String ||
        amount is! int ||
        frequency is! String ||
        due is! String ||
        anchor is! int ||
        (source != null && source is! String)) {
      throw const FormatException('Plan has missing or invalid fields.');
    }
    final freq = PlanFrequency.values.where((f) => f.name == frequency);
    final parsed = DateTime.tryParse(due);
    if (freq.isEmpty || parsed == null) {
      throw const FormatException('Plan frequency or date is invalid.');
    }
    final plan = RecurringPlan(
      id: id,
      title: title,
      category: category,
      amountMinor: amount,
      frequency: freq.first,
      nextDue: DateTime(parsed.year, parsed.month, parsed.day),
      anchorDay: anchor,
      sourceTransactionId: source as String?,
    );
    plan.validate();
    return plan;
  }

  static String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Adds [months] calendar months, landing on [anchorDay] or the last day of a
  /// shorter month.
  static DateTime _addMonths(DateTime from, int months, int anchorDay) {
    final total = from.year * 12 + (from.month - 1) + months;
    final year = total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, anchorDay > lastDay ? lastDay : anchorDay);
  }
}
