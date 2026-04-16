import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database.dart';
import '../providers/app_state.dart';
import '../utils/formatters.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Map<String, Object?>> _byCat = [];
  List<Map<String, Object?>> _daily = [];
  Map<String, double> _totals = {'debit': 0, 'credit': 0};
  String _scope = 'month'; // month | week | year

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
      appBar: AppBar(
        title: const Text('Insights'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
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
            if (_scope == 'month') ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () async {
                      final m = state.selectedMonth;
                      await state.setSelectedMonth(DateTime(m.year, m.month - 1));
                      _load();
                    },
                  ),
                  Text(monthLabel(state.selectedMonth),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () async {
                      final m = state.selectedMonth;
                      await state.setSelectedMonth(DateTime(m.year, m.month + 1));
                      _load();
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _stat('Spent', spent, Colors.red.shade700)),
                const SizedBox(width: 8),
                Expanded(child: _stat('Income', earned, Colors.green.shade700)),
                const SizedBox(width: 8),
                Expanded(child: _stat('Net', earned - spent, (earned - spent) >= 0 ? Colors.green.shade700 : Colors.red.shade700)),
              ],
            ),
            const SizedBox(height: 20),
            Text('Spending by category', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _pieChart(state),
            const SizedBox(height: 8),
            ..._byCat.where((r) => r['total'] != null).map((r) {
              final total = (r['total'] as num).toDouble();
              final share = spent > 0 ? total / spent : 0;
              final color = Color((r['color'] as int?) ?? 0xFFBDBDBD);
              return ListTile(
                dense: true,
                leading: CircleAvatar(radius: 8, backgroundColor: color),
                title: Text((r['name'] as String?) ?? 'Uncategorized'),
                subtitle: LinearProgressIndicator(
                  value: share.toDouble(),
                  color: color,
                  backgroundColor: color.withOpacity(0.15),
                ),
                trailing: Text(inr(total)),
              );
            }),
            const SizedBox(height: 16),
            Text('Daily spend', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(height: 200, child: _lineChart(state)),
            const SizedBox(height: 16),
            Text('Budgets', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._budgetRows(state),
          ],
        ),
      ),
    );
  }

  int _lastSeenCount = -1;

  Widget _stat(String label, double v, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12)),
          const SizedBox(height: 4),
          Text(inr(v), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _pieChart(AppState state) {
    final nonEmpty = _byCat.where((r) => (r['total'] as num?) != null && (r['total'] as num).toDouble() > 0).toList();
    if (nonEmpty.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('No expenses in this period')));
    }
    final total = nonEmpty.fold<double>(0, (s, r) => s + (r['total'] as num).toDouble());
    return SizedBox(
      height: 200,
      child: PieChart(PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: nonEmpty.map((r) {
          final v = (r['total'] as num).toDouble();
          final color = Color((r['color'] as int?) ?? 0xFFBDBDBD);
          final pct = total > 0 ? (v / total * 100).round() : 0;
          return PieChartSectionData(
            color: color,
            value: v,
            title: '$pct%',
            radius: 56,
            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
          );
        }).toList(),
      )),
    );
  }

  Widget _lineChart(AppState state) {
    if (_daily.isEmpty) return const Center(child: Text('No data'));
    final spots = _daily.map((r) {
      final day = (r['day'] as num).toDouble();
      final total = (r['total'] as num).toDouble();
      return FlSpot(day, total);
    }).toList();
    final xs = spots.map((s) => s.x).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final maxY = spots.map((s) => s.y).fold<double>(0, (a, b) => a > b ? a : b);
    return LineChart(LineChartData(
      minX: minX,
      maxX: maxX == minX ? minX + 1 : maxX,
      minY: 0,
      maxY: maxY == 0 ? 1 : maxY * 1.2,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.redAccent,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.15)),
        ),
      ],
    ));
  }

  List<Widget> _budgetRows(AppState state) {
    if (state.budgets.isEmpty) {
      return [const Text('No budgets set. Add them in Settings.', style: TextStyle(color: Colors.grey))];
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(cat?.name ?? 'Category')),
                Text('${inr(spent)} / ${inr(b.monthlyLimit)}',
                    style: TextStyle(color: over ? Colors.red : Colors.grey.shade700)),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: share,
              color: over ? Colors.red : Colors.blue,
              backgroundColor: Colors.grey.shade200,
            ),
          ],
        ),
      );
    }).toList();
  }
}
