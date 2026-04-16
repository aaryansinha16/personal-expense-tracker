import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../sms/sms_service.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';
import '../widgets/floating_nav.dart';
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
          SnackBar(content: Text('Scanned ${res.scanned} → ${res.imported} imported, ${res.queued} to review')),
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
      extendBody: true,
      body: IndexedStack(index: _tab, children: screens),
      floatingActionButton: _tab == 0 || _tab == 1
          ? Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AddTxnScreen(),
                  ));
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            )
          : null,
      bottomNavigationBar: FloatingNav(
        selectedIndex: _tab,
        onSelect: (i) => setState(() => _tab = i),
        items: [
          const FloatingNavItem(icon: Icons.home_rounded, selectedIcon: Icons.home_rounded, label: 'Home'),
          const FloatingNavItem(icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long_rounded, label: 'Txns'),
          const FloatingNavItem(icon: Icons.insights_outlined, selectedIcon: Icons.insights_rounded, label: 'Insights'),
          FloatingNavItem(icon: Icons.inbox_outlined, selectedIcon: Icons.inbox_rounded, label: 'Review', badge: pendingCount),
          const FloatingNavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: 'Settings'),
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Scan SMS inbox',
            onPressed: scanning ? null : onScan,
            icon: scanning
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sms_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AppState>().refreshAll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 180),
          children: [
            _MonthCard(month: state.selectedMonth, spent: spent, earned: earned, balance: balance),
            const SizedBox(height: 22),
            SectionHeader(
              title: 'RECENT',
              trailing: state.pendingSms.isNotEmpty
                  ? PillChip(
                      label: '${state.pendingSms.length} to review',
                      color: Colors.orange.shade700,
                      icon: Icons.fiber_manual_record,
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            if (state.recentTxns.isEmpty)
              BubbleCard(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 34,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35)),
                      const SizedBox(height: 8),
                      const Text('No transactions yet'),
                      const SizedBox(height: 4),
                      Text(
                        'Tap Add or scan your SMS inbox',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              BubbleCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final t in state.recentTxns.take(15))
                      TxnTile(txn: t, state: state),
                  ],
                ),
              ),
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
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final positive = balance >= 0;

    return BubbleCard(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      gradient: LinearGradient(
        colors: isLight
            ? [scheme.primary.withOpacity(0.92), scheme.primary]
            : [scheme.primary.withOpacity(0.6), scheme.primary.withOpacity(0.85)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                monthLabel(month).toUpperCase(),
                style: TextStyle(
                  color: scheme.onPrimary.withOpacity(0.8),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              PillChip(
                label: positive ? 'Net +' : 'Net −',
                color: scheme.onPrimary,
                icon: positive ? Icons.trending_up : Icons.trending_down,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            inr(balance.abs()),
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            positive ? 'Saved this month' : 'Overspent this month',
            style: TextStyle(color: scheme.onPrimary.withOpacity(0.75), fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _miniStat(context, 'Income', earned, Icons.arrow_downward_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _miniStat(context, 'Spent', spent, Icons.arrow_upward_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext c, String label, double v, IconData icon) {
    final onPrimary = Theme.of(c).colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: onPrimary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: onPrimary.withOpacity(0.85)),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: onPrimary.withOpacity(0.85), fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(inr(v),
              style: TextStyle(color: onPrimary, fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: -0.3)),
        ],
      ),
    );
  }
}
