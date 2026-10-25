import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/budget_monitor_service.dart';

/// Gate 2.2: budget notifications use the SELECTED salary day and the same
/// cycle boundary as the dashboard. The Android notifications implementation
/// is faked so the exact titles/bodies are captured instead of posted.

List<String> shown = [];

class _FakeAndroidNotifications extends AndroidFlutterLocalNotificationsPlugin {
  @override
  Future<bool> initialize(
    AndroidInitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<bool?> requestNotificationsPermission() async => true;

  @override
  Future<void> show(
    int id,
    String? title,
    String? body, {
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown.add('$title|$body');
  }
}

TransactionModel _tx(String id, int amountMinor, DateTime date) =>
    TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: TransactionType.expense,
      merchant: 'Merchant',
      category: 'Food',
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: '',
      isExcluded: false,
    );

Future<TransactionProvider> _provider({
  required int salaryDay,
  required int budgetMinor,
}) async {
  SharedPreferences.setMockInitialValues({'salary_day': salaryDay});
  final provider = TransactionProvider();
  await provider.ready;
  await provider.setMonthlyBudgetMinor(budgetMinor);
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    shown = [];
    FlutterLocalNotificationsPlatform.instance = _FakeAndroidNotifications();
  });

  test('spending is measured on the salary cycle, not the calendar month',
      () async {
    final provider = await _provider(salaryDay: 15, budgetMinor: 10000);
    final cycle = provider.currentSalaryCycle;

    // 60% inside the cycle, 20% just before the cycle started. A calendar
    // month sum would cross the 80% warning threshold; the salary cycle must
    // not.
    provider.debugSeed([
      _tx('in-cycle', 6000, cycle.start.add(const Duration(days: 1))),
      _tx('before-cycle', 2000, cycle.start.subtract(const Duration(days: 5))),
    ]);

    await BudgetMonitorService().checkBudgetAlert(provider);

    expect(shown, hasLength(1));
    expect(shown.single, contains('Budget Check-in'));
    expect(shown.single, isNot(contains('Budget Warning')));
  });

  test('80% of the cycle budget raises the warning', () async {
    final provider = await _provider(salaryDay: 1, budgetMinor: 10000);
    final cycle = provider.currentSalaryCycle;
    provider.debugSeed([
      _tx('a', 8000, cycle.start.add(const Duration(days: 1))),
    ]);

    await BudgetMonitorService().checkBudgetAlert(provider);

    expect(shown.single, contains('Budget Warning'));
    expect(shown.single, contains('(80%)'));
  });

  test('100% of the cycle budget raises the exceeded alert', () async {
    final provider = await _provider(salaryDay: 1, budgetMinor: 10000);
    final cycle = provider.currentSalaryCycle;
    provider.debugSeed([
      _tx('a', 10000, cycle.start.add(const Duration(days: 1))),
    ]);

    await BudgetMonitorService().checkBudgetAlert(provider);

    expect(shown.single, contains('Budget Exceeded!'));
  });

  test('under 50% of the cycle budget stays silent', () async {
    final provider = await _provider(salaryDay: 1, budgetMinor: 10000);
    final cycle = provider.currentSalaryCycle;
    provider.debugSeed([
      _tx('a', 4999, cycle.start.add(const Duration(days: 1))),
    ]);

    await BudgetMonitorService().checkBudgetAlert(provider);

    expect(shown, isEmpty);
  });

  group('user-chosen warning thresholds', () {
    Future<TransactionProvider> seeded(int spent, List<String>? thresholds) async {
      SharedPreferences.setMockInitialValues({
        'salary_day': 1,
        if (thresholds != null) 'budget_alert_thresholds': thresholds,
      });
      final provider = TransactionProvider();
      await provider.ready;
      await provider.setMonthlyBudgetMinor(10000);
      final cycle = provider.currentSalaryCycle;
      provider.debugSeed([
        _tx('a', spent, cycle.start.add(const Duration(days: 1))),
      ]);
      return provider;
    }

    test('only the 100% level enabled: 85% stays silent', () async {
      await BudgetMonitorService().checkBudgetAlert(await seeded(8500, ['100']));
      expect(shown, isEmpty);
    });

    test('the 50% level enabled: 55% raises a check-in', () async {
      await BudgetMonitorService()
          .checkBudgetAlert(await seeded(5500, ['50', '100']));
      expect(shown.single, contains('Budget Check-in'));
    });

    test('the highest crossed enabled level wins', () async {
      await BudgetMonitorService()
          .checkBudgetAlert(await seeded(8000, ['50', '80', '100']));
      expect(shown.single, contains('Budget Warning'));
    });

    test('no levels enabled: never notifies, even when exceeded', () async {
      await BudgetMonitorService().checkBudgetAlert(await seeded(20000, []));
      expect(shown, isEmpty);
    });
  });
}