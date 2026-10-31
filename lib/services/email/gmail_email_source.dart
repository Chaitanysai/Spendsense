import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';

import 'gmail_token_client.dart';

/// Thrown when an email import is requested while another ledger sync is
/// running. The caller should tell the person to try again rather than report
/// "no new emails".
class EmailImportBusyException implements Exception {
  const EmailImportBusyException();
}

/// Thrown when the person has not run the explicit Gmail consent flow.
class EmailConsentRequiredException implements Exception {
  const EmailConsentRequiredException();
}

/// Thrown when Gmail authorisation cannot be completed interactively.
class EmailAuthUnavailableException implements Exception {
  final String message;

  const EmailAuthUnavailableException(this.message);

  @override
  String toString() => 'EmailAuthUnavailableException: $message';
}

/// One bank alert message returned by [GmailEmailSource].
class GmailAlert {
  final String id;
  final String subject;
  final String from;
  final String text;
  final DateTime date;

  const GmailAlert({
    required this.id,
    required this.subject,
    required this.from,
    required this.text,
    required this.date,
  });
}

/// On-device Gmail reader.
///
/// This service does not parse transactions. It only:
///  * asks for explicit consent before the OAuth scope is requested,
///  * lists messages from the allowlisted bank senders after the last import,
///  * extracts plain text from the message body,
///  * returns the text with a stable Gmail message id and date.
///
/// The access token never leaves the process; Gmail messages are fetched
/// directly to the device, and only the recipient's own mailbox is readable.
/// The scope is read-only and is never used to send or modify mail.
class GmailEmailSource {
  static const prefsConsentKey = 'email_gmail_consent_v1';
  static const prefsLastSyncKey = 'email_gmail_last_sync_v1';
  static const prefsSendersKey = 'email_gmail_senders_v1';
  static const prefsConnectedEmailKey = 'email_gmail_connected_email_v1';

  static const _serverClientId = String.fromEnvironment('GMAIL_SERVER_CLIENT_ID');
  static const scope = 'https://www.googleapis.com/auth/gmail.readonly';

  /// Bank alert senders. Kept as exact domains (not free-form regexes) so a
  /// look-alike domain cannot be introduced by typing into the field.
  static const defaultSenderDomains = <String>[
    'hdfcbank.net',
    'hdfcbank.com',
    'icicibank.com',
    'sbi.co.in',
    'onlinesbi.sbi',
    'axisbank.com',
    'kotak.com',
    'idfcfirstbank.com',
    'yesbank.in',
    'indusind.com',
    'federalbank.co.in',
    'bankofbaroda.in',
    'pnb.co.in',
    'canarabank.com',
    'unionbankofindia.co.in',
  ];

  /// A Gmail message is only eligible when the From domain is in the allowlist
  /// and the subject looks like a transaction alert.
  static const _debitSubjectHints = <String>[
    'debit',
    'debited',
    'spent',
    'transaction',
    'payment',
    'purchase',
    'withdrawn',
    'alert',
  ];

  Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsConsentKey) ?? false;
  }

  Future<void> setConsent(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsConsentKey, value);
    if (!value) {
      await prefs.remove(prefsLastSyncKey);
      await prefs.remove(prefsConnectedEmailKey);
    }
  }

  Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsLastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Records a successful import cursor.
  ///
  /// Callers must invoke this only after the parsed batch has been durably
  /// committed; advancing it earlier would skip the messages that failed to
  /// save. The value is the newest Gmail `internalDate` seen, not wall-clock
  /// time, so a clock skew or a slow sync cannot move it past unread mail.
  Future<void> markImported(DateTime newestMessageTime) async {
    final existing = await lastSyncAt();
    if (existing != null && existing.isAfter(newestMessageTime)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsLastSyncKey,
      newestMessageTime.toUtc().toIso8601String(),
    );
  }

  Future<String?> connectedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsConnectedEmailKey);
  }

  Future<List<String>> senderDomains() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(prefsSendersKey);
    return stored == null || stored.isEmpty
        ? List.of(defaultSenderDomains)
        : stored;
  }

  Future<void> setSenderDomains(List<String> domains) async {
    final normalised = <String>{};
    final domainPattern = RegExp(
      r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
    );
    for (final raw in domains) {
      final domain = raw.trim().toLowerCase();
      if (domainPattern.hasMatch(domain)) normalised.add(domain);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefsSendersKey, normalised.toList()..sort());
  }

  Future<void> _initialise() async {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
    } catch (_) {
      throw const EmailAuthUnavailableException(
        'Google Sign-In is not configured for this build.',
      );
    }
  }

  /// Requests the read-only Gmail scope. Must only be called after
  /// [hasConsent] is true and after a person presses Connect.
  Future<String> connect() async {
    if (!await hasConsent()) {
      throw const EmailConsentRequiredException();
    }
    await _initialise();
    final account = await _connectInteractive();
    final authorization =
        await account.authorizationClient.authorizeScopes(const [scope]);
    if (authorization.accessToken.isEmpty) {
      throw const EmailAuthUnavailableException('Gmail did not grant access.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsConnectedEmailKey, account.email);
    return account.email;
  }

  Future<GoogleSignInAccount> _syncSilently() async {
    // A normal sync must never show account or consent UI. If the silent path
    // is unavailable the person has to press Connect again.
    try {
      final account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account != null) return account;
    } catch (_) {
      // Fall through to the actionable error below.
    }
    throw const EmailAuthUnavailableException(
      'Gmail needs to be reconnected before syncing.',
    );
  }

  Future<GoogleSignInAccount> _connectInteractive() async {
    try {
      return await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // Do not echo platform text; it can include account identifiers.
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const EmailAuthUnavailableException('Google sign-in cancelled.');
      }
      throw const EmailAuthUnavailableException(
        'Gmail is not available in this build: the Android OAuth client is '
        'missing from google-services.json. Re-download that file after '
        'creating the client for package com.example.spendsense and this '
        "build's signing SHA-1, then rebuild and reinstall.",
      );
    } catch (_) {
      throw const EmailAuthUnavailableException(
        'Google sign-in could not complete on this device.',
      );
    }
  }

  Future<void> disconnect() async {
    try {
      await _initialise();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Disconnect is best-effort; local consent is cleared regardless.
    }
    // setConsent(false) also drops the cursor and the connected address.
    await setConsent(false);
  }

  /// Lists bank alert messages and returns extracted text.
  ///
  /// This never advances the cursor. The caller must call [markImported] after
  /// the batch is committed. Pagination is exhausted so a large mailbox cannot
  /// silently lose messages beyond one page.
  ///
  /// Messages whose `gmail:<id>` is in [seenIds] are skipped before the body is
  /// fetched, so a repeated sync does not re-download already imported mail.
  Future<List<GmailAlert>> fetchBankAlerts({
    required Set<String> seenIds,
    DateTime? since,
  }) async {
    if (!await hasConsent()) {
      throw const EmailConsentRequiredException();
    }
    await _initialise();
    final account = await _syncSilently();
    final authorization =
        await account.authorizationClient.authorizeScopes(const [scope]);
    final client = GmailTokenClient(authorization.accessToken);
    final api = gmail.GmailApi(client);
    // The Gmail client owns no request-specific auth state; the bearer header
    // is attached by GmailTokenClient for every call.
    try {
      final domains = await senderDomains();
      final query = _buildQuery(domains, since);
      final messageRefs = <gmail.Message>[];
      String? pageToken;
      do {
        final list = await api.users.messages.list(
          'me',
          q: query,
          pageToken: pageToken,
          maxResults: 100,
        );
        messageRefs.addAll(list.messages ?? const []);
        pageToken = list.nextPageToken;
      } while (pageToken != null);

      final results = <GmailAlert>[];
      for (final ref in messageRefs) {
        final id = ref.id;
        if (id == null || seenIds.contains('gmail:$id')) continue;
        final message = await api.users.messages.get(
          'me',
          id,
          format: 'full',
        );
        final subject = _header(message, 'Subject');
        final from = _header(message, 'From');
        if (!isAllowedSender(from, domains)) continue;
        if (!isDebitSubject(subject)) continue;
        final text = _extractText(message.payload);
        if (text.trim().isEmpty) continue;
        results.add(
          GmailAlert(
            id: id,
            subject: subject,
            from: from,
            text: text,
            // Gmail's internalDate is epoch milliseconds. It survives time
            // zones and is preferred over the RFC 2822 Date header.
            date: _messageDate(message),
          ),
        );
      }
      return results;
    } finally {
      client.close();
    }
  }

  @visibleForTesting
  static DateTime messageDateForTest(gmail.Message message) =>
      _messageDate(message);

  static DateTime _messageDate(gmail.Message message) {
    final internal = int.tryParse(message.internalDate ?? '');
    if (internal != null) {
      return DateTime.fromMillisecondsSinceEpoch(internal, isUtc: true);
    }
    return _parseDate(_header(message, 'Date')) ?? DateTime.now();
  }

  static String _buildQuery(List<String> domains, DateTime? since) {
    final senders = domains.map((d) => 'from:$d').join(' OR ');
    final after = since == null
        ? ''
        : ' after:${since.toUtc().millisecondsSinceEpoch ~/ 1000}';
    return '($senders) newer_than:30d$after';
  }

  static String _header(gmail.Message message, String name) {
    for (final header in message.payload?.headers ?? const []) {
      if (header.name?.toLowerCase() == name.toLowerCase()) {
        return header.value ?? '';
      }
    }
    return '';
  }

  /// The From header can contain `Name <alerts@bank.example>`. Only the
  /// mailbox domain is compared, case-insensitively, against exact domains.
  ///
  /// A display name may itself contain angle brackets — e.g.
  /// `"HDFC <alerts@hdfcbank.net>" <x@attacker.example>` — so this rejects any
  /// header with more than one angle-addr and uses the **last** one. Taking the
  /// first match would let a sender borrow an allowlisted domain in the
  /// display name while the real mailbox belongs to the attacker.
  @visibleForTesting
  static bool isAllowedSender(String from, List<String> domains) {
    final angleAddresses =
        RegExp(r'<([^<>]*)>').allMatches(from).map((m) => m.group(1)!.trim());
    final list = angleAddresses.toList();
    if (list.length > 1) return false;
    final address = (list.isEmpty ? from.trim() : list.single).toLowerCase();
    final at = address.lastIndexOf('@');
    if (at < 0 || at == address.length - 1) return false;
    final domain = address.substring(at + 1);
    return domains.contains(domain);
  }

  @visibleForTesting
  static bool isDebitSubject(String subject) {
    final lower = subject.toLowerCase();
    return _debitSubjectHints.any(lower.contains);
  }

  /// Parses an email `Date` header, which is RFC 2822, not ISO 8601.
  ///
  /// Example: `Tue, 14 Oct 2026 10:00:00 +0530`. Only used as a fallback when
  /// Gmail omits `internalDate`.
  @visibleForTesting
  static DateTime? parseRfc2822Date(String value) {
    if (value.isEmpty) return null;
    // Drop the optional day-of-week and any trailing comments.
    final cleaned = value
        .replaceFirst(RegExp(r'^[A-Za-z]{3},\s*'), '')
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .trim();
    final match = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s+([+-])(\d{2})(\d{2})$',
    ).firstMatch(cleaned);
    if (match == null) return null;
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    final sign = match.group(7) == '-' ? -1 : 1;
    final offsetMinutes =
        sign * (int.parse(match.group(8)!) * 60 + int.parse(match.group(9)!));
    final utc = DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
    );
    return utc.subtract(Duration(minutes: offsetMinutes));
  }

  static DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value) ?? parseRfc2822Date(value);
  }

  /// Walk MIME parts and return `text/plain` when present, otherwise the HTML
  /// body stripped to text. Remote images are not loaded; no network call is
  /// made for any part of the message.
  static String _extractText(gmail.MessagePart? part) {
    if (part == null) return '';
    final mimeType = part.mimeType?.toLowerCase() ?? '';
    if (mimeType == 'text/plain' && part.body?.data != null) {
      return _decodeBody(part.body!.data!);
    }
    if (mimeType == 'text/html' && part.body?.data != null) {
      return htmlToText(_decodeBody(part.body!.data!));
    }
    for (final child in part.parts ?? const <gmail.MessagePart>[]) {
      final text = _extractText(child);
      if (text.trim().isNotEmpty) return text;
    }
    return '';
  }

  static String _decodeBody(String encoded) {
    try {
      return utf8.decode(
        base64Url.decode(base64Url.normalize(encoded)),
        allowMalformed: true,
      );
    } catch (_) {
      return '';
    }
  }

  /// Removes scripts, styles, tags and common entities. Whitespace is
  /// collapsed so the parser sees readable lines.
  @visibleForTesting
  static String htmlToText(String html) {
    return html
        .replaceAll(
            RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#8377;', '₹')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }
}


