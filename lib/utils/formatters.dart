import 'package:intl/intl.dart';

class Formatters {
  static final currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final fullCurrency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
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
