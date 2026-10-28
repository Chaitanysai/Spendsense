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
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../widgets/app_button.dart';
import '../widgets/pressable.dart';
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

  double get _amount => double.tryParse(_amountController.text) ?? 0;

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
                _AmountCard(
                  amountController: _amountController,
                  amount: _amount,
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
                  _CategoryPicker(
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
        // Bottom inset follows the keyboard so the primary action is never
        // hidden behind it inside the sheet.
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            widget.asSheet
                ? AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom
                : AppSpacing.lg,
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
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: SafeArea(top: false, child: content),
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

/// The live amount surface: a green focal card, with the field inside it so the
/// entered figure and the formatted preview are never two different numbers.
class _AmountCard extends StatelessWidget {
  final TextEditingController amountController;
  final double amount;
  final bool isIncome;

  /// Inline validation message, shown under the field on the card itself.
  final String? errorText;

  static String _safePreview(double amount) {
    final raw = amount.toString();
    // Guard against exponential notation and NaN/Infinity from double
    if (raw.contains('e') || raw.contains('E')) {
      return Formatters.currency.format(0);
    }
    try {
      return Formatters.currency.format(parseRupeesToPaise(raw));
    } on MoneyParseException {
      return Formatters.currency.format(0);
    }
  }

  const _AmountCard({
    required this.amountController,
    required this.amount,
    required this.isIncome,
    this.errorText,
  });

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
                _safePreview(amount),
                maxLines: 1,
                style: AppText.onGradient(size: 36, weight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: amountController,
              autofocus: true,
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
                errorStyle: AppText.onGradient(size: 12, weight: FontWeight.w600),
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

class _CategoryPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _CategoryPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: CategoryStyle.pickerCategories.map((c) {
        final isSelected = selected == c;
        final color = CategoryStyle.color(c);
        return Semantics(
          button: true,
          selected: isSelected,
          label: c,
          excludeSemantics: true,
          child: Pressable(
            onTap: () => onSelect(c),
            sound: SoundEventType.selectionChanged,
            child: AnimatedContainer(
              duration: AppMotion.respect(context, AppMotion.fast),
              curve: AppMotion.easeOut,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.14)
                    : AppColors.surfaceColor(context),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: isSelected
                      ? color.withValues(alpha: 0.55)
                      : AppColors.border(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CategoryStyle.icon(c),
                    size: 16,
                    color:
                        isSelected ? color : AppColors.textSecondary(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    c,
                    style: AppText.label(context).copyWith(
                      fontSize: 12,
                      color:
                          isSelected ? color : AppColors.textSecondary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
