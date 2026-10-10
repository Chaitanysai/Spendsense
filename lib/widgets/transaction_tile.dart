import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../utils/formatters.dart';
import '../screens/transaction_details_screen.dart';
import '../utils/app_colors.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;

  const TransactionTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == TransactionType.expense;
    final amountColor =
        isExpense ? AppColors.expenseRed : AppColors.incomeGreen;
    final amountPrefix = isExpense ? '−' : '+';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  TransactionDetailsScreen(transaction: transaction),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor(context),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.border(context).withValues(alpha: 0.6),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow(context),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                // ── Category icon container with soft gradient ─────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _iconBg(transaction.category),
                        _iconBg(transaction.category).withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _iconBg(transaction.category).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _emoji(transaction.category),
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // ── Merchant + date / category hierarchy ─────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.merchant,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary(context),
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt(context),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              transaction.category,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '•  ${Formatters.date(transaction.date)}',
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // ── Amount & payment method ──────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$amountPrefix ${Formatters.currency.format(transaction.amount)}',
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: amountColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        transaction.paymentMethod,
                        style: TextStyle(
                          fontSize: 10,
                          color: amountColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _emoji(String category) {
    const map = {
      'Food': '🍔',
      'Shopping': '🛍️',
      'Fuel': '⛽',
      'Travel': '🚗',
      'Bills': '💡',
      'Transfer': '💸',
      'Cash': '💵',
      'Entertainment': '🎬',
      'Health': '🏥',
      'Investment': '📈',
      'Other': '📦',
      'Others': '📦',
    };
    return map[category] ?? '💳';
  }

  Color _iconBg(String category) {
    const map = {
      'Food': Color(0xFFFF9F43),
      'Shopping': Color(0xFF9b59b6),
      'Fuel': Color(0xFF1abc9c),
      'Travel': Color(0xFF3498db),
      'Bills': Color(0xFFe74c3c),
      'Transfer': Color(0xFF2ecc71),
      'Cash': Color(0xFF27ae60),
      'Entertainment': Color(0xFFe84393),
      'Health': Color(0xFF00b894),
      'Investment': Color(0xFF0984e3),
      'Other': Color(0xFF636e72),
      'Others': Color(0xFF636e72),
    };
    return map[category] ?? AppColors.primaryTeal;
  }
}
