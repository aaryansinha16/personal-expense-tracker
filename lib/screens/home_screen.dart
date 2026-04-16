import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../sms/sms_service.dart';
import '../utils/formatters.dart';
import '../widgets/txn_tile.dart';
import 'add_txn_screen.dart';
import 'analytics_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _scanning = false;

  final _sms = SmsService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await _sms.requestPermissions();
      if (!ok) return;
      if (!mounted) return;
      _sms.startListener(onNewTxn: () {
        context.read<AppState>().refreshAll();
      });
    });
  }

  Future<void> _scanInbox() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final ok = await _sms.requestPermissions();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission denied.')),
        );
        setState(() => _scanning = false);
      }
      return;
    }
    final since = DateTime.now().subtract(const Duration(days: 90));
    try {
      final res = await _sms.scanInbox(since: since);
      if (mounted) {
        await context.read<AppState>().refreshAll();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanned ${res.scanned} SMS → ${res.imported} imported, ${res.queued} to review')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _Dashboard(onScan: _scanInbox, scanning: _scanning),
      const TransactionsScreen(),
      const AnalyticsScreen(),
      const ReviewScreen(),
      const SettingsScreen(),
    ];
    final state = context.watch<AppState>();
    final pendingCount = state.pendingSms.length;

    return Scaffold(
      body: IndexedStack(index: _tab, children: screens),
      floatingActionButton: _tab == 0 || _tab == 1
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AddTxnScreen(),
                ));
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Txns'),
          const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Insights'),
          NavigationDestination(
            icon: Badge.count(
              count: pendingCount,
              isLabelVisible: pendingCount > 0,
              child: const Icon(Icons.inbox_outlined),
            ),
            selectedIcon: const Icon(Icons.inbox),
            label: 'Review',
          ),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final VoidCallback onScan;
  final bool scanning;
  const _Dashboard({required this.onScan, required this.scanning});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spent = state.monthTotals['debit'] ?? 0;
    final earned = state.monthTotals['credit'] ?? 0;
    final balance = earned - spent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Scan SMS inbox',
            onPressed: scanning ? null : onScan,
            icon: scanning
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sms_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AppState>().refreshAll(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MonthCard(month: state.selectedMonth, spent: spent, earned: earned, balance: balance),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent', style: Theme.of(context).textTheme.titleMedium),
                if (state.pendingSms.isNotEmpty)
                  Text('${state.pendingSms.length} to review',
                      style: TextStyle(color: Colors.orange.shade700)),
              ],
            ),
            const SizedBox(height: 8),
            if (state.recentTxns.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No transactions yet. Tap Add or scan your SMS.')),
              )
            else
              ...state.recentTxns.take(15).map((t) => TxnTile(txn: t, state: state)),
          ],
        ),
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  final DateTime month;
  final double spent;
  final double earned;
  final double balance;

  const _MonthCard({required this.month, required this.spent, required this.earned, required this.balance});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(monthLabel(month),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(inr(balance),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: balance >= 0 ? Colors.green.shade800 : Colors.red.shade700)),
            const SizedBox(height: 4),
            Text('Net this month', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _miniStat(context, 'Income', earned, Colors.green.shade700, Icons.arrow_downward)),
                const SizedBox(width: 12),
                Expanded(child: _miniStat(context, 'Spent', spent, Colors.red.shade700, Icons.arrow_upward)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(BuildContext c, String label, double v, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(color: color))]),
          const SizedBox(height: 4),
          Text(inr(v), style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 16)),
        ],
      ),
    );
  }
}
