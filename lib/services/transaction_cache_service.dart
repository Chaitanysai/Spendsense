import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ledger_encryption_service.dart';
import '../models/transaction_model.dart';
import 'ledger_tombstone_store.dart';

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
  static const _syncMetaMigrationKey = 'tx_sync_metadata_v1';
  static const _rejectedIdsKey = 'tx_rejected_ids';
  static const _metaKey = 'tx_cache_meta';
  static const _prefix = 'tx_';
  static const _encryptedPrefix = 'txe_';

  /// Deliberately outside the `tx_` namespace so no record id can collide.
  static const _journalKey = 'txj_import_journal';

  /// Where an unreadable record or journal is moved aside. Outside both the
  /// `tx_` and `txe_` namespaces, so nothing reads it back into the ledger.
  static const _quarantinePrefix = 'txq_';

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

    // Every step below can fail, and a retry re-runs all of them. Starting from
    // empty in-memory state keeps a half-finished earlier attempt from being
    // mistaken for the stored ledger.
    _cachedIds.clear();
    _rejected.clear();
    _legacyPlaintextIndex = false;

    final encryptedRaw = _prefs.getString(_encryptedIdsKey);
    if (encryptedRaw != null) {
      await _loadIndex(encryptedRaw);
    } else {
      final legacyRaw = _prefs.getString(_idsKey);
      List<String> legacyIds;
      try {
        legacyIds = legacyRaw == null ? <String>[] : _decodeIds(legacyRaw);
      } on LedgerMigrationException {
        // A damaged plaintext index loses the id order, not the records; the
        // sources are still on disk, so fall back to those.
        debugPrint('⚠️ Legacy index unreadable — using the sources on disk');
        legacyIds = await _legacySourceIds();
      }
      await _migrateLegacyStore(legacyIds);
      // Only the ids that actually got an encrypted record join the ledger;
      // anything else is dropped or set aside by [_reconcileIndex].
      _cachedIds.addAll(legacyIds
          .where((id) => _prefs.getString('$_encryptedPrefix$id') != null));
    }

    await _readRejected();
    await _recoverJournal();
    if (_legacyPlaintextIndex) {
      await _writeIndex(_cachedIds.toList());
      _legacyPlaintextIndex = false;
    }
    await _reconcileLegacyStore();
    // Only a start that began without an index can have lost it; a legacy
    // migration writes its own index above, so presence now says nothing.
    await _recoverEmptyIndex(indexWasMissing: encryptedRaw == null);
    await _reconcileIndex();
    await _migrateSyncMetadata();
    await _pruneRejected();

    // Marked ready only once EVERY step succeeded. Setting this earlier made a
    // failed start look initialized, so the retry the error card offers
    // returned immediately and the ledger stayed empty until a full resync.
    _initialised = true;
    debugPrint(
        '📦 Local DB init — ${_cachedIds.length} txs, ${_rejected.length} rejected');
  }

  /// Loads the skipped-message list, tolerating damaged contents.
  ///
  /// This list holds only SMS ids and coarse reason codes, so an unreadable
  /// copy costs a re-scan of those messages — it must never keep the whole
  /// ledger from opening, which is what a plain `jsonDecode` cast did.
  Future<void> _readRejected() async {
    final raw = _prefs.getString(_rejectedIdsKey);
    if (raw == null) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      decoded = null;
    }
    if (decoded is! List) {
      debugPrint('⚠️ Skipped-message list unreadable — reset');
      await _prefs.remove(_rejectedIdsKey);
      return;
    }
    for (final entry in decoded) {
      final parsed = RejectedMessage.tryParse(entry);
      if (parsed != null) _rejected[parsed.id] = parsed;
    }
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
      // Compatibility with the old plaintext index. It is upgraded in place;
      // each plaintext source is kept until its encrypted copy has been
      // verified, then retired by [_reconcileLegacyStore].
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

  /// Rebuilds a lost id index from the payloads that authenticate with the
  /// ledger key.
  ///
  /// The index is the last write of an activation and is a single key. If it
  /// goes missing while its payloads survive — an interrupted write, a platform
  /// that dropped one key — every record is unindexed, so the next
  /// [_reconcileIndex] would set them all aside and the app would open empty
  /// with no error. A sync then re-imports the same rows, and the cycle repeats
  /// on the next launch. That is the field symptom this recovery ends.
  ///
  /// Only a completely empty ledger gets here. A payload that authenticates
  /// proves it was written by this key, and deletions remove payloads (through
  /// a journalled index switch that [_recoverJournal] has already finished for
  /// this start), so a surviving payload is not a deleted row.
  ///
  /// The index must have been missing when this start began, not merely empty:
  /// an existing index that says `[]` is a committed answer — the ledger
  /// intends to show nothing — and its unlisted payloads keep the stricter
  /// quarantine rule. Only a missing key means no activation ever committed,
  /// which is the state that strands payloads and used to empty the dashboard.
  ///
  /// A key that cannot be read is rethrown: the caller must see the error card
  /// instead of losing records to a key problem.
  Future<void> _recoverEmptyIndex({required bool indexWasMissing}) async {
    if (_cachedIds.isNotEmpty) return;
    if (!indexWasMissing) return;
    final payloadKeys = _prefs
        .getKeys()
        .where((key) => key.startsWith(_encryptedPrefix))
        .toList();
    if (payloadKeys.isEmpty) return;

    await _encryption.requireExistingKey();

    final recovered = <String>[];
    for (final key in payloadKeys) {
      final id = key.substring(_encryptedPrefix.length);
      try {
        if (await _readEncrypted(id) != null) recovered.add(id);
      } on LedgerMigrationException {
        // Unauthenticated bytes are left for [_reconcileIndex] to set aside.
        debugPrint('⚠️ Unindexed payload $id could not be authenticated');
      }
    }
    if (recovered.isEmpty) return;

    recovered.sort();
    await _writeIndex(recovered);
    _cachedIds
      ..clear()
      ..addAll(recovered);
    debugPrint('🧩 Ledger index rebuilt from ${recovered.length} payloads');
  }

  /// Makes the id index agree with the records actually on disk.
  ///
  /// SharedPreferences cannot write several keys atomically, so an interrupted
  /// activation — or a platform that dropped a write — can leave the index and
  /// its payloads disagreeing. That used to throw `index_inconsistent` on
  /// every start, which is indistinguishable from "the ledger is empty" to a
  /// reader that ignores the error, and never repaired itself. Instead:
  ///
  /// * an indexed id with no payload is dropped (its bytes are already gone;
  ///   the rest of the ledger must still open);
  /// * a payload with no index entry is moved to a quarantine key. The index is
  ///   the only thing that makes a record visible, so a payload outside it is
  ///   either a write whose index commit never landed or the leftover of a
  ///   delete/replace cut short — indistinguishable on disk, and adopting it
  ///   would resurrect rows the ledger decided not to show, so it is set aside
  ///   rather than loaded.
  ///
  /// Only this bookkeeping mismatch is healed. Authentication of the index
  /// itself still fails closed (see [_loadIndex]).
  Future<void> _reconcileIndex() async {
    final payloadIds = _prefs
        .getKeys()
        .where((key) => key.startsWith(_encryptedPrefix))
        .map((key) => key.substring(_encryptedPrefix.length))
        .toSet();
    final missing = [
      for (final id in _cachedIds)
        if (!payloadIds.contains(id)) id
    ];
    final orphans = [
      for (final id in payloadIds)
        if (!_cachedIds.contains(id)) id
    ]..sort();
    if (missing.isEmpty && orphans.isEmpty) return;

    for (final id in orphans) {
      await _quarantine('$_encryptedPrefix$id');
    }

    if (missing.isNotEmpty) {
      // Only ids that still have a payload may stay in the index; an id whose
      // record is gone would make loadAll throw on every launch.
      _cachedIds.removeAll(missing);
      final next = _cachedIds.toList()..sort();
      await _writeIndex(next);
      _cachedIds
        ..clear()
        ..addAll(next);
    }
    debugPrint('🧩 Ledger index reconciled — ${missing.length} dropped, '
        '${orphans.length} set aside');
  }

  /// Copies [key] aside and removes it from the live namespace.
  ///
  /// The bytes stay on the device for diagnosis; nothing reads the copy back,
  /// so a record that can no longer be authenticated cannot keep the ledger
  /// from opening.
  Future<void> _quarantine(String key) async {
    final raw = _prefs.getString(key);
    if (raw == null) return;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = '$_quarantinePrefix${stamp}_$key';
    if (!await _prefs.setString(target, raw)) {
      debugPrint('⚠️ Quarantine write failed — leaving $key in place');
      return;
    }
    await _prefs.remove(key);
  }

  Future<void> _migrateLegacyStore(List<String> legacyIds) async {
    final stagedIds = _prefs
        .getKeys()
        .where((key) => key.startsWith(_encryptedPrefix))
        .map((key) => key.substring(_encryptedPrefix.length))
        .toSet();
    if (stagedIds.isNotEmpty) {
      // Staged payloads mean an earlier pass already created the key; creating
      // it again would mint a second key and orphan every encrypted record.
      await _encryption.requireExistingKey();
    } else {
      await _encryption.createKeyIfMissing();
    }

    final progress = await _readMigrationProgress();
    final converted = <String>{...progress.convertedIds};
    try {
      for (final id in legacyIds) {
        final raw = _prefs.getString('$_prefix$id');
        if (raw == null) {
          debugPrint('⚠️ Legacy record $id is missing — skipped');
          continue;
        }
        final TransactionModel tx;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map) throw const FormatException('not an object');
          tx = _decodeLegacyTransaction(
            Map<String, dynamic>.from(decoded),
            expectedId: id,
          );
        } catch (_) {
          // Undecodable sources cannot be migrated. They keep their plaintext
          // copy, which the reconciliation step sets aside.
          debugPrint('⚠️ Legacy record $id is undecodable — skipped');
          continue;
        }

        if (converted.contains(id)) {
          TransactionModel? staged;
          try {
            staged = await _readEncrypted(id);
          } on LedgerMigrationException {
            staged = null;
          }
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

  /// Read-back and legacy-comparison equality. It is used both to verify what
  /// was just written and to compare stored records with re-parsed legacy
  /// sources, so it compares the record's identity and content. `syncId` is
  /// excluded: legacy plaintext sources predate sync metadata and each re-parse
  /// of them would mint a fresh id, causing spurious conflicts. `updatedAtMs`
  /// is included — legacy sources default to 0, matching migrated records.
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
      a.needsReview == b.needsReview &&
      a.billKindHint == b.billKindHint &&
      a.billReminderHint == b.billReminderHint &&
      a.updatedAtMs == b.updatedAtMs;

  bool contains(String smsId) =>
      _cachedIds.contains(smsId) || _rejected.containsKey(smsId);

  Future<List<String>> _legacySourceIds() async {
    final ids = <String>{};
    final rawIndex = _prefs.getString(_idsKey);
    if (rawIndex != null) {
      // The key scan below still finds every source, so a damaged plaintext
      // index is ignored instead of aborting the reconciliation.
      try {
        ids.addAll(_decodeIds(rawIndex));
      } catch (_) {
        debugPrint('⚠️ Legacy index unreadable — ignored');
      }
    }

    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix) || key.startsWith(_encryptedPrefix)) {
        continue;
      }
      if (key == _idsKey ||
          key == _encryptedIdsKey ||
          key == _migrationKey ||
          key == _syncMetaMigrationKey ||
          key == _rejectedIdsKey ||
          key == _metaKey ||
          key == LedgerTombstoneStore.storeKey) {
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
        // The plaintext source is gone. When the ledger still holds the record
        // the migration for it is simply already finished.
        if (_cachedIds.contains(id)) converted.add(id);
        continue;
      }

      final TransactionModel source;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException('not an object');
        source = _decodeLegacyTransaction(
          Map<String, dynamic>.from(decoded),
          expectedId: id,
        );
      } catch (_) {
        // A source that cannot be decoded restores nothing, and it must never
        // veto startup. The encrypted record, if any, is kept as it is; the
        // undecodable bytes are set aside rather than deleted.
        if (_cachedIds.contains(id)) converted.add(id);
        debugPrint('⚠️ Legacy source $id is unreadable — set aside');
        await _quarantine('$_prefix$id');
        continue;
      }

      TransactionModel? current;
      try {
        current = await _readEncrypted(id);
      } on LedgerMigrationException {
        current = null;
      }

      if (current != null) {
        // The encrypted record is authoritative: it carries the user's edits
        // and the sync metadata the plaintext source never had. Re-comparing
        // the two on every start meant that once the sync stamped
        // `updatedAtMs` the comparison could never match again, so init threw
        // `legacy_conflict` on every launch (the data reappeared only after a
        // retry, which skipped the checks). Retiring the source ends that.
        //
        // The record may have been written by an earlier pass that died before
        // its index commit. The source proves this id belongs in the ledger, so
        // finish that commit here: the index is what makes a record visible,
        // and no other path may add an un-indexed payload back.
        if (!_cachedIds.contains(id)) {
          final nextIds = {..._cachedIds, id}.toList()..sort();
          await _writeIndex(nextIds);
          _cachedIds
            ..clear()
            ..addAll(nextIds);
        }
        converted.add(id);
        await _prefs.remove('$_prefix$id');
        continue;
      }

      // No usable encrypted record: the plaintext source is the only copy of
      // this transaction, so it is restored into the encrypted ledger. The
      // index is committed BEFORE the source is retired, so an interruption
      // here leaves the source in place for the next start to resume from
      // instead of an un-indexed payload nothing would ever look at.
      await _writeEncrypted(source);
      final nextIds = {..._cachedIds, id}.toList()..sort();
      await _writeIndex(nextIds);
      _cachedIds
        ..clear()
        ..addAll(nextIds);
      converted.add(id);
      await _writeMigrationProgress(
          'legacy_reconciliation', 'copying', ordered, converted);
      await _prefs.remove('$_prefix$id');
    }

    await _writeMigrationProgress(
        'legacy_reconciliation', 'committed', ordered, converted);
    await _prefs.remove(_migrationKey);
    // The plaintext index has no role once the encrypted one owns the ledger;
    // leaving it behind made every later start re-walk a stale id list.
    await _prefs.remove(_idsKey);
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

  /// Records modified after [epochMs], for the sync layer's incremental pull.
  ///
  /// A record whose modification time is unknown (`updatedAtMs` 0, a legacy
  /// record) is always treated as changed: it must be uploaded at least once
  /// so the sync learns its timestamp.
  Future<List<TransactionModel>> loadChangedSince(int epochMs) async {
    _assertInit();
    final all = await loadAll();
    return [
      for (final tx in all)
        if (tx.updatedAtMs == 0 || tx.updatedAtMs > epochMs) tx
    ];
  }

  /// One-time migration giving every stored record a persistent sync identity.
  ///
  /// Older records were written before the sync metadata existed. Each gains a
  /// fresh [TransactionModel.newSyncId] which is then persisted, so the id
  /// stays stable for the sync layer. The marker key is written only after
  /// every record is saved, and the per-record work is skipped when a record
  /// already has a syncId, so an interrupted run simply resumes. Money fields
  /// are carried through [copyWith] untouched, and nothing runs if the ledger
  /// encryption key is unavailable.
  Future<void> _migrateSyncMetadata() async {
    if (_prefs.getString(_syncMetaMigrationKey) != null) return;
    try {
      await _encryption.requireExistingKey();
    } catch (error) {
      debugPrint(
          '⏭️ Sync metadata migration skipped (key unavailable, ${error.runtimeType})');
      return;
    }
    var migrated = 0;
    for (final id in List.of(_cachedIds)) {
      final tx = await _readEncrypted(id);
      if (tx == null) {
        throw const LedgerMigrationException('missing_encrypted_record',
            'A ledger record is missing during sync metadata migration.');
      }
      if (tx.syncId.isNotEmpty) continue;
      final stamped = tx.copyWith(syncId: TransactionModel.newSyncId());
      await _writeEncrypted(stamped);
      migrated++;
    }
    await _prefs.setString(
      _syncMetaMigrationKey,
      jsonEncode({'done': true, 'migrated': migrated}),
    );
    debugPrint('🔄 Sync metadata migration — $migrated records given a syncId');
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

  /// Deletes several records through ONE journalled index switch.
  ///
  /// The visible index changes once; a crash is completed from the encrypted
  /// journal on the next start. Returns how many of [smsIds] existed.
  Future<int> removeMany(Iterable<String> smsIds) async {
    _assertInit();
    final targets = <String>{};
    for (final id in smsIds) {
      if (_cachedIds.contains(id)) targets.add(id);
    }
    if (targets.isEmpty) return 0;
    final targetIds = [
      for (final id in _cachedIds)
        if (!targets.contains(id)) id
    ];
    await _writeJournal({
      'v': 2,
      'phase': 'delete_pending',
      'remove': targets.toList(growable: false),
      'targetIds': targetIds,
    });
    await _recoverJournal();
    return targets.length;
  }

  /// Records that [smsId] was skipped, with a coarse [reason] code.
  ///
  /// Re-marking an already-skipped message keeps its ORIGINAL `firstSeen`, so
  /// repeated scans cannot extend the 90-day retention window.
  Future<void> markRejected(String smsId, {String reason = 'UNKNOWN'}) async {
    _assertInit();
    await markRejectedAll({smsId: reason});
  }

  /// Records several skipped messages through ONE flush.
  ///
  /// A scan skips dozens of messages; writing the whole list once per message
  /// rewrote the same key text for every one of them. New ids inherit the
  /// mapped reason; already-known ids keep their original `firstSeen`.
  Future<int> markRejectedAll(Map<String, String> reasons) async {
    _assertInit();
    final now = DateTime.now();
    var added = 0;
    for (final entry in reasons.entries) {
      final id = entry.key;
      if (id.isEmpty || _rejected.containsKey(id)) continue;
      _rejected[id] = RejectedMessage(
        id: id,
        reason: entry.value,
        firstSeen: now,
      );
      added++;
    }
    if (added == 0) return 0;
    await _pruneRejected(flush: false);
    await _flushRejected();
    return added;
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

  Future<int> _pruneRejected({DateTime? now, bool flush = true}) async {
    final cutoff = (now ?? DateTime.now()).subtract(rejectedRetention);
    final expired = [
      for (final r in _rejected.values)
        if (r.firstSeen.isBefore(cutoff)) r.id
    ];
    if (expired.isEmpty) return 0;
    for (final id in expired) {
      _rejected.remove(id);
    }
    if (flush) await _flushRejected();
    return expired.length;
  }

  /// Persists the skipped-message list through the same write seam as every
  /// other mutation, but a failure is not fatal: the list only saves a re-scan,
  /// so losing it costs nothing the next start cannot rebuild.
  Future<void> _flushRejected() async {
    try {
      await _set(
        _rejectedIdsKey,
        jsonEncode([for (final r in _rejected.values) r.toJson()]),
      );
    } catch (error) {
      debugPrint('⚠️ Skipped-message list not saved (${error.runtimeType})');
    }
  }

  Future<void> clearAll() async {
    _assertInit();
    for (final id in List.of(_cachedIds)) {
      await _prefs.remove('$_encryptedPrefix$id');
      await _prefs.remove('$_prefix$id');
    }
    // Quarantined bytes belong to this ledger too; a clear must not leave them.
    for (final key in _prefs
        .getKeys()
        .where((k) => k.startsWith(_quarantinePrefix))
        .toList()) {
      await _prefs.remove(key);
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
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final ms = decoded['lastSyncMs'];
      if (ms is! int) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      // Sync bookkeeping must never be able to abort startup.
      return null;
    }
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
                  // Non-sensitive bill metadata: an enum name and a flag only.
                  if (tx.billKindHint != null) 'billKindHint': tx.billKindHint,
                  if (tx.billReminderHint) 'billReminderHint': true,
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
      'billKindHint',
      'syncId',
    ]) {
      final v = json[key];
      if (v != null && v is! String) {
        throw bad('invalid_field', 'A record has a field of the wrong type.');
      }
    }
    for (final key in const [
      'isExcluded',
      'needsReview',
      'billReminderHint',
    ]) {
      final v = json[key];
      if (v != null && v is! bool) {
        throw bad('invalid_field', 'A record has a field of the wrong type.');
      }
    }
    final confidence = json['confidence'];
    if (confidence != null && confidence is! num) {
      throw bad('invalid_field', 'A record has a field of the wrong type.');
    }
    final syncIdValue = json['syncId'];
    if (syncIdValue != null &&
        (syncIdValue is! String || syncIdValue.isEmpty)) {
      throw bad('invalid_field', 'A record has a field of the wrong type.');
    }
    if (json['updatedAtMs'] != null && json['updatedAtMs'] is! int) {
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
  ///
  /// A journal that cannot be INTERPRETED is set aside: it describes a write
  /// that never became visible, so nothing in it was ever part of the ledger,
  /// and leaving it in place used to make every later start fail at recovery.
  ///
  /// A journal whose writes fail is different: the activation may be half
  /// applied, and the journal is the only record of how to finish it. That
  /// failure is surfaced (as `journal_recovery_failed`) so the caller sees an
  /// error and the next start retries recovery instead of discarding it.
  Future<void> _recoverJournal() async {
    final Map<String, dynamic>? read;
    try {
      read = await _readJournal();
    } catch (error) {
      // Reaching this point means the encryption key already opened the index,
      // so an unreadable journal is a damaged journal, not a key problem.
      debugPrint(
          '⚠️ Ledger journal unreadable (${error.runtimeType}) — set aside');
      await _quarantine(_journalKey);
      return;
    }
    if (read == null) return;
    final journal = read;
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
      // replace superseded; otherwise they linger outside the index and the
      // next start has to set them aside.
      if (phase == 'committed' ||
          (phase == 'pending' && journal['replace'] == true)) {
        for (final id
            in (journal['remove'] as List? ?? const []).cast<String>()) {
          await _remove('$_encryptedPrefix$id');
        }
      }
      await _remove(_journalKey);
      debugPrint('♻️ Finished an interrupted encrypted activation');
    } on LedgerMigrationException {
      // Reading or writing the ledger failed. The journal still records how to
      // finish, so keep it and let the next start retry.
      rethrow;
    } on StateError {
      throw const LedgerMigrationException('journal_recovery_failed',
          'The ledger activation could not recover.');
    } catch (_) {
      // The journal cannot be interpreted, so no activation can be completed
      // from it and nothing it lists was ever visible. Set it aside — the
      // txq_ copy keeps the evidence — instead of failing every later start.
      debugPrint('⚠️ Ledger journal could not be interpreted — set aside');
      await _quarantine(_journalKey);
    }
  }

  // ─── PRIVATE ────────────────────────────────_______________

  void _assertInit() {
    assert(_initialised, 'Call TransactionCacheService.init() before using it');
  }
}
