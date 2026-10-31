import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Single source of truth for category presentation.
///
/// Replaces scattered emoji maps with a consistent Material icon + colour so
/// the UI stays coherent (the ui-ux-pro-max guidance flags emoji-as-icon).
///
/// The hues below are *data encoding* — they keep neighbouring categories
/// separable — but each one is pulled 18% toward the active brand at read time
/// so a plum, navy or pastel world tints its categories instead of showing a
/// fixed rainbow that belongs to the emerald theme.
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

  /// Cool-dominant so categories sit inside the navy identity, with a few warm
  /// hues kept separable for the colour-blind (amber vs. rose vs. green).
  static const Map<String, Color> _colors = {
    'Food': Color(0xFFFFB020),
    'Shopping': Color(0xFF7C5CFF),
    'Fuel': Color(0xFF22D3EE),
    'Travel': Color(0xFF5B8DEF),
    'Bills': Color(0xFF2F6BFF),
    'Transfer': Color(0xFF12B76A),
    'Cash': Color(0xFF12B76A),
    'Entertainment': Color(0xFFF0577B),
    'Health': Color(0xFFFF8FA3),
    'Investment': Color(0xFF00C48C),
    'UPI': Color(0xFF4C9BFF),
    'Other': Color(0xFF8FA3C4),
    'Others': Color(0xFF8FA3C4),
    'Income': Color(0xFF12B76A),
  };

  static IconData icon(String category) =>
      _icons[category] ?? Icons.account_balance_wallet_rounded;

  static Color color(String category) {
    final base = _colors[category] ?? AppColors.brandBright;
    return Color.lerp(base, AppColors.brand, 0.18) ?? base;
  }

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
