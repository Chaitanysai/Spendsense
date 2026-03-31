import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../utils/formatters.dart';

class TransactionDetailsScreen extends StatelessWidget {
  final TransactionModel transaction;
  const TransactionDetailsScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);

    return Scaffold(
      appBar: AppBar(
          title: Text("Transaction"),
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
                radius: 35,
                backgroundColor: Color(0xFF6B38FB).withOpacity(0.1),
                child: Icon(Icons.shopping_bag,
                    size: 30, color: Color(0xFF6B38FB))),
            SizedBox(height: 24),
            Text(transaction.merchant,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text("\$ ${transaction.amount}",
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                  color: Color(0xFFE0E0FF),
                  borderRadius: BorderRadius.circular(20)),
              child: Text("PENDING",
                  style: TextStyle(
                      color: Color(0xFF6B38FB),
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
            SizedBox(height: 40),
            _infoRow(Icons.calendar_today, "Date & Time",
                "${Formatters.date(transaction.date)} • ${transaction.time}"),
            _categoryPicker(context, provider),
            _infoRow(Icons.account_balance_wallet_outlined, "Payment Method",
                transaction.paymentMethod),
            SizedBox(height: 24),
            SwitchListTile(
              title: Text("Exclude from Insights"),
              subtitle: Text("Don't count this in monthly totals"),
              value: transaction.isExcluded,
              onChanged: (_) => provider.toggleExclude(transaction.id),
            ),
            SizedBox(height: 32),
            Align(
                alignment: Alignment.centerLeft,
                child: Text("Original Receipt Log",
                    style: TextStyle(fontWeight: FontWeight.bold))),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16)),
              child: Text(transaction.originalSms,
                  style: TextStyle(color: Colors.black54, height: 1.5)),
            )
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: Colors.grey[100],
              child: Icon(icon, color: Colors.grey)),
          SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.grey, fontSize: 12)),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
          ])
        ],
      ),
    );
  }

  Widget _categoryPicker(BuildContext context, TransactionProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: Colors.grey[100],
              child: Icon(Icons.category_outlined, color: Colors.grey)),
          SizedBox(width: 16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Category",
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              DropdownButton<String>(
                value: transaction.category,
                isExpanded: true,
                underline: SizedBox(),
                items: [
                  "Shopping",
                  "Food",
                  "Entertainment",
                  "Travel",
                  "Bills",
                  "Transfer",
                  "Others"
                ]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) =>
                    provider.updateCategory(transaction.id, val!),
              ),
            ]),
          )
        ],
      ),
    );
  }
}
