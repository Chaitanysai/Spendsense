import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

/// The date on a Home row: "9 Nov", with the year only when it is not this one.
///
/// The full "Nov 09, 2026" was the first thing to clip on a 390dp phone: the
/// amount column takes its width first, so three of eight rows ended in
/// "Nov 09, 20…". Activity hides the date entirely and the details screen
/// formats its own, so this changes nothing outside the Home feed.
String _compactDate(DateTime d) {
  final sameYear = d.year == DateTime.now().year;
  return DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(d);
}

/// A mark for transactions that did *not* arrive from the phone's SMS inbox.
///
/// SMS is the default channel, so marking it would put a glyph on almost every
/// row to say nothing new. Email imports and hand-entered rows are the
/// exceptions worth spotting at a glance — particularly while checking that an
/// email import actually landed.
///
/// Returns null for SMS sources, which is the signal to draw nothing.
IconData? transactionSourceIcon(String source) {
  switch (source) {
    case 'Email-Gmail':
      return Icons.mail_outline_rounded;
    case 'Manual':
      return Icons.edit_rounded;
    default:
      // SMS-Parser, SMS-AI, and any future SMS variant stay unmarked.
      return null;
  }
}

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

  /// Flat rows sit inside a shared list surface instead of carrying their own
  /// card. The dashboard uses this so a feed of transactions reads as one
  /// object, the way Suno's track list does, rather than as a stack of tiles.
  final bool flat;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.dense = false,
    this.showDate = true,
    this.flat = false,
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
      // Excluded rows are listed (Activity shows the whole ledger) but are not
      // counted in any total, so the row says so instead of looking counted.
      // Placed before the bank: on a narrow row the end of the line is what
      // truncates, and the status matters more than the bank name.
      if (transaction.isExcluded) 'Excluded',
      if (transaction.bankName.isNotEmpty) transaction.bankName,
      if (showDate) _compactDate(transaction.date),
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.only(bottom: flat ? 0 : AppSpacing.sm),
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
              '$amountPrefix ${Formatters.currency.format(transaction.amountMinor)}'
              '${transaction.isExcluded ? ', excluded from totals' : ''}',
          excludeSemantics: true,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: dense ? AppSpacing.sm : AppSpacing.md,
            ),
            decoration: flat
                ? null
                : AppColors.panelDecoration(
                    context,
                    borderRadius: radius,
                    shadow: false,
                  ),
            child: Row(
              children: [
                Container(
                  width: bubble,
                  height: bubble,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.wash(context, catColor),
                  ),
                  child: Icon(
                    CategoryStyle.icon(transaction.category),
                    // A same-hue glyph on its own wash collapses the hue
                    // distance; the ink is resolved against the real plate.
                    color: AppColors.inkOnWash(context, catColor),
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
                              style: AppText.bodyStrong(context),
                            ),
                          ),
                          if (transaction.needsReview) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.warning.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'REVIEW',
                                style: AppText.weight(
                                  AppText.label(context),
                                  FontWeight.w700,
                                ).copyWith(
                                  fontSize: 10,
                                  // A fixed brown was unreadable on dark cards;
                                  // the ink is resolved against the badge as
                                  // it is actually composited.
                                  color: AppColors.inkOnWash(
                                    context,
                                    AppColors.warning,
                                    alpha: 0.18,
                                  ),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      _MetaLine(
                        source: transaction.source,
                        text: meta,
                        dense: dense,
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
                        size: 16,
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

/// The meta line under the merchant, optionally led by a source glyph.
///
/// The glyph sits inside the flexible part of the row and the text keeps its
/// own ellipsis, so adding a mark never pushes the amount out of alignment and
/// a narrow screen still truncates the text rather than the icon.
class _MetaLine extends StatelessWidget {
  final String source;
  final String text;
  final bool dense;

  const _MetaLine({
    required this.source,
    required this.text,
    required this.dense,
  });

  @override
  Widget build(BuildContext context) {
    final style = AppText.body(context).copyWith(
      fontSize: 11.5,
      color: AppColors.textTertiary(context),
    );
    final icon = transactionSourceIcon(source);
    if (icon == null) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Row(
      children: [
        Icon(
          icon,
          size: dense ? 11 : 12,
          color: AppColors.textTertiary(context),
        ),
        const SizedBox(width: 4),
        // Flexible, not Expanded: the text keeps the row's own ellipsis and a
        // short meta line does not stretch the glyph away from it.
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
