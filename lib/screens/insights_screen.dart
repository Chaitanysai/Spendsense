import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/ai_chat_message.dart';
import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../services/ai_query_service.dart';
import '../services/ai_service.dart';
import '../utils/app_colors.dart';
import '../widgets/app_logo.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AIQueryService _localAI = AIQueryService();
  final AIService _cloudAI = AIService();
  late final bool _cloudAvailable = AppConfig.hasAnyAiProviderConfigured;

  late final List<_ChatEntry> _messages = [
    _ChatEntry(
      message: AIChatMessage(
        role: 'assistant',
        content: _cloudAvailable
            ? 'I can answer follow-up questions about your spending and keep the context of this conversation.'
            : 'I can answer quick questions from your local transaction data. Cloud AI is not configured on this build yet.',
      ),
    ),
  ];

  bool _isLoading = false;
  bool _isAssistantExpanded = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final metrics = _buildMetrics(provider);

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(size: 28),
            const SizedBox(width: 12),
            Text(
              'Insights & AI',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    height: 166,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _statCard(
                          context,
                          title: 'This Month',
                          value: '₹${metrics.currentTotal.toStringAsFixed(0)}',
                          subtitle:
                              DateFormat('MMMM yyyy').format(DateTime.now()),
                          gradient: AppColors.brandGradient,
                          icon: Icons.calendar_month_rounded,
                        ),
                        _statCard(
                          context,
                          title: 'Change',
                          value: '${metrics.percentChange.toStringAsFixed(1)}%',
                          subtitle: metrics.percentChange >= 0
                              ? 'Spending is up vs last month'
                              : 'Spending is down vs last month',
                          gradient: LinearGradient(
                            colors: metrics.percentChange >= 0
                                ? const [Color(0xFFEF4444), Color(0xFFF97316)]
                                : const [Color(0xFF059669), Color(0xFF11B5A4)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          icon: metrics.percentChange >= 0
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                        ),
                        _statCard(
                          context,
                          title: 'Top Category',
                          value: metrics.topCategory,
                          subtitle: 'Highest-spend category this month',
                          gradient: AppColors.altGradient,
                          icon: Icons.auto_awesome_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSmartTip(context, metrics),
                  const SizedBox(height: 16),
                  _buildAssistantLauncherCard(context),
                ],
              ),
            ),
            _buildAssistantOverlay(context, provider),
          ],
        ),
      ),
    );
  }

  _InsightMetrics _buildMetrics(TransactionProvider provider) {
    final now = DateTime.now();

    final currentMonthTx = provider.transactions.where((t) {
      return t.date.month == now.month &&
          t.date.year == now.year &&
          !t.isExcluded &&
          t.type == TransactionType.expense;
    }).toList();

    final lastMonth = DateTime(now.year, now.month - 1);
    final lastMonthTx = provider.transactions.where((t) {
      return t.date.month == lastMonth.month &&
          t.date.year == lastMonth.year &&
          !t.isExcluded &&
          t.type == TransactionType.expense;
    }).toList();

    final currentTotal =
        currentMonthTx.fold<double>(0, (sum, t) => sum + t.amount);
    final lastTotal = lastMonthTx.fold<double>(0, (sum, t) => sum + t.amount);

    double percentChange = 0;
    if (lastTotal > 0) {
      percentChange = ((currentTotal - lastTotal) / lastTotal) * 100;
    }

    final categoryMap = <String, double>{};
    for (final t in currentMonthTx) {
      categoryMap[t.category] = (categoryMap[t.category] ?? 0) + t.amount;
    }

    final topCategory = categoryMap.isEmpty
        ? 'No data'
        : categoryMap.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    return _InsightMetrics(
      currentTotal: currentTotal,
      percentChange: percentChange,
      topCategory: topCategory,
    );
  }

  Widget _statCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required Gradient gradient,
    required IconData icon,
  }) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, color: Colors.white70),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantLauncherCard(BuildContext context) {
    return GestureDetector(
      onTap: _openAssistant,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow(context),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Tap to open',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Chat with AI Bot',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _messages.last.message.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantOverlay(
    BuildContext context,
    TransactionProvider provider,
  ) {
    return IgnorePointer(
      ignoring: !_isAssistantExpanded,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: _isAssistantExpanded ? 1 : 0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _closeAssistant,
          child: Container(
            color: Colors.black.withValues(alpha: 0.28),
            padding: const EdgeInsets.all(12),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  scale: _isAssistantExpanded ? 1 : 0.92,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.8,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceColor(context),
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 24,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: _buildAssistantPanel(context, provider),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmartTip(BuildContext context, _InsightMetrics metrics) {
    String tip = 'Spending is steady. Ask the bot what drove the month.';

    if (metrics.currentTotal > 10000) {
      tip =
          'High spending detected. Ask the bot for top merchants and trim ideas.';
    } else if (metrics.percentChange > 20) {
      tip =
          'This month jumped sharply. A follow-up question about categories will help.';
    } else if (metrics.percentChange < -10) {
      tip = 'You are spending less than last month. Ask what improved most.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panel(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.altGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.lightbulb_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Tip',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tip,
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantPanel(
    BuildContext context,
    TransactionProvider provider,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.smart_toy_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SpendSense Bot',
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Understands follow-up messages in this chat',
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _closeAssistant,
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _cloudAvailable
                          ? const Color(0xFFDCFCE7)
                          : AppColors.surfaceAlt(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _cloudAvailable ? 'AI ONLINE' : 'LOCAL ONLY',
                      style: TextStyle(
                        color: _cloudAvailable
                            ? const Color(0xFF166534)
                            : AppColors.textSecondary(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _promptChip(
                      context,
                      label: 'Top category?',
                      onTap: () => _submitQuery(
                          provider, 'What is my top category this month?'),
                    ),
                    _promptChip(
                      context,
                      label: 'Highest spend?',
                      onTap: () => _submitQuery(
                          provider, 'What is my highest transaction?'),
                    ),
                    _promptChip(
                      context,
                      label: 'Fuel spend',
                      onTap: () => _submitQuery(
                          provider, 'How much did I spend on fuel?'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final entry = _messages[index];
              return _messageBubble(context, entry);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) =>
                      _submitQuery(provider, _controller.text.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Ask a follow-up about your spending...',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _isLoading
                    ? null
                    : () => _submitQuery(provider, _controller.text.trim()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(54, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _promptChip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        backgroundColor: AppColors.surfaceAlt(context),
        side: BorderSide(color: AppColors.border(context)),
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }

  Widget _messageBubble(BuildContext context, _ChatEntry entry) {
    final isUser = entry.message.role == 'user';
    final bubbleColor =
        isUser ? AppColors.primaryPurple : AppColors.surfaceAlt(context);
    final textColor = isUser ? Colors.white : AppColors.textPrimary(context);
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    entry.message.content,
                    style: TextStyle(
                      color: textColor,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!isUser && entry.usedCloud)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 4),
              child: Text(
                'via cloud AI',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _submitQuery(
    TransactionProvider provider,
    String query,
  ) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty || _isLoading) return;

    _controller.clear();

    setState(() {
      _messages.add(
        _ChatEntry(
          message: AIChatMessage(role: 'user', content: cleaned),
        ),
      );
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      if (_cloudAvailable) {
        final history = _messages
            .map((entry) => entry.message)
            .skip(_messages.length > 12 ? _messages.length - 12 : 0)
            .toList();
        final cloudResponse =
            await _cloudAI.askAI(history, provider.transactions);

        if (cloudResponse != null) {
          setState(() {
            _messages.add(
              _ChatEntry(
                message: AIChatMessage(
                  role: 'assistant',
                  content: cloudResponse,
                ),
                usedCloud: true,
              ),
            );
          });
          return;
        }
      }

      final localResponse = _localAI.tryAnswer(cleaned, provider.transactions);

      if (localResponse != null) {
        setState(() {
          _messages.add(
            _ChatEntry(
              message: AIChatMessage(
                role: 'assistant',
                content: localResponse,
              ),
            ),
          );
        });
      } else {
        setState(() {
          _messages.add(
            const _ChatEntry(
              message: AIChatMessage(
                role: 'assistant',
                content:
                    "I couldn't answer that from the current data. Try syncing more transactions or asking in a more specific way.",
              ),
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _openAssistant() {
    setState(() => _isAssistantExpanded = true);
  }

  void _closeAssistant() {
    if (!_isAssistantExpanded) return;
    setState(() => _isAssistantExpanded = false);
  }
}

class _InsightMetrics {
  final double currentTotal;
  final double percentChange;
  final String topCategory;

  const _InsightMetrics({
    required this.currentTotal,
    required this.percentChange,
    required this.topCategory,
  });
}

class _ChatEntry {
  final AIChatMessage message;
  final bool usedCloud;

  const _ChatEntry({
    required this.message,
    this.usedCloud = false,
  });
}
