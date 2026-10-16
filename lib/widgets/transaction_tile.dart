import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../screens/transaction_details_screen.dart';
import 'app_page_route.dart';
import 'pressable.dart';

/// Rounded white transaction panel with a circular category bubble, merchant
/// hierarchy and amount. Matches the reference's "rounded white panels".
class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final bool dense;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == TransactionType.expense;
    final amountColor =
        isExpense ? AppColors.expenseRed : AppColors.incomeGreen;
    final amountPrefix = isExpense ? '−' : '+';
    final catColor = CategoryStyle.color(transaction.category);
    final radius = BorderRadius.circular(AppRadius.md);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Pressable(
        borderRadius: radius,
        onTap: () => Navigator.of(context).push(
          AppPageRoute(
            builder: (_) => TransactionDetailsScreen(transaction: transaction),
          ),
        ),
        child: Container(
          padding: EdgeInsets.all(dense ? AppSpacing.md : AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceColor(context),
            borderRadius: radius,
            border: Border.all(
              color: AppColors.border(context).withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow(context),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Circular category bubble
              Container(
                width: dense ? 42 : 48,
                height: dense ? 42 : 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      catColor.withValues(alpha: 0.22),
                      catColor.withValues(alpha: 0.10),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: catColor.withValues(alpha: 0.30)),
                ),
                child: Icon(
                  CategoryStyle.icon(transaction.category),
                  color: catColor,
                  size: dense ? 20 : 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Merchant + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            transaction.merchant,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppText.title(context).copyWith(fontSize: 15),
                          ),
                        ),
                        if (transaction.needsReview) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'REVIEW',
                              style: AppText.label(context).copyWith(
                                fontSize: 9,
                                color: const Color(0xFFB87A00),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt(context),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            transaction.category,
                            style:
                                AppText.label(context).copyWith(fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            Formatters.date(transaction.date),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(context).copyWith(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.sm),

              // Amount + payment pill
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$amountPrefix ${Formatters.currency.format(transaction.amount)}',
                    style: AppText.amount(
                      context,
                      size: 16,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: amountColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      transaction.paymentMethod,
                      style: AppText.label(context).copyWith(
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
    );
  }
}
