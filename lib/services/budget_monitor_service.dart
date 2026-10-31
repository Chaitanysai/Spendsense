import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/budget_math.dart';
import '../utils/formatters.dart';
import '../providers/transaction_provider.dart';

class BudgetMonitorService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // Android initialization
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);

    // Request permissions
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _isInitialized = true;
    debugPrint(' Budget Monitor initialized');
  }

  /// Check spending against the budget for the SALARY CYCLE (approved rule 6:
  /// the monthly budget applies to the salary cycle, not the calendar month),
  /// using the same boundary as the dashboard so the notification and the
  /// gauge can never disagree.
  Future<void> checkBudgetAlert(TransactionProvider provider) async {
    await init();

    final budget = provider.monthlyBudgetMinor;
    final spent = provider.totalExpensesForPeriod(provider.currentSalaryCycle);
    if (budget <= 0) return;

    // Keep threshold decisions in integer paise. Only the label is double.
    final percentage = spent * 100.0 / budget;

    // The user may choose which of 50 / 80 / 100 % warn them (Budgets screen).
    // Without a saved choice the original ladder below applies unchanged.
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('budget_alert_thresholds');
    if (stored != null) {
      final crossed = BudgetProgress(spentMinor: spent, budgetMinor: budget)
          .crossedThreshold(normalizeBudgetThresholds(stored.map(int.tryParse)));
      if (crossed == null) return;
      final spentLabel = Formatters.currency.format(spent);
      final budgetLabel = Formatters.currency.format(budget);
      // Over budget is a fact about spent vs budget, not about which threshold
      // was configured. Checking only `crossed` printed "money left" whenever
      // the 100% threshold was disabled.
      if (spent >= budget) {
        await _showNotification('Budget Exceeded!',
            'You have spent $spentLabel out of $budgetLabel. Consider reducing expenses.');
      } else {
        await _showNotification(
            crossed >= 80 ? 'Budget Warning' : 'Budget Check-in',
            'You have spent $spentLabel out of $budgetLabel '
            '(${percentage.toStringAsFixed(0)}%). '
            '${Formatters.currency.format(budget - spent)} left.');
      }
      return;
    }

    // Don't alert if under 50% - too early
    if (spent * 100 < budget * 50) return;

    String? title;
    String? body;

    if (percentage >= 100) {
      title = 'Budget Exceeded!';
      body = 'You have spent ${Formatters.currency.format(spent)} out of '
          '${Formatters.currency.format(budget)}. Consider reducing expenses.';
    } else if (percentage >= 80) {
      title = 'Budget Warning';
      body = 'You have spent ${Formatters.currency.format(spent)} out of '
          '${Formatters.currency.format(budget)} '
          '(${percentage.toStringAsFixed(0)}%). Only '
          '${Formatters.currency.format(budget - spent)} left!';
    } else if (percentage >= 60) {
      title = 'Budget Check-in';
      body = 'You have spent ${Formatters.currency.format(spent)} out of '
          '${Formatters.currency.format(budget)}. You are doing well!';
    }

    if (title != null && body != null) {
      await _showNotification(title, body);
    }
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'budget_alerts',
      'Budget Alerts',
      channelDescription: 'Notifications about your spending budget',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
    );

    debugPrint(' Notification shown: $title');
  }

  /// Cancel all budget notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
