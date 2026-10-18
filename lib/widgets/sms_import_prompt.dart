import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/transaction_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'app_button.dart';

class SmsImportPrompt {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SmsImportPromptSheet(),
    );
  }
}

class _SmsImportPromptSheet extends StatefulWidget {
  const _SmsImportPromptSheet();

  @override
  State<_SmsImportPromptSheet> createState() => _SmsImportPromptSheetState();
}

class _SmsImportPromptSheetState extends State<_SmsImportPromptSheet> {
  late DateTime _selectedDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('d MMM yyyy').format(_selectedDate);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(Icons.sms_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text('Check SMS from when?',
                        style: AppText.h2(context)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'SpendSense will scan bank and UPI SMS from the date you choose and build your transactions from there.',
                style: AppText.body(context).copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xl),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: _saving ? null : _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt(context),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(Icons.calendar_month_rounded,
                            color: AppColors.brand),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('START DATE',
                                style: AppText.overline(context)),
                            const SizedBox(height: 2),
                            Text(label,
                                style: AppText.title(context)
                                    .copyWith(fontSize: 15)),
                          ],
                        ),
                      ),
                      Icon(Icons.edit_rounded,
                          size: 20, color: AppColors.textSecondary(context)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppPrimaryButton(
                label: 'Start syncing SMS',
                icon: Icons.sync_rounded,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDate: _selectedDate,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context
        .read<TransactionProvider>()
        .setSmsScanStartDate(_selectedDate);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
