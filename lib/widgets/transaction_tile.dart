import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../screens/transaction_details_screen.dart';
import 'app_page_route.dart';
import 'pressable.dart';

/// Compact transaction row: a circular category icon, merchant over its meta
/// line, and a right-aligned amount.
///
/// The amount is the loudest element in the row and uses tabular figures, so a
/// column of rows lines up exactly. Sign, colour and icon all carry direction —
/// colour alone never does.
class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final bool dense;

  /// Activity groups rows under date headers, so it hides the per-row date and
  /// uses the space for the bank. Home has no headers and keeps the date.
  final bool showDate;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.dense = false,
    this.showDate = true,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == TransactionType.expense;
    final amountColor =
        isExpense ? AppColors.expenseRed : AppColors.incomeGreen;
    final amountPrefix = isExpense ? '−' : '+';
    final catColor = CategoryStyle.color(transaction.category);
    final radius = BorderRadius.circular(AppRadius.md);
    final bubble = dense ? 40.0 : 44.0;

    final meta = <String>[
      transaction.category,
      if (transaction.bankName.isNotEmpty) transaction.bankName,
      if (showDate) Formatters.date(transaction.date),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Pressable(
        borderRadius: radius,
        onTap: () => Navigator.of(context).push(
          AppPageRoute(
            builder: (_) => TransactionDetailsScreen(transaction: transaction),
          ),
        ),
        sound: SoundEventType.buttonTap,
        child: Semantics(
          button: true,
          label: '${transaction.merchant}, ${transaction.category}, '
              '$amountPrefix ${Formatters.currency.format(transaction.amountMinor)}',
          excludeSemantics: true,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? AppSpacing.sm : AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor(context),
              borderRadius: radius,
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: bubble,
                  height: bubble,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: catColor.withValues(alpha: 0.13),
                  ),
                  child: Icon(
                    CategoryStyle.icon(transaction.category),
                    color: catColor,
                    size: bubble * 0.44,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),

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
                                  AppText.title(context).copyWith(fontSize: 14),
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
                                  fontSize: 8.5,
                                  color: const Color(0xFF8A5A00),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(context).copyWith(
                          fontSize: 11.5,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                // Scale down rather than ellipsize: a long merchant must never
                // truncate the amount itself.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$amountPrefix ${Formatters.currency.format(transaction.amountMinor)}',
                      maxLines: 1,
                      softWrap: false,
                      style: AppText.amount(
                        context,
                        size: 14.5,
                        color: amountColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
