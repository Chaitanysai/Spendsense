import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/formatters.dart';

class SummaryCard extends StatelessWidget {
  final double total;
  final int count;
  final String topCat;

  const SummaryCard({
    super.key,
    required this.total,
    required this.count,
    required this.topCat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.mainGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
              color: AppColors.primaryPurple.withOpacity(0.3),
              blurRadius: 20,
              offset: Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("TOTAL EXPENSES",
              style: TextStyle(
                  color: Colors.white70,
                  letterSpacing: 1.2,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(Formatters.fullCurrency.format(total),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 20),
          Divider(color: Colors.white24),
          SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoItem("TRANSACTIONS", count.toString()),
              _infoItem("AVG / DAY", Formatters.currency.format(total / 30)),
              _infoItem("TOP CATEGORY", topCat),
            ],
          )
        ],
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
        SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
