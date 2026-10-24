import 'package:flutter/material.dart';
import 'app_sheet.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/transaction_provider.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'app_button.dart';
import 'pressable.dart';
import 'sound_scope.dart';

class SmsImportPrompt {
  static Future<void> show(BuildContext context) {
    return showAppSheet(
      context: context,
      // The prompt is a helpful first-run setup, not a navigation lock. Users
      // must still be able to reach Activity and configure the date later.
      isDismissible: true,
      enableDrag: true,
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
              Pressable(
                onTap: _saving ? null : _pickDate,
                sound: SoundEventType.buttonTap,
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
      // The picker returned across an async gap, so re-check before touching
      // the scope or the state of a sheet that may have been dismissed.
      if (!mounted) return;
      SoundScope.play(context, SoundEventType.selectionChanged);
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Resolved before the await: this sheet pops itself once the write lands.
    final sound = SoundScope.maybeOf(context);
    try {
      await context
          .read<TransactionProvider>()
          .setSmsScanStartDate(_selectedDate);
    } catch (error) {
      // The scan window was not stored, so nothing succeeded and nothing may
      // announce success. Leave the sheet open so the date can be retried.
      debugPrint('SmsImportPrompt: could not save start date — $error');
      if (!mounted) return;
      setState(() => _saving = false);
      SoundScope.playOn(sound, SoundEventType.actionFailed);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Please try again.')),
      );
      return;
    }
    SoundScope.playOn(sound, SoundEventType.actionSucceeded);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
