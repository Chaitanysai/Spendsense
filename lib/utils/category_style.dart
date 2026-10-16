import 'package:flutter/material.dart';

/// Single source of truth for category presentation.
///
/// Replaces scattered emoji maps with a consistent Material icon + colour so
/// the UI stays coherent (the ui-ux-pro-max guidance flags emoji-as-icon).
class CategoryStyle {
  CategoryStyle._();

  static const Map<String, IconData> _icons = {
    'Food': Icons.restaurant_rounded,
    'Shopping': Icons.shopping_bag_rounded,
    'Fuel': Icons.local_gas_station_rounded,
    'Travel': Icons.directions_car_rounded,
    'Bills': Icons.receipt_long_rounded,
    'Transfer': Icons.swap_horiz_rounded,
    'Cash': Icons.payments_rounded,
    'Entertainment': Icons.movie_rounded,
    'Health': Icons.favorite_rounded,
    'Investment': Icons.trending_up_rounded,
    'UPI': Icons.qr_code_rounded,
    'Other': Icons.category_rounded,
    'Others': Icons.category_rounded,
    'Income': Icons.savings_rounded,
  };

  static const Map<String, Color> _colors = {
    'Food': Color(0xFFFF7A1A),
    'Shopping': Color(0xFFC81E3A),
    'Fuel': Color(0xFFE23A2E),
    'Travel': Color(0xFF5B6B8C),
    'Bills': Color(0xFFF0432B),
    'Transfer': Color(0xFF12B76A),
    'Cash': Color(0xFF12B76A),
    'Entertainment': Color(0xFFFFB020),
    'Health': Color(0xFFE8A0A8),
    'Investment': Color(0xFFB3123A),
    'UPI': Color(0xFFC81E3A),
    'Other': Color(0xFF8A7A77),
    'Others': Color(0xFF8A7A77),
    'Income': Color(0xFF12B76A),
  };

  static IconData icon(String category) =>
      _icons[category] ?? Icons.account_balance_wallet_rounded;

  static Color color(String category) =>
      _colors[category] ?? const Color(0xFFC81E3A);

  /// The user-visible category list for pickers (kept in sync with the model).
  static const List<String> pickerCategories = [
    'Food',
    'Shopping',
    'Entertainment',
    'Travel',
    'Bills',
    'Transfer',
    'Fuel',
    'Health',
    'Investment',
    'UPI',
    'Cash',
    'Other',
  ];
}
