import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/gradient_hero_card.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();

  String _category = 'Food';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
    _merchantController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountController.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: Text('Add transaction', style: AppText.title(context)),
        backgroundColor: Colors.transparent,
      ),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.sm,
                    AppSpacing.page,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Live amount hero
                      GradientHeroCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AMOUNT',
                                style: AppText.onGradient(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    opacity: 0.85,
                                    letterSpacing: 1.4)),
                            const SizedBox(height: AppSpacing.sm),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                Formatters.currency.format(_amount),
                                style: AppText.onGradient(
                                    size: 40, weight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _amountController,
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
                              ],
                              style: AppText.onGradient(
                                  size: 16, weight: FontWeight.w600),
                              cursorColor: Colors.white,
                              decoration: InputDecoration(
                                hintText: 'Enter amount',
                                hintStyle:
                                    AppText.onGradient(size: 15, opacity: 0.85),
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.20),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg,
                                    vertical: AppSpacing.md),
                                prefixIcon: const Icon(
                                    Icons.currency_rupee_rounded,
                                    color: Colors.white),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                  borderSide: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.6)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      Text('Merchant', style: AppText.title(context)),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _merchantController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Swiggy, Uber, Reliance',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      Text('Category', style: AppText.title(context)),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: CategoryStyle.pickerCategories.map((c) {
                          final selected = _category == c;
                          final color = CategoryStyle.color(c);
                          return GestureDetector(
                            onTap: () => setState(() => _category = c),
                            child: AnimatedContainer(
                              duration:
                                  AppMotion.respect(context, AppMotion.fast),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: selected
                                    ? color.withValues(alpha: 0.16)
                                    : AppColors.surfaceColor(context),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                                border: Border.all(
                                  color: selected
                                      ? color.withValues(alpha: 0.5)
                                      : AppColors.border(context),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CategoryStyle.icon(c),
                                      size: 16,
                                      color: selected
                                          ? color
                                          : AppColors.textSecondary(context)),
                                  const SizedBox(width: 6),
                                  Text(
                                    c,
                                    style: AppText.label(context).copyWith(
                                      fontSize: 12,
                                      color: selected
                                          ? color
                                          : AppColors.textSecondary(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  0,
                  AppSpacing.page,
                  AppSpacing.lg,
                ),
                child: AppPrimaryButton(
                  label: 'Add transaction',
                  icon: Icons.check_rounded,
                  loading: _saving,
                  onPressed: _amount > 0 ? _save : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amount = _amount;
    if (amount <= 0) return;

    setState(() => _saving = true);
    final provider = context.read<TransactionProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final tx = TransactionModel(
      id: DateTime.now().toString(),
      amount: amount.toInt(),
      type: TransactionType.expense,
      merchant: _merchantController.text.isEmpty
          ? 'Manual'
          : _merchantController.text,
      category: _category,
      paymentMethod: 'Manual',
      date: DateTime.now(),
      time: '',
      originalSms: '',
      isExcluded: false,
      source: 'Manual',
    );

    await provider.addTransaction(tx);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Transaction added')),
    );
    navigator.pop();
  }
}
