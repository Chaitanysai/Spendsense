import 'dart:convert';

import '../../models/assistant_models.dart';
import '../../models/transaction_model.dart';
import '../../utils/formatters.dart';
import 'assistant_audit.dart';
import 'assistant_composer.dart';
import 'assistant_date_resolver.dart';
import 'assistant_ledger.dart';
import 'assistant_settings.dart';
import 'finance_tool_engine.dart';
import 'gemini_proxy_client.dart';
import 'local_intent_parser.dart';

class AssistantOrchestrator {
  final AssistantLedger ledger;
  final AssistantAuditRepository audit;
  final AssistantConsentStore consent;
  final AssistantRemoteClient? remoteClient;
  final DateTime Function() clock;

  AssistantPendingAction? _pending;
  bool _applying = false;

  AssistantOrchestrator({
    required this.ledger,
    required this.audit,
    required this.consent,
    this.remoteClient,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  AssistantPendingAction? get pending {
    final value = _pending;
    if (value != null && value.isExpiredAt(clock())) {
      _pending = null;
      return null;
    }
    return _pending;
  }

  bool get isCloudConfigured => remoteClient != null;

  /// Drops an unconfirmed preview without changing the ledger. Used when the
  /// conversation is cleared so an invisible preview can never be confirmed.
  void discardPending() {
    _pending = null;
  }

  FinanceToolEngine _engine() => FinanceToolEngine(
        transactions: ledger.transactions,
        plans: ledger.plans,
        hiddenBillKeys: ledger.hiddenBillKeys,
        now: clock(),
      );

  AssistantComposer _composer() => AssistantComposer(_engine());

  /// Explicit UI confirmation only. A free-text "okay" never reaches this.
  Future<AssistantReply> confirmPending(String actionId) async {
    if (_applying) {
      return const AssistantReply(
        text: 'A change is already being applied. Wait for it to finish.',
        isError: true,
      );
    }
    final action = pending;
    if (action == null) {
      return const AssistantReply(
        text: 'There is no active preview. Nothing was changed.',
        isError: true,
      );
    }
    if (action.id != actionId) {
      return const AssistantReply(
        text: 'That confirmation does not match the current preview. '
            'Nothing was changed; review the latest preview.',
        isError: true,
      );
    }
    if (action.isExpiredAt(clock())) {
      _pending = null;
      return const AssistantReply(
        text: 'That preview expired, so nothing was changed. Ask again to '
            'create a fresh preview.',
        isError: true,
      );
    }

    final byId = {for (final tx in ledger.transactions) tx.id: tx};
    for (final id in action.transactionIds) {
      final tx = byId[id];
      if (tx == null) {
        _pending = null;
        return const AssistantReply(
          text: 'The ledger changed after this preview was created, so the '
              'change was not applied. Ask again for a fresh preview.',
          isError: true,
        );
      }
      if (action.expectedFingerprints[id] != action.fingerprintOf(tx)) {
        _pending = null;
        return const AssistantReply(
          text: 'One of the previewed transactions changed, so the change was '
              'not applied. Ask again for a fresh preview.',
          isError: true,
        );
      }
    }
    if (action.type == AssistantChangeType.exclusion &&
        action.transactionIds.any((id) => byId[id]!.isExcluded)) {
      _pending = null;
      return const AssistantReply(
        text: 'Some of those transactions are already excluded. Nothing was '
            'changed. Ask again for a fresh preview.',
        isError: true,
      );
    }

    _applying = true;
    final previousExcluded = <String, bool>{};
    List<TransactionModel> removed = const [];
    try {
      if (action.type == AssistantChangeType.exclusion) {
        for (final id in action.transactionIds) {
          previousExcluded[id] = byId[id]!.isExcluded;
        }
        final changed = await ledger.setExclusionForIds(
          action.transactionIds.toSet(),
          true,
        );
        if (changed != action.expectedCount) {
          await ledger.restoreExclusionStates(previousExcluded);
          _pending = null;
          return const AssistantReply(
            text: 'The ledger did not match the preview exactly, so the change '
                'was rolled back. Nothing was changed. Ask again.',
            isError: true,
          );
        }
      } else {
        removed = await ledger.deleteTransactionsByIds(
          action.transactionIds.toSet(),
        );
        if (removed.length != action.expectedCount) {
          if (removed.isNotEmpty) {
            await ledger.restoreTransactions(removed);
          }
          _pending = null;
          return const AssistantReply(
            text: 'The ledger did not match the preview exactly, so the '
                'deletion was rolled back. Nothing was changed.',
            isError: true,
          );
        }
      }

      final entry = AssistantAuditEntry(
        id: action.id,
        type: action.type,
        createdAt: clock(),
        affectedCount: action.expectedCount,
        totalMinor: action.expectedTotalMinor,
        transactionIds: action.transactionIds,
        previousExcluded: previousExcluded,
        deletedSnapshots: [
          for (final tx in removed) auditSnapshot(tx),
        ],
      );
      try {
        await audit.append(entry);
      } catch (_) {
        // The audit trail is part of the operation's contract. If it cannot be
        // recorded, reverse the financial change instead of leaving an
        // unauditable mutation.
        var rolledBack = false;
        try {
          if (action.type == AssistantChangeType.exclusion) {
            await ledger.restoreExclusionStates(previousExcluded);
          } else {
            await ledger.restoreTransactions(removed);
          }
          rolledBack = true;
        } catch (_) {
          rolledBack = false;
        }
        _pending = null;
        return AssistantReply(
          text: rolledBack
              ? 'The change was not applied because its audit record could not '
                  'be saved. Nothing was changed.'
              : 'The change could not be audited and the automatic rollback '
                  'also failed. Review your transactions before trying again.',
          isError: true,
        );
      }

      _pending = null;
      return _appliedReply(action);
    } catch (_) {
      return const AssistantReply(
        text: 'The change could not be completed. Your existing transactions '
            'were left in place. Nothing was changed.',
        isError: true,
      );
    } finally {
      _applying = false;
    }
  }

  Future<AssistantReply> cancelPending(String actionId) async {
    final action = pending;
    if (action == null || action.id != actionId) {
      return const AssistantReply(
        text: 'That preview is no longer active. Nothing was changed.',
        isError: true,
      );
    }
    _pending = null;
    return const AssistantReply(
      text: 'Preview cancelled. Nothing was changed.',
    );
  }

  Future<AssistantReply> undoLast() async {
    try {
      final entries = await audit.load();
      final last = entries.reversed.where((e) => !e.undone).firstOrNull;
      if (last == null) {
        return const AssistantReply(
          text: 'There is no assistant change available to undo.',
        );
      }
      if (last.type == AssistantChangeType.exclusion) {
        final restored = await ledger.restoreExclusionStates(
          last.previousExcluded,
        );
        await audit.markUndone(last.id);
        _pending = null;
        return AssistantReply(
          text:
              'Undone. ${restored == 0 ? 'No flags needed changing' : '$restored transaction${restored == 1 ? '' : 's'} restored to their previous exclusion state'}. '
              'Home, Insights, budgets and instrument totals now use the '
              'restored values.',
        );
      }
      final snapshots = <TransactionModel>[];
      try {
        for (final raw in last.deletedSnapshots) {
          snapshots.add(transactionFromAuditSnapshot(raw));
        }
      } catch (_) {
        return const AssistantReply(
          text: 'The audit copy of that deletion is unreadable, so it was not '
              'restored. Nothing was changed.',
          isError: true,
        );
      }
      if (snapshots.isEmpty) {
        return const AssistantReply(
          text: 'The audit copy of that deletion is empty, so it was not '
              'restored. Nothing was changed.',
          isError: true,
        );
      }
      final restored = await ledger.restoreTransactions(snapshots);
      await audit.markUndone(last.id);
      _pending = null;
      return AssistantReply(
        text: 'Undone. Restored $restored deleted transaction'
            '${restored == 1 ? '' : 's'}. Search, Home, Insights, budgets and '
            'instrument totals are recalculated from the restored ledger.',
      );
    } catch (_) {
      return const AssistantReply(
        text: 'Undo could not be completed. No records were changed by the '
            'undo attempt.',
        isError: true,
      );
    }
  }

  Future<AssistantReply> handle(
    String message, {
    List<AssistantChatMessage> history = const [],
  }) async {
    final text = message.trim();
    if (text.isEmpty) {
      return const AssistantReply(
          text: 'Ask a question about your transactions.');
    }
    // A vague acknowledgement must never apply a pending change.
    if (pending != null && _isVagueConfirmation(text)) {
      return const AssistantReply(
        text: 'There is a pending preview, but it is not applied from a chat '
            'message. Open the preview card and tap Review & confirm, or tap '
            'Cancel. Nothing has changed.',
      );
    }

    final intent = LocalIntentParser.parse(text, now: clock());
    if (intent != null) {
      if (intent is UndoIntent) return undoLast();
      try {
        final reply = _composer().compose(intent);
        if (reply.pendingAction != null) {
          _pending = reply.pendingAction;
        }
        return reply;
      } on FinanceToolException catch (e) {
        return AssistantReply(text: e.message, isError: true);
      } catch (_) {
        return const AssistantReply(
          text: 'I could not complete that local request. Nothing was changed.',
          isError: true,
        );
      }
    }

    if (remoteClient == null) {
      return const AssistantReply(
        text: 'I can run core requests fully on this device — for example: '
            'list Groww and Zerodha transactions, spending by category, '
            'biggest expenses, unpaid bills, month comparisons, exclusions, '
            'deletions and undo.\n\n'
            'Gemini cloud assistance is not configured in this build, so your '
            'financial data stays local. Try one of the suggested commands.',
        suggestions: _suggestions,
      );
    }

    if (!await consent.hasCloudConsent()) {
      return const AssistantReply(
        text: 'That question needs Gemini. Cloud assistance is currently off, '
            'so nothing was sent. You can review exactly what would be shared '
            'and enable it in Assistant privacy. Core commands keep working '
            'offline.',
        needsCloudConsent: true,
        suggestions: _suggestions,
      );
    }

    return _remote(text, history);
  }

  Future<AssistantReply> _remote(
    String message,
    List<AssistantChatMessage> history,
  ) async {
    final engine = _engine();
    final composer = AssistantComposer(engine);
    final remote = remoteClient!;
    final remoteHistory = [
      for (final turn in history
          .where((m) => !m.isLoading && !m.isError && m.text.trim().isNotEmpty)
          .toList()
          .reversed
          .take(GeminiProxyClient.maxHistoryTurns)
          .toList()
          .reversed)
        RemoteHistoryTurn(
          role: turn.isUser ? 'user' : 'model',
          text: turn.text,
        ),
    ];

    final exchanges = <RemoteToolExchange>[];
    final displayedResults = <FinanceToolResult>[];
    final seenCalls = <String, Map<String, dynamic>>{};
    AssistantPendingAction? prepared;
    String? finalText;

    try {
      for (var round = 0; round <= GeminiProxyClient.maxToolRounds; round++) {
        final turn = await remote.send(
          message: message,
          history: remoteHistory,
          toolExchanges: exchanges,
        );
        if (turn.functionCalls.isEmpty) {
          finalText = turn.text;
          break;
        }
        if (round == GeminiProxyClient.maxToolRounds) {
          return const AssistantReply(
            text: 'The assistant needed too many steps. Try a narrower '
                'question. Nothing was changed.',
            isError: true,
          );
        }

        final calls = <RemoteToolCall>[];
        final responses = <Map<String, dynamic>>[];
        for (final call in turn.functionCalls) {
          final signature = '${call.name}:${jsonEncode(call.arguments)}';
          final cached = seenCalls[signature];
          if (cached != null) {
            calls.add(call);
            responses.add({'name': call.name, 'response': cached});
            continue;
          }
          try {
            final result = engine.execute(call.name, call.arguments);
            if (result.pending != null) {
              if (prepared != null &&
                  prepared.transactionIds.join(',') !=
                      result.pending!.transactionIds.join(',')) {
                const error = {
                  'error': 'conflicting_preview',
                  'message':
                      'Only one pending preview is allowed. Ask the user to confirm or cancel the existing preview first.',
                };
                seenCalls[signature] = error;
                calls.add(call);
                responses.add({'name': call.name, 'response': error});
                continue;
              }
              prepared = result.pending;
            }
            final forModel = _sanitiseForModel(result);
            seenCalls[signature] = forModel;
            displayedResults.add(result);
            calls.add(call);
            responses.add({'name': call.name, 'response': forModel});
          } on FinanceToolException catch (e) {
            final error = e.toJson();
            seenCalls[signature] = error;
            calls.add(call);
            responses.add({'name': call.name, 'response': error});
          }
        }
        exchanges.add(RemoteToolExchange(calls: calls, responses: responses));
      }

      if (finalText == null) {
        return const AssistantReply(
          text: 'The assistant stopped before producing an answer. Nothing was '
              'changed.',
          isError: true,
        );
      }
      if (prepared != null) {
        _pending = prepared;
        finalText = finalText.trim().isEmpty
            ? 'I prepared a preview. No change has been applied.'
            : 'Preview only — no change has been applied.\n\n$finalText';
      }
      return composer.composeRemote(
        text: finalText,
        toolResults: displayedResults,
        pending: prepared,
      );
    } on AssistantRemoteException catch (e) {
      return AssistantReply(
        text: '${e.message} Nothing was changed.',
        isError: true,
        suggestions: _suggestions,
      );
    } catch (_) {
      return const AssistantReply(
        text: 'Gemini is unavailable right now. Local commands still work. '
            'Nothing was changed.',
        isError: true,
        suggestions: _suggestions,
      );
    }
  }

  /// Remove full record lists from preview results sent to Gemini: it only
  /// needs the counts and totals to ask for confirmation.
  Map<String, dynamic> _sanitiseForModel(FinanceToolResult result) {
    final data = Map<String, dynamic>.from(result.data);
    if (result.pending != null) {
      data.remove('records');
    }
    return data;
  }

  AssistantReply _appliedReply(AssistantPendingAction action) {
    final engine = _engine();
    final window = action.spendingScopeStart == null
        ? const AssistantDateWindow.allTime()
        : AssistantDateWindow.range(
            start: action.spendingScopeStart!,
            end: action.spendingScopeEnd!,
            label: action.spendingScopeLabel,
          );
    final summary = _summaryAfter(engine, window);
    final verb = action.isDeletion ? 'Deleted' : 'Excluded';
    final kept = action.isDeletion
        ? 'The records were removed from your encrypted ledger.'
        : 'The records are still in your ledger, marked excluded from spending.';
    final change = action.spendingBeforeMinor == summary.spendingMinor
        ? 'Spending in ${window.preciseLabel} is unchanged.'
        : 'Spending in ${window.preciseLabel} changed from '
            '${Formatters.currency.format(action.spendingBeforeMinor)} to '
            '${Formatters.currency.format(summary.spendingMinor)}.';
    return AssistantReply(
      text: '$verb ${action.expectedCount} transaction'
          '${action.expectedCount == 1 ? '' : 's'} totaling '
          '${Formatters.currency.format(action.expectedTotalMinor)}. $kept '
          '$change Home, Insights, budgets and payment-instrument totals now '
          'use the updated ledger.\n\n'
          'You can undo this from the assistant.',
      summary: summary,
    );
  }

  AssistantSummary _summaryAfter(
    FinanceToolEngine engine,
    AssistantDateWindow window,
  ) {
    final result = engine.execute('get_spending_summary', {
      if (!window.isAllTime) ...{
        'startDate': window.startIso,
        'endDate': window.endIso,
      },
    });
    final data = result.data;
    final range = data['range'] as Map<String, dynamic>;
    return AssistantSummary(
      label: window.preciseLabel,
      start: (range['startDate'] as String).isEmpty
          ? null
          : DateTime.tryParse(range['startDate'] as String),
      end: (range['endDate'] as String).isEmpty
          ? null
          : DateTime.tryParse(range['endDate'] as String),
      spendingMinor: data['spendingMinor'] as int,
      incomeMinor: data['incomeMinor'] as int,
      excludedMinor: data['excludedMinor'] as int,
      investmentMinor: data['investmentMinor'] as int,
      transferMinor: data['transferMinor'] as int,
      expenseCount: data['expenseCount'] as int,
      incomeCount: data['incomeCount'] as int,
      excludedCount: data['excludedCount'] as int,
      totalCount: data['transactionCount'] as int,
    );
  }

  bool _isVagueConfirmation(String message) {
    final normalized =
        message.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').trim();
    final compact = normalized.replaceAll(RegExp(r'\s+'), ' ');
    return const {
      'ok',
      'okay',
      'yes',
      'yep',
      'yeah',
      'sure',
      'do it',
      'go ahead',
      'confirm',
      'confirmed',
      'proceed',
      'apply',
      'apply it',
      'delete',
      'exclude',
    }.contains(compact);
  }

  static const List<String> _suggestions = [
    'List my Groww and Zerodha transactions',
    'How much did I spend on food last month?',
    'Show my biggest expenses this year',
    'Show my unpaid bills',
    'Why is my spending higher this month?',
  ];
}
