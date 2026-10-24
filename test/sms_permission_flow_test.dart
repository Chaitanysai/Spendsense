import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spendsense/services/sms_service.dart';

/// Regression: the Activity tab starts an SMS sync on launch and on every
/// return to the tab. After the user denied the permission, that background
/// sync used to open Android's App info page each time. Settings may only open
/// when the user explicitly asked for a sync.
void main() {
  late int settingsOpened;

  SmsService serviceWith(PermissionStatus status) {
    settingsOpened = 0;
    return SmsService(
      requestSmsPermission: () async => status,
      openSettings: () async {
        settingsOpened++;
        return true;
      },
    );
  }

  test('a background sync never opens settings when permanently denied',
      () async {
    final service = serviceWith(PermissionStatus.permanentlyDenied);
    expect(await service.requestPermissions(), isFalse);
    expect(settingsOpened, 0);
  });

  test('an explicit user sync opens settings once when permanently denied',
      () async {
    final service = serviceWith(PermissionStatus.permanentlyDenied);
    expect(
        await service.requestPermissions(openSettingsIfBlocked: true), isFalse);
    expect(settingsOpened, 1);
  });

  test('an ordinary denial never opens settings, even on a user sync',
      () async {
    final service = serviceWith(PermissionStatus.denied);
    expect(
        await service.requestPermissions(openSettingsIfBlocked: true), isFalse);
    expect(settingsOpened, 0);
  });

  test('a granted permission passes and opens nothing', () async {
    final service = serviceWith(PermissionStatus.granted);
    expect(
        await service.requestPermissions(openSettingsIfBlocked: true), isTrue);
    expect(settingsOpened, 0);
  });
}
