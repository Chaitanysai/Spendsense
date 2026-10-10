import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/period_provider.dart';
import '../utils/app_colors.dart';

/// Shows a bottom sheet asking the user which day of the month their salary
/// arrives. Call once on first launch (when PeriodProvider.isSetupDone == false).
///
/// Usage:
///   SalaryDayPrompt.show(context);
class SalaryDayPrompt {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 24),

          // Title
          Text(
            'When do you get your salary?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This sets the start of your monthly spending period. '
            'You can change it later in Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary(context),
            ),
          ),

          const SizedBox(height: 28),

          // Day picker — scrollable horizontal chip grid
          SizedBox(
            height: 180,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: 31,
              itemBuilder: (context, index) {
                final day = index + 1;
                final isSelected = day == _selected;
                return GestureDetector(
                  onTap: () => setState(() => _selected = day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryPurple
                          : AppColors.scaffold(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryPurple
                            : AppColors.border(context),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary(context),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Helper text for the selected day
          Text(
            _periodPreview(_selected),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),

          const SizedBox(height: 24),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () async {
                await context.read<PeriodProvider>().setSalaryDay(_selected);
                if (context.mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Set salary day',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows e.g. "Your period: 25 Mar – 24 Apr" based on today
  String _periodPreview(int day) {
    final range = PeriodProvider.salaryAlignedPeriod(day, months: 1);
    final s = range.start;
    final e = range.end;
    const months = ['','Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];
    return 'Current period: ${s.day} ${months[s.month]} – ${e.day} ${months[e.month]}';
  }
}
