import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  /// Check spending vs budget and show alerts
  Future<void> checkBudgetAlert(TransactionProvider provider) async {
    await init();

    final budget = provider.monthlyBudget;
    final spent = provider.totalExpenses;
    final percentage = (spent / budget) * 100;

    // Don't alert if under 50% - too early
    if (percentage < 50) return;

    String? title;
    String? body;

    if (percentage >= 100) {
      title = 'Budget Exceeded!';
      body =
          'You have spent ${spent.toStringAsFixed(0)} out of ${budget.toStringAsFixed(0)}. Consider reducing expenses.';
    } else if (percentage >= 80) {
      title = 'Budget Warning';
      body =
          'You have spent ${spent.toStringAsFixed(0)} out of ${budget.toStringAsFixed(0)} (${percentage.toStringAsFixed(0)}%). Only ${(budget - spent).toStringAsFixed(0)} left!';
    } else if (percentage >= 60) {
      title = 'Budget Check-in';
      body =
          'You have spent ${spent.toStringAsFixed(0)} out of ${budget.toStringAsFixed(0)}. You are doing well!';
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
