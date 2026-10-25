import 'package:spendsense/models/recurring_plan.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/assistant/assistant_audit.dart';
import 'package:spendsense/services/assistant/assistant_auth.dart';
import 'package:spendsense/services/assistant/assistant_ledger.dart';
import 'package:spendsense/services/assistant/assistant_settings.dart';
import 'package:spendsense/services/assistant/gemini_proxy_client.dart';

TransactionModel tx({
  required String id,
  required int amountMinor,
  required DateTime date,
  String merchant = 'Merchant',
  String category = 'Shopping',
  TransactionType type = TransactionType.expense,
  bool excluded = false,
  String originalSms = '',
  String? reference,
  String source = 'SMS-Parser',
}) =>
    TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: originalSms,
      isExcluded: excluded,
      reference: reference,
      source: source,
    );

class MemoryLedger implements AssistantLedger {
  final List<TransactionModel> _transactions;
  final List<RecurringPlan> _plans;
  final Set<String> _hidden;
  int exclusionWrites = 0;
  int deletionWrites = 0;

  MemoryLedger({
    List<TransactionModel>? transactions,
    List<RecurringPlan>? plans,
    Set<String>? hidden,
  })  : _transactions = [...?transactions],
        _plans = [...?plans],
        _hidden = {...?hidden};

  @override
  List<TransactionModel> get transactions => List.unmodifiable(_transactions);

  @override
  List<RecurringPlan> get plans => List.unmodifiable(_plans);

  @override
  Set<String> get hiddenBillKeys => Set.unmodifiable(_hidden);

  @override
  Future<int> setExclusionForIds(Set<String> ids, bool excluded) async {
    exclusionWrites++;
    var changed = 0;
    for (var i = 0; i < _transactions.length; i++) {
      final item = _transactions[i];
      if (!ids.contains(item.id) || item.isExcluded == excluded) continue;
      _transactions[i] = item.copyWith(isExcluded: excluded);
      changed++;
    }
    return changed;
  }

  @override
  Future<List<TransactionModel>> deleteTransactionsByIds(
      Set<String> ids) async {
    deletionWrites++;
    final removed = [
      for (final item in _transactions)
        if (ids.contains(item.id)) item
    ];
    _transactions.removeWhere((item) => ids.contains(item.id));
    return removed;
  }

  @override
  Future<int> restoreTransactions(List<TransactionModel> snapshots) async {
    final byId = {for (final item in snapshots) item.id: item};
    for (var i = 0; i < _transactions.length; i++) {
      final replacement = byId[_transactions[i].id];
      if (replacement != null) _transactions[i] = replacement;
    }
    final existing = {for (final item in _transactions) item.id};
    _transactions.addAll(
      snapshots.where((item) => !existing.contains(item.id)),
    );
    return snapshots.length;
  }

  @override
  Future<int> restoreExclusionStates(Map<String, bool> previousStates) async {
    var changed = 0;
    for (var i = 0; i < _transactions.length; i++) {
      final target = previousStates[_transactions[i].id];
      if (target == null || _transactions[i].isExcluded == target) continue;
      _transactions[i] = _transactions[i].copyWith(isExcluded: target);
      changed++;
    }
    return changed;
  }
}

class MemoryAudit implements AssistantAuditRepository {
  final List<AssistantAuditEntry> entries = [];
  bool failAppend = false;

  @override
  Future<void> append(AssistantAuditEntry entry) async {
    if (failAppend) throw const AssistantAuditException('forced failure');
    entries.add(entry);
  }

  @override
  Future<void> clear() async => entries.clear();

  @override
  Future<List<AssistantAuditEntry>> load() async => List.unmodifiable(entries);

  @override
  Future<void> markUndone(String id) async {
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index == -1) {
      throw const AssistantAuditException('missing');
    }
    entries[index] = entries[index].copyWith(undone: true);
  }
}

class StaticAuthTokenProvider implements AssistantAuthTokenProvider {
  final String? token;
  final Object? error;
  int calls = 0;

  StaticAuthTokenProvider({this.token = 'test-app-check-token', this.error});

  @override
  bool get isConfigured => true;

  @override
  Future<String> getToken() async {
    calls++;
    if (error != null) throw error!;
    final value = token;
    if (value == null || value.isEmpty) {
      throw const AssistantAuthException(
        'auth_unavailable',
        'The assistant could not verify this app installation.',
      );
    }
    return value;
  }
}

class StaticIdentityTokenProvider implements AssistantIdentityTokenProvider {
  final String? token;
  final Object? error;
  int calls = 0;

  StaticIdentityTokenProvider({this.token = 'test-id-token', this.error});

  @override
  bool get isConfigured => true;

  @override
  Future<String> getIdToken() async {
    calls++;
    if (error != null) throw error!;
    final value = token;
    if (value == null || value.isEmpty) {
      throw const AssistantAuthException(
        'auth_unavailable',
        'Your sign-in session could not be verified.',
      );
    }
    return value;
  }
}

class MemoryConsent implements AssistantConsentStore {
  bool allowed;
  MemoryConsent({this.allowed = false});

  @override
  Future<bool> hasCloudConsent() async => allowed;

  @override
  Future<void> setCloudConsent(bool value) async => allowed = value;
}

class ScriptedRemote implements AssistantRemoteClient {
  final List<RemoteAssistantTurn> turns;
  final List<RemoteCall> calls = [];
  int index = 0;
  Object? error;

  ScriptedRemote({List<RemoteAssistantTurn>? turns, this.error})
      : turns = [...?turns];

  @override
  Future<RemoteAssistantTurn> send({
    required String message,
    required List<RemoteHistoryTurn> history,
    required List<RemoteToolExchange> toolExchanges,
  }) async {
    calls.add(RemoteCall(
      message: message,
      history: List.of(history),
      toolExchanges: List.of(toolExchanges),
    ));
    if (error != null) throw error!;
    if (index >= turns.length) {
      return const RemoteAssistantTurn(text: 'Done.');
    }
    return turns[index++];
  }
}

class RemoteCall {
  final String message;
  final List<RemoteHistoryTurn> history;
  final List<RemoteToolExchange> toolExchanges;

  const RemoteCall({
    required this.message,
    required this.history,
    required this.toolExchanges,
  });
}
