import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../utils/formatters.dart';
import '../utils/app_colors.dart';

class TransactionDetailsScreen extends StatefulWidget {
  final TransactionModel transaction;

  const TransactionDetailsScreen({super.key, required this.transaction});

  @override
  State<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends State<TransactionDetailsScreen> {
  late final TextEditingController _merchantController;
  late final TextEditingController _amountController;
  late String _category;
  late TransactionType _type;
  late bool _isExcluded;
  bool _saving = false;

  static const _categories = [
    'Shopping',
    'Food',
    'Entertainment',
    'Travel',
    'Bills',
    'Transfer',
    'Fuel',
    'Health',
    'Investment',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _merchantController =
        TextEditingController(text: widget.transaction.merchant);
    _amountController =
        TextEditingController(text: widget.transaction.amount.toString());
    _category = _normalizedCategory(widget.transaction.category);
    _type = widget.transaction.type;
    _isExcluded = widget.transaction.isExcluded;
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: const Text('Edit Transaction'),
        foregroundColor: AppColors.textPrimary(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerCard(context),
            const SizedBox(height: 24),
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: 'Merchant',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TransactionType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                prefixIcon: Icon(Icons.swap_vert_rounded),
              ),
              items: const [
                DropdownMenuItem(
                  value: TransactionType.expense,
                  child: Text('Expense'),
                ),
                DropdownMenuItem(
                  value: TransactionType.income,
                  child: Text('Income'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _type = value);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _categories
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _category = value);
                }
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor(context),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Date & Time',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Formatters.date(widget.transaction.date)} • ${widget.transaction.time}',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Payment Method',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.transaction.paymentMethod,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Exclude from Insights"),
              subtitle: const Text("Don't count this transaction in totals"),
              value: _isExcluded,
              onChanged: (value) => setState(() => _isExcluded = value),
            ),
            const SizedBox(height: 24),
            Text(
              'Original SMS',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.transaction.originalSms,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(BuildContext context) {
    final isExpense = _type == TransactionType.expense;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isExpense ? 'Expense' : 'Income',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹ ${_amountController.text.isEmpty ? '0' : _amountController.text}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _merchantController.text.isEmpty
                ? 'Unknown merchant'
                : _merchantController.text,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  String _normalizedCategory(String category) {
    if (_categories.contains(category)) return category;
    if (category == 'Others') return 'Other';
    return 'Other';
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amountController.text.trim());
    final merchant = _merchantController.text.trim();

    if (amount == null || amount <= 0 || merchant.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid merchant and amount')),
      );
      return;
    }

    setState(() => _saving = true);
    await context.read<TransactionProvider>().updateTransaction(
          widget.transaction.id,
          amount: amount,
          merchant: merchant,
          category: _category,
          type: _type,
          isExcluded: _isExcluded,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
