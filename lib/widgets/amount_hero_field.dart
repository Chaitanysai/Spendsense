import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';

/// The live amount surface, shared by Add and Edit.
///
/// The field lives *inside* the gradient card so the entered figure and the
/// formatted preview are never two different numbers, and the amount input is
/// always the visual centre of a transaction screen — editing an existing
/// entry gets the same focal card as creating one.
class AmountHeroField extends StatelessWidget {
  final TextEditingController controller;
  final bool isIncome;

  /// Inline validation message, shown under the field on the card itself.
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
    final gradient = isIncome
        ? AppColors.successGradient
        : AppColors.heroSurfaceGradient(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(gradient: gradient),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isIncome ? 'AMOUNT IN' : 'AMOUNT OUT',
              style: AppText.onGradient(
                size: 10.5,
                weight: FontWeight.w700,
                opacity: 0.82,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _safePreview(controller.text),
                maxLines: 1,
                style: AppText.onGradient(size: 36, weight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: autofocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [
                AmountInputFormatter(),
              ],
              style: AppText.onGradient(size: 16, weight: FontWeight.w600),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Enter amount',
                hintStyle: AppText.onGradient(size: 15, opacity: 0.8),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.22),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                prefixIcon: const Icon(
                  Icons.currency_rupee_rounded,
                  color: Colors.white,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                // The card is a saturated gradient, so the theme's error colour
                // would not be legible here. A white message with a warning
                // glyph carries the meaning on this surface.
                errorStyle:
                    AppText.onGradient(size: 12, weight: FontWeight.w600),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: Colors.white, width: 1.5),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: Colors.white, width: 1.5),
                ),
                errorText: errorText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
