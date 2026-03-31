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
  final SmsQuery _query = SmsQuery();

  // 🔐 Request SMS permission
  Future<bool> requestPermissions() async {
    final status = await Permission.sms.request();

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    return false;
  }

  // 📩 Fetch SMS from inbox
  Future<List<SmsMessageModel>> fetchTransactionSms() async {
    try {
      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 200,
      );

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
      }).toList();
    } catch (e) {
      print("❌ SMS fetch error: $e");
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
