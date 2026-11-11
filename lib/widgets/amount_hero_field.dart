import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import 'app_surface.dart';

/// The live amount surface, shared by Add and Edit.
///
/// The field lives *inside* the surface so the entered figure and the formatted
/// preview are never two different numbers, and the amount is always the visual
/// centre of a transaction screen. It is a solid grouped surface with an ink
/// figure, not a gradient card (spec 11 §2.6: the only gradient in the app is
/// the payment card), so every palette and both brightnesses read it with the
/// same contrast as any other text on a card.
///
/// Direction is carried by the label ("Amount in" / "Amount out"), the glyph and
/// the type toggle above it; the figure itself stays ink, because the number is
/// the message and colour belongs to the money lists.
class AmountHeroField extends StatelessWidget {
  final TextEditingController controller;
  final bool isIncome;

  /// Inline validation message, shown under the field with a warning glyph.
  final String? errorText;

  final bool autofocus;

  const AmountHeroField({
    super.key,
    required this.controller,
    required this.isIncome,
    this.errorText,
    this.autofocus = false,
  });

  static String _safePreview(String raw) {
    // Empty input is not "no amount yet" that can be displayed as zero: the
    // preview sits directly above the input, so a literal `₹0` read as a
    // committed figure and contradicted the "Enter amount" hint underneath it.
    if (raw.trim().isEmpty) return '—';
    try {
      return Formatters.currency.format(parseRupeesToPaise(raw));
    } on MoneyParseException {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppColors.textPrimary(context);
    final edge = AppColors.border(context);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return AppSurface(
      level: AppSurfaceLevel.grouped,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isIncome ? 'Amount in' : 'Amount out',
            style: AppText.label(context).copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _safePreview(controller.text),
              maxLines: 1,
              style: AppText.amount(
                context,
                size: 32,
                weight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [AmountInputFormatter()],
            style: AppText.amount(
              context,
              size: 16,
              weight: FontWeight.w600,
              color: ink,
            ),
            cursorColor: AppColors.brandInk(context),
            decoration: InputDecoration(
              hintText: 'Enter amount',
              hintStyle: AppText.body(context).copyWith(
                fontSize: 15,
                color: AppColors.textTertiary(context),
              ),
              filled: true,
              fillColor: AppColors.surfaceColor(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              prefixIcon: Icon(Icons.currency_rupee_rounded, color: ink),
              border: border(edge),
              enabledBorder: border(edge),
              focusedBorder: border(AppColors.brandInk(context), 1.5),
              errorBorder: border(AppColors.danger, 1.5),
              focusedErrorBorder: border(AppColors.danger, 1.5),
              // On a solid card the theme's danger colour is legible, and the
              // message is announced with the field.
              errorStyle: AppText.label(context).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
              errorText: errorText,
            ),
          ),
        ],
      ),
    );
  }
}
