import 'package:intl/intl.dart';

import '../../models/assistant_models.dart';
import '../../models/transaction_model.dart';
import '../../utils/formatters.dart';
import 'assistant_date_resolver.dart';
import 'finance_tool_engine.dart';
import 'local_intent_parser.dart';
import 'merchant_matcher.dart';

/// Turns authoritative tool output into chat copy and result cards.
///
/// Every amount, count and date range displayed here is copied from a tool
/// result; the copy itself only supplies wording.
class AssistantComposer {
  final FinanceToolEngine engine;

  const AssistantComposer(this.engine);

  AssistantReply compose(LocalIntent intent) {
    return switch (intent) {
      UndoIntent() => const AssistantReply(
          text:
              'Use undo from the assistant header or ask again after a change.',
        ),
      UnpaidBillsIntent() => _bills(intent),
      WhyHigherIntent() => _whyHigher(intent),
      DeleteDuplicatesIntent() => _deleteDuplicates(intent),
      MerchantTransactionsIntent() => _merchantTransactions(intent),
      ExcludeBrandsIntent() => _brandChange(
          intent.brands, AssistantChangeType.exclusion,
          window: intent.window),
      DeleteBrandsIntent() => _brandChange(
          intent.brands, AssistantChangeType.deletion,
          window: intent.window),
      AmbiguousBrandRemovalIntent() => _ambiguousRemoval(intent),
      CategorySpendIntent() => _categorySpend(intent),
      TopExpensesIntent() => _topExpenses(intent),
      SpendingSummaryIntent() => _summary(intent.window, 'spending'),
      IncomeSummaryIntent() => _summary(intent.window, 'income'),
      CategorySummaryIntent() => _categorySummary(intent),
      MerchantSummaryIntent() => _merchantSummary(intent),
      RecentTransactionsIntent() => _recentTransactions(intent),
      SpendingCountIntent() => _summary(intent.window, 'count'),
    };
  }

  // ── Merchant list (Groww / Zerodha) ──────────────────────────────────────

  AssistantReply _merchantTransactions(MerchantTransactionsIntent intent) {
    final sections = <AssistantSection>[];
    final missing = <String>[];
    final foundParts = <String>[];
    var combinedSpending = 0;
    var combinedInvestment = 0;
    var combinedCount = 0;
    var combinedExcluded = 0;
    var combinedIncome = 0;
    var combinedExpenseCount = 0;
    var combinedIncomeCount = 0;
    DateTime? first;
    DateTime? last;

    for (final brand in intent.brands) {
      final result = engine.execute('search_transactions', {
        'brand': brand.key,
        'includeExcluded': true,
        'limit': FinanceToolEngine.maxSearchLimit,
        'sort': 'date_desc',
        if (!intent.window.isAllTime) ...{
          'startDate': intent.window.startIso,
          'endDate': intent.window.endIso,
        },
      });
      final data = result.data;
      final matched = data['matchedCount'] as int;
      if (matched == 0) {
        missing.add(brand.label);
        continue;
      }
      final totals = data['totals'] as Map<String, dynamic>;
      final transactions = _viewsFor(data);
      final section = AssistantSection(
        title: brand.label,
        subtitle: (totals['investmentMinor'] as int) > 0
            ? 'Investment / transfer outflows — not everyday consumption'
            : 'Matched merchant transactions',
        matchedCount: matched,
        totalMinor:
            (totals['expenseMinor'] as int) + (totals['incomeMinor'] as int),
        expenseMinor: totals['expenseMinor'] as int,
        incomeMinor: totals['incomeMinor'] as int,
        investmentMinor: totals['investmentMinor'] as int,
        excludedMinor: totals['excludedMinor'] as int,
        excludedCount: totals['excludedCount'] as int,
        transactions: transactions,
        truncated: (data['returnedCount'] as int) < matched,
      );
      sections.add(section);
      foundParts.add('${transactions.length} of $matched ${brand.label}');
      combinedSpending += section.expenseMinor;
      combinedInvestment += section.investmentMinor;
      combinedIncome += section.incomeMinor;
      combinedExcluded += section.excludedMinor;
      combinedExpenseCount += totals['expenseCount'] as int;
      combinedIncomeCount += totals['incomeCount'] as int;
      combinedCount += matched;
      for (final tx in transactions) {
        if (first == null || tx.date.isBefore(first)) first = tx.date;
        if (last == null || tx.date.isAfter(last)) last = tx.date;
      }
    }

    if (sections.isEmpty) {
      final names = intent.brands.map((b) => b.label).join(' or ');
      return AssistantReply(
        text: 'I couldn\'t find any $names transactions in your local ledger. '
            'Nothing was changed.',
        suggestions: const [
          'Show my unpaid bills',
          'How much did I spend this month?'
        ],
      );
    }

    final summary = AssistantSummary(
      label:
          '${intent.brands.map((b) => b.label).join(' + ')} · ${intent.window.preciseLabel}',
      start: intent.window.start ?? first,
      end: intent.window.end ?? last,
      spendingMinor: combinedSpending,
      incomeMinor: combinedIncome,
      excludedMinor: combinedExcluded,
      investmentMinor: combinedInvestment,
      transferMinor: 0,
      expenseCount: combinedExpenseCount,
      incomeCount: combinedIncomeCount,
      excludedCount: sections.fold<int>(0, (s, e) => s + e.excludedCount),
      totalCount: combinedCount,
    );

    final missingText = missing.isEmpty
        ? ''
        : ' No ${missing.join(' or ')} transactions were found for that period.';
    final investmentText = combinedInvestment > 0
        ? ' The highlighted amounts are money moved to investments/transfers, '
            'not genuine consumption spending. They remain in spending totals '
            'unless you exclude them.'
        : '';
    final excludedText = combinedExcluded > 0
        ? ' ${Formatters.currency.format(combinedExcluded)} is already excluded '
            'from spending calculations.'
        : '';

    return AssistantReply(
      text:
          'Found ${foundParts.join(' and ')} in your local ledger.$missingText'
          '$investmentText$excludedText Nothing was modified.',
      sections: sections,
      summary: summary,
      suggestions: const [
        'Exclude Groww from my spending',
        'Show my biggest expenses this year',
      ],
    );
  }

  // ── Bulk changes ─────────────────────────────────────────────────────────

  AssistantReply _brandChange(
    List<MerchantBrand> brands,
    AssistantChangeType type, {
    AssistantDateWindow? window,
  }) {
    final result = _collectBrandTransactions(brands, window: window);
    if (result.totalMatched > FinanceToolEngine.maxPreviewRecords) {
      return AssistantReply(
        text:
            'I found ${result.totalMatched} ${brands.map((b) => b.label).join(' / ')} '
            'transactions. The safety limit for one bulk change is '
            '${FinanceToolEngine.maxPreviewRecords}. Narrow the date range or '
            'change them in smaller batches. Nothing was modified.',
      );
    }
    if (result.transactions.isEmpty) {
      return AssistantReply(
        text: 'I couldn\'t find any ${brands.map((b) => b.label).join(' or ')} '
            'transactions to change. Nothing was modified.',
      );
    }
    final candidates = type == AssistantChangeType.exclusion
        ? result.transactions.where((tx) => !tx.isExcluded).toList()
        : result.transactions;
    if (candidates.isEmpty) {
      return AssistantReply(
        text: 'All ${brands.map((b) => b.label).join(' or ')} transactions '
            'matching that request are already excluded from spending. '
            'Nothing was modified.',
      );
    }
    final preview = engine.execute(
      type == AssistantChangeType.exclusion
          ? 'preview_transaction_exclusion'
          : 'preview_transaction_deletion',
      {
        'transactionIds': [for (final tx in candidates) tx.id],
      },
    );
    final pending = preview.pending!;
    final section = _sectionForPending(pending, brands);
    final difference = type == AssistantChangeType.exclusion
        ? 'Excluding keeps every record in your encrypted ledger. It only '
            'removes the rows from spending, Insights, budgets and instrument '
            'totals, and it is reversible.\n\nDeleting permanently removes the '
            'records from the ledger. If you only want spending totals to change, '
            'choose exclusion.'
        : 'Deleting permanently removes these records from your encrypted '
            'ledger. If you only want to stop counting them as spending, cancel '
            'and choose exclusion instead.';
    return AssistantReply(
      text: 'I prepared a preview for ${pending.expectedCount} '
          '${brands.map((b) => b.label).join(' / ')} transactions totaling '
          '${Formatters.currency.format(pending.expectedTotalMinor)}.\n\n'
          '$difference\n\nNo change has been applied. Review the exact records '
          'and tap Confirm to apply it. This preview expires in '
          '${AssistantPendingAction.lifetime.inMinutes} minutes.',
      sections: [section],
      pendingAction: pending,
    );
  }

  AssistantReply _ambiguousRemoval(AmbiguousBrandRemovalIntent intent) {
    final names = intent.brands.map((b) => b.label).join(' / ');
    return AssistantReply(
      text: 'I can interpret "remove $names" in two different ways, so I have '
          'not changed anything.\n\n'
          '• Exclude from spending: keep the records and reverse their effect on '
          'spending totals. This is reversible.\n'
          '• Delete permanently: remove the records from your encrypted ledger.\n\n'
          'Tell me which one you mean — for example, "Exclude $names from my '
          'spending" or "Delete my $names transactions".',
      suggestions: [
        'Exclude $names from my spending',
        'List my $names transactions',
      ],
    );
  }

  AssistantReply _deleteDuplicates(DeleteDuplicatesIntent intent) {
    final result = engine.execute('find_duplicate_transactions', {
      'limit': 50,
      if (!intent.window.isAllTime) ...{
        'startDate': intent.window.startIso,
        'endDate': intent.window.endIso,
      },
    });
    final data = result.data;
    final groupCount = data['groupCount'] as int;
    if (groupCount == 0) {
      return const AssistantReply(
        text: 'I found no likely duplicate transactions. Nothing was changed.',
      );
    }

    final groups = (data['groups'] as List).cast<Map<String, dynamic>>();
    if (groups.length < groupCount) {
      return AssistantReply(
        text: 'I found $groupCount duplicate groups, which is more than one '
            'safe preview can show (${groups.length}). Narrow the date range and '
            'ask again. Nothing was changed.',
      );
    }
    final toDelete = <String>[];
    final txById = {for (final tx in engine.transactions) tx.id: tx};
    for (final group in groups) {
      final records = (group['transactions'] as List)
          .cast<Map<String, dynamic>>()
          .map((j) => txById[j['id']])
          .whereType<TransactionModel>()
          .toList()
        ..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });
      // Keep the earliest copy; delete the extra copies.
      for (final tx in records.skip(1)) {
        toDelete.add(tx.id);
      }
    }
    if (toDelete.isEmpty) {
      return const AssistantReply(
        text:
            'I found no extra duplicate copies to remove. Nothing was changed.',
      );
    }
    final preview = engine.execute('preview_transaction_deletion', {
      'transactionIds': toDelete,
    });
    final pending = preview.pending!;
    return AssistantReply(
      text:
          'I found $groupCount duplicate groups. To preserve one copy of each, '
          'I selected ${pending.expectedCount} extra transactions totaling '
          '${Formatters.currency.format(pending.expectedTotalMinor)} for deletion.\n\n'
          'This is a permanent deletion, not an exclusion. Nothing has been '
          'deleted yet. Review the records and tap Confirm. This preview expires '
          'in ${AssistantPendingAction.lifetime.inMinutes} minutes.',
      sections: [
        AssistantSection(
          title: 'Duplicate copies to delete',
          subtitle: 'One original from each group is preserved',
          matchedCount: pending.expectedCount,
          totalMinor: pending.expectedTotalMinor,
          expenseMinor: pending.transactions
              .where((t) => !t.isIncome)
              .fold<int>(0, (s, t) => s + t.amountMinor),
          incomeMinor: pending.transactions
              .where((t) => t.isIncome)
              .fold<int>(0, (s, t) => s + t.amountMinor),
          investmentMinor: 0,
          excludedMinor: 0,
          excludedCount: 0,
          transactions: pending.transactions,
        ),
      ],
      pendingAction: pending,
    );
  }

  // ── Bills ────────────────────────────────────────────────────────────────

  AssistantReply _bills(UnpaidBillsIntent intent) {
    final result =
        engine.execute('list_bills', {'status': 'unpaid', 'limit': 20});
    final data = result.data;
    final bills = _billsFrom(data);
    if (bills.isEmpty) {
      return const AssistantReply(
        text: 'You have no unpaid bills detected from your ledger and plans.',
      );
    }
    final total = bills.fold<int>(0, (s, b) => s + b.amountMinor);
    final overdue = bills.where((b) => b.status == 'Overdue').length;
    return AssistantReply(
      text:
          'You have ${bills.length} unpaid bill${bills.length == 1 ? '' : 's'} '
          'totaling ${Formatters.currency.format(total)}'
          '${overdue > 0 ? ', including $overdue overdue' : ''}. '
          'These are derived from your local bills and transactions.',
      bills: bills,
    );
  }

  // ── Comparisons ──────────────────────────────────────────────────────────

  AssistantReply _whyHigher(WhyHigherIntent intent) {
    final month = intent.window.start == null
        ? null
        : DateFormat('yyyy-MM').format(intent.window.start!);
    final result = engine.execute('get_monthly_comparison', {
      if (month != null) 'month': month,
    });
    final data = result.data;
    final current = data['current'] as Map<String, dynamic>;
    final previous = data['previous'] as Map<String, dynamic>;
    final currentSpending = current['spendingMinor'] as int;
    final previousSpending = previous['spendingMinor'] as int;
    final delta = data['deltaMinor'] as int;
    final percent = (data['percentChange'] as num).toDouble();
    final categories = (data['categoryDrivers'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => (d['deltaMinor'] as int) > 0)
        .take(3)
        .toList();
    final merchants = (data['merchantDrivers'] as List)
        .cast<Map<String, dynamic>>()
        .where((d) => (d['deltaMinor'] as int) > 0)
        .take(3)
        .toList();

    final comparison = AssistantComparison(
      currentLabel: current['label'] as String,
      previousLabel: previous['label'] as String,
      currentSpendingMinor: currentSpending,
      previousSpendingMinor: previousSpending,
      deltaMinor: delta,
      percentChange: percent,
      categoryDrivers: [
        for (final d in categories)
          AssistantDriver(
            label: d['category'] as String,
            currentMinor: d['currentMinor'] as int,
            previousMinor: d['previousMinor'] as int,
            deltaMinor: d['deltaMinor'] as int,
          ),
      ],
      merchantDrivers: [
        for (final d in merchants)
          AssistantDriver(
            label: d['merchant'] as String,
            currentMinor: d['currentMinor'] as int,
            previousMinor: d['previousMinor'] as int,
            deltaMinor: d['deltaMinor'] as int,
          ),
      ],
    );

    if (delta <= 0) {
      return AssistantReply(
        text: 'Your spending is not higher than the previous month. '
            '${current['label']} is ${Formatters.currency.format(currentSpending)} '
            'versus ${Formatters.currency.format(previousSpending)} in '
            '${previous['label']}.',
        comparison: comparison,
      );
    }
    final reasons = <String>[
      if (categories.isNotEmpty)
        'the biggest category increases were ${categories.map((d) => '${d['category']} (+${Formatters.currency.format(d['deltaMinor'])})').join(', ')}',
      if (merchants.isNotEmpty)
        'the largest merchant contributors were ${merchants.map((d) => '${d['merchant']} (+${Formatters.currency.format(d['deltaMinor'])})').join(', ')}',
    ];
    return AssistantReply(
      text: '${current['label']} spending is '
          '${Formatters.currency.format(currentSpending)}, up '
          '${Formatters.currency.format(delta)} '
          '(${percent.toStringAsFixed(1)}%) from '
          '${previous['label']} (${Formatters.currency.format(previousSpending)}).'
          '${reasons.isEmpty ? '' : '\n\nDriven by ${reasons.join('; ')}.'}'
          '\n\nThese figures use non-excluded expense rows only.',
      comparison: comparison,
    );
  }

  // ── Summaries ────────────────────────────────────────────────────────────

  AssistantReply _summary(AssistantDateWindow window, String kind) {
    final result = engine.execute('get_spending_summary', {
      if (!window.isAllTime) ...{
        'startDate': window.startIso,
        'endDate': window.endIso,
      },
    });
    final data = result.data;
    final summary = _summaryFromData(window, data);
    if (kind == 'income') {
      return AssistantReply(
        text: 'Your recorded income/credits for ${window.preciseLabel} are '
            '${Formatters.currency.format(summary.incomeMinor)} across '
            '${summary.incomeCount} transaction${summary.incomeCount == 1 ? '' : 's'}. '
            'Refunds are stored as income rows and included here.',
        summary: summary,
      );
    }
    if (kind == 'count') {
      return AssistantReply(
        text: 'You have ${summary.expenseCount} spending transaction'
            '${summary.expenseCount == 1 ? '' : 's'} in ${window.preciseLabel}, '
            'totaling ${Formatters.currency.format(summary.spendingMinor)}. '
            'Excluded transactions are not counted.',
        summary: summary,
      );
    }
    return AssistantReply(
      text: 'You spent ${Formatters.currency.format(summary.spendingMinor)} in '
          '${window.preciseLabel} across ${summary.expenseCount} transaction'
          '${summary.expenseCount == 1 ? '' : 's'}. '
          '${summary.excludedCount > 0 ? '${summary.excludedCount} excluded transaction${summary.excludedCount == 1 ? '' : 's'} (${Formatters.currency.format(summary.excludedMinor)}) are not counted. ' : ''}'
          '${summary.investmentMinor > 0 ? '${Formatters.currency.format(summary.investmentMinor)} of the counted spending is investment/transfer outflows. ' : ''}',
      summary: summary,
    );
  }

  AssistantReply _categorySpend(CategorySpendIntent intent) {
    final result = engine.execute('get_spending_summary', {
      'category': intent.category,
      if (!intent.window.isAllTime) ...{
        'startDate': intent.window.startIso,
        'endDate': intent.window.endIso,
      },
    });
    final summary = _summaryFromData(intent.window, result.data);
    return AssistantReply(
      text: 'You spent ${Formatters.currency.format(summary.spendingMinor)} on '
          '${intent.category} in ${intent.window.preciseLabel} across '
          '${summary.expenseCount} transaction'
          '${summary.expenseCount == 1 ? '' : 's'}. '
          '${summary.spendingMinor == 0 ? 'No matching non-excluded expenses were found. ' : ''}'
          'Excluded transactions are not counted.',
      summary: summary,
    );
  }

  AssistantReply _topExpenses(TopExpensesIntent intent) {
    final result = engine.execute('search_transactions', {
      'type': 'expense',
      'includeExcluded': false,
      'sort': 'amount_desc',
      'limit': intent.limit,
      if (!intent.window.isAllTime) ...{
        'startDate': intent.window.startIso,
        'endDate': intent.window.endIso,
      },
    });
    final data = result.data;
    final summary = _summaryFromData(intent.window, data);
    final views = _viewsFor(data);
    if (views.isEmpty) {
      return AssistantReply(
        text:
            'I found no non-excluded expenses in ${intent.window.preciseLabel}.',
      );
    }
    return AssistantReply(
      text:
          'Your biggest non-excluded expenses in ${intent.window.preciseLabel} '
          'are shown below. The total spending for that period is '
          '${Formatters.currency.format(summary.spendingMinor)} across '
          '${summary.expenseCount} transactions.',
      summary: summary,
      sections: [
        AssistantSection(
          title: 'Biggest expenses',
          subtitle: 'Ranked by amount, excluded rows omitted',
          matchedCount:
              (data['totals'] as Map<String, dynamic>)['expenseCount'] as int,
          totalMinor: summary.spendingMinor,
          expenseMinor: summary.spendingMinor,
          incomeMinor: 0,
          investmentMinor: summary.investmentMinor,
          excludedMinor: summary.excludedMinor,
          excludedCount: summary.excludedCount,
          transactions: views,
        ),
      ],
    );
  }

  AssistantReply _categorySummary(CategorySummaryIntent intent) {
    final result = engine.execute('get_category_summary', {
      'limit': 20,
      if (!intent.window.isAllTime) ...{
        'startDate': intent.window.startIso,
        'endDate': intent.window.endIso,
      },
    });
    final data = result.data;
    final total = data['totalSpendingMinor'] as int;
    final categories =
        (data['categories'] as List).cast<Map<String, dynamic>>();
    if (categories.isEmpty) {
      return AssistantReply(
        text: 'No non-excluded spending categories were found for '
            '${intent.window.preciseLabel}.',
      );
    }
    final lines = categories
        .take(8)
        .map((c) =>
            '• ${c['category']}: ${Formatters.currency.format(c['amountMinor'])} '
            '(${c['count']} transaction${(c['count'] as int) == 1 ? '' : 's'}, '
            '${c['sharePercent']}%)')
        .join('\n');
    return AssistantReply(
      text: 'Spending by category for ${intent.window.preciseLabel} totals '
          '${Formatters.currency.format(total)}:\n\n$lines',
      summary: _summaryFromData(intent.window, {
        'spendingMinor': total,
        'incomeMinor': 0,
        'excludedMinor': 0,
        'investmentMinor': 0,
        'transferMinor': 0,
        'expenseCount':
            categories.fold<int>(0, (s, c) => s + (c['count'] as int)),
        'incomeCount': 0,
        'excludedCount': 0,
        'totalCount': 0,
      }),
    );
  }

  AssistantReply _merchantSummary(MerchantSummaryIntent intent) {
    final result = engine.execute('group_transactions_by_merchant', {
      'limit': 20,
      if (!intent.window.isAllTime) ...{
        'startDate': intent.window.startIso,
        'endDate': intent.window.endIso,
      },
    });
    final data = result.data;
    final groups = (data['groups'] as List).cast<Map<String, dynamic>>();
    if (groups.isEmpty) {
      return AssistantReply(
        text:
            'No merchant spending was found for ${intent.window.preciseLabel}.',
      );
    }
    final lines = groups
        .take(8)
        .map((g) =>
            '• ${g['merchant']}: ${Formatters.currency.format(g['expenseMinor'])} '
            'across ${g['count']} transaction${(g['count'] as int) == 1 ? '' : 's'}')
        .join('\n');
    final total = groups.fold<int>(0, (s, g) => s + (g['expenseMinor'] as int));
    return AssistantReply(
      text: 'Top merchants for ${intent.window.preciseLabel}:\n\n$lines',
      summary: _summaryFromData(intent.window, {
        'spendingMinor': total,
        'incomeMinor': 0,
        'excludedMinor': 0,
        'investmentMinor': 0,
        'transferMinor': 0,
        'expenseCount': groups.fold<int>(0, (s, g) => s + (g['count'] as int)),
        'incomeCount': 0,
        'excludedCount': 0,
        'totalCount': 0,
      }),
    );
  }

  AssistantReply _recentTransactions(RecentTransactionsIntent intent) {
    final result = engine.execute('search_transactions', {
      'includeExcluded': true,
      'limit': 20,
      'sort': 'date_desc',
      if (!intent.window.isAllTime) ...{
        'startDate': intent.window.startIso,
        'endDate': intent.window.endIso,
      },
    });
    final data = result.data;
    final views = _viewsFor(data);
    if (views.isEmpty) {
      return AssistantReply(
        text: 'No transactions found for ${intent.window.preciseLabel}.',
      );
    }
    final totals = data['totals'] as Map<String, dynamic>;
    return AssistantReply(
      text: 'Here are the latest ${views.length} of '
          '${data['matchedCount']} matching transactions for '
          '${intent.window.preciseLabel}.',
      summary: _summaryFromData(intent.window, data),
      sections: [
        AssistantSection(
          title: 'Transactions',
          subtitle: 'Income, expenses and excluded rows are labelled',
          matchedCount: data['matchedCount'] as int,
          totalMinor:
              (totals['expenseMinor'] as int) + (totals['incomeMinor'] as int),
          expenseMinor: totals['expenseMinor'] as int,
          incomeMinor: totals['incomeMinor'] as int,
          investmentMinor: totals['investmentMinor'] as int,
          excludedMinor: totals['excludedMinor'] as int,
          excludedCount: totals['excludedCount'] as int,
          transactions: views,
          truncated:
              (data['returnedCount'] as int) < (data['matchedCount'] as int),
        ),
      ],
    );
  }

  /// Attaches authoritative cards to a Gemini-authored explanation. The model
  /// never supplies amounts used in a card.
  AssistantReply composeRemote({
    required String text,
    required List<FinanceToolResult> toolResults,
    AssistantPendingAction? pending,
  }) {
    final sections = <AssistantSection>[];
    AssistantSummary? summary;
    AssistantComparison? comparison;
    var bills = <AssistantBillCard>[];

    for (final result in toolResults) {
      final data = result.data;
      switch (result.tool) {
        case 'search_transactions':
          final totals = data['totals'] as Map<String, dynamic>;
          sections.add(AssistantSection(
            title: 'Matching transactions',
            subtitle: data['range']?['label'] as String?,
            matchedCount: data['matchedCount'] as int,
            totalMinor: (totals['expenseMinor'] as int) +
                (totals['incomeMinor'] as int),
            expenseMinor: totals['expenseMinor'] as int,
            incomeMinor: totals['incomeMinor'] as int,
            investmentMinor: totals['investmentMinor'] as int,
            excludedMinor: totals['excludedMinor'] as int,
            excludedCount: totals['excludedCount'] as int,
            transactions: _viewsFor(data),
            truncated:
                (data['returnedCount'] as int) < (data['matchedCount'] as int),
          ));
          break;
        case 'get_spending_summary':
          final window = _windowFromData(data);
          summary = _summaryFromData(window, data);
          break;
        case 'get_category_summary':
          final total = data['totalSpendingMinor'] as int? ?? 0;
          summary = AssistantSummary(
            label:
                (data['range'] as Map<String, dynamic>?)?['label'] as String? ??
                    'Category summary',
            spendingMinor: total,
            incomeMinor: 0,
            excludedMinor: 0,
            investmentMinor: 0,
            transferMinor: 0,
            expenseCount: ((data['categories'] as List?) ?? const []).fold<int>(
              0,
              (s, c) => s + ((c as Map<String, dynamic>)['count'] as int? ?? 0),
            ),
            incomeCount: 0,
            excludedCount: 0,
            totalCount: 0,
          );
          break;
        case 'get_monthly_comparison':
          final current = data['current'] as Map<String, dynamic>;
          final previous = data['previous'] as Map<String, dynamic>;
          comparison = AssistantComparison(
            currentLabel: current['label'] as String,
            previousLabel: previous['label'] as String,
            currentSpendingMinor: current['spendingMinor'] as int,
            previousSpendingMinor: previous['spendingMinor'] as int,
            deltaMinor: data['deltaMinor'] as int,
            percentChange: (data['percentChange'] as num).toDouble(),
            categoryDrivers: [
              for (final d in (data['categoryDrivers'] as List)
                  .cast<Map<String, dynamic>>())
                AssistantDriver(
                  label: d['category'] as String,
                  currentMinor: d['currentMinor'] as int,
                  previousMinor: d['previousMinor'] as int,
                  deltaMinor: d['deltaMinor'] as int,
                ),
            ],
            merchantDrivers: [
              for (final d in (data['merchantDrivers'] as List)
                  .cast<Map<String, dynamic>>())
                AssistantDriver(
                  label: d['merchant'] as String,
                  currentMinor: d['currentMinor'] as int,
                  previousMinor: d['previousMinor'] as int,
                  deltaMinor: d['deltaMinor'] as int,
                ),
            ],
          );
          break;
        case 'list_bills':
          bills = _billsFrom(data);
          break;
        case 'preview_transaction_exclusion':
        case 'preview_transaction_deletion':
          // The preview card below is built from the pinned pending action.
          break;
        default:
          break;
      }
    }

    if (pending != null) {
      sections.insert(
        0,
        AssistantSection(
          title: pending.isDeletion ? 'Delete preview' : 'Exclusion preview',
          subtitle: '${pending.expectedCount} records · no changes applied yet',
          matchedCount: pending.expectedCount,
          totalMinor: pending.expectedTotalMinor,
          expenseMinor: pending.transactions
              .where((t) => !t.isIncome && !t.isExcluded)
              .fold<int>(0, (s, t) => s + t.amountMinor),
          incomeMinor: pending.transactions
              .where((t) => t.isIncome)
              .fold<int>(0, (s, t) => s + t.amountMinor),
          investmentMinor: pending.transactions
              .where((t) => t.kind == AssistantTransactionKind.investment)
              .fold<int>(0, (s, t) => s + t.amountMinor),
          excludedMinor: pending.transactions
              .where((t) => t.isExcluded)
              .fold<int>(0, (s, t) => s + t.amountMinor),
          excludedCount: pending.transactions.where((t) => t.isExcluded).length,
          transactions: pending.transactions,
        ),
      );
    }

    final fallback = pending != null
        ? 'I prepared a preview for ${pending.expectedCount} transactions. '
            'Review the exact records and confirm before anything changes.'
        : 'I found the authoritative data below.';
    return AssistantReply(
      text: text.trim().isEmpty ? fallback : text.trim(),
      sections: sections,
      summary: summary,
      comparison: comparison,
      bills: bills,
      pendingAction: pending,
    );
  }

  AssistantDateWindow _windowFromData(Map<String, dynamic> data) {
    final range = data['range'] as Map<String, dynamic>?;
    if (range == null ||
        (range['startDate'] as String? ?? '').isEmpty ||
        (range['endDate'] as String? ?? '').isEmpty) {
      return const AssistantDateWindow.allTime();
    }
    final start = DateTime.tryParse(range['startDate'] as String);
    final end = DateTime.tryParse(range['endDate'] as String);
    if (start == null || end == null) {
      return const AssistantDateWindow.allTime();
    }
    return AssistantDateWindow.range(
      start: start,
      end: end,
      label: range['label'] as String? ?? 'Selected period',
    );
  }

  // ── Shared mapping ───────────────────────────────────────────────────────

  AssistantSummary _summaryFromData(
    AssistantDateWindow window,
    Map<String, dynamic> data,
  ) {
    final range = data['range'] as Map<String, dynamic>?;
    final start =
        (range == null || (range['startDate'] as String? ?? '').isEmpty)
            ? window.start
            : DateTime.tryParse(range['startDate'] as String) ?? window.start;
    final end = (range == null || (range['endDate'] as String? ?? '').isEmpty)
        ? window.end
        : DateTime.tryParse(range['endDate'] as String) ?? window.end;
    return AssistantSummary(
      label: window.preciseLabel,
      start: start,
      end: end,
      spendingMinor: data['spendingMinor'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['expenseMinor'] as int? ??
          0,
      incomeMinor: data['incomeMinor'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['incomeMinor'] as int? ??
          0,
      excludedMinor: data['excludedMinor'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['excludedMinor'] as int? ??
          0,
      investmentMinor: data['investmentMinor'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['investmentMinor']
              as int? ??
          0,
      transferMinor: data['transferMinor'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['transferMinor'] as int? ??
          0,
      expenseCount: data['expenseCount'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['expenseCount'] as int? ??
          0,
      incomeCount: data['incomeCount'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['incomeCount'] as int? ??
          0,
      excludedCount: data['excludedCount'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['excludedCount'] as int? ??
          0,
      totalCount: data['transactionCount'] as int? ??
          (data['totals'] as Map<String, dynamic>?)?['totalCount'] as int? ??
          0,
    );
  }

  List<AssistantTransactionView> _viewsFor(Map<String, dynamic> data) {
    final raw = (data['transactions'] as List?) ?? const [];
    final byId = {for (final tx in engine.transactions) tx.id: tx};
    return [
      for (final item in raw.cast<Map<String, dynamic>>())
        if (byId[item['id']] != null)
          AssistantTransactionView.fromTransaction(byId[item['id']]!),
    ];
  }

  _Collected _collectBrandTransactions(
    List<MerchantBrand> brands, {
    AssistantDateWindow? window,
  }) {
    final all = <TransactionModel>[];
    final seen = <String>{};
    var totalMatched = 0;
    for (final brand in brands) {
      var offset = 0;
      var brandMatched = 0;
      // Stop one page past the safety limit so an over-limit set is detected
      // rather than silently truncated.
      while (offset <= FinanceToolEngine.maxPreviewRecords) {
        final result = engine.execute('search_transactions', {
          'brand': brand.key,
          'includeExcluded': true,
          'limit': FinanceToolEngine.maxSearchLimit,
          'offset': offset,
          'sort': 'date_desc',
          // A request like "delete my Groww transactions last month" must never
          // widen to all time: the window is part of the intent.
          if (window != null && !window.isAllTime) ...{
            'startDate': window.startIso,
            'endDate': window.endIso,
          },
        });
        final data = result.data;
        final raw = (data['transactions'] as List).cast<Map<String, dynamic>>();
        final byId = {for (final tx in engine.transactions) tx.id: tx};
        for (final item in raw) {
          final tx = byId[item['id']];
          // Defence in depth: the tool window may be ignored by a future
          // implementation, so re-check the dates here as well.
          if (tx != null &&
              (window == null || window.isAllTime || window.contains(tx.date)) &&
              seen.add(tx.id)) {
            all.add(tx);
          }
        }
        brandMatched = data['matchedCount'] as int;
        offset += raw.length;
        if (offset >= brandMatched || raw.isEmpty) break;
      }
      totalMatched += brandMatched;
    }
    return _Collected(all, totalMatched);
  }

  AssistantSection _sectionForPending(
    AssistantPendingAction pending,
    List<MerchantBrand> brands,
  ) {
    final views = pending.transactions;
    return AssistantSection(
      title: pending.isDeletion ? 'Delete preview' : 'Exclusion preview',
      subtitle:
          '${brands.map((b) => b.label).join(' / ')} · no changes applied yet',
      matchedCount: pending.expectedCount,
      totalMinor: pending.expectedTotalMinor,
      expenseMinor: views
          .where((t) => !t.isIncome && !t.isExcluded)
          .fold<int>(0, (s, t) => s + t.amountMinor),
      incomeMinor: views
          .where((t) => t.isIncome)
          .fold<int>(0, (s, t) => s + t.amountMinor),
      investmentMinor: views
          .where((t) =>
              t.kind == AssistantTransactionKind.investment && !t.isExcluded)
          .fold<int>(0, (s, t) => s + t.amountMinor),
      excludedMinor: views
          .where((t) => t.isExcluded)
          .fold<int>(0, (s, t) => s + t.amountMinor),
      excludedCount: views.where((t) => t.isExcluded).length,
      transactions: views,
    );
  }

  List<AssistantBillCard> _billsFrom(Map<String, dynamic> data) {
    return [
      for (final bill in (data['bills'] as List).cast<Map<String, dynamic>>())
        AssistantBillCard(
          title: bill['title'] as String,
          category: bill['category'] as String,
          amountMinor: bill['amountMinor'] as int,
          dueDate: bill['dueDate'] == null
              ? null
              : DateTime.tryParse(bill['dueDate'] as String),
          status: bill['state'] as String,
          isRecurring: bill['isRecurring'] as bool? ?? false,
          confidence: (bill['confidence'] as num?)?.toDouble(),
        ),
    ];
  }
}

class _Collected {
  final List<TransactionModel> transactions;
  final int totalMatched;
  const _Collected(this.transactions, this.totalMatched);
}
