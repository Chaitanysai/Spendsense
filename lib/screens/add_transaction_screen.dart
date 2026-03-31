import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();

  String _category = "Other";

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Add Transaction")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: "Amount"),
            ),
            TextField(
              controller: _merchantController,
              decoration: InputDecoration(labelText: "Merchant"),
            ),
            DropdownButton<String>(
              value: _category,
              items: ["Food", "Shopping", "UPI", "Other"]
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() => _category = val!);
              },
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(_amountController.text) ?? 0;

                if (amount <= 0) return;

                final tx = TransactionModel(
                  id: DateTime.now().toString(),
                  amount: amount,
                  type: TransactionType.expense,
                  merchant: _merchantController.text.isEmpty
                      ? "Manual"
                      : _merchantController.text,
                  category: _category,
                  paymentMethod: "Manual",
                  date: DateTime.now(),
                  time: "",
                  originalSms: "",
                  isExcluded: false,
                );

                await context.read<TransactionProvider>().addTransaction(tx);
                if (!mounted) return;

                Navigator.pop(context);
              },
              child: Text("Add"),
            )
          ],
        ),
      ),
    );
  }
}
