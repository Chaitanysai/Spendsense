import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ai_chat_message.dart';
import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../services/ai_query_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_background.dart';
import '../widgets/app_page_route.dart';
import '../widgets/category_bubble.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/glass_card.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final metrics = _buildMetrics(provider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.navClearance,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const [AppLogo(size: 34, showWordmark: true)]),
              const SizedBox(height: AppSpacing.xl),
              Text('Insights', style: AppText.h1(context)),
              const SizedBox(height: 4),
              Text('Understand your spending at a glance',
                  style: AppText.body(context)),
              const SizedBox(height: AppSpacing.xl),

              // ── Stat cards ────────────────────────────────────────────
              SizedBox(
                height: 168,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  children: [
                    FadeSlideIn(
                      child: _statCard(
                        context,
                        title: 'This month',
                        value: '₹${metrics.currentTotal.toStringAsFixed(0)}',
                        subtitle:
                            DateFormat('MMMM yyyy').format(DateTime.now()),
                        gradient: AppColors.heroGradient,
                        icon: Icons.calendar_month_rounded,
                      ),
                    ),
                    FadeSlideIn(
                      child: _statCard(
                        context,
                        title: 'Change',
                        value: '${metrics.percentChange.toStringAsFixed(1)}%',
                        subtitle: metrics.percentChange >= 0
                            ? 'Up vs last month'
                            : 'Down vs last month',
                        gradient: metrics.percentChange >= 0
                            ? AppColors.flameGradient
                            : const LinearGradient(
                                colors: [
                                  Color(0xFF12B76A),
                                  Color(0xFF0E9F6E),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        glowColor: metrics.percentChange >= 0
                            ? null
                            : const Color(0xFF12B76A),
                        icon: metrics.percentChange >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                      ),
                    ),
                    FadeSlideIn(
                      child: _statCard(
                        context,
                        title: 'Top category',
                        value: metrics.topCategory,
                        subtitle: 'Highest spend this month',
                        gradient: const LinearGradient(
                          colors: [AppColors.crimsonDeep, AppColors.crimson],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        glowColor: AppColors.crimson,
                        icon: Icons.auto_awesome_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _buildCategoryBubbles(context, metrics),
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(child: _buildSmartTip(context, metrics)),
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(child: _buildAssistantLauncherCard(context)),
            ],
          ),
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

    final sortedCategories = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topCategory =
        sortedCategories.isEmpty ? 'No data' : sortedCategories.first.key;

    return _InsightMetrics(
      currentTotal: currentTotal,
      percentChange: percentChange,
      topCategory: topCategory,
      totalCategories: currentTotal,
      categories: sortedCategories.take(6).toList(),
    );
  }

  Widget _statCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required Gradient gradient,
    required IconData icon,
    Color? glowColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: SizedBox(
        width: 220,
        child: GradientHeroCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          gradient: gradient,
          glowColor: glowColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(title,
                      style: AppText.onGradient(
                          size: 12, weight: FontWeight.w600, opacity: 0.9)),
                  const Spacer(),
                  Icon(icon,
                      color: Colors.white.withValues(alpha: 0.9), size: 20),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style:
                        AppText.onGradient(size: 28, weight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.onGradient(
                      size: 11, weight: FontWeight.w500, opacity: 0.9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBubbles(BuildContext context, _InsightMetrics metrics) {
    final total = metrics.totalCategories;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Top categories', style: AppText.title(context)),
              const Spacer(),
              Text('THIS MONTH', style: AppText.overline(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (metrics.categories.isEmpty)
            Text('No spending data yet this month.',
                style: AppText.body(context))
          else
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: metrics.categories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.lg),
                itemBuilder: (context, i) {
                  final entry = metrics.categories[i];
                  final pct = total > 0 ? entry.value / total * 100 : 0.0;
                  return SizedBox(
                    width: 64,
                    child: CategoryBubble(
                      category: entry.key,
                      size: 52,
                      label: entry.key,
                      percentLabel: '${pct.toStringAsFixed(0)}%',
                      highlighted: i == 0,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAssistantLauncherCard(BuildContext context) {
    return GradientHeroCard(
      onTap: () => _openAssistant(context),
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
                child: const Icon(Icons.smart_toy_rounded, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('Tap to open',
                    style:
                        AppText.onGradient(size: 11, weight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Ask SpendSense AI',
              style: AppText.onGradient(size: 24, weight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ask about your top categories, largest merchants, or how this month compares — all answered on-device.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.onGradient(size: 13, opacity: 0.9, height: 1.4),
          ),
        ],
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
          'This month jumped sharply. A follow-up about categories will help.';
    } else if (metrics.percentChange < -10) {
      tip = 'You are spending less than last month. Ask what improved most.';
    }

    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.amberGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                const Icon(Icons.lightbulb_rounded, color: Color(0xFF5A3B00)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Smart tip', style: AppText.title(context)),
                const SizedBox(height: 6),
                Text(tip, style: AppText.body(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAssistant(BuildContext context) {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const _AssistantChatScreen()),
    );
  }
}

/// Full-screen, self-contained assistant chat. Rendered as its own route so it
/// sits above the shell's floating nav bar and gets correct keyboard insets.
class _AssistantChatScreen extends StatefulWidget {
  const _AssistantChatScreen();

  @override
  State<_AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<_AssistantChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AIQueryService _localAI = AIQueryService();
  late final List<_ChatEntry> _messages = [
    _ChatEntry(
      message: AIChatMessage(
        role: 'assistant',
        content:
            'I can answer questions from your locally stored transactions.',
      ),
    ),
  ];

  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          titleSpacing: 0,
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.smart_toy_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SpendSense Bot', style: AppText.title(context)),
                    Text('Answers from your local data',
                        style: AppText.body(context).copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 0, AppSpacing.page, AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt(context),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 13,
                              color: AppColors.textSecondary(context)),
                          const SizedBox(width: 6),
                          Text('LOCAL ONLY',
                              style: AppText.overline(context)
                                  .copyWith(fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.page),
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
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: AppColors.border(context)),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                      AppSpacing.lg, AppSpacing.page, AppSpacing.md),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) =>
                      _messageBubble(context, _messages[index]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.sm, AppSpacing.page, AppSpacing.md),
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
                          hintText: 'Ask about your spending…',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.flameGradient,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: IconButton(
                        onPressed: _isLoading
                            ? null
                            : () =>
                                _submitQuery(provider, _controller.text.trim()),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded,
                                color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _promptChip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ActionChip(
        backgroundColor: AppColors.surfaceAlt(context),
        side: BorderSide(color: AppColors.border(context)),
        label:
            Text(label, style: AppText.label(context).copyWith(fontSize: 12)),
        onPressed: onTap,
      ),
    );
  }

  Widget _messageBubble(BuildContext context, _ChatEntry entry) {
    final isUser = entry.message.role == 'user';
    final bubbleColor =
        isUser ? AppColors.crimson : AppColors.surfaceAlt(context);
    final textColor = isUser ? Colors.white : AppColors.textPrimary(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                entry.message.content,
                style: AppText.body(context)
                    .copyWith(color: textColor, height: 1.4),
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
        _ChatEntry(message: AIChatMessage(role: 'user', content: cleaned)),
      );
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final localResponse = _localAI.tryAnswer(cleaned, provider.transactions);

      setState(() {
        _messages.add(
          _ChatEntry(
            message: AIChatMessage(
              role: 'assistant',
              content: localResponse ??
                  "I can only answer supported spending questions from your local transactions. Try asking about total spent, categories, averages, income, or transaction counts.",
            ),
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
        curve: AppMotion.easeOut,
      );
    });
  }
}

class _InsightMetrics {
  final double currentTotal;
  final double percentChange;
  final String topCategory;
  final double totalCategories;
  final List<MapEntry<String, double>> categories;

  const _InsightMetrics({
    required this.currentTotal,
    required this.percentChange,
    required this.topCategory,
    required this.totalCategories,
    required this.categories,
  });
}

class _ChatEntry {
  final AIChatMessage message;

  const _ChatEntry({required this.message});
}
