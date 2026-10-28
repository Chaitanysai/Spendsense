import 'package:intl/intl.dart';

class MoneyFormatter {
  const MoneyFormatter();

  String format(num amountMinor) {
    final minor = amountMinor.round();
    final negative = minor < 0;
    final absolute = minor.abs();
    final rupees = absolute ~/ 100;
    final paise = absolute % 100;
    final grouped = NumberFormat.decimalPattern('en_IN').format(rupees);
    final value = paise == 0
        ? '₹$grouped'
        : '₹$grouped.${paise.toString().padLeft(2, '0')}';
    return negative ? '− $value' : value;
  }
}

class Formatters {
  static const currency = MoneyFormatter();
  static const fullCurrency = MoneyFormatter();
  static String date(DateTime d) => DateFormat('MMM dd, yyyy').format(d);
  static String time(DateTime d) => DateFormat('hh:mm a').format(d);

  /// Time-of-day greeting for the Home header: morning before noon, afternoon
  /// until 17:00, evening after that.
  static String greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// How long ago [moment] was, in the compact form a status pill can carry.
  ///
  /// A bare time-of-day ("09:30 AM") cannot tell the user whether a sync
  /// happened four minutes or four days ago, which is exactly what a sync
  /// affordance needs to communicate. Anything older than a week falls back to
  /// a date, because "9d ago" is no more useful than the date itself.
  ///
  /// [now] is injectable so the output is testable without a clock.
  static String relativeTime(DateTime moment, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final delta = reference.difference(moment);

    // A clock that moved backwards, or a sync seconds in the future, reads as
    // "just now" rather than a negative interval.
    if (delta.inSeconds < 60) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return date(moment);
  }
}
