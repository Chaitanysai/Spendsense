import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../services/sms_content_policy.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import '../widgets/amount_hero_field.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_list_row.dart';
import '../widgets/app_surface.dart';
import '../widgets/category_chip_picker.dart';
import '../widgets/icon_well.dart';
import '../widgets/sound_scope.dart';
import '../widgets/transaction_type_toggle.dart';

/// View and edit one transaction.
///
/// There is deliberately no delete here. The app has no user-facing delete
/// today (only the assistant deletes, with its own audit trail), and adding one
/// is a ledger-and-sync decision that was put to the owner and declined for this
/// stage. See docs/design-redesign/14-transactions-plan.md §4.
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

  /// Inline message for the merchant field, or null when it is valid.
  String? _merchantError;

  /// Set when the write was rejected. Shown above the Save button until the
  /// next edit. It used to be a SnackBar, which floats at the bottom of the
  /// screen and covered the Save button the user had to press again (measured
  /// 52 to 54dp of overlap at 1x and 2x text).
  String? _saveError;

  /// The expense category to restore when the type flips back from income.
  String? _stashedCategory;

  // What the form held when it opened, to tell "edited" from "untouched" when
  // the user tries to leave.
  late final String _initialMerchant;
  late final String _initialAmount;
  late final String _initialBank;
  late final String _initialCategory;
  late final TransactionType _initialType;
  late final bool _initialExcluded;

  /// True once the edit has been written. The route then pops, and a save is
  /// not a discard, so the leave guard stands down.
  bool _saved = false;

  bool get _dirty =>
      !_saved &&
      (_merchantController.text != _initialMerchant ||
          _amountController.text != _initialAmount ||
          _bankController.text != _initialBank ||
          _category != _initialCategory ||
          _type != _initialType ||
          _isExcluded != _initialExcluded);

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

    _initialMerchant = _merchantController.text;
    _initialAmount = _amountController.text;
    _initialBank = _bankController.text;
    _initialCategory = _category;
    _initialType = _type;
    _initialExcluded = _isExcluded;

    _amountController.addListener(() {
      // The save rule and the formatted preview both track this text, and
      // editing it clears a stale error so the message never sits against
      // text the user has already corrected.
      setState(() {
        if (_amountError != null) _amountError = null;
        if (_saveError != null) _saveError = null;
      });
    });
    // Every edit rebuilds: `PopScope.canPop` is read at build time, so a field
    // that edits without rebuilding leaves the leave guard believing nothing
    // changed, and back then discards the edit without asking.
    _merchantController.addListener(() {
      setState(() {
        _merchantError = null;
        _saveError = null;
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

  /// Asks before discarding edits. A back press with nothing changed leaves at
  /// once; with changes it names what is at stake and defaults to staying.
  Future<void> _confirmLeave() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showAppConfirmDialog(
      context,
      title: 'Discard changes?',
      message: 'Your edits to this transaction have not been saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
      icon: Icons.edit_off_rounded,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffold(context),
        appBar: AppBar(
          title: const Text('Edit transaction'),
          // The default 16dp spacing after the 56dp leading slot put the title
          // 32dp from the arrow glyph and 56dp off the page edge that every
          // field below starts on. Zero keeps it one step from the arrow.
          titleSpacing: 0,
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
                        // choice should not open a full-width overlay. The
                        // toggle plays the selection cue itself.
                        TransactionTypeToggle(
                          isIncome: _type == TransactionType.income,
                          onSelect: _setType,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        // The hero is the amount input itself, the same focal
                        // surface Add uses, so the figure is never written in
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
                          decoration: InputDecoration(
                            labelText: 'Merchant',
                            prefixIcon: const Icon(Icons.storefront_outlined),
                            errorText: _merchantError,
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
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Bank',
                            prefixIcon: Icon(Icons.account_balance_rounded),
                            helperText: 'Leave blank if unknown',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _detailsGroup(context),
                        const SizedBox(height: AppSpacing.xl),
                        Semantics(
                          header: true,
                          child: Text('Original SMS',
                              style: AppText.title(context)),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppSurface(
                          level: AppSurfaceLevel.tertiary,
                          radius: AppRadius.md,
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: SizedBox(
                            width: double.infinity,
                            child: Text(
                              widget.transaction.originalSms.isEmpty
                                  // Two honest reasons a body can be absent now:
                                  // the entry was typed, or it came from SMS
                                  // under the reduce-only policy that stops
                                  // storing the raw text. Stored bodies (older
                                  // records) still display unchanged.
                                  ? (widget.transaction.source == 'Manual'
                                      ? 'No source message (manually added).'
                                      : 'The source message is not stored. '
                                          'Amount, merchant and date were read '
                                          'from your bank SMS.')
                                  : SmsContentPolicy.preserve(
                                      widget.transaction.originalSms),
                              style:
                                  AppText.body(context).copyWith(height: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // The action bar is its own band: a hairline ends the scroll
                // region, then 12dp of air before the button. Without it the
                // last field (Bank) ran straight into the button's top edge
                // and read as cut off.
                const AppSeparator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.md,
                    AppSpacing.page,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_saveError != null) ...[
                        _FormError(message: _saveError!),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      AppPrimaryButton(
                        label: 'Save changes',
                        icon: Icons.save_rounded,
                        loading: _saving,
                        // The saved cue is this button's real feedback.
                        sound: null,
                        // Same rule as Add: the amount must be present before
                        // the action lights up.
                        onPressed:
                            _amountController.text.trim().isEmpty || _saving
                                ? null
                                : _save,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

  /// What is known about the transaction and cannot be edited here: when, how,
  /// and whether it counts. One grouped surface with hairlines, in the shape of
  /// the other detail lists in the app, not two cards.
  Widget _detailsGroup(BuildContext context) {
    // 'time' is empty on manually added entries, so the bullet only exists
    // when there is a time on the other side of it.
    final savedTime = widget.transaction.time.trim();
    final dateTimeLine = savedTime.isEmpty
        ? Formatters.date(widget.transaction.date)
        : '${Formatters.date(widget.transaction.date)} • $savedTime';
    return AppListGroup(
      semanticLabel: 'Transaction details',
      rows: [
        AppListRow(
          title: 'Date & time',
          subtitle: dateTimeLine,
          leadingIcon: Icons.event_rounded,
          leadingTone: AppColors.textSecondary(context),
          showDivider: true,
        ),
        AppListRow(
          title: 'Payment method',
          subtitle: widget.transaction.paymentMethod,
          leadingIcon: Icons.account_balance_wallet_outlined,
          leadingTone: AppColors.textSecondary(context),
          showDivider: true,
        ),
        // The switch row owns its own Material so the ink never paints on the
        // surface behind it (a regression guard in sound_integration_test).
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            // The same 40dp plate and 12dp gap the rows above use
            // (AppListRow), so all three titles start on one line.
            secondary: IconWell(
              icon: Icons.visibility_off_outlined,
              color: AppColors.textSecondary(context),
            ),
            horizontalTitleGap: AppSpacing.md,
            title: Text('Exclude from Insights',
                style: AppText.bodyStrong(context)),
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
      ],
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
      // negative outcome. No success cue is reachable from here. The message is
      // on the field it is about and also shown above the button.
      SoundScope.play(context, SoundEventType.actionFailed);
      setState(() {
        _merchantError = 'Enter a merchant.';
        _saveError = 'Enter a valid merchant and amount';
      });
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });

    // Resolved before the await: this route pops itself once the write lands.
    final sound = SoundScope.maybeOf(context);
    final transactions = context.read<TransactionProvider>();

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
      setState(() {
        _saving = false;
        _saveError = 'Could not save. Please try again.';
      });
      return;
    }

    // Fired only once the edit is persisted and the route is still here. The
    // route is popped without the discard prompt: the edits are saved.
    SoundScope.playOn(sound, SoundEventType.transactionSaved);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    Navigator.of(context).pop();
  }
}

/// A message about the form as a whole, announced as it appears.
class _FormError extends StatelessWidget {
  final String message;

  const _FormError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppText.label(context).copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
