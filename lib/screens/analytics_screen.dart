import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database.dart';
import '../providers/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';
import '../widgets/insights_row.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Map<String, Object?>> _byCat = [];
  List<Map<String, Object?>> _daily = [];
  Map<String, double> _totals = {'debit': 0, 'credit': 0};
  String _scope = 'month';
  int _lastSeenCount = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _range(AppState s) {
    final now = DateTime.now();
    switch (_scope) {
      case 'week':
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        return (start, start.add(const Duration(days: 7, milliseconds: -1)));
      case 'year':
        return (DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1).subtract(const Duration(milliseconds: 1)));
      default:
        final m = s.selectedMonth;
        return (DateTime(m.year, m.month, 1), DateTime(m.year, m.month + 1, 1).subtract(const Duration(milliseconds: 1)));
    }
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final (from, to) = _range(state);
    final db = AppDb.instance;
    final byCat = await db.totalsByCategory(from, to);
    final daily = await db.dailyTotals(from, to);
    final totals = await db.totalsByType(from, to);
    if (!mounted) return;
    setState(() {
      _byCat = byCat;
      _daily = daily;
      _totals = totals;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final need = state.recentTxns.length;
        if (need != _lastSeenCount) {
          _lastSeenCount = need;
          _load();
        }
      }
    });

    final spent = _totals['debit'] ?? 0;
    final earned = _totals['credit'] ?? 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Insights')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 180),
          children: [
            if (state.insights.isNotEmpty) ...[
              const SectionHeader(title: 'INSIGHTS'),
              InsightsRow(insights: state.insights),
              const SizedBox(height: 16),
            ],
            BubbleCard(
              padding: const EdgeInsets.all(6),
              child: SegmentedButton<String>(
                style: SegmentedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  side: BorderSide.none,
                  selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                  selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                segments: const [
                  ButtonSegment(value: 'week', label: Text('Week')),
                  ButtonSegment(value: 'month', label: Text('Month')),
                  ButtonSegment(value: 'year', label: Text('Year')),
                ],
                selected: {_scope},
                onSelectionChanged: (s) {
                  setState(() => _scope = s.first);
                  _load();
                },
              ),
            ),
            if (_scope == 'month') ...[
              const SizedBox(height: 12),
              BubbleCard(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () async {
                        final m = state.selectedMonth;
                        await state.setSelectedMonth(DateTime(m.year, m.month - 1));
                        _load();
                      },
                    ),
                    Text(monthLabel(state.selectedMonth),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () async {
                        final m = state.selectedMonth;
                        await state.setSelectedMonth(DateTime(m.year, m.month + 1));
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _stat('Spent', spent, Colors.red.shade600)),
                const SizedBox(width: 8),
                Expanded(child: _stat('Income', earned, Colors.green.shade600)),
                const SizedBox(width: 8),
                Expanded(
                  child: _stat(
                    'Net',
                    earned - spent,
                    (earned - spent) >= 0 ? Colors.green.shade600 : Colors.red.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'BY CATEGORY'),
            BubbleCard(
              child: Column(
                children: [
                  _pieChart(state),
                  const SizedBox(height: 12),
                  ..._byCat.where((r) => r['total'] != null).map((r) {
                    final total = (r['total'] as num).toDouble();
                    final share = spent > 0 ? total / spent : 0;
                    final color = Color((r['color'] as int?) ?? 0xFFBDBDBD);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(radius: 6, backgroundColor: color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text((r['name'] as String?) ?? 'Uncategorized',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              ),
                              Text(inr(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: share.toDouble(),
                              minHeight: 6,
                              color: color,
                              backgroundColor: color.withOpacity(0.14),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'DAILY SPEND'),
            BubbleCard(
              child: SizedBox(height: 200, child: _lineChart()),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'BUDGETS'),
            BubbleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _budgetRows(state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double v, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(inr(v), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3)),
          ),
        ],
      ),
    );
  }

  Widget _pieChart(AppState state) {
    final nonEmpty = _byCat
        .where((r) => (r['total'] as num?) != null && (r['total'] as num).toDouble() > 0)
        .toList();
    if (nonEmpty.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text('No expenses in this period',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
        ),
      );
    }
    final total = nonEmpty.fold<double>(0, (s, r) => s + (r['total'] as num).toDouble());
    return SizedBox(
      height: 200,
      child: PieChart(PieChartData(
        sectionsSpace: 3,
        centerSpaceRadius: 48,
        sections: nonEmpty.map((r) {
          final v = (r['total'] as num).toDouble();
          final color = Color((r['color'] as int?) ?? 0xFFBDBDBD);
          final pct = total > 0 ? (v / total * 100).round() : 0;
          return PieChartSectionData(
            color: color,
            value: v,
            title: '$pct%',
            radius: 52,
            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
          );
        }).toList(),
      )),
    );
  }

  Widget _lineChart() {
    if (_daily.isEmpty) {
      return Center(
        child: Text('No data', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
      );
    }
    final spots = _daily.map((r) {
      final day = (r['day'] as num).toDouble();
      final total = (r['total'] as num).toDouble();
      return FlSpot(day, total);
    }).toList();
    final xs = spots.map((s) => s.x).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final maxY = spots.map((s) => s.y).fold<double>(0, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    return LineChart(LineChartData(
      minX: minX,
      maxX: maxX == minX ? minX + 1 : maxX,
      minY: 0,
      maxY: maxY == 0 ? 1 : maxY * 1.2,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: scheme.onSurface.withOpacity(0.06), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            getTitlesWidget: (v, _) => Text(
              inr(v, decimals: false).replaceAll('₹', '₹'),
              style: TextStyle(fontSize: 10, color: scheme.onSurface.withOpacity(0.5)),
            ),
          ),
        ),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.3,
          color: scheme.primary,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [scheme.primary.withOpacity(0.28), scheme.primary.withOpacity(0.02)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    ));
  }

  List<Widget> _budgetRows(AppState state) {
    if (state.budgets.isEmpty) {
      return [
        const Text('No budgets set', style: TextStyle(color: Colors.grey)),
      ];
    }
    return state.budgets.map((b) {
      final cat = state.categoryById(b.categoryId);
      final row = _byCat.firstWhere(
        (r) => r['category_id'] == b.categoryId,
        orElse: () => <String, Object?>{'total': 0},
      );
      final spent = (row['total'] as num?)?.toDouble() ?? 0;
      final share = (spent / b.monthlyLimit).clamp(0.0, 1.0);
      final over = spent > b.monthlyLimit;
      final color = over ? Colors.red.shade600 : (cat != null ? Color(cat.color) : Theme.of(context).colorScheme.primary);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(cat?.name ?? 'Category', style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${inr(spent)} / ${inr(b.monthlyLimit)}',
                    style: TextStyle(color: over ? Colors.red : Colors.grey.shade700)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 7,
                color: color,
                backgroundColor: color.withOpacity(0.15),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
