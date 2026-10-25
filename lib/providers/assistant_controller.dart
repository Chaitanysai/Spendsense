import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/assistant_models.dart';
import '../providers/planner_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/assistant/assistant_audit.dart';
import '../services/assistant/assistant_auth.dart';
import '../services/assistant/assistant_ledger.dart';
import '../services/assistant/assistant_orchestrator.dart';
import '../services/assistant/assistant_settings.dart';
import '../services/assistant/gemini_proxy_client.dart';

/// UI-facing state for one assistant session.
///
/// Conversation text and pending actions live only in memory. Changes and their
/// audit/undo data are persisted through [AssistantOrchestrator].
class AssistantController extends ChangeNotifier {
  final AssistantOrchestrator _orchestrator;
  final AssistantConsentStore _consentStore;
  final AssistantAuditRepository _audit;
  final DateTime Function() _clock;

  final List<AssistantChatMessage> _messages = [];
  bool _busy = false;
  String _status = '';
  bool _disposed = false;
  bool _consentLoaded = false;
  bool _cloudConsent = false;
  String? _lastAttempt;
  List<AssistantChatMessage> _lastHistory = const [];
  Timer? _expiryTimer;

  AssistantController({
    required AssistantLedger ledger,
    required AssistantAuditRepository audit,
    required AssistantConsentStore consentStore,
    AssistantRemoteClient? remoteClient,
    DateTime Function()? clock,
  })  : _audit = audit,
        _consentStore = consentStore,
        _clock = clock ?? DateTime.now,
        _orchestrator = AssistantOrchestrator(
          ledger: ledger,
          audit: audit,
          consent: consentStore,
          remoteClient: remoteClient,
          clock: clock,
        ) {
    _messages.add(AssistantChatMessage(
      id: 'welcome',
      isUser: false,
      text: 'Ask me about your transactions. I use deterministic local '
          'calculations for totals, and I will show a preview before any '
          'bulk change. Nothing is deleted or excluded without your explicit '
          'confirmation.',
      createdAt: _clock(),
      reply: const AssistantReply(
        text: '',
        suggestions: [
          'List my Groww and Zerodha transactions',
          'How much did I spend on food last month?',
          'Show my biggest expenses this year',
          'Show my unpaid bills',
          'Why is my spending higher this month?',
        ],
      ),
    ));
    _loadConsent();
  }

  factory AssistantController.forApp(
    TransactionProvider transactions, [
    PlannerProvider? planner,
  ]) {
    const appCheck = FirebaseAppCheckTokenProvider();
    const identity = FirebaseAssistantIdentityTokenProvider();
    final remote = AssistantConfig.isCloudConfigured &&
            appCheck.isConfigured &&
            identity.isConfigured
        ? GeminiProxyClient.fromBaseUrl(
            AssistantConfig.proxyUrl,
            authTokenProvider: appCheck,
            identityTokenProvider: identity,
          )
        : null;
    return AssistantController(
      ledger: ProviderAssistantLedger(transactions, planner),
      audit: EncryptedAssistantAuditRepository(),
      consentStore: PreferencesAssistantConsentStore(),
      remoteClient: remote,
    );
  }

  List<AssistantChatMessage> get messages => List.unmodifiable(_messages);
  bool get isBusy => _busy;
  String get status => _status;
  bool get cloudConfigured => _orchestrator.isCloudConfigured;
  bool get cloudConsent => _cloudConsent;
  bool get consentLoaded => _consentLoaded;
  AssistantPendingAction? get pendingAction => _orchestrator.pending;
  bool get hasPending => pendingAction != null;

  Future<void> _loadConsent() async {
    try {
      _cloudConsent = await _consentStore.hasCloudConsent();
    } catch (_) {
      _cloudConsent = false;
    }
    _consentLoaded = true;
    _notify();
  }

  /// Re-reads consent after returning from the privacy screen.
  Future<void> reloadConsent() => _loadConsent();

  Future<void> setCloudConsent(bool allowed) async {
    // Consent only matters when the build has a secure proxy configured.
    if (allowed && !cloudConfigured) return;
    await _consentStore.setCloudConsent(allowed);
    _cloudConsent = allowed;
    _notify();
  }

  Future<void> send(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty || _busy) return;
    final history = List<AssistantChatMessage>.of(_messages);
    _lastAttempt = cleaned;
    _lastHistory = history;
    _messages.add(AssistantChatMessage(
      id: _newId(),
      isUser: true,
      text: cleaned,
      createdAt: _clock(),
    ));
    await _run(cleaned, history);
  }

  Future<void> retryLast() async {
    final message = _lastAttempt;
    if (message == null || _busy) return;
    // Remove the trailing assistant failure/consent prompt so retry replaces it.
    while (_messages.isNotEmpty &&
        !_messages.last.isUser &&
        (_messages.last.isError ||
            _messages.last.reply?.needsCloudConsent == true)) {
      _messages.removeLast();
    }
    await _run(message, _lastHistory);
  }

  Future<void> enableCloudAndRetry() async {
    await setCloudConsent(true);
    await retryLast();
  }

  Future<void> _run(
    String text,
    List<AssistantChatMessage> history,
  ) async {
    _setBusy(
        true,
        cloudConfigured
            ? 'Checking your ledger and preparing a reply…'
            : 'Searching your encrypted ledger…');
    try {
      final reply = await _orchestrator.handle(text, history: history);
      _messages.add(AssistantChatMessage(
        id: _newId(),
        isUser: false,
        text: reply.text,
        createdAt: _clock(),
        reply: reply,
        isError: reply.isError,
      ));
      _armExpiry();
    } catch (_) {
      _messages.add(AssistantChatMessage(
        id: _newId(),
        isUser: false,
        text: 'Something went wrong. Nothing was changed. You can retry.',
        createdAt: _clock(),
        isError: true,
      ));
    } finally {
      _setBusy(false, '');
    }
  }

  Future<void> confirmPending(String actionId) async {
    if (_busy) return;
    _setBusy(true, 'Applying the confirmed change…');
    try {
      final reply = await _orchestrator.confirmPending(actionId);
      _messages.add(AssistantChatMessage(
        id: _newId(),
        isUser: false,
        text: reply.text,
        createdAt: _clock(),
        reply: reply,
        isError: reply.isError,
      ));
      _armExpiry();
    } catch (_) {
      _messages.add(AssistantChatMessage(
        id: _newId(),
        isUser: false,
        text: 'The change could not be completed. Nothing is assumed to have '
            'changed.',
        createdAt: _clock(),
        isError: true,
      ));
    } finally {
      _setBusy(false, '');
    }
  }

  Future<void> cancelPending(String actionId) async {
    final reply = await _orchestrator.cancelPending(actionId);
    _messages.add(AssistantChatMessage(
      id: _newId(),
      isUser: false,
      text: reply.text,
      createdAt: _clock(),
      reply: reply,
      isError: reply.isError,
    ));
    _armExpiry();
    _notify();
  }

  Future<void> undoLast() async {
    if (_busy) return;
    _messages.add(AssistantChatMessage(
      id: _newId(),
      isUser: true,
      text: 'Undo the last change',
      createdAt: _clock(),
    ));
    _setBusy(true, 'Restoring the previous ledger state…');
    try {
      final reply = await _orchestrator.undoLast();
      _messages.add(AssistantChatMessage(
        id: _newId(),
        isUser: false,
        text: reply.text,
        createdAt: _clock(),
        reply: reply,
        isError: reply.isError,
      ));
      _armExpiry();
    } finally {
      _setBusy(false, '');
    }
  }

  Future<void> clearAuditTrail() => _audit.clear();

  void clearConversation() {
    _orchestrator.discardPending();
    _expiryTimer?.cancel();
    _messages.removeWhere((m) => m.id != 'welcome');
    _notify();
  }

  void _armExpiry() {
    _expiryTimer?.cancel();
    if (_orchestrator.pending == null) return;
    _expiryTimer = Timer(const Duration(seconds: 20), () {
      if (_disposed) return;
      if (_orchestrator.pending == null) {
        _notify();
        return;
      }
      _armExpiry();
    });
  }

  void _setBusy(bool value, String status) {
    _busy = value;
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _newId() => '${_clock().microsecondsSinceEpoch}_${_messages.length}';

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    super.dispose();
  }
}
