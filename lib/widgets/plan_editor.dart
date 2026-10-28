import 'package:flutter/material.dart';
import 'app_sheet.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/recurring_plan.dart';
import '../models/transaction_model.dart';
import '../providers/planner_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/money_parser.dart';

/// Opens the bill/recurring-plan editor.
///
/// Pass [plan] to edit, or [from] to start a plan from an existing transaction
/// (the transaction itself is only read, never changed). Saving writes a
/// *plan*; it never creates a ledger transaction.
Future<void> showPlanEditor(
  BuildContext context, {
  RecurringPlan? plan,
  TransactionModel? from,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _PlanEditor(plan: plan, from: from),
  );
}

class _PlanEditor extends StatefulWidget {
  final RecurringPlan? plan;
  final TransactionModel? from;

  const _PlanEditor({this.plan, this.from});

  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late String _category;
  late PlanFrequency _frequency;
  late DateTime _due;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    final t = widget.from;
    _title = TextEditingController(text: p?.title ?? t?.merchant ?? '');
    final minor = p?.amountMinor ?? t?.amountMinor;
    _amount = TextEditingController(
        text: minor == null ? '' : formatPaise(minor, trimZeroPaise: true));
    _category =
        p?.category ?? t?.category ?? CategoryStyle.pickerCategories.first;
    _frequency = p?.frequency ?? PlanFrequency.monthly;
    if (p != null) {
      _due = p.nextDue;
    } else if (t != null) {
      // First occurrence on or after today, stepping from the transaction date.
      _due = RecurringPlan.create(
        id: 'preview',
        title: 'x',
        category: 'x',
        amountMinor: 1,
        frequency: _frequency,
        nextDue: t.date,
      ).rolledForwardTo(DateTime.now()).nextDue;
    } else {
      final n = DateTime.now();
      _due = DateTime(n.year, n.month, n.day).add(const Duration(days: 7));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final planner = context.read<PlannerProvider>();
    final existing = widget.plan;
    try {
      final minor = parseRupeesToPaise(_amount.text);
      final candidate = existing == null
          ? RecurringPlan.create(
              id: 'plan_${DateTime.now().microsecondsSinceEpoch}',
              title: _title.text,
              category: _category,
              amountMinor: minor,
              frequency: _frequency,
              nextDue: _due,
              sourceTransactionId: widget.from?.id,
            )
          : existing.copyWith(
              title: _title.text,
              category: _category,
              amountMinor: minor,
              frequency: _frequency,
              nextDue: _due,
            );
      candidate.validate();
      setState(() {
        _saving = true;
        _error = null;
      });
      existing == null
          ? await planner.addPlan(candidate)
          : await planner.updatePlan(candidate);
      if (mounted) Navigator.pop(context);
    } on MoneyParseException {
      setState(() => _error = 'Enter a valid amount.');
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'This could not be saved.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = {
      ...CategoryStyle.pickerCategories,
      _category,
    }.toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.plan == null ? 'Plan a bill' : 'Edit bill',
                style: AppText.h2(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'A plan is a reminder of what you expect to pay. It never adds '
              'a transaction by itself.',
              style: AppText.bodySmall(context),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration:
                  const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              borderRadius: AppRadius.mdAll,
              dropdownColor: AppColors.surfaceColor(context),
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<PlanFrequency>(
              initialValue: _frequency,
              isExpanded: true,
              borderRadius: AppRadius.mdAll,
              dropdownColor: AppColors.surfaceColor(context),
              decoration: const InputDecoration(labelText: 'Repeats'),
              items: [
                for (final f in PlanFrequency.values)
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: (v) => setState(() => _frequency = v ?? _frequency),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_rounded),
              label: Text('Next due ${DateFormat('d MMM yyyy').format(_due)}'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(_error!,
                    style: AppText.label(context)
                        .copyWith(color: AppColors.expenseRed)),
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(widget.plan == null ? 'Save plan' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
