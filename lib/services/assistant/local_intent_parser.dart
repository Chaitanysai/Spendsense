import 'assistant_date_resolver.dart';
import 'merchant_matcher.dart';

sealed class LocalIntent {
  const LocalIntent();
}

class UndoIntent extends LocalIntent {
  const UndoIntent();
}

class UnpaidBillsIntent extends LocalIntent {
  const UnpaidBillsIntent();
}

class WhyHigherIntent extends LocalIntent {
  final AssistantDateWindow window;
  const WhyHigherIntent(this.window);
}

class DeleteDuplicatesIntent extends LocalIntent {
  final AssistantDateWindow window;
  const DeleteDuplicatesIntent(this.window);
}

class MerchantTransactionsIntent extends LocalIntent {
  final List<MerchantBrand> brands;
  final AssistantDateWindow window;
  const MerchantTransactionsIntent(this.brands, this.window);
}

class ExcludeBrandsIntent extends LocalIntent {
  final List<MerchantBrand> brands;
  final AssistantDateWindow? window;
  const ExcludeBrandsIntent(this.brands, {this.window});
}

class DeleteBrandsIntent extends LocalIntent {
  final List<MerchantBrand> brands;
  final AssistantDateWindow? window;
  const DeleteBrandsIntent(this.brands, {this.window});
}

class AmbiguousBrandRemovalIntent extends LocalIntent {
  final List<MerchantBrand> brands;
  const AmbiguousBrandRemovalIntent(this.brands);
}

class CategorySpendIntent extends LocalIntent {
  final String category;
  final AssistantDateWindow window;
  const CategorySpendIntent(this.category, this.window);
}

class TopExpensesIntent extends LocalIntent {
  final AssistantDateWindow window;
  final int limit;
  const TopExpensesIntent(this.window, {this.limit = 5});
}

class SpendingSummaryIntent extends LocalIntent {
  final AssistantDateWindow window;
  const SpendingSummaryIntent(this.window);
}

class IncomeSummaryIntent extends LocalIntent {
  final AssistantDateWindow window;
  const IncomeSummaryIntent(this.window);
}

class CategorySummaryIntent extends LocalIntent {
  final AssistantDateWindow window;
  const CategorySummaryIntent(this.window);
}

class MerchantSummaryIntent extends LocalIntent {
  final AssistantDateWindow window;
  const MerchantSummaryIntent(this.window);
}

class RecentTransactionsIntent extends LocalIntent {
  final AssistantDateWindow window;
  const RecentTransactionsIntent(this.window);
}

class SpendingCountIntent extends LocalIntent {
  final AssistantDateWindow window;
  const SpendingCountIntent(this.window);
}

/// Rule-based parser for the assistant's deterministic offline mode.
///
/// It returns `null` for anything it cannot confidently map, which lets the
/// caller offer Gemini (when consented/configured) or a helpful fallback. A
/// transaction description is never parsed as a command: only the user's typed
/// message reaches this parser.
class LocalIntentParser {
  LocalIntentParser._();

  static const List<String> _categories = [
    'food',
    'shopping',
    'fuel',
    'travel',
    'bills',
    'transfer',
    'cash',
    'entertainment',
    'health',
    'investment',
  ];

  static LocalIntent? parse(String message, {DateTime? now}) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;
    final q =
        ' ${trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
    bool has(String phrase) => q.contains(' $phrase ');
    bool hasAny(Iterable<String> phrases) => phrases.any(has);

    final window = AssistantDateResolver.resolve(trimmed, now: now);

    if (hasAny(const ['undo', 'revert', 'roll back', 'rollback']) &&
        hasAny(const ['last', 'change', 'that', 'this'])) {
      return const UndoIntent();
    }

    if (hasAny(const ['bill', 'bills', 'unpaid', 'due'])) {
      if (hasAny(
          const ['unpaid', 'due', 'overdue', 'upcoming', 'show', 'list'])) {
        return const UnpaidBillsIntent();
      }
    }

    if (hasAny(const ['why', 'explain']) &&
        hasAny(const ['higher', 'more', 'increased', 'up', 'jump'])) {
      return WhyHigherIntent(window);
    }

    final brands = MerchantMatcher.detectInQuery(trimmed);
    final duplicate =
        hasAny(const ['duplicate', 'duplicates', 'same transaction']);
    if (duplicate && hasAny(const ['delete', 'remove', 'clean'])) {
      return DeleteDuplicatesIntent(window);
    }

    if (brands.isNotEmpty) {
      final asksDelete =
          hasAny(const ['delete', 'permanently delete', 'erase']);
      final asksExclude = hasAny(const ['exclude', 'ignore', 'hide']);
      final removal = hasAny(const ['remove', 'take out', 'leave out']);
      final spendingScope = hasAny(const [
        'spending',
        'calculations',
        'calculation',
        'totals',
        'total',
        'reports',
        'spend',
      ]);
      if (asksDelete) return DeleteBrandsIntent(brands, window: window);
      if (asksExclude || (removal && spendingScope)) {
        return ExcludeBrandsIntent(brands, window: window);
      }
      if (removal) return AmbiguousBrandRemovalIntent(brands);
      if (hasAny(const [
        'list',
        'show',
        'transactions',
        'transaction',
        'payments',
        'purchases',
        'history',
        'spent',
        'spend',
        'how much',
      ])) {
        return MerchantTransactionsIntent(brands, window);
      }
    }

    if (hasAny(const [
      'largest',
      'biggest',
      'highest',
      'top expense',
      'top expenses'
    ])) {
      return TopExpensesIntent(window);
    }

    if (hasAny(const [
      'top category',
      'category summary',
      'categories',
      'by category'
    ])) {
      return CategorySummaryIntent(window);
    }
    if (hasAny(
        const ['top merchant', 'top merchants', 'by merchant', 'merchants'])) {
      return MerchantSummaryIntent(window);
    }

    for (final category in _categories) {
      if (has(category) &&
          hasAny(const [
            'spend',
            'spent',
            'spending',
            'paid',
            'how much',
            'total',
            'transactions',
          ])) {
        return CategorySpendIntent(
          category[0].toUpperCase() + category.substring(1),
          window,
        );
      }
    }

    if (hasAny(const ['how many', 'count', 'number of'])) {
      return SpendingCountIntent(window);
    }

    if (hasAny(const [
      'income',
      'salary',
      'credited',
      'earned',
      'refund',
      'refunds'
    ])) {
      return IncomeSummaryIntent(window);
    }

    if (hasAny(const [
      'recent transaction',
      'recent transactions',
      'latest transaction',
      'latest transactions'
    ])) {
      return RecentTransactionsIntent(window);
    }

    if (hasAny(const [
      'total spent',
      'how much did i spend',
      'how much have i spent',
      'spending summary',
      'my spending',
      'total spending'
    ])) {
      return SpendingSummaryIntent(window);
    }

    if (hasAny(const [
      'show my transactions',
      'list my transactions',
      'all transactions'
    ])) {
      return RecentTransactionsIntent(window);
    }

    return null;
  }
}
