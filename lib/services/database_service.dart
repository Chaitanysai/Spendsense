import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

class LegacyDatabaseFormatException implements Exception {
  final String message;

  const LegacyDatabaseFormatException(this.message);

  @override
  String toString() => 'LegacyDatabaseFormatException: $message';
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  final Set<String> _cachedIds = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'spendsense_v2.db');

    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            amountMinor INTEGER NOT NULL,
            schemaVersion INTEGER NOT NULL,
            currency TEXT NOT NULL,
            amountUnit TEXT NOT NULL,
            type TEXT NOT NULL,
            merchant TEXT NOT NULL,
            category TEXT NOT NULL,
            paymentMethod TEXT NOT NULL,
            date TEXT NOT NULL,
            time TEXT NOT NULL,
            originalSms TEXT NOT NULL,
            isExcluded INTEGER NOT NULL,
            bank TEXT,
            account TEXT,
            reference TEXT,
            source TEXT NOT NULL,
            confidence REAL NOT NULL,
            isReviewed INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion >= 2) return;

        // Version 1's `amount` column was explicitly whole INR rupees.
        // Convert it inside the database upgrade transaction only once.
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN schemaVersion INTEGER NOT NULL DEFAULT 1');
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN currency TEXT NOT NULL DEFAULT 'INR'");
        await db
            .execute('ALTER TABLE transactions ADD COLUMN amountMinor INTEGER');
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN amountUnit TEXT NOT NULL DEFAULT 'INR_WHOLE_RUPEES_V1'");

        final rows = await db.query('transactions', columns: ['id', 'amount']);
        for (final row in rows) {
          final id = row['id'];
          final amount = row['amount'];
          if (id is! String ||
              id.isEmpty ||
              amount is! int ||
              amount < 0 ||
              amount > 90000000000000) {
            throw const LegacyDatabaseFormatException(
                'A legacy SQLite amount is ambiguous.');
          }
          await db.update(
            'transactions',
            {
              'amountMinor': amount * 100,
              'schemaVersion': 2,
              'currency': 'INR',
              'amountUnit': 'paise',
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      },
    );

    await _loadIds();
    _initialized = true;
    debugPrint(
        '📦 Database initialized. Cached IDs count: ${_cachedIds.length}');
  }

  Future<void> _loadIds() async {
    if (_database == null) return;
    final rows = await _database!.query('transactions', columns: ['id']);
    _cachedIds.clear();
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id != null) _cachedIds.add(id);
    }
  }

  bool contains(String id) => _cachedIds.contains(id);

  Set<String> get cachedIds => Set.unmodifiable(_cachedIds);

  Future<List<TransactionModel>> loadAll() async {
    if (_database == null) await init();
    final rows = await _database!.query('transactions', orderBy: 'date DESC');
    return rows.map((r) => TransactionModel.fromJson(_rowMap(r))).toList();
  }

  Future<TransactionModel?> get(String id) async {
    if (_database == null) await init();
    final rows = await _database!.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TransactionModel.fromJson(_rowMap(rows.first));
  }

  @visibleForTesting
  static TransactionModel decodeRowForTesting(Map<String, dynamic> row) =>
      TransactionModel.fromJson(_canonicalRow(row));

  static Map<String, dynamic> _canonicalRow(Map<String, dynamic> row) {
    if (row['schemaVersion'] != 2 ||
        row['currency'] != 'INR' ||
        row['amountUnit'] != 'paise' ||
        row['amountMinor'] is! int ||
        (row['amountMinor'] as int) < 0) {
      throw const LegacyDatabaseFormatException(
          'The SQLite row has no trusted paise unit.');
    }
    return {
      'schemaVersion': 2,
      'currency': 'INR',
      'amountMinor': row['amountMinor'],
      'id': row['id'],
      'type': row['type'],
      'merchant': row['merchant'],
      'category': row['category'],
      'paymentMethod': row['paymentMethod'],
      'date': row['date'],
      'time': row['time'],
      'originalSms': row['originalSms'],
      'isExcluded': row['isExcluded'] == 1 || row['isExcluded'] == true,
      'bank': row['bank'],
      'account': row['account'],
      'reference': row['reference'],
      'source': row['source'] ?? 'sqlite_v2',
      'confidence': row['confidence'] ?? 1.0,
      'needsReview': row['isReviewed'] == 1 || row['needsReview'] == true,
      // Legacy tables have no hint columns; null remains fully supported.
      'billKindHint': row['billKindHint'],
      'billReminderHint':
          row['billReminderHint'] == 1 || row['billReminderHint'] == true,
    };
  }

  Map<String, dynamic> _rowMap(Map<String, dynamic> row) => _canonicalRow(row);

  Future<void> put(TransactionModel tx) async {
    throw StateError(
        'Legacy DatabaseService cannot write v2 transactions. Use TransactionCacheService.');
  }

  Future<void> putAll(List<TransactionModel> txs) async {
    throw StateError(
        'Legacy DatabaseService cannot write v2 transactions. Use TransactionCacheService.');
  }

  Future<void> remove(String id) async {
    if (_database == null) await init();
    await _database!.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    _cachedIds.remove(id);
  }

  Future<void> clearAll() async {
    if (_database == null) await init();
    await _database!.delete('transactions');
    _cachedIds.clear();
    debugPrint('🗑️ Database cleared');
  }
}
