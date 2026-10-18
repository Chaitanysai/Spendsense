import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/glossy_pill.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/sound_scope.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({
    super.key,
    this.initialType = TransactionType.expense,
  });

  /// Lets the dashboard's two action pills open straight into the right mode.
  final TransactionType initialType;

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  // No setState listeners on either controller: the places that read the amount
  // live in ListenableBuilder scopes below, so a keystroke rebuilds those
  // instead of the whole screen.
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();

  String _category = 'Food';
  bool _saving = false;
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
                      _TypeToggle(
                        isIncome: _isIncome,
                        onSelect: _setType,
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Live amount hero
                      GradientHeroCard(
                        gradient: _isIncome ? AppColors.successGradient : null,
                        glowColor: _isIncome ? AppColors.incomeGreen : null,
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
                            ListenableBuilder(
                              listenable: _amountController,
                              builder: (context, _) => FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  Formatters.currency.format(_amount),
                                  style: AppText.onGradient(
                                      size: 40, weight: FontWeight.w800),
                                ),
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

                      if (!_isIncome) ...[
                        Text('Category', style: AppText.title(context)),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (!_isIncome)
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: CategoryStyle.pickerCategories.map((c) {
                            final selected = _category == c;
                            final color = CategoryStyle.color(c);
                            final dark = AppColors.isDark(context);
                            // Selected: glossy gradient derived from category color so it stays tappable/legible.
                            final Gradient catGrad = dark
                                ? LinearGradient(
                                    colors: [
                                      color,
                                      Color.lerp(color, const Color(0xFF3B1D6E),
                                              0.28) ??
                                          color,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : LinearGradient(
                                    colors: [
                                      Color.lerp(color, Colors.white, 0.18) ??
                                          color,
                                      color,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  );
                            return Semantics(
                              button: true,
                              selected: selected,
                              label: c,
                              excludeSemantics: true,
                              child: GlossyPill(
                                selected: selected,
                                selectedGradient: catGrad,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 13, vertical: 9),
                                onTap: () {
                                  if (_category == c) return;
                                  SoundScope.play(
                                      context, SoundEventType.selectionChanged);
                                  setState(() => _category = c);
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(CategoryStyle.icon(c),
                                        size: 16,
                                        color: selected
                                            ? Colors.white
                                            : AppColors.textSecondary(context)),
                                    const SizedBox(width: 6),
                                    Text(
                                      c,
                                      style: AppText.label(context).copyWith(
                                        fontSize: 12,
                                        color: selected
                                            ? Colors.white
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
                child: ListenableBuilder(
                  listenable: _amountController,
                  builder: (context, _) => AppPrimaryButton(
                    label: _isIncome ? 'Add income' : 'Add expense',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    // The saved cue is the button's feedback, so suppress the
                    // generic tap tick rather than stacking two sounds.
                    sound: null,
                    onPressed: _amount > 0 ? _save : null,
                  ),
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
    // Resolved before the await: this route pops itself once the write lands,
    // so the context is no longer usable for the cue.
    final sound = SoundScope.maybeOf(context);

    final tx = TransactionModel(
      id: DateTime.now().toString(),
      amount: amount.toInt(),
      type: _type,
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

    try {
      await provider.addTransaction(tx);
    } catch (error) {
      // Nothing was persisted, so nothing may be announced. Tell the user and
      // leave the form open so the entry can be retried.
      debugPrint('AddTransactionScreen: could not save — $error');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
      return;
    } finally {
      // Always hand the button back, so a failed save can be retried.
      if (mounted) setState(() => _saving = false);
    }

    // Only now, after the write completed and the route is still here: a
    // rejected write returns above, so "saved" is never a lie.
    SoundScope.playOn(sound, SoundEventType.transactionSaved);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(_isIncome ? 'Income added' : 'Expense added')),
    );
    navigator.pop();
  }
}

/// Green-tinted hero variant for income, so money-in reads differently from
/// money-out without depending on the label alone.
class _TypeToggle extends StatelessWidget {
  final bool isIncome;
  final ValueChanged<TransactionType> onSelect;

  const _TypeToggle({required this.isIncome, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              context,
              label: 'Expense',
              icon: Icons.trending_down_rounded,
              selected: !isIncome,
              tint: AppColors.expenseRed,
              onTap: () => onSelect(TransactionType.expense),
            ),
          ),
          Expanded(
            child: _segment(
              context,
              label: 'Income',
              icon: Icons.trending_up_rounded,
              selected: isIncome,
              tint: AppColors.incomeGreen,
              onTap: () => onSelect(TransactionType.income),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required Color tint,
    required VoidCallback onTap,
  }) {
    // The same glossy pill the nav badges and chips use, tinted with the
    // segment's semantic colour so money-out and money-in keep reading
    // red/green rather than the brand ramp. Unselected it stays bare.
    final Gradient selectedGradient = LinearGradient(
      colors: [
        tint.withValues(alpha: 0.16),
        Color.lerp(tint, AppColors.azure, 0.18)!.withValues(alpha: 0.24),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GlossyPill(
        selected: selected,
        bareWhenUnselected: true,
        // The track is a Row of Expanded segments, so the pill has to claim the
        // full width. Without this the pill's Stack shrink-wraps the label and
        // the selected fill would stop short of the segment's edge.
        width: double.infinity,
        selectedGradient: selectedGradient,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        // _setType owns the cue and knows whether the type actually changed, so
        // a cue here would double it on every tap of an already-active segment.
        sound: null,
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? tint : AppColors.textTertiary(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.label(context).copyWith(
                fontSize: 13,
                color: selected ? tint : AppColors.textTertiary(context),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
