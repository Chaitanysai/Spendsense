import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../utils/formatters.dart';
import '../screens/transaction_details_screen.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  const TransactionTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    bool isExpense = transaction.type == TransactionType.expense;

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  TransactionDetailsScreen(transaction: transaction))),
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(12)),
              child:
                  Icon(_getIcon(transaction.category), color: Colors.black54),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(transaction.merchant,
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                      "${Formatters.date(transaction.date)} • ${transaction.time}",
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            Text(
              "${isExpense ? '-' : '+'} ${Formatters.currency.format(transaction.amount)}",
              style: TextStyle(
                  color: isExpense ? Color(0xFFB1097C) : Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            )
          ],
        ),
      ),
    );
  }

  IconData _getIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'shopping':
        return Icons.shopping_bag_outlined;
      case 'food':
        return Icons.restaurant_outlined;
      case 'transfer':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }
}
