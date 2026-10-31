import 'package:flutter/material.dart';
import 'app_sheet.dart';
import 'package:provider/provider.dart';
import '../providers/period_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'app_button.dart';
import 'pressable.dart';
import 'sound_scope.dart';

/// Shows a bottom sheet asking the user which day of the month their salary
/// arrives. Call once on first launch (when PeriodProvider.isSetupDone == false).
///
/// Usage:
///   SalaryDayPrompt.show(context);
class SalaryDayPrompt {
  static Future<void> show(BuildContext context) {
    return showAppSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SalaryDaySheet(),
    );
  }
}

class _SalaryDaySheet extends StatefulWidget {
  const _SalaryDaySheet();

  @override
  State<_SalaryDaySheet> createState() => _SalaryDaySheetState();
}

class _SalaryDaySheetState extends State<_SalaryDaySheet> {
  int _selected = 1;

  @override
  void initState() {
    super.initState();
    // Pre-select whatever is already saved (default 1)
    _selected = context.read<PeriodProvider>().salaryDay;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.page,
        right: AppSpacing.page,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          Text(
            'When do you get your salary?',
            style: AppText.h2(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This sets the start of your monthly spending period. '
            'You can change it later in Settings.',
            textAlign: TextAlign.center,
            style: AppText.body(context).copyWith(height: 1.4),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Day picker — chip grid. It is the only flexible row so all seven
          // days can use the space available without pushing the confirm
          // button off-screen on short devices.
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: 31,
              itemBuilder: (context, index) {
                final day = index + 1;
                final isSelected = day == _selected;
                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: '$day',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: () {
                      if (isSelected) return;
                      SoundScope.play(context, SoundEventType.selectionChanged);
                      setState(() => _selected = day);
                    },
                    sound: null,
                    child: AnimatedContainer(
                      duration: AppMotion.respect(context, AppMotion.fast),
                      decoration: BoxDecoration(
                        gradient: isSelected ? AppColors.brandGradient : null,
                        color:
                            isSelected ? null : AppColors.surfaceAlt(context),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : AppColors.border(context),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$day',
                        style: AppText.label(context).copyWith(
                          fontSize: 13,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          Text(
            _periodPreview(_selected),
            textAlign: TextAlign.center,
            style: AppText.bodySmall(context),
          ),

          const SizedBox(height: AppSpacing.xl),

          AppPrimaryButton(
            label: 'Set salary day',
            icon: Icons.check_rounded,
            onPressed: () async {
              final transactions = context.read<TransactionProvider>();
              await context.read<PeriodProvider>().setSalaryDay(_selected);
              // Budget alerts read the provider's cached cycle; keep it in
              // step with the dashboard instead of waiting for a restart.
              await transactions.reloadSalaryDay();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  /// Shows e.g. "Current period: 25 Sep – 24 Oct" for the salary day the user
  /// has selected, so the preview matches the cycle they will actually get.
  String _periodPreview(int day) {
    final range = PeriodProvider.salaryAlignedPeriod(salaryDay: day);
    final s = range.start;
    final e = range.end;
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return 'Current period: ${s.day} ${months[s.month]} – ${e.day} ${months[e.month]}';
  }
}
