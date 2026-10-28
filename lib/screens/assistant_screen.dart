import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/assistant_models.dart';
import '../providers/assistant_controller.dart';
import '../providers/planner_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';
import '../widgets/app_page_route.dart';
import '../widgets/assistant_cards.dart';
import '../widgets/glass_card.dart';
import '../widgets/sound_scope.dart';
import 'assistant_privacy_screen.dart';

class AssistantScreen extends StatefulWidget {
  static const String routeName = 'spendsense-assistant';

  /// Test seam: inject a controller with in-memory dependencies. Production
  /// builds create one from the real transaction and planner providers.
  final AssistantController? controller;

  const AssistantScreen({super.key, this.controller});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  AssistantController? _controller;
  bool _ownsController = false;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final injected = widget.controller;
    if (injected != null) {
      _controller = injected;
    } else {
      _ownsController = true;
      PlannerProvider? planner;
      try {
        planner = context.read<PlannerProvider>();
      } on ProviderNotFoundException {
        // Embedded previews and focused widget tests may omit the planner;
        // bill tools then see no user plans rather than failing to open.
        planner = null;
      }
      _controller = AssistantController.forApp(
        context.read<TransactionProvider>(),
        planner,
      );
    }
    _controller!.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _scheduleScroll();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    if (_ownsController) _controller?.dispose();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final reduced = MediaQuery.maybeDisableAnimationsOf(context) == true;
      final target = _scroll.position.maxScrollExtent;
      if (reduced) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: AppMotion.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final controller = _controller!;
    if (text.trim().isEmpty || controller.isBusy) return;
    _input.clear();
    SoundScope.play(context, SoundEventType.buttonTap);
    await controller.send(text);
    _focus.requestFocus();
  }

  Future<void> _openPrivacy() async {
    final controller = _controller!;
    await Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => AssistantPrivacyScreen(controller: controller),
      ),
    );
    await controller.reloadConsent();
  }

  Future<void> _undo() async {
    await _controller!.undoLast();
    if (!mounted) return;
    SoundScope.play(context, SoundEventType.actionSucceeded);
  }

  Future<void> _clearConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'This only clears the chat shown here. Transactions, exclusions and '
          'the encrypted audit trail are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (confirmed == true) _controller!.clearConversation();
  }

  Future<void> _reviewPending(AssistantPendingAction action) async {
    final controller = _controller!;
    final confirmed = await showAssistantConfirmationSheet(
      context,
      action: action,
    );
    if (!confirmed || !mounted) return;
    SoundScope.play(context, SoundEventType.buttonTap);
    await controller.confirmPending(action.id);
    if (!mounted) return;
    _scheduleScroll();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SpendSense Assistant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title(context)),
                    AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => Text(
                        controller.cloudConfigured && controller.cloudConsent
                            ? 'Local calculations · Gemini with consent'
                            : 'Local-first finance assistant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Undo last assistant change',
              onPressed: controller.isBusy ? null : _undo,
              icon: const Icon(Icons.undo_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: 'Assistant options',
              onSelected: (value) {
                if (value == 'privacy') _openPrivacy();
                if (value == 'clear') _clearConversation();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'privacy',
                  child: Text('Privacy & consent'),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear conversation'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return Column(
                children: [
                  _PrivacyStrip(controller: controller, onTap: _openPrivacy),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: ListView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.page,
                            AppSpacing.md,
                            AppSpacing.page,
                            AppSpacing.lg,
                          ),
                          children: [
                            _PromptRail(
                              suggestions: const [
                                'List my Groww and Zerodha transactions',
                                'How much did I spend on food last month?',
                                'Show my biggest expenses this year',
                                'Show my unpaid bills',
                              ],
                              onTap: controller.isBusy ? null : _send,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            for (final message in controller.messages)
                              _MessageBlock(
                                message: message,
                                onSuggestion: controller.isBusy ? null : _send,
                                onReview: _reviewPending,
                                onRetry: controller.isBusy
                                    ? null
                                    : controller.retryLast,
                                onEnableCloud: controller.isBusy ||
                                        !controller.cloudConfigured
                                    ? null
                                    : controller.enableCloudAndRetry,
                                onPrivacy: _openPrivacy,
                                onCancelPending: controller.isBusy
                                    ? null
                                    : (id) => controller.cancelPending(id),
                              ),
                            if (controller.isBusy)
                              _ThinkingBubble(status: controller.status),
                            if (controller.messages.length == 1 &&
                                _input.text.trim().isEmpty)
                              const _LocalCapabilityNote(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _Composer(
                    controller: _input,
                    focusNode: _focus,
                    enabled: !controller.isBusy,
                    onSend: _send,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  final AssistantController controller;
  final VoidCallback onTap;

  const _PrivacyStrip({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cloudOn = controller.cloudConfigured && controller.cloudConsent;
    final color = cloudOn ? AppColors.amber : AppColors.incomeGreen;
    final text = !controller.cloudConfigured
        ? 'On-device only. Gemini is not configured in this build.'
        : cloudOn
            ? 'Gemini may receive only the minimum context you ask for.'
            : 'Local only. Cloud assistance is off — data is not sent.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(context),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(text,
                      style: AppText.body(context).copyWith(fontSize: 10.5)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptRail extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String>? onTap;

  const _PromptRail({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final text = suggestions[index];
          return ActionChip(
            onPressed: onTap == null ? null : () => onTap!(text),
            backgroundColor: AppColors.surfaceAlt(context),
            side: BorderSide(color: AppColors.border(context)),
            label: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(context),
            ),
          );
        },
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  final AssistantChatMessage message;
  final ValueChanged<String>? onSuggestion;
  final Future<void> Function(AssistantPendingAction) onReview;
  final VoidCallback? onRetry;
  final VoidCallback? onEnableCloud;
  final VoidCallback onPrivacy;
  final Future<void> Function(String)? onCancelPending;

  const _MessageBlock({
    required this.message,
    required this.onSuggestion,
    required this.onReview,
    required this.onRetry,
    required this.onEnableCloud,
    required this.onPrivacy,
    required this.onCancelPending,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md, left: 40),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.deepFill(context),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppRadius.md),
              topRight: Radius.circular(AppRadius.md),
              bottomLeft: Radius.circular(AppRadius.md),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            message.text,
            style: AppText.body(context).copyWith(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    final reply = message.reply;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.text.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: message.isError
                          ? AppColors.danger.withValues(alpha: 0.08)
                          : AppColors.surfaceColor(context),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(AppRadius.md),
                        bottomLeft: Radius.circular(AppRadius.md),
                        bottomRight: Radius.circular(AppRadius.md),
                        topLeft: Radius.circular(4),
                      ),
                      border: Border.all(
                        color: message.isError
                            ? AppColors.danger.withValues(alpha: 0.35)
                            : AppColors.border(context),
                      ),
                    ),
                    child: SelectableText(
                      message.text,
                      style: AppText.body(context).copyWith(
                        fontSize: 13.5,
                        height: 1.45,
                        color: message.isError
                            ? AppColors.danger
                            : AppColors.textPrimary(context),
                      ),
                    ),
                  ),
                if (reply != null) ...[
                  if (reply.summary != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AssistantSummaryCard(summary: reply.summary!),
                  ],
                  if (reply.comparison != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AssistantComparisonCard(comparison: reply.comparison!),
                  ],
                  if (reply.bills.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AssistantBillsCard(bills: reply.bills),
                  ],
                  for (final section in reply.sections) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AssistantSectionCard(section: section),
                  ],
                  if (reply.pendingAction != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AssistantPendingActionCard(
                      action: reply.pendingAction!,
                      onReview: () => onReview(reply.pendingAction!),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: onCancelPending == null
                          ? null
                          : () => onCancelPending!(reply.pendingAction!.id),
                      child: const Text('Cancel preview'),
                    ),
                  ],
                  if (reply.needsCloudConsent) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onEnableCloud,
                            icon: const Icon(Icons.lock_open_rounded, size: 18),
                            label: const Text('Review & enable Gemini'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton(
                          tooltip: 'Privacy details',
                          onPressed: onPrivacy,
                          icon: const Icon(Icons.info_outline_rounded),
                        ),
                      ],
                    ),
                  ],
                  if (message.isError && onRetry != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                  if (reply.suggestions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final suggestion in reply.suggestions)
                          ActionChip(
                            onPressed: onSuggestion == null
                                ? null
                                : () => onSuggestion!(suggestion),
                            backgroundColor: AppColors.surfaceAlt(context),
                            side: BorderSide(color: AppColors.border(context)),
                            label: Text(
                              suggestion,
                              style: AppText.label(context)
                                  .copyWith(fontSize: 10.5),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  final String status;

  const _ThinkingBubble({required this.status});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    status.isEmpty ? 'Working…' : status,
                    style: AppText.caption(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalCapabilityNote extends StatelessWidget {
  const _LocalCapabilityNote();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.offline_bolt_rounded,
                  size: 18, color: AppColors.brandInk(context)),
              const SizedBox(width: AppSpacing.sm),
              Text('Works without Gemini',
                  style: AppText.title(context).copyWith(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Totals, searches, bills and previews run deterministically on your '
            'device. Cloud AI is optional and never sees your full ledger. '
            'Bulk changes always require an explicit preview and confirmation.',
            style: AppText.body(context).copyWith(fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onSend;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.scaffold(context).withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: AppColors.border(context))),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final canSend = enabled && value.text.trim().isNotEmpty;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 1000,
                      buildCounter: (context,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: canSend ? onSend : null,
                      decoration: const InputDecoration(
                        hintText: 'Ask about your transactions…',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Semantics(
                    button: true,
                    label: 'Send message',
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: canSend ? AppColors.actionGradient : null,
                          color: canSend ? null : AppColors.surfaceAlt(context),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: IconButton(
                          onPressed: canSend ? () => onSend(value.text) : null,
                          tooltip: 'Send',
                          icon: Icon(
                            Icons.arrow_upward_rounded,
                            color: canSend
                                ? Colors.white
                                : AppColors.textTertiary(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
