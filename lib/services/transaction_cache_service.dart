import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ledger_encryption_service.dart';
import '../models/transaction_model.dart';

/// Test seam: called immediately BEFORE every persisted mutation made by a
/// ledger import. Throwing simulates a failed or interrupted write.
typedef WriteHook = Future<void> Function(String op, String key);

/// One message the scanner decided not to turn into a transaction.
///
/// Deliberately minimal: an SMS id, a coarse reason CODE and when it was first
/// skipped. The message body, merchant, amount and account are never stored —
/// the reason is enough to diagnose and the id is enough to retry.
@immutable
class RejectedMessage {
  final String id;

  /// One of: CREDIT, OTP_SECURITY, NOT_COMPLETED, PROMO, BALANCE_ONLY,
  /// UNKNOWN, NO_PARSE. Never derived from message text beyond the code.
  final String reason;

  /// When this message was first skipped. Drives the retention window.
  final DateTime firstSeen;

  const RejectedMessage({
    required this.id,
    required this.reason,
    required this.firstSeen,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'reason': reason,
        'firstSeen': firstSeen.toIso8601String(),
      };

  /// Accepts the current map format and the legacy bare-string entry (an id
  /// with no metadata, treated as first seen now).
  static RejectedMessage? tryParse(Object? raw, {DateTime? now}) {
    if (raw is String) {
      if (raw.isEmpty) return null;
      return RejectedMessage(
          id: raw, reason: 'UNKNOWN', firstSeen: now ?? DateTime.now());
    }
    if (raw is Map) {
      final id = raw['id'];
      if (id is! String || id.isEmpty) return null;
      final reason = raw['reason'];
      final seen = raw['firstSeen'];
      return RejectedMessage(
        id: id,
        reason: reason is String && reason.isNotEmpty ? reason : 'UNKNOWN',
        firstSeen: (seen is String ? DateTime.tryParse(seen) : null) ??
            now ??
            DateTime.now(),
      );
    }
    return null;
  }
}

/// A backup was rejected, or could not be saved. Messages never contain
/// record contents (merchants, amounts, SMS text) — only a stable [code], a
/// fixed description and, when relevant, the zero-based [recordIndex].
class LedgerImportException implements Exception {
  final String code;
  final String message;
  final int? recordIndex;

  const LedgerImportException(this.code, this.message, {this.recordIndex});

  @override
  String toString() => 'LedgerImportException($code'
      '${recordIndex == null ? '' : ' @record $recordIndex'}): $message';
}

class LedgerMigrationException implements Exception {
  final String code;
  final String message;

  const LedgerMigrationException(this.code, this.message);

  @override
  String toString() => 'LedgerMigrationException($code): $message';
}

class _MigrationProgress {
  final String kind;
  final String state;
  final Set<String> sourceIds;
  final Set<String> convertedIds;
  final bool explicitLists;

  const _MigrationProgress({
    required this.kind,
    required this.state,
    required this.sourceIds,
    required this.convertedIds,
    required this.explicitLists,
  });
}

/// SpendSense 2.0 Local Database & Repository
/// Persists parsed transactions locally so the app never re-parses or
/// re-calls the AI for SMS messages already processed.
/// Also supports JSON export and import for backup/restore.
///
/// ## Import policy
///
/// An import is validated completely before anything is written; any problem
/// rejects the whole file and leaves the ledger byte-for-byte unchanged.
///
/// * Envelope: `{"version": 2|"2"|"2.0" (optional), "count": int (optional),
///   "transactions": [...]}` or a bare list (legacy backups).
/// * Each record needs a non-empty string `id` (max 200 chars, not one of the
///   reserved storage names), an integral `amount` of 1..1,000,000,000,000
///   whole rupees, `type` "expense"|"income" and a parseable `date`. Optional
///   fields must have the right type when present.
/// * Duplicate ids, a `count` that disagrees with the records, an unsupported
///   version, and an empty payload in replace mode are rejected.
/// * merge (default) upserts by id, the imported record winning.
///   replace makes the ledger exactly the imported set. Both are idempotent.
///
/// ## Activation
///
/// SharedPreferences cannot change several keys atomically, so a validated
/// import is first written as ONE key (the journal). Payloads are then written
/// and read back, and the visible ledger switches in a single write of the id
/// index. A failure before that switch is rolled back; a crash is completed
/// from the journal on the next start. Nothing partial is ever visible.
class TransactionCacheService {
  static const _idsKey = 'tx_cache_ids';
  static const _encryptedIdsKey = 'tx_cache_ids_v2';
  static const _migrationKey = 'tx_money_migration_v2';
  static const _rejectedIdsKey = 'tx_rejected_ids';
  static const _metaKey = 'tx_cache_meta';
  static const _prefix = 'tx_';
  static const _encryptedPrefix = 'txe_';

  /// Deliberately outside the `tx_` namespace so no record id can collide.
  static const _journalKey = 'txj_import_journal';

  /// `tx_` + id is a storage key, so these ids would overwrite the ledger's
  /// own bookkeeping keys.
  static const _indexRecordId = '__ledger_index__';
  static const _migrationRecordId = '__migration_progress__';
  static const _reservedIds = {'cache_ids', 'rejected_ids', 'cache_meta'};

  static const _maxIdLength = 200;
  static const _maxAmountMinor = 100000000000000;

  late SharedPreferences _prefs;
  final Set<String> _cachedIds = {};
  final LedgerEncryptionService _encryption;

  /// Skipped messages, keyed by SMS id. Only an id, a reason code and a
  /// timestamp are retained; never the message body or any financial field.
  final Map<String, RejectedMessage> _rejected = {};

  bool _initialised = false;
  bool _legacyPlaintextIndex = false;

  /// How long a skipped message is remembered before it is forgotten and can
  /// be reconsidered. Approved policy: 90 days.
  static const Duration rejectedRetention = Duration(days: 90);

  /// See [writeHook]. Null in production.
  WriteHook? writeHook;

  /// Test-only accessor for [writeHook] from other libraries.
  @visibleForTesting
  WriteHook? get debugWriteHook => writeHook;
  @visibleForTesting
  set debugWriteHook(WriteHook? hook) => writeHook = hook;

  TransactionCacheService({
    this.writeHook,
    LedgerEncryptionService? encryption,
  }) : _encryption = encryption ?? LedgerEncryptionService();

  Future<void> init() async {
    if (_initialised) return;
    _prefs = await SharedPreferences.getInstance();

    final encryptedRaw = _prefs.getString(_encryptedIdsKey);
    if (encryptedRaw != null) {
      await _loadIndex(encryptedRaw);
    } else {
      final legacyRaw = _prefs.getString(_idsKey);
      final legacyIds = legacyRaw == null ? <String>[] : _decodeIds(legacyRaw);
      await _migrateLegacyStore(legacyIds);
      _cachedIds.addAll(legacyIds);
    }

    final rawRejected = _prefs.getString(_rejectedIdsKey);
    if (rawRejected != null) {
      final list = jsonDecode(rawRejected) as List;
      for (final entry in list) {
        final parsed = RejectedMessage.tryParse(entry);
        if (parsed != null) _rejected[parsed.id] = parsed;
      }
    }
    _initialised = true;
    await _recoverJournal();
    if (_legacyPlaintextIndex) {
      await _writeIndex(_cachedIds.toList());
      _legacyPlaintextIndex = false;
    }
    await _reconcileLegacyStore();
    await _validateIndexConsistency();
    await _pruneRejected();
    debugPrint(
        '📦 Local DB init — ${_cachedIds.length} txs, ${_rejected.length} rejected');
  }

  Future<void> _loadIndex(String raw) async {
    final trimmed = raw.trim();
    final List<String> ids;
    if (trimmed.startsWith('{')) {
      await _encryption.requireExistingKey();
      final clear = await _encryption.decryptText(
        raw,
        expectedRecordId: _indexRecordId,
      );
      ids = _decodeIds(clear);
    } else {
      // Compatibility with the old plaintext index. Upgrade it only after
      // validating all payloads and retaining the old source records.
      ids = _decodeIds(raw);
      final hasPayloads =
          _prefs.getKeys().any((key) => key.startsWith(_encryptedPrefix));
      if (hasPayloads) {
        await _encryption.requireExistingKey();
      } else {
        await _encryption.createKeyIfMissing();
      }
      _legacyPlaintextIndex = true;
    }
    _cachedIds.addAll(ids);
  }

  List<String> _decodeIds(String raw) {
    final value = jsonDecode(raw);
    if (value is! List || value.any((id) => id is! String)) {
      throw const LedgerMigrationException(
          'invalid_index', 'The ledger index is invalid.');
    }
    final ids = value.cast<String>();
    if (ids.any((id) => id.isEmpty) || ids.toSet().length != ids.length) {
      throw const LedgerMigrationException(
          'invalid_index', 'The ledger index contains duplicate or empty ids.');
    }
    return ids;
  }

  Future<void> _validateIndexConsistency() async {
    final payloadIds = _prefs
        .getKeys()
        .where((key) => key.startsWith(_encryptedPrefix))
        .map((key) => key.substring(_encryptedPrefix.length))
        .toSet();
    final indexedIds = _cachedIds.toSet();
    if (payloadIds.length != indexedIds.length ||
        !payloadIds.containsAll(indexedIds)) {
      throw const LedgerMigrationException('index_inconsistent',
          'The encrypted ledger index does not match its records.');
    }
  }

  Future<void> _migrateLegacyStore(List<String> legacyIds) async {
    final stagedIds = _prefs
        .getKeys()
        .where((key) => key.startsWith(_encryptedPrefix))
        .map((key) => key.substring(_encryptedPrefix.length))
        .toSet();
    if (stagedIds.isNotEmpty) {
      await _encryption.requireExistingKey();
      if (legacyIds.isEmpty || !stagedIds.every(legacyIds.contains)) {
        throw const LedgerMigrationException('index_inconsistent',
            'Staged ledger records have no matching legacy index.');
      }
    } else {
      await _encryption.createKeyIfMissing();
    }

    final progress = await _readMigrationProgress();
    final converted = <String>{...progress.convertedIds};
    try {
      for (final id in legacyIds) {
        final raw = _prefs.getString('$_prefix$id');
        if (raw == null) {
          throw const LedgerMigrationException(
              'missing_record', 'A legacy ledger record is missing.');
        }
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const LedgerMigrationException(
              'invalid_record', 'A legacy ledger record is invalid.');
        }
        final tx = _decodeLegacyTransaction(
          Map<String, dynamic>.from(decoded),
          expectedId: id,
        );

        if (converted.contains(id)) {
          final staged = await _readEncrypted(id);
          if (staged != null && _sameTransaction(staged, tx)) continue;
          converted.remove(id);
        }

        final encrypted = await _encryption.encryptText(
          jsonEncode(tx.toJson()),
          recordId: id,
        );
        if (!await _prefs.setString('$_encryptedPrefix$id', encrypted)) {
          throw const LedgerMigrationException(
              'write_failed', 'A migrated ledger record could not be saved.');
        }
        final check = await _readEncrypted(id);
        if (check == null || !_sameTransaction(check, tx)) {
          throw const LedgerMigrationException(
              'verify_failed', 'A migrated ledger record failed verification.');
        }
        converted.add(id);
        await _writeMigrationProgress(
            'legacy_money_migration', 'copying', legacyIds, converted);
      }

      final ordered = [
        for (final id in legacyIds)
          if (converted.contains(id)) id
      ];
      await _writeIndex(ordered);
      await _writeMigrationProgress(
          'legacy_money_migration', 'committed', legacyIds, converted);
    } on LedgerMigrationException {
      rethrow;
    } on FormatException {
      throw const LedgerMigrationException('ambiguous_record',
          'A legacy ledger record has an unsupported format.');
    } catch (_) {
      throw const LedgerMigrationException(
          'encryption_failed', 'The ledger migration could not be completed.');
    }
  }

  Future<_MigrationProgress> _readMigrationProgress() async {
    final raw = _prefs.getString(_migrationKey);
    if (raw == null) {
      return const _MigrationProgress(
        kind: '',
        state: 'none',
        sourceIds: {},
        convertedIds: {},
        explicitLists: false,
      );
    }

    final trimmed = raw.trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw const LedgerMigrationException(
          'invalid_migration_journal', 'The migration journal is invalid.');
    }
    final Map<String, dynamic> payload;
    if (decoded is Map &&
        decoded['schemaVersion'] == 2 &&
        decoded['algorithm'] == 'AES-256-GCM') {
      final clear = await _encryption.decryptText(
        raw,
        expectedRecordId: _migrationRecordId,
      );
      final Object? clearValue;
      try {
        clearValue = jsonDecode(clear);
      } catch (_) {
        throw const LedgerMigrationException(
            'invalid_migration_journal', 'The migration journal is invalid.');
      }
      if (clearValue is! Map) {
        throw const LedgerMigrationException(
            'invalid_migration_journal', 'The migration journal is invalid.');
      }
      payload = Map<String, dynamic>.from(clearValue);
    } else if (decoded is Map &&
        decoded['version'] == 2 &&
        decoded['state'] is String) {
      // Compatibility with the earlier plaintext journal. Its progress is
      // revalidated against source records and rewritten encrypted below.
      payload = Map<String, dynamic>.from(decoded);
    } else {
      throw const LedgerMigrationException(
          'invalid_migration_journal', 'The migration journal is invalid.');
    }

    final kind = payload['kind'] as String? ?? 'legacy_money_migration';
    final state = payload['state'] as String?;
    if ((kind != 'legacy_money_migration' && kind != 'legacy_reconciliation') ||
        (state != 'copying' && state != 'committed')) {
      throw const LedgerMigrationException(
          'invalid_migration_journal', 'The migration journal is invalid.');
    }
    Set<String> ids(Object? value, String field) {
      if (value == null) return {};
      if (value is! List || value.any((id) => id is! String)) {
        throw LedgerMigrationException('invalid_migration_journal',
            'The migration journal $field is invalid.');
      }
      final result = value.cast<String>().toSet();
      if (result.length != value.length || result.any((id) => id.isEmpty)) {
        throw LedgerMigrationException('invalid_migration_journal',
            'The migration journal $field is invalid.');
      }
      return result;
    }

    return _MigrationProgress(
      kind: kind,
      state: state!,
      sourceIds: ids(payload['legacyIds'], 'sourceIds'),
      convertedIds: ids(payload['convertedIds'], 'convertedIds'),
      explicitLists: payload.containsKey('legacyIds') ||
          payload.containsKey('convertedIds'),
    );
  }

  Future<void> _writeMigrationProgress(
    String kind,
    String state,
    Iterable<String> legacyIds,
    Iterable<String> converted,
  ) async {
    final sourceIds = legacyIds.toList(growable: false);
    final convertedIds = converted.toSet().toList(growable: false);
    final payload = jsonEncode({
      'journalVersion': 3,
      'kind': kind,
      'state': state,
      'legacyIds': sourceIds,
      'convertedIds': convertedIds,
    });
    final encrypted = await _encryption.encryptText(
      payload,
      recordId: _migrationRecordId,
    );
    if (!await _prefs.setString(_migrationKey, encrypted)) {
      throw const LedgerMigrationException(
          'journal_write_failed', 'The migration journal could not be saved.');
    }
  }

  TransactionModel _decodeLegacyTransaction(
    Map<String, dynamic> json, {
    required String expectedId,
  }) {
    if (json['id'] != expectedId || expectedId.isEmpty) {
      throw const FormatException('legacy id mismatch');
    }

    final normalized = Map<String, dynamic>.from(json);
    final schema = json['schemaVersion'];
    if (schema == null) {
      final amount = json['amount'];
      if (amount is! int || amount < 0) {
        throw const FormatException('legacy amount is ambiguous');
      }
      normalized
        ..remove('amount')
        ..['schemaVersion'] = 2
        ..['currency'] = 'INR'
        ..['amountMinor'] = amount * 100;
    } else if (schema == 2 &&
        json['currency'] == 'INR' &&
        json['amountMinor'] is int &&
        (json['amountMinor'] as int) >= 0) {
      // A canonical staged source is already in paise.
    } else {
      throw const FormatException('unsupported legacy schema');
    }

    if (normalized['type'] != 'expense' && normalized['type'] != 'income') {
      throw const FormatException('legacy type is ambiguous');
    }
    final date = normalized['date'];
    if (date is! String || DateTime.tryParse(date) == null) {
      throw const FormatException('legacy date is ambiguous');
    }
    for (final key in const [
      'merchant',
      'category',
      'paymentMethod',
      'time',
      'originalSms',
      'isExcluded',
    ]) {
      if (!normalized.containsKey(key)) {
        throw const FormatException('legacy field is missing');
      }
    }
    for (final key in const [
      'merchant',
      'category',
      'paymentMethod',
      'time',
      'originalSms',
    ]) {
      if (normalized[key] is! String) {
        throw const FormatException('legacy field type is invalid');
      }
    }
    if (normalized['isExcluded'] is! bool) {
      throw const FormatException('legacy exclusion flag is invalid');
    }
    for (final key in const ['bank', 'account', 'reference', 'source']) {
      if (normalized[key] != null && normalized[key] is! String) {
        throw const FormatException('legacy optional field type is invalid');
      }
    }
    if (normalized['confidence'] != null && normalized['confidence'] is! num) {
      throw const FormatException('legacy confidence is invalid');
    }
    return TransactionModel.fromJson(normalized);
  }

  bool _sameTransaction(TransactionModel a, TransactionModel b) =>
      a.id == b.id &&
      a.amountMinor == b.amountMinor &&
      a.type == b.type &&
      a.merchant == b.merchant &&
      a.category == b.category &&
      a.paymentMethod == b.paymentMethod &&
      a.date == b.date &&
      a.time == b.time &&
      a.originalSms == b.originalSms &&
      a.isExcluded == b.isExcluded &&
      a.bank == b.bank &&
      a.account == b.account &&
      a.reference == b.reference &&
      a.source == b.source &&
      a.confidence == b.confidence &&
      a.needsReview == b.needsReview;

  bool contains(String smsId) =>
      _cachedIds.contains(smsId) || _rejected.containsKey(smsId);

  Future<List<String>> _legacySourceIds() async {
    final ids = <String>{};
    final rawIndex = _prefs.getString(_idsKey);
    if (rawIndex != null) ids.addAll(_decodeIds(rawIndex));

    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix) || key.startsWith(_encryptedPrefix)) {
        continue;
      }
      if (key == _idsKey ||
          key == _encryptedIdsKey ||
          key == _migrationKey ||
          key == _rejectedIdsKey ||
          key == _metaKey) {
        continue;
      }
      final id = key.substring(_prefix.length);
      if (id.isNotEmpty) ids.add(id);
    }

    final result = ids.toList()..sort();
    if (result.any((id) => _reservedIds.contains(id))) {
      throw const LedgerMigrationException(
          'invalid_legacy_id', 'The legacy ledger contains a reserved id.');
    }
    return result;
  }

  Future<void> _reconcileLegacyStore() async {
    final progress = await _readMigrationProgress();
    final sourceIds = <String>{
      ...await _legacySourceIds(),
      ...progress.sourceIds,
    };
    if (sourceIds.isEmpty) {
      if (progress.kind.isEmpty) return;
      if (progress.explicitLists &&
          progress.state == 'committed' &&
          progress.convertedIds.isEmpty) {
        await _prefs.remove(_migrationKey);
        return;
      }
      throw const LedgerMigrationException('invalid_migration_journal',
          'The migration journal has no recoverable source records.');
    }

    await _encryption.requireExistingKey();
    final ordered = sourceIds.toList()..sort();
    final converted = <String>{...progress.convertedIds};
    await _writeMigrationProgress(
        'legacy_reconciliation', 'copying', ordered, converted);

    for (final id in ordered) {
      final raw = _prefs.getString('$_prefix$id');
      if (raw == null) {
        throw const LedgerMigrationException(
            'missing_record', 'A legacy ledger record is missing.');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const LedgerMigrationException(
            'invalid_record', 'A legacy ledger record is invalid.');
      }
      final source = _decodeLegacyTransaction(
        Map<String, dynamic>.from(decoded),
        expectedId: id,
      );

      if (_cachedIds.contains(id)) {
        final current = await _readEncrypted(id);
        if (current == null || !_sameTransaction(current, source)) {
          throw const LedgerMigrationException('legacy_conflict',
              'A legacy record conflicts with its encrypted v2 record.');
        }
        converted.add(id);
        continue;
      }

      final staged = _prefs.getString('$_encryptedPrefix$id');
      if (staged != null) {
        final recovered = await _readEncrypted(id);
        if (recovered == null || !_sameTransaction(recovered, source)) {
          throw const LedgerMigrationException('legacy_conflict',
              'A staged legacy record conflicts with its source.');
        }
      } else {
        await _writeEncrypted(source);
      }

      final nextIds = [..._cachedIds, id]..sort();
      await _writeIndex(nextIds);
      _cachedIds
        ..clear()
        ..addAll(nextIds);
      converted.add(id);
      await _writeMigrationProgress(
          'legacy_reconciliation', 'copying', ordered, converted);
    }

    await _writeMigrationProgress(
        'legacy_reconciliation', 'committed', ordered, converted);
    await _prefs.remove(_migrationKey);
  }

  Future<void> _writeIndex(List<String> ids) async {
    final unique = ids.toSet();
    if (unique.length != ids.length || ids.any((id) => id.isEmpty)) {
      throw const LedgerMigrationException(
          'invalid_index', 'The ledger index contains duplicate or empty ids.');
    }
    final encoded = await _encryption.encryptText(
      jsonEncode(ids),
      recordId: _indexRecordId,
    );
    await _set(_encryptedIdsKey, encoded);
  }

  Set<String> get cachedIds => Set.unmodifiable(_cachedIds);

  Future<TransactionModel?> get(String smsId) async {
    _assertInit();
    return _readEncrypted(smsId);
  }

  Future<TransactionModel?> _readEncrypted(String smsId) async {
    final encoded = _prefs.getString('$_encryptedPrefix$smsId');
    if (encoded == null) return null;
    try {
      final clear = await _encryption.decryptText(
        encoded,
        expectedRecordId: smsId,
      );
      final tx =
          TransactionModel.fromJson(jsonDecode(clear) as Map<String, dynamic>);
      if (tx.id != smsId) {
        throw const FormatException('record id mismatch');
      }
      return tx;
    } catch (_) {
      throw const LedgerMigrationException(
          'decrypt_failed', 'A ledger record could not be authenticated.');
    }
  }

  Future<List<TransactionModel>> loadAll() async {
    _assertInit();
    final results = <TransactionModel>[];
    for (final id in _cachedIds) {
      final tx = await get(id);
      if (tx == null) {
        throw const LedgerMigrationException('missing_encrypted_record',
            'An encrypted ledger record is missing.');
      }
      results.add(tx);
    }
    results.sort((a, b) => b.date.compareTo(a.date));
    debugPrint('📦 Local DB loaded ${results.length} transactions');
    return results;
  }

  Future<void> put(TransactionModel tx) async {
    _assertInit();
    await _activationWrite([tx], replace: false);
  }

  Future<void> _writeEncrypted(TransactionModel tx) async {
    final encoded = await _encryption.encryptText(
      jsonEncode(tx.toJson()),
      recordId: tx.id,
    );
    if (!await _prefs.setString('$_encryptedPrefix${tx.id}', encoded)) {
      throw const LedgerMigrationException(
          'write_failed', 'The ledger record could not be saved.');
    }
    final check = await _readEncrypted(tx.id);
    if (check == null || !_sameTransaction(check, tx)) {
      throw const LedgerMigrationException(
          'write_verify_failed', 'The ledger record failed verification.');
    }
  }

  Future<void> putAll(List<TransactionModel> txs) async {
    _assertInit();
    if (txs.isEmpty) return;
    final ids = <String>{};
    for (final tx in txs) {
      if (!ids.add(tx.id)) {
        throw const LedgerImportException(
            'duplicate_id', 'The ledger contains the same id twice.');
      }
    }
    await _activationWrite(txs, replace: false);
    debugPrint('📦 Local DB saved ${txs.length} transactions');
  }

  Future<void> remove(String smsId) async {
    _assertInit();
    if (!_cachedIds.contains(smsId)) return;
    await _writeJournal({
      'v': 2,
      'phase': 'delete_pending',
      'remove': [smsId],
      'targetIds': [
        for (final id in _cachedIds)
          if (id != smsId) id
      ],
    });
    await _recoverJournal();
  }

  /// Records that [smsId] was skipped, with a coarse [reason] code.
  ///
  /// Re-marking an already-skipped message keeps its ORIGINAL `firstSeen`, so
  /// repeated scans cannot extend the 90-day retention window.
  Future<void> markRejected(String smsId, {String reason = 'UNKNOWN'}) async {
    _assertInit();
    if (smsId.isEmpty || _rejected.containsKey(smsId)) return;
    _rejected[smsId] = RejectedMessage(
      id: smsId,
      reason: reason,
      firstSeen: DateTime.now(),
    );
    await _pruneRejected();
    await _flushRejected();
  }

  /// Skipped messages still inside the retention window, newest first. Ids and
  /// reason codes only — never message contents.
  List<RejectedMessage> get rejectedMessages {
    final list = _rejected.values.toList()
      ..sort((a, b) => b.firstSeen.compareTo(a.firstSeen));
    return List.unmodifiable(list);
  }

  /// How many messages are currently being skipped (ids only, never contents).
  int get rejectedCount => _rejected.length;

  /// Makes every skipped message eligible for processing again, and returns
  /// how many there were. Saved transactions keep blocking re-import, so a
  /// recheck can never create a duplicate: the next scan re-parses a message
  /// and either saves it once (its id is then in the saved set) or skips it
  /// again.
  Future<int> clearRejected() async {
    _assertInit();
    final n = _rejected.length;
    if (n == 0) return 0;
    await _prefs.remove(_rejectedIdsKey);
    _rejected.clear();
    debugPrint('♻️ Cleared $n skipped message records for recheck');
    return n;
  }

  /// Drops skip records older than [rejectedRetention]. Returns how many.
  Future<int> pruneExpiredRejected({DateTime? now}) async {
    _assertInit();
    return _pruneRejected(now: now);
  }

  Future<int> _pruneRejected({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(rejectedRetention);
    final expired = [
      for (final r in _rejected.values)
        if (r.firstSeen.isBefore(cutoff)) r.id
    ];
    if (expired.isEmpty) return 0;
    for (final id in expired) {
      _rejected.remove(id);
    }
    await _flushRejected();
    return expired.length;
  }

  Future<void> _flushRejected() async {
    await _prefs.setString(
      _rejectedIdsKey,
      jsonEncode([for (final r in _rejected.values) r.toJson()]),
    );
  }

  Future<void> clearAll() async {
    _assertInit();
    for (final id in List.of(_cachedIds)) {
      await _prefs.remove('$_encryptedPrefix$id');
      await _prefs.remove('$_prefix$id');
    }
    _cachedIds.clear();
    await _prefs.remove(_encryptedIdsKey);
    await _prefs.remove(_idsKey);
    await _prefs.remove(_migrationKey);
    await _prefs.remove(_metaKey);
    await _prefs.remove(_rejectedIdsKey);
    _rejected.clear();
    debugPrint('🗑️ Local DB cleared');
  }

  Future<void> updateSyncMeta() async {
    _assertInit();
    await _prefs.setString(
      _metaKey,
      jsonEncode({
        'lastSyncMs': DateTime.now().millisecondsSinceEpoch,
        'count': _cachedIds.length,
      }),
    );
  }

  DateTime? get lastSyncTime {
    final raw = _prefs.getString(_metaKey);
    if (raw == null) return null;
    final ms = (jsonDecode(raw) as Map)['lastSyncMs'] as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int get cachedCount => _cachedIds.length;

  // ─── JSON EXPORT / IMPORT BACKUP ──────────────────────────────────────────

  /// Exports a backup without raw SMS or source identifiers by default.
  /// Canonical records store INR in integer paise.
  Future<String> exportToJsonString({bool includeSensitive = false}) async {
    _assertInit();
    final allTxs = await loadAll();
    final exportData = {
      'version': '2.0',
      'amountUnit': 'paise',
      'currency': 'INR',
      'exportedAt': DateTime.now().toIso8601String(),
      'count': allTxs.length,
      'transactions': [
        for (final tx in allTxs)
          includeSensitive
              ? tx.toJson()
              : {
                  'schemaVersion': 2,
                  'currency': 'INR',
                  'amountMinor': tx.amountMinor,
                  'id': tx.id,
                  'type':
                      tx.type == TransactionType.income ? 'income' : 'expense',
                  'merchant': tx.merchant,
                  'category': tx.category,
                  'date': tx.date.toIso8601String(),
                  'isExcluded': tx.isExcluded,
                },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Replaces the WHOLE ledger with [transactions], whose ids must match
  /// [expectedIds] exactly. Used by a resync, which knows the complete set it
  /// intends to end up with.
  ///
  /// Same journalled activation as an import: the payloads are written and read
  /// back first, then ONE write of the id index makes them visible. A failure
  /// before that write rolls back; a crash is finished from the journal on the
  /// next start. Nothing partial is visible, and a retry is idempotent.
  Future<void> replaceAllWithIds(
    List<TransactionModel> transactions, {
    required Set<String> expectedIds,
  }) async {
    _assertInit();
    final ids = <String>{};
    for (final t in transactions) {
      if (!ids.add(t.id)) {
        throw const LedgerImportException(
            'duplicate_id', 'The ledger contains the same id twice.');
      }
    }
    if (ids.length != expectedIds.length || !ids.containsAll(expectedIds)) {
      throw const LedgerImportException(
          'incomplete_scan', 'The scan did not produce the expected ledger.');
    }
    await _activationWrite(transactions, replace: true);
  }

  /// Shared journalled activation: stage, verify, then switch the index.
  Future<void> _activationWrite(
    List<TransactionModel> records, {
    required bool replace,
  }) async {
    await _recoverJournal();

    final newIds = [for (final r in records) r.id];
    final newSet = newIds.toSet();
    final removeIds = replace
        ? [
            for (final id in _cachedIds)
              if (!newSet.contains(id)) id
          ]
        : <String>[];

    final oldIndex = List<String>.of(_cachedIds);
    final oldIndexRaw = _prefs.getString(_encryptedIdsKey);
    final oldPayloads = <String, String?>{
      for (final id in newIds) id: _prefs.getString('$_encryptedPrefix$id'),
    };

    try {
      await _writeJournal({
        'v': 2,
        'phase': 'pending',
        'replace': replace,
        'records': [for (final r in records) r.toJson()],
        'remove': removeIds,
      });
      await _applyPayloads(records);
      await _commitIndex(newIds, replace);
    } catch (e) {
      debugPrint('❌ Activation not saved (${e.runtimeType}) — rolling back');
      final restored = await _rollback(oldIndex, oldIndexRaw, oldPayloads);
      if (e is LedgerImportException) rethrow;
      throw restored
          ? const LedgerImportException(
              'write_failed',
              'Your data could not be saved. Nothing was changed.',
            )
          : const LedgerImportException(
              'write_failed_recoverable',
              'Your data could not be saved completely. Restart the app and it '
                  'will be finished automatically.',
            );
    }

    try {
      await _writeJournal({
        'v': 2,
        'phase': 'committed',
        'remove': removeIds,
      });
      for (final id in removeIds) {
        await _remove('$_encryptedPrefix$id');
      }
      await _remove(_journalKey);
    } catch (e) {
      debugPrint('⚠️ Activation saved; cleanup deferred (${e.runtimeType})');
    }
  }

  /// Imports a JSON backup. See the class comment for the full policy.
  ///
  /// Returns the number of records in the backup. Throws
  /// [LedgerImportException] if the backup is rejected or cannot be saved; in
  /// every such case the existing ledger is unchanged (or, after a crash,
  /// completed on the next start).
  Future<int> importFromJsonString(String jsonString,
      {bool replace = false}) async {
    _assertInit();

    // 1. Validate everything. No I/O happens before this returns.
    final records = _parseAndValidate(jsonString, replace: replace);
    if (records.isEmpty) return 0;

    // 2. Stage, verify, then switch the index — one shared implementation.
    await _activationWrite(records, replace: replace);

    debugPrint('📥 Successfully imported ${records.length} transactions');
    return records.length;
  }

  // ─── IMPORT: VALIDATION ───────────────────────────────────────────────────

  List<TransactionModel> _parseAndValidate(String jsonString,
      {required bool replace}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      throw const LedgerImportException(
          'invalid_json', 'The backup is not valid JSON.');
    }

    final List<dynamic> list;
    if (decoded is Map) {
      final txs = decoded['transactions'];
      if (txs is! List) {
        throw const LedgerImportException(
            'invalid_format', 'The backup has no transaction list.');
      }
      if (decoded.containsKey('version') &&
          !_isSupportedVersion(decoded['version'])) {
        throw const LedgerImportException(
            'unsupported_version', 'This backup version is not supported.');
      }
      if (decoded.containsKey('count')) {
        final count = decoded['count'];
        if (count is! int || count != txs.length) {
          throw const LedgerImportException('count_mismatch',
              'The backup is incomplete: its record count does not match.');
        }
      }
      list = txs;
    } else if (decoded is List) {
      list = decoded;
    } else {
      throw const LedgerImportException(
          'invalid_format', 'The backup format is not recognised.');
    }

    if (replace && list.isEmpty) {
      throw const LedgerImportException('empty_replace',
          'An empty backup cannot replace the existing transactions.');
    }

    final seen = <String>{};
    final out = <TransactionModel>[];
    for (var i = 0; i < list.length; i++) {
      final model = _validateRecord(list[i], i);
      if (!seen.add(model.id)) {
        throw LedgerImportException(
            'duplicate_id', 'Two records share the same id.',
            recordIndex: i);
      }
      out.add(model);
    }
    return out;
  }

  static bool _isSupportedVersion(Object? v) {
    if (v is num) return v == 2;
    if (v is String) return double.tryParse(v.trim()) == 2.0;
    return false;
  }

  TransactionModel _validateRecord(Object? item, int i) {
    LedgerImportException bad(String code, String message) =>
        LedgerImportException(code, message, recordIndex: i);

    if (item is! Map) {
      throw bad('invalid_record', 'A record is not an object.');
    }
    final json = Map<String, dynamic>.from(item);

    final id = json['id'];
    if (id is! String || id.isEmpty || id.length > _maxIdLength) {
      throw bad('invalid_id', 'A record has a missing or invalid id.');
    }
    if (_reservedIds.contains(id)) {
      throw bad('reserved_id', 'A record uses a reserved id.');
    }

    final schema = json['schemaVersion'];
    final rawMinor = json['amountMinor'];
    final int amountMinor;
    if (schema == 2 && json['currency'] == 'INR' && rawMinor is int) {
      amountMinor = rawMinor;
    } else {
      final rawAmount = json['amount'];
      final int legacyAmount;
      if (rawAmount is int) {
        legacyAmount = rawAmount;
      } else if (rawAmount is double &&
          rawAmount.isFinite &&
          rawAmount == rawAmount.truncateToDouble()) {
        legacyAmount = rawAmount.toInt();
      } else {
        throw bad(
            'invalid_amount', 'A record has a missing or invalid amount.');
      }
      if (legacyAmount < 0 || legacyAmount > _maxAmountMinor ~/ 100) {
        throw bad(
            'invalid_amount', 'A record amount is outside the allowed range.');
      }
      json['schemaVersion'] = 2;
      json['currency'] = 'INR';
      json['amountMinor'] = legacyAmount * 100;
      amountMinor = legacyAmount * 100;
    }
    if (amountMinor <= 0 || amountMinor > _maxAmountMinor) {
      throw bad(
          'invalid_amount', 'A record amount is outside the allowed range.');
    }

    final type = json['type'];
    if (type != 'expense' && type != 'income') {
      throw bad('invalid_type', 'A record has a missing or invalid type.');
    }

    final date = json['date'];
    if (date is! String || DateTime.tryParse(date) == null) {
      throw bad('invalid_date', 'A record has a missing or invalid date.');
    }

    for (final key in const [
      'merchant',
      'category',
      'paymentMethod',
      'time',
      'originalSms',
      'source',
      'bank',
      'account',
      'reference',
    ]) {
      final v = json[key];
      if (v != null && v is! String) {
        throw bad('invalid_field', 'A record has a field of the wrong type.');
      }
    }
    for (final key in const ['isExcluded', 'needsReview']) {
      final v = json[key];
      if (v != null && v is! bool) {
        throw bad('invalid_field', 'A record has a field of the wrong type.');
      }
    }
    final confidence = json['confidence'];
    if (confidence != null && confidence is! num) {
      throw bad('invalid_field', 'A record has a field of the wrong type.');
    }

    return TransactionModel.fromJson(json);
  }

  // ─── IMPORT: STAGING, ACTIVATION, ROLLBACK, RECOVERY ──────────────────────

  Future<void> _set(String key, String value) async {
    await writeHook?.call('set', key);
    if (!await _prefs.setString(key, value)) {
      throw StateError('write_failed');
    }
  }

  Future<void> _remove(String key) async {
    await writeHook?.call('remove', key);
    if (!await _prefs.remove(key)) {
      throw StateError('write_failed');
    }
  }

  /// Writes every payload, then reads each back to prove it was stored intact.
  /// Payloads are invisible until [_commitIndex] runs, except that an upsert
  /// of an existing id replaces its payload — which is what the rollback
  /// snapshot and the journal protect.
  Future<void> _applyPayloads(List<TransactionModel> records) async {
    for (final r in records) {
      await writeHook?.call('set', '$_encryptedPrefix${r.id}');
      await _writeEncrypted(r);
    }
    for (final r in records) {
      final check = await _readEncrypted(r.id);
      if (check == null || !_sameTransaction(check, r)) {
        throw StateError('verify_failed');
      }
    }
  }

  /// The single write that makes the import visible.
  Future<void> _commitIndex(List<String> newIds, bool replace) async {
    final next = replace
        ? newIds
        : [
            ..._cachedIds,
            for (final id in newIds)
              if (!_cachedIds.contains(id)) id,
          ];
    await _writeIndex(next);
    _cachedIds
      ..clear()
      ..addAll(next);
  }

  Future<void> _commitExactIndex(List<String> ids) async {
    await _writeIndex(ids);
    _cachedIds
      ..clear()
      ..addAll(ids);
  }

  /// Restores the pre-import state exactly. Returns false if storage would not
  /// cooperate; the journal then stays, and the next start completes the
  /// import rather than leaving a hybrid.
  Future<bool> _rollback(
    List<String> oldIndex,
    String? oldIndexRaw,
    Map<String, String?> oldPayloads,
  ) async {
    _cachedIds
      ..clear()
      ..addAll(oldIndex);
    try {
      for (final e in oldPayloads.entries) {
        final key = '$_encryptedPrefix${e.key}';
        if (e.value == null) {
          await _remove(key);
        } else {
          await _set(key, e.value!);
        }
      }
      if (oldIndexRaw == null) {
        await _remove(_encryptedIdsKey);
      } else {
        await _set(_encryptedIdsKey, oldIndexRaw);
      }
      await _remove(_journalKey);
      return true;
    } catch (e) {
      debugPrint('⚠️ Import rollback incomplete (${e.runtimeType})');
      return false;
    }
  }

  Future<void> _writeJournal(Map<String, dynamic> journal) async {
    final encrypted = await _encryption.encryptText(jsonEncode(journal));
    await _set(
      _journalKey,
      jsonEncode({'schemaVersion': 2, 'ciphertext': encrypted}),
    );
  }

  Future<Map<String, dynamic>?> _readJournal() async {
    final raw = _prefs.getString(_journalKey);
    if (raw == null) return null;
    final envelope = jsonDecode(raw);
    if (envelope is! Map || envelope['schemaVersion'] != 2) {
      throw const LedgerMigrationException(
          'invalid_journal', 'The ledger migration journal is invalid.');
    }
    final clear =
        await _encryption.decryptText(envelope['ciphertext'] as String);
    final decoded = jsonDecode(clear);
    if (decoded is! Map) {
      throw const LedgerMigrationException(
          'invalid_journal', 'The ledger migration journal is invalid.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Completes an encrypted activation that a crash interrupted.
  Future<void> _recoverJournal() async {
    final journal = await _readJournal();
    if (journal == null) return;
    try {
      if (journal['v'] != 2) {
        throw const FormatException('unsupported journal version');
      }
      final phase = journal['phase'];
      if (phase == 'pending') {
        final records = [
          for (final e in (journal['records'] as List))
            TransactionModel.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
        await _applyPayloads(records);
        await _commitIndex(
            [for (final r in records) r.id], journal['replace'] == true);
      } else if (phase == 'delete_pending') {
        final targetIds = (journal['targetIds'] as List).cast<String>();
        await _commitExactIndex(targetIds);
        for (final id in (journal['remove'] as List).cast<String>()) {
          await _remove('$_encryptedPrefix$id');
        }
      } else if (phase != 'committed') {
        throw const FormatException('unsupported journal phase');
      }
      // A recovered 'pending' replace-commit must also drop the payloads the
      // replace superseded; otherwise the orphan fails the very next
      // index-consistency validation and init can never succeed again.
      if (phase == 'committed' ||
          (phase == 'pending' && journal['replace'] == true)) {
        for (final id
            in (journal['remove'] as List? ?? const []).cast<String>()) {
          await _remove('$_encryptedPrefix$id');
        }
      }
      await _remove(_journalKey);
      debugPrint('♻️ Finished an interrupted encrypted activation');
    } catch (_) {
      throw const LedgerMigrationException('journal_recovery_failed',
          'The ledger activation could not recover.');
    }
  }

  // ─── PRIVATE ────────────────────────────────_______________

  void _assertInit() {
    assert(_initialised, 'Call TransactionCacheService.init() before using it');
  }
}
