import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsMessageModel {
  final String id;
  final String body;
  final DateTime date;

  SmsMessageModel({
    required this.id,
    required this.body,
    required this.date,
  });
}

class SmsService {
  /// The permission request and the system-settings opener are injectable so
  /// the denial flow can be tested without a device.
  SmsService({
    Future<PermissionStatus> Function()? requestSmsPermission,
    Future<bool> Function()? openSettings,
  })  : _requestSmsPermission =
            requestSmsPermission ?? (() => Permission.sms.request()),
        _openSettings = openSettings ?? openAppSettings;

  final SmsQuery _query = SmsQuery();
  final Future<PermissionStatus> Function() _requestSmsPermission;
  final Future<bool> Function() _openSettings;

  /// Requests SMS permission and reports whether it is granted.
  ///
  /// Android's system settings are opened for a permanently denied permission
  /// only when [openSettingsIfBlocked] is true, i.e. the user just asked for a
  /// sync. Background syncs (the Activity tab syncs on launch and on every
  /// return to the tab) must never throw the user out of the app.
  Future<bool> requestPermissions({bool openSettingsIfBlocked = false}) async {
    final status = await _requestSmsPermission();

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied && openSettingsIfBlocked) {
      await _openSettings();
    }

    return false;
  }

  // 📩 Fetch SMS from inbox
  Future<List<SmsMessageModel>> fetchTransactionSms({
    DateTime? fromDate,
  }) async {
    try {
      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count:
            800, // Process larger chunk so we don't miss past sms due to inbox limit
      );

      final normalizedFromDate = fromDate == null
          ? null
          : DateTime(fromDate.year, fromDate.month, fromDate.day);

      return messages.map((msg) {
        // ─── FIX: msg.date from flutter_sms_inbox is DateTime?, NOT int ───
        // The previous `msg.date is int` check was always false, causing
        // every transaction to use DateTime.now() instead of the real date.
        final DateTime resolvedDate = _safeDate(msg.date);

        return SmsMessageModel(
          id: msg.id?.toString() ?? "",
          body: msg.body ?? "",
          date: resolvedDate,
        );
      }).where((msg) {
        if (normalizedFromDate == null) return true;
        final smsDay = DateTime(msg.date.year, msg.date.month, msg.date.day);
        return !smsDay.isBefore(normalizedFromDate);
      }).toList();
    } catch (e) {
      debugPrint("❌ SMS fetch error: $e");
      return [];
    }
  }

  /// Safely resolves an SMS date from flutter_sms_inbox.
  ///
  /// flutter_sms_inbox exposes [SmsMessage.date] as [DateTime?].
  /// It can also sometimes surface as a raw millisecond int on older
  /// plugin versions — handle both cases defensively.
  DateTime _safeDate(dynamic raw) {
    if (raw == null) return DateTime.now();

    // Modern plugin versions return DateTime directly
    if (raw is DateTime) return raw;

    // Older / edge cases may return a millisecond epoch int
    if (raw is int) {
      // Sanity-check: epoch ms for year 2000 = 946684800000
      // Anything smaller is likely seconds, not milliseconds
      if (raw > 946684800000) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      } else if (raw > 946684800) {
        // Looks like epoch seconds — convert
        return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
      }
    }

    // String fallback (some OEM ROMs serialize as ISO string)
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }

    return DateTime.now();
  }
}
