import 'package:intl/intl.dart';

class Formatters {
  static final currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final fullCurrency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static String date(DateTime d) => DateFormat('MMM dd, yyyy').format(d);
  static String time(DateTime d) => DateFormat('hh:mm a').format(d);
}
