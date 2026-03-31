import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/transaction_provider.dart';
import '../services/ai_query_service.dart';
import '../services/ai_service.dart';
import '../utils/app_colors.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final TextEditingController _controller = TextEditingController();

  String _aiResponse = "";
  bool _isLoading = false;
  bool _usedCloudAI = false; // shows a subtle "via cloud AI" label

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);

    final now = DateTime.now();

    /// 📅 CURRENT MONTH TX
    final currentMonthTx = provider.transactions.where((t) {
      return t.date.month == now.month &&
          t.date.year == now.year &&
          !t.isExcluded;
    }).toList();

    /// 📅 LAST MONTH TX
    final lastMonth = DateTime(now.year, now.month - 1);
    final lastMonthTx = provider.transactions.where((t) {
      return t.date.month == lastMonth.month &&
          t.date.year == lastMonth.year &&
          !t.isExcluded;
    }).toList();

    /// 💰 TOTALS
    final currentTotal =
        currentMonthTx.fold<double>(0, (sum, t) => sum + t.amount);
    final lastTotal = lastMonthTx.fold<double>(0, (sum, t) => sum + t.amount);

    /// 📈 CHANGE %
    double percentChange = 0;
    if (lastTotal > 0) {
      percentChange = ((currentTotal - lastTotal) / lastTotal) * 100;
    }

    /// 🏆 TOP CATEGORY
    Map<String, double> categoryMap = {};
    for (var t in currentMonthTx) {
      categoryMap[t.category] = (categoryMap[t.category] ?? 0) + t.amount;
    }

    String topCategory = "None";
    if (categoryMap.isNotEmpty) {
      topCategory =
          categoryMap.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Monthly Insights 📊",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            /// 💰 THIS MONTH
            _statCard(
              "This Month",
              "₹${currentTotal.toStringAsFixed(0)}",
              AppColors.primaryPurple,
              DateFormat('MMMM yyyy').format(now),
            ),

            SizedBox(height: 16),

            /// 📈 CHANGE
            _statCard(
              "Change",
              "${percentChange.toStringAsFixed(1)}%",
              percentChange >= 0 ? Colors.red : Colors.green,
              percentChange >= 0
                  ? "You spent more than last month"
                  : "You saved compared to last month",
              icon:
                  percentChange >= 0 ? Icons.trending_up : Icons.trending_down,
            ),

            SizedBox(height: 16),

            /// 🏆 CATEGORY
            _statCard(
              "Top Category",
              topCategory,
              Colors.white,
              "Highest spending category",
              icon: Icons.star,
            ),

            SizedBox(height: 24),

            /// 💡 SMART TIP
            _buildSmartTip(currentTotal, percentChange),

            SizedBox(height: 24),

            /// 🤖 AI SECTION
            _buildAISection(provider),
          ],
        ),
      ),
    );
  }

  /// 🔥 STAT CARD
  Widget _statCard(String label, String value, Color color, String sub,
      {IconData? icon}) {
    bool isDark = color != Colors.white;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              if (icon != null)
                Icon(icon, color: AppColors.primaryPink, size: 16),
              if (icon != null) SizedBox(width: 8),
              Text(
                sub,
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppColors.primaryPink,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  /// 💡 SMART TIP
  Widget _buildSmartTip(double total, double change) {
    String tip = "You're managing your money well 👍";

    if (total > 10000) {
      tip = "High spending 🚨 Try reducing non-essential expenses.";
    } else if (change > 20) {
      tip = "Spending increased 📈 Keep track.";
    } else if (change < -10) {
      tip = "Great job! You're saving 💰";
    }

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Color(0xFFE8ECEF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Smart Tip 💡",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text(tip),
        ],
      ),
    );
  }

  /// 🤖 AI SECTION — local first, cloud fallback
  Widget _buildAISection(TransactionProvider provider) {
    final localAI = AIQueryService();
    final cloudAI = AIService();

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            "Ask AI about your spending 🤖",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: "e.g. lowest transaction, total spent",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              final query = _controller.text.trim();
              if (query.isEmpty) return;

              setState(() {
                _isLoading = true;
                _aiResponse = "";
                _usedCloudAI = false;
              });

              // ⚡ 1. Try local AI first — returns null if not understood
              final localResponse =
                  localAI.tryAnswer(query, provider.transactions);

              if (localResponse != null) {
                // ✅ Local AI handled it — fast, free, offline
                setState(() {
                  _aiResponse = localResponse;
                  _isLoading = false;
                  _usedCloudAI = false;
                });
              } else {
                // ☁️ 2. Escalate to cloud AI
                final cloudResponse =
                    await cloudAI.askAI(query, provider.transactions);

                setState(() {
                  _aiResponse = cloudResponse;
                  _isLoading = false;
                  _usedCloudAI = true;
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              minimumSize: Size(double.infinity, 45),
            ),
            child: Text("Ask AI"),
          ),
          SizedBox(height: 12),
          if (_isLoading) CircularProgressIndicator(),
          if (_aiResponse.isNotEmpty && !_isLoading)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(0xFFF1F3F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_aiResponse),
                  if (_usedCloudAI) ...[
                    SizedBox(height: 8),
                    Text(
                      "✦ via cloud AI",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                  ]
                ],
              ),
            ),
        ],
      ),
    );
  }
}
