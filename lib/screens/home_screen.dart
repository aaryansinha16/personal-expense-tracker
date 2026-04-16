import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../sms/sms_service.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';
import '../widgets/daily_budget_card.dart';
import '../widgets/floating_nav.dart';
import '../widgets/txn_tile.dart';
import '../services/daily_budget.dart';
import 'add_txn_screen.dart';
import 'analytics_screen.dart';
import 'budget_setup_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'sms_sync_screen.dart';
import 'transactions_screen.dart';

Future<void> _showRedistributeSheet(BuildContext context, DailyBudget b) async {
  final scheme = Theme.of(context).colorScheme;
  final over = b.spentToday - b.todayAllowed;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.auto_graph_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                const Text('Adjust future days',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'You\'ve spent ${inr(b.spentToday)} today, ${inr(over)} over your '
              '${inr(b.todayAllowed)} daily limit.',
              style: TextStyle(fontSize: 13.5, color: scheme.onSurface.withOpacity(0.75), height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spreading the overspend across the remaining '
                    '${b.daysLeftExclusive} day${b.daysLeftExclusive == 1 ? '' : 's'}:',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurface.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Was', style: TextStyle(fontSize: 11)),
                            Text(inr(b.todayAllowed),
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Now', style: TextStyle(fontSize: 11, color: scheme.primary)),
                            Text(
                              inr(b.projectedFutureDailyAllowance),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The app recalculates your daily limit automatically every time you refresh — '
              'no saved override is needed.',
              style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.55), height: 1.4),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Got it'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

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

  void _openSmsSync() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SmsSyncScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _Dashboard(onSms: _openSmsSync),
      const TransactionsScreen(),
      const AnalyticsScreen(),
      const ReviewScreen(),
      const SettingsScreen(),
    ];
    final state = context.watch<AppState>();
    final pendingCount = state.pendingSms.length + state.pendingEmails.length;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _tab, children: screens),
      floatingActionButton: _tab == 0 || _tab == 1
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AddTxnScreen(),
                ));
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
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
  final VoidCallback onSms;
  const _Dashboard({required this.onSms});

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
            tooltip: 'SMS sync',
            onPressed: onSms,
            icon: const Icon(Icons.sms_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AppState>().refreshAll(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, FloatingNav.reservedHeight(context) + 80),
          children: [
            if (state.dailyBudget != null) ...[
              DailyBudgetCard(
                budget: state.dailyBudget!,
                onTapSetup: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const BudgetSetupScreen(),
                )),
                onRedistribute: () => _showRedistributeSheet(context, state.dailyBudget!),
              ),
              const SizedBox(height: 14),
            ],
            _MonthCard(month: state.selectedMonth, spent: spent, earned: earned, balance: balance),
            const SizedBox(height: 22),
            SectionHeader(
              title: 'RECENT',
              trailing: (state.pendingSms.length + state.pendingEmails.length) > 0
                  ? PillChip(
                      label:
                          '${state.pendingSms.length + state.pendingEmails.length} to review',
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
