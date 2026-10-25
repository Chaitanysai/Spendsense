import '../../models/recurring_plan.dart';
import '../../models/transaction_model.dart';
import '../../providers/planner_provider.dart';
import '../../providers/transaction_provider.dart';

/// The only surface the assistant has over local records.
///
/// It exposes typed operations, never the database, filesystem, encryption
/// service or arbitrary storage. Tests use an in-memory implementation.
abstract interface class AssistantLedger {
  List<TransactionModel> get transactions;

  List<RecurringPlan> get plans;

  Set<String> get hiddenBillKeys;

  Future<int> setExclusionForIds(Set<String> ids, bool excluded);

  Future<List<TransactionModel>> deleteTransactionsByIds(Set<String> ids);

  Future<int> restoreTransactions(List<TransactionModel> snapshots);

  Future<int> restoreExclusionStates(Map<String, bool> previousStates);
}

class ProviderAssistantLedger implements AssistantLedger {
  final TransactionProvider _transactions;
  final PlannerProvider? _planner;

  const ProviderAssistantLedger(this._transactions, [this._planner]);

  @override
  List<TransactionModel> get transactions => _transactions.transactions;

  @override
  List<RecurringPlan> get plans => _planner?.plans ?? const [];

  @override
  Set<String> get hiddenBillKeys => _planner?.hiddenBillKeys ?? const {};

  @override
  Future<int> setExclusionForIds(Set<String> ids, bool excluded) =>
      _transactions.setExclusionForIds(ids, excluded);

  @override
  Future<List<TransactionModel>> deleteTransactionsByIds(Set<String> ids) =>
      _transactions.deleteTransactionsByIds(ids);

  @override
  Future<int> restoreTransactions(List<TransactionModel> snapshots) =>
      _transactions.restoreTransactions(snapshots);

  @override
  Future<int> restoreExclusionStates(Map<String, bool> previousStates) =>
      _transactions.restoreExclusionStates(previousStates);
}
