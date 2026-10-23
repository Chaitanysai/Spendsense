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
}
