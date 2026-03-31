import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../providers/transaction_provider.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_tile.dart';
import '../utils/app_colors.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TransactionProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=a'),
          ),
        ),
        title: Text(
          "SpendSense",
          style: TextStyle(
            color: AppColors.primaryPurple,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.syncFromSms(),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// 🔥 LAST SYNCED SECTION (NEW)
              Consumer<TransactionProvider>(
                builder: (context, provider, _) {
                  if (provider.lastSynced == null) {
                    return Text(
                      "Not synced yet",
                      style: TextStyle(color: Colors.grey),
                    );
                  }

                  final formatted = DateFormat('dd MMM, hh:mm a')
                      .format(provider.lastSynced!);

                  return Text(
                    "Last synced: $formatted",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  );
                },
              ),

              SizedBox(height: 16),

              /// SUMMARY
              SummaryCard(
                total: provider.totalExpenses,
                count: provider.transactions.length,
                topCat: provider.topCategory,
              ),

              SizedBox(height: 24),

              /// BREAKDOWN
              _buildBreakdownSection(provider),

              SizedBox(height: 24),

              /// FINANCIAL HEALTH
              _buildFinancialHealth(),

              SizedBox(height: 24),

              /// HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Recent Transactions",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "See All",
                    style: TextStyle(
                        color: AppColors.primaryPink,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              SizedBox(height: 16),

              /// LIST
              provider.isSyncing
                  ? Center(child: CircularProgressIndicator())
                  : provider.transactions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              "No transactions yet.\nPull to sync.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          itemCount: provider.transactions.length,
                          itemBuilder: (context, index) => TransactionTile(
                            transaction: provider.transactions[index],
                          ),
                        ),
            ],
          ),
        ),
      ),
    );
  }

  /// 📊 BREAKDOWN
  Widget _buildBreakdownSection(TransactionProvider provider) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Breakdown",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Icon(Icons.auto_graph_rounded, color: Colors.grey[400]),
            ],
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 140,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: 45,
                      sections: [
                        PieChartSectionData(
                            color: Color(0xFFC2185B),
                            value: 45,
                            radius: 20,
                            showTitle: false),
                        PieChartSectionData(
                            color: Color(0xFF6B38FB),
                            value: 25,
                            radius: 20,
                            showTitle: false),
                        PieChartSectionData(
                            color: Color(0xFFF48FB1),
                            value: 20,
                            radius: 20,
                            showTitle: false),
                        PieChartSectionData(
                            color: Color(0xFFE0E0FF),
                            value: 10,
                            radius: 20,
                            showTitle: false),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    _legendItem("Shopping", Color(0xFFC2185B)),
                    _legendItem("Food", Color(0xFF6B38FB)),
                    _legendItem("UPI", Color(0xFFF48FB1)),
                    _legendItem("Other", Color(0xFFE0E0FF)),
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(radius: 5, backgroundColor: color),
          SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  /// 💹 FINANCIAL HEALTH
  Widget _buildFinancialHealth() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFFE8ECEF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Financial Health",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Monthly Budget",
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    Text("82%",
                        style: TextStyle(
                            color: AppColors.primaryPink,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: 0.82,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    color: AppColors.primaryPink,
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
