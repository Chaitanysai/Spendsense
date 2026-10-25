import 'package:intl/intl.dart';

import 'transaction_model.dart';

/// The finance-facing classification used **only for presentation** inside the
/// assistant. It never changes a stored transaction and never changes a total:
/// every authoritative amount still comes from [TransactionModel.amountMinor]
/// and [TransactionModel.type].
///
/// SpendSense stores income and expense magnitudes. A refund is an income row
/// whose description uses refund language; a transfer is a Transfer-category
/// row (or an investment rail such as Groww / Zerodha). Excluded is a separate
/// flag, not a kind, so an excluded transfer can still be labelled correctly.
enum AssistantTransactionKind {
  expense,
  income,
  refund,
  transfer,
  investment,
}

extension AssistantTransactionKindX on AssistantTransactionKind {
  String get label => switch (this) {
        AssistantTransactionKind.expense => 'Expense',
        AssistantTransactionKind.income => 'Income',
        AssistantTransactionKind.refund => 'Refund / credit',
        AssistantTransactionKind.transfer => 'Transfer',
        AssistantTransactionKind.investment => 'Investment transfer',
      };
}

/// A safe, display-only projection of a stored transaction.
///
/// Raw SMS, account numbers and references are deliberately absent. The model
/// receives only what is needed to identify a record and render its card.
class AssistantTransactionView {
  final String id;
  final String merchant;
  final String category;
  final String? bank;
  final String paymentMethod;
  final DateTime date;
  final int amountMinor;
  final TransactionType type;
  final bool isExcluded;
  final AssistantTransactionKind kind;
  final String source;

  const AssistantTransactionView({
    required this.id,
    required this.merchant,
    required this.category,
    required this.paymentMethod,
    required this.date,
    required this.amountMinor,
    required this.type,
    required this.isExcluded,
    required this.kind,
    this.bank,
    this.source = '',
  });

  factory AssistantTransactionView.fromTransaction(TransactionModel tx) {
    return AssistantTransactionView(
      id: tx.id,
      merchant: tx.merchant,
      category: tx.category,
      bank: tx.bankName,
      paymentMethod: tx.paymentMethod,
      date: tx.date,
      amountMinor: tx.amountMinor,
      type: tx.type,
      isExcluded: tx.isExcluded,
      kind: classifyTransaction(tx),
      source: tx.source,
    );
  }

  bool get isIncome => type == TransactionType.income;

  String get signedLabel => '${isIncome ? '+' : '−'} ${NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: amountMinor % 100 == 0 ? 0 : 2,
      ).format(amountMinor / 100)}';

  String get dateLabel => DateFormat('d MMM yyyy').format(date.toLocal());

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchant': merchant,
        'category': category,
        'date': DateFormat('yyyy-MM-dd').format(date.toLocal()),
        'amountMinor': amountMinor,
        'type': type == TransactionType.income ? 'income' : 'expense',
        'isExcluded': isExcluded,
        'kind': kind.name,
      };

  /// Minimal projection sent to Gemini when a tool result is needed.
  /// Bank, payment method, references and raw SMS are deliberately absent.
  Map<String, dynamic> toToolJson() => toJson();
}

/// Deterministic display classification. Refund language is matched only on
/// merchant text; no raw body is retained for new records.
AssistantTransactionKind classifyTransaction(TransactionModel tx) {
  final category = tx.category.trim().toLowerCase();
  final merchant = tx.merchant.trim().toLowerCase();
  final looksInvestment = const [
    'groww',
    'zerodha',
    'mutual fund',
    'sip',
    'smallcase',
    'upstox',
    'angel one',
    'kuvera',
    'indmoney',
  ].any((term) => _containsTerm(merchant, term));
  if (category == 'investment' || looksInvestment) {
    return AssistantTransactionKind.investment;
  }
  if (category == 'transfer') return AssistantTransactionKind.transfer;
  if (tx.type == TransactionType.income) {
    final looksRefund = const [
      'refund',
      'reversal',
      'reversed',
      'cashback',
      'chargeback',
      'returned',
    ].any((term) => _containsTerm(merchant, term));
    return looksRefund
        ? AssistantTransactionKind.refund
        : AssistantTransactionKind.income;
  }
  return AssistantTransactionKind.expense;
}

bool _containsTerm(String haystack, String term) {
  final normalized =
      haystack.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return ' $normalized '.contains(' $term ');
}

/// One rendered result section, e.g. "Groww" and "Zerodha".
class AssistantSection {
  final String title;
  final String? subtitle;
  final int matchedCount;
  final int totalMinor;
  final int expenseMinor;
  final int incomeMinor;
  final int investmentMinor;
  final int excludedMinor;
  final int excludedCount;
  final List<AssistantTransactionView> transactions;
  final bool truncated;

  const AssistantSection({
    required this.title,
    required this.matchedCount,
    required this.totalMinor,
    required this.expenseMinor,
    required this.incomeMinor,
    required this.investmentMinor,
    required this.excludedMinor,
    required this.excludedCount,
    required this.transactions,
    this.subtitle,
    this.truncated = false,
  });

  bool get hasInvestmentTransfers => investmentMinor > 0;
}

/// Authoritative totals returned by deterministic code. No value here is ever
/// computed by the language model.
class AssistantSummary {
  final String label;
  final DateTime? start;
  final DateTime? end;
  final int spendingMinor;
  final int incomeMinor;
  final int excludedMinor;
  final int investmentMinor;
  final int transferMinor;
  final int expenseCount;
  final int incomeCount;
  final int excludedCount;
  final int totalCount;

  const AssistantSummary({
    required this.label,
    required this.spendingMinor,
    required this.incomeMinor,
    required this.excludedMinor,
    required this.investmentMinor,
    required this.transferMinor,
    required this.expenseCount,
    required this.incomeCount,
    required this.excludedCount,
    required this.totalCount,
    this.start,
    this.end,
  });

  String get rangeLabel {
    if (start == null || end == null) return 'All time';
    final format = DateFormat('d MMM yyyy');
    return '${format.format(start!.toLocal())} – ${format.format(end!.toLocal())}';
  }
}

class AssistantDriver {
  final String label;
  final int currentMinor;
  final int previousMinor;
  final int deltaMinor;

  const AssistantDriver({
    required this.label,
    required this.currentMinor,
    required this.previousMinor,
    required this.deltaMinor,
  });
}

class AssistantComparison {
  final String currentLabel;
  final String previousLabel;
  final int currentSpendingMinor;
  final int previousSpendingMinor;
  final int deltaMinor;
  final double percentChange;
  final List<AssistantDriver> categoryDrivers;
  final List<AssistantDriver> merchantDrivers;

  const AssistantComparison({
    required this.currentLabel,
    required this.previousLabel,
    required this.currentSpendingMinor,
    required this.previousSpendingMinor,
    required this.deltaMinor,
    required this.percentChange,
    this.categoryDrivers = const [],
    this.merchantDrivers = const [],
  });
}

class AssistantBillCard {
  final String title;
  final String category;
  final int amountMinor;
  final DateTime? dueDate;
  final String status;
  final bool isRecurring;
  final double? confidence;

  const AssistantBillCard({
    required this.title,
    required this.category,
    required this.amountMinor,
    required this.status,
    required this.isRecurring,
    this.dueDate,
    this.confidence,
  });

  String get dueLabel => dueDate == null
      ? 'No due date'
      : DateFormat('d MMM yyyy').format(dueDate!);
}

enum AssistantChangeType { exclusion, deletion }

extension AssistantChangeTypeX on AssistantChangeType {
  String get label => this == AssistantChangeType.exclusion
      ? 'Exclude from spending'
      : 'Delete permanently';
}

/// A validated, immutable plan that the user must explicitly confirm.
///
/// [expectedFingerprints] pins every record the preview was built from. If the
/// ledger changed after the preview, apply fails rather than acting on a
/// different set.
class AssistantPendingAction {
  static const Duration lifetime = Duration(minutes: 5);
  static const int maxRecords = 200;

  final String id;
  final AssistantChangeType type;
  final List<String> transactionIds;
  final List<AssistantTransactionView> transactions;
  final Map<String, String> expectedFingerprints;
  final int expectedCount;
  final int expectedTotalMinor;
  final int spendingBeforeMinor;
  final int spendingAfterMinor;
  final String spendingScopeLabel;
  final DateTime? spendingScopeStart;
  final DateTime? spendingScopeEnd;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String explanation;

  const AssistantPendingAction({
    required this.id,
    required this.type,
    required this.transactionIds,
    required this.transactions,
    required this.expectedFingerprints,
    required this.expectedCount,
    required this.expectedTotalMinor,
    required this.spendingBeforeMinor,
    required this.spendingAfterMinor,
    required this.spendingScopeLabel,
    required this.createdAt,
    required this.expiresAt,
    required this.explanation,
    this.spendingScopeStart,
    this.spendingScopeEnd,
  });

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  bool get isDeletion => type == AssistantChangeType.deletion;

  String fingerprintOf(TransactionModel tx) =>
      '${tx.amountMinor}|${tx.isExcluded ? 1 : 0}|${tx.type.name}|'
      '${tx.date.toIso8601String()}|${tx.merchant}';
}

/// A complete assistant turn: all authoritative cards plus the optional pending
/// action that must be confirmed by an explicit tap.
class AssistantReply {
  final String text;
  final List<AssistantSection> sections;
  final AssistantSummary? summary;
  final AssistantComparison? comparison;
  final List<AssistantBillCard> bills;
  final AssistantPendingAction? pendingAction;
  final bool needsCloudConsent;
  final bool isError;
  final List<String> suggestions;

  const AssistantReply({
    required this.text,
    this.sections = const [],
    this.summary,
    this.comparison,
    this.bills = const [],
    this.pendingAction,
    this.needsCloudConsent = false,
    this.isError = false,
    this.suggestions = const [],
  });
}

class AssistantChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final AssistantReply? reply;
  final bool isLoading;
  final bool isError;
  final DateTime createdAt;

  const AssistantChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.createdAt,
    this.reply,
    this.isLoading = false,
    this.isError = false,
  });
}
