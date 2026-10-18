import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            amount INTEGER NOT NULL,
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
    );

    // Load existing IDs into memory set for O(1) duplicate checks
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

  Future<void> put(TransactionModel tx) async {
    if (_database == null) await init();
    await _database!.insert(
      'transactions',
      _txMap(tx),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _cachedIds.add(tx.id);
  }

  Future<void> putAll(List<TransactionModel> txs) async {
    if (_database == null) await init();
    if (txs.isEmpty) return;

    await _database!.transaction((txn) async {
      for (final tx in txs) {
        await txn.insert(
          'transactions',
          _txMap(tx),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        _cachedIds.add(tx.id);
      }
    });
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

  Map<String, dynamic> _txMap(TransactionModel t) => {
        'id': t.id,
        'amount': t.amount,
        'type': t.type == TransactionType.income ? 'income' : 'expense',
        'merchant': t.merchant,
        'category': t.category,
        'paymentMethod': t.paymentMethod,
        'date': t.date.toIso8601String(),
        'time': t.time,
        'originalSms': t.originalSms,
        'isExcluded': t.isExcluded ? 1 : 0,
        'bank': t.bank,
        'account': t.account,
        'reference': t.reference,
        'source': t.source,
        'confidence': t.confidence,
        'needsReview': t.needsReview ? 1 : 0,
      };

  Map<String, dynamic> _rowMap(Map<String, dynamic> row) => {
        'id': row['id'],
        'amount': row['amount'],
        'type': row['type'],
        'merchant': row['merchant'],
        'category': row['category'],
        'paymentMethod': row['paymentMethod'],
        'date': row['date'],
        'time': row['time'],
        'originalSms': row['originalSms'],
        'isExcluded': row['isExcluded'] == 1,
        'bank': row['bank'],
        'account': row['account'],
        'reference': row['reference'],
        'source': row['source'] ?? 'sms_local',
        'confidence': row['confidence'] ?? 1.0,
        'needsReview': row['isReviewed'] == 1,
      };
}
