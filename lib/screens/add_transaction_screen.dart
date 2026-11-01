import 'package:flutter/material.dart';
import '../widgets/app_sheet.dart';
import 'package:provider/provider.dart';

import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';
import '../services/sound_service.dart';
import '../utils/money_parser.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/amount_hero_field.dart';
import '../widgets/app_button.dart';
import '../widgets/category_chip_picker.dart';
import '../widgets/sound_scope.dart';
import '../widgets/transaction_type_toggle.dart';

/// Presents the shared transaction form as a modal sheet. Every entry point —
/// the Home floating action, the quick-action tiles, the activity screen — calls
/// this so validation, categories and persistence stay in one place.
Future<void> showAddTransactionSheet(
  BuildContext context, {
  TransactionType initialType = TransactionType.expense,
}) {
  // One shared entrance for every entry point (see [showAppSheet]); motion
  // collapses to zero when the platform asks for reduced motion.
  return showAppSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        AddTransactionScreen(initialType: initialType, asSheet: true),
  );
}

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({
    super.key,
    this.initialType = TransactionType.expense,
    this.asSheet = false,
  });

  /// Lets the dashboard's action tiles open straight into the right mode.
  final TransactionType initialType;

  /// When true the widget renders as sheet content (no Scaffold/AppBar) so it
  /// can be hosted by [showAddTransactionSheet]. Defaults to a full page, which
  /// keeps direct navigation and widget tests working unchanged.
  final bool asSheet;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();

  String _category = 'Food';
  bool _saving = false;

  /// Inline validation message for the amount field, or null when it is valid.
  String? _amountError;
  late TransactionType _type = widget.initialType;

  bool get _isIncome => _type == TransactionType.income;

  void _setType(TransactionType next) {
    if (_type == next) return;
    // A real mode change is a selection change; re-tapping the active segment
    // stays silent.
    SoundScope.play(context, SoundEventType.selectionChanged);
    setState(() {
      _type = next;
      // Income has no merchant taxonomy in this app; the parser labels it
      // 'Income', so keep manual entries consistent with that.
      _category = next == TransactionType.income ? 'Income' : 'Food';
    });
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      setState(() {
        // Editing the amount clears a stale error, so the message never sits
        // against text the user has already corrected.
        if (_amountError != null) _amountError = null;
      });
    });
    _merchantController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        if (widget.asSheet) const _SheetGrabber(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              widget.asSheet ? AppSpacing.xs : AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.asSheet) ...[
                  Text(
                    _isIncome ? 'Add income' : 'Add expense',
                    style: AppText.h2(context),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Saved locally to this device',
                    style: AppText.bodySmall(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                TransactionTypeToggle(isIncome: _isIncome, onSelect: _setType),
                const SizedBox(height: AppSpacing.lg),
                AmountHeroField(
                  controller: _amountController,
                  isIncome: _isIncome,
                  errorText: _amountError,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Merchant', style: AppText.title(context)),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _merchantController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Swiggy, Uber, Reliance',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                if (!_isIncome) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text('Category', style: AppText.title(context)),
                  const SizedBox(height: AppSpacing.md),
                  CategoryChipPicker(
                    selected: _category,
                    onSelect: (c) {
                      if (_category == c) return;
                      SoundScope.play(context, SoundEventType.selectionChanged);
                      setState(() => _category = c);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        // The action row sits inside the sheet, whose height already had the
        // keyboard inset removed, so it needs no `viewInsets` padding of its
        // own — adding it here is what drew the button back over the Merchant
        // field once the IME was up.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          child: AppPrimaryButton(
            label: _isIncome ? 'Add income' : 'Add expense',
            icon: Icons.check_rounded,
            loading: _saving,
            // The saved cue is this button's real feedback, so suppress the
            // generic tap tick rather than stacking two sounds.
            sound: null,
            onPressed: _amountController.text.trim().isNotEmpty && !_saving
                ? _save
                : null,
          ),
        ),
      ],
    );

    if (!widget.asSheet) {
      return Scaffold(
        backgroundColor: AppColors.scaffold(context),
        appBar: AppBar(
          title: Text('Add transaction', style: AppText.title(context)),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(top: false, child: content),
      );
    }

    // A bounded height is what lets the inner Expanded scroll region and the
    // pinned action row coexist inside a modal sheet.
    //
    // The cap alone was not enough. A bottom sheet is positioned by its *bottom*
    // edge, which on Android sits at the screen bottom — behind the keyboard.
    // Capping the height therefore shrank the sheet from the top while its
    // bottom stayed under the IME, so at 1.3 scale the amount field was sliced
    // in half and Merchant, Category and the submit row were unreachable.
    // Subtracting [viewInsets] here and anchoring with
    // `mainAxisAlignment: end` inside a bottom-padded box lifts the whole sheet
    // above the keys; the sheet then sizes to `min(content, cap)` and the inner
    // scroll view takes up the slack.
    //
    // `useSafeArea` in [showAppSheet] already keeps the sheet below the status
    // bar, so the top inset is not subtracted a second time.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final available = MediaQuery.sizeOf(context).height - keyboardInset;
    final cap = available > 0 ? available * 0.92 : 0.0;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `Flexible` is what makes the cap real: the inner content is a Column
          // (grabber + Expanded scroll view + pinned button), which sizes to its
          // natural height and would overflow this box rather than shrink into
          // it. Flexible lets the ConstrainedBox be *given* the capped height
          // instead of overflowing it.
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: cap),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor(context),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                  border: Border.all(color: AppColors.border(context)),
                ),
                // The keyboard inset is already removed from the layout above,
                // so the sheet's own bottom padding must not add it again.
                child: SafeArea(top: false, child: content),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final int amountMinor;
    try {
      amountMinor = parseRupeesToPaise(_amountController.text);
    } on MoneyParseException {
      // Previously this returned silently: the button did nothing and said
      // nothing. The error now appears against the amount field.
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

    final provider = context.read<TransactionProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Resolved before the await: this route pops itself once the write lands,
    // so the context is no longer usable for the cue.
    final sound = SoundScope.maybeOf(context);

    setState(() => _saving = true);

    final tx = TransactionModel(
      id: DateTime.now().toString(),
      amountMinor: amountMinor,
      type: _type,
      merchant: _merchantController.text.trim().isEmpty
          ? 'Manual'
          : _merchantController.text.trim(),
      category: _category,
      paymentMethod: 'Manual',
      date: DateTime.now(),
      time: '',
      originalSms: '',
      isExcluded: false,
      source: 'Manual',
    );

    try {
      // Only after this await resolves does the entry exist locally; the
      // success message (and any success feedback) belongs after it, never on
      // a failed write.
      await provider.addTransaction(tx);
    } catch (_) {
      // Nothing was persisted, so nothing may be announced. Tell the user and
      // leave the form open so the entry can be retried.
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
      return;
    }

    // Only now, after the write completed and the route is still here: a
    // rejected write returned above, so "saved" is never a lie.
    SoundScope.playOn(sound, SoundEventType.transactionSaved);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(_isIncome ? 'Income added' : 'Expense added')),
    );
    navigator.pop();
  }
}

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin:
            const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.border(context),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

