import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../services/sms_content_policy.dart';
import '../providers/transaction_provider.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/amount_hero_field.dart';
import '../widgets/category_chip_picker.dart';
import '../widgets/glass_card.dart';
import '../widgets/icon_well.dart';
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

  /// Inline validation message for the amount field, or null when it is valid.
  String? _amountError;

  /// The expense category to restore when the type flips back from income.
  String? _stashedCategory;

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
    _type = widget.transaction.type;
    // Income entries have no category taxonomy in this app; the parser labels
    // them 'Income', so an income transaction edits as Income.
    _category = _type == TransactionType.income
        ? 'Income'
        : _normalizedCategory(widget.transaction.category);
    _isExcluded = widget.transaction.isExcluded;
    _amountController.addListener(() {
      // The save rule and the formatted preview both track this text, and
      // editing it clears a stale error so the message never sits against
      // text the user has already corrected.
      setState(() {
        if (_amountError != null) _amountError = null;
      });
    });
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
                      // Two visible segments instead of a dropdown: a binary
                      // choice should not open a full-width overlay. The toggle
                      // plays the selection cue itself.
                      TransactionTypeToggle(
                        isIncome: _type == TransactionType.income,
                        onSelect: _setType,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      // The hero is the amount input itself — the same focal
                      // surface Add uses — so the figure is never written in
                      // two places.
                      AmountHeroField(
                        controller: _amountController,
                        isIncome: _type == TransactionType.income,
                        errorText: _amountError,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      TextField(
                        controller: _merchantController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Merchant',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      if (_type == TransactionType.expense) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Text('Category', style: AppText.title(context)),
                        const SizedBox(height: AppSpacing.md),
                        // The same chip picker Add uses, so one data set wears
                        // one control across the whole flow.
                        CategoryChipPicker(
                          selected: _category,
                          onSelect: (c) {
                            if (_category == c) return;
                            setState(() => _category = c);
                          },
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      TextField(
                        controller: _bankController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Bank',
                          prefixIcon: Icon(Icons.account_balance_rounded),
                          helperText: 'Leave blank if unknown',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _metadataCard(context),
                      const SizedBox(height: AppSpacing.lg),
                      _excludeCard(context),
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
                  // Same rule as Add: the amount must be present before the
                  // action lights up.
                  onPressed:
                      _amountController.text.trim().isEmpty || _saving
                          ? null
                          : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setType(TransactionType next) {
    if (_type == next) return;
    setState(() {
      // Income has no category taxonomy here; it edits as Income and the
      // previous expense category is stashed so flipping back restores it.
      if (next == TransactionType.income) {
        _stashedCategory = _category;
        _category = 'Income';
      } else {
        _category = _stashedCategory ?? 'Food';
      }
      _type = next;
    });
  }

  String _normalizedCategory(String category) {
    // SMS entries can carry any stored category. Keep the ones the picker
    // lists, fold 'Others' into its canonical form, and let anything unknown
    // fall back to Other.
    if (CategoryStyle.pickerCategories.contains(category)) return category;
    if (category == 'Others') return 'Other';
    return 'Other';
  }

  Widget _metaLabel(String text) => Text(
        text.toUpperCase(),
        style: AppText.overline(context),
      );

  Widget _metadataCard(BuildContext context) {
    // 'time' is empty on manually added entries, so the bullet only exists
    // when there is a time on the other side of it.
    final savedTime = widget.transaction.time.trim();
    final dateTimeLine = savedTime.isEmpty
        ? Formatters.date(widget.transaction.date)
        : '${Formatters.date(widget.transaction.date)} • $savedTime';
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metaLabel('Date & time'),
          const SizedBox(height: AppSpacing.xs),
          Text(dateTimeLine, style: AppText.bodyStrong(context)),
          const SizedBox(height: AppSpacing.lg),
          _metaLabel('Payment method'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.transaction.paymentMethod,
            style: AppText.bodyStrong(context),
          ),
        ],
      ),
    );
  }

  Widget _excludeCard(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          secondary: IconWell(
            icon: Icons.visibility_off_outlined,
            color: AppColors.textTertiary(context),
          ),
          title: Text('Exclude from Insights', style: AppText.bodyStrong(context)),
          subtitle: Text(
            "Don't count this in totals",
            style: AppText.bodySmall(context),
          ),
          value: _isExcluded,
          onChanged: (value) {
            SoundScope.play(context, SoundEventType.selectionChanged);
            setState(() => _isExcluded = value);
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final int amountMinor;
    try {
      amountMinor = parseRupeesToPaise(_amountController.text.trim());
    } on MoneyParseException {
      setState(() => _amountError = 'Enter a valid amount.');
      SoundScope.play(context, SoundEventType.actionFailed);
      return;
    }
    if (amountMinor <= 0) {
      setState(() => _amountError = 'Enter an amount greater than zero.');
      SoundScope.play(context, SoundEventType.actionFailed);
      return;
    }
    if (_amountError != null) setState(() => _amountError = null);

    final merchant = _merchantController.text.trim();
    if (merchant.isEmpty) {
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
