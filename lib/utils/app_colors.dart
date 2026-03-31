import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryPink = Color(0xFFB1097C);
  static const Color primaryPurple = Color(0xFF6B38FB);
  static const Color background = Color(0xFFF8F9FB);
  static const Color surface = Colors.white;

  static const LinearGradient mainGradient = LinearGradient(
    colors: [primaryPink, primaryPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Color getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'shopping':
        return Color(0xFFC2185B);
      case 'food':
        return Color(0xFF6B38FB);
      case 'entertainment':
        return Color(0xFFD81B60);
      case 'travel':
        return Color(0xFF43A047);
      case 'bills':
        return Color(0xFFFB8C00);
      case 'upi':
        return Color(0xFFF06292);
      default:
        return Color(0xFF9FA8DA);
    }
  }
}
