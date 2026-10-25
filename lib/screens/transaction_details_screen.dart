import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../services/sms_content_policy.dart';
import '../providers/transaction_provider.dart';
import '../services/sound_service.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/sound_scope.dart';
import '../widgets/transaction_type_toggle.dart';

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
  late final TextEditingController _bankController;
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
    _amountController = TextEditingController(
      text: formatPaise(widget.transaction.amountMinor, trimZeroPaise: true),
    );
    _bankController = TextEditingController(
      text: widget.transaction.bank?.trim() ?? '',
    );
    _category = _normalizedCategory(widget.transaction.category);
    _type = widget.transaction.type;
    _isExcluded = widget.transaction.isExcluded;
    _amountController.addListener(() => setState(() {}));
    _merchantController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    _bankController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: const Text('Edit transaction'),
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
                      _headerCard(context),
                      const SizedBox(height: AppSpacing.xl),
                      TextField(
                        controller: _merchantController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Merchant',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: const [
                          AmountInputFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: Icon(Icons.currency_rupee_rounded),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Two visible segments instead of a dropdown: a binary
                      // choice should not open a full-width overlay. The toggle
                      // plays the selection cue itself.
                      TransactionTypeToggle(
                        isIncome: _type == TransactionType.income,
                        onSelect: (value) {
                          if (value != _type) setState(() => _type = value);
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        borderRadius: AppRadius.mdAll,
                        dropdownColor: AppColors.surfaceColor(context),
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: _categories
                            .map((item) => DropdownMenuItem(
                                value: item, child: Text(item)))
                            .toList(),
                        onChanged: (value) {
                          if (value != null && value != _category) {
                            SoundScope.play(
                                context, SoundEventType.selectionChanged);
                            setState(() => _category = value);
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _bankController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Bank',
                          prefixIcon: Icon(Icons.account_balance_rounded),
                          helperText: 'Leave blank if unknown',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceColor(context),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.border(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _metaLabel('Date & time'),
                            const SizedBox(height: 4),
                            Text(
                              '${Formatters.date(widget.transaction.date)} • ${widget.transaction.time}',
                              style:
                                  AppText.title(context).copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _metaLabel('Payment method'),
                            const SizedBox(height: 4),
                            Text(
                              widget.transaction.paymentMethod,
                              style:
                                  AppText.title(context).copyWith(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceColor(context),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.border(context)),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md),
                            title: Text('Exclude from Insights',
                                style: AppText.title(context)
                                    .copyWith(fontSize: 14)),
                            subtitle: Text("Don't count this in totals",
                                style: AppText.body(context)
                                    .copyWith(fontSize: 12)),
                            value: _isExcluded,
                            onChanged: (value) {
                              SoundScope.play(
                                  context, SoundEventType.selectionChanged);
                              setState(() => _isExcluded = value);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Original SMS', style: AppText.title(context)),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt(context),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Text(
                          widget.transaction.originalSms.isEmpty
                              // Two honest reasons a body can be absent now:
                              // the entry was typed, or it came from SMS under
                              // the reduce-only policy that stops storing the
                              // raw text. Stored bodies (older records) still
                              // display unchanged.
                              ? (widget.transaction.source == 'Manual'
                                  ? 'No source message (manually added).'
                                  : 'The source message is not stored. '
                                      'Amount, merchant and date were read '
                                      'from your bank SMS.')
                              : SmsContentPolicy.preserve(
                                  widget.transaction.originalSms),
                          style: AppText.body(context).copyWith(height: 1.5),
                        ),
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
                  label: 'Save changes',
                  icon: Icons.save_rounded,
                  loading: _saving,
                  // The saved cue is this button's real feedback.
                  sound: null,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaLabel(String text) => Text(
        text.toUpperCase(),
        style: AppText.overline(context),
      );

  Widget _headerCard(BuildContext context) {
    final isExpense = _type == TransactionType.expense;
    return GradientHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  isExpense ? 'Expense' : 'Income',
                  style: AppText.onGradient(size: 11, weight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              if (widget.transaction.needsReview)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text('Needs review',
                      style: AppText.onGradient(
                          size: 11, weight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _safeHeaderAmount(),
              style: AppText.onGradient(size: 38, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _merchantController.text.isEmpty
                ? 'Unknown merchant'
                : _merchantController.text,
            style: AppText.onGradient(size: 14, opacity: 0.9),
          ),
        ],
      ),
    );
  }

  String _safeHeaderAmount() {
    final raw = _amountController.text.trim();
    if (raw.isEmpty) return '₹ 0';
    try {
      final minor = parseRupeesToPaise(raw);
      return Formatters.currency.format(minor);
    } on MoneyParseException {
      return '₹ 0';
    }
  }

  String _normalizedCategory(String category) {
    if (_categories.contains(category)) return category;
    if (category == 'Others') return 'Other';
    return 'Other';
  }

  Future<void> _save() async {
    final int amountMinor;
    try {
      amountMinor = parseRupeesToPaise(_amountController.text.trim());
    } on MoneyParseException {
      SoundScope.play(context, SoundEventType.actionFailed);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid merchant and amount')),
      );
      return;
    }
    final merchant = _merchantController.text.trim();

    if (amountMinor <= 0 || merchant.isEmpty) {
      // Validation failed: the user is told, and the matching cue confirms the
      // negative outcome. No success cue is reachable from here.
      SoundScope.play(context, SoundEventType.actionFailed);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid merchant and amount')),
      );
      return;
    }

    setState(() => _saving = true);

    // Resolved before the await: this route pops itself once the write lands.
    final sound = SoundScope.maybeOf(context);
    final transactions = context.read<TransactionProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await transactions.updateTransaction(
        widget.transaction.id,
        amount: amountMinor,
        merchant: merchant,
        category: _category,
        type: _type,
        isExcluded: _isExcluded,
        // Empty string clears the bank; the model then renders 'Others'.
        bank: _bankController.text.trim(),
      );
    } catch (error) {
      // The edit was not persisted, so nothing may be announced. Tell the user
      // and keep the screen open with the edits intact.
      debugPrint('TransactionDetailsScreen: could not save — $error');
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
      return;
    }

    // Fired only once the edit is persisted and the route is still here.
    SoundScope.playOn(sound, SoundEventType.transactionSaved);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
