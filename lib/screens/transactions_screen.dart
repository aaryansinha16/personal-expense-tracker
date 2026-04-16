import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database.dart';
import '../db/models.dart';
import '../providers/app_state.dart';
import '../widgets/bubble_card.dart';
import '../widgets/floating_nav.dart';
import '../widgets/txn_tile.dart';
import 'add_txn_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _typeFilter = 'all';
  int? _catFilter;
  DateTimeRange? _range;
  List<Txn> _txns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txns = await AppDb.instance.listTxns(
      from: _range?.start,
      to: _range?.end,
      categoryId: _catFilter,
      type: _typeFilter == 'all' ? null : _typeFilter,
    );
    if (!mounted) return;
    setState(() => _txns = txns);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && state.recentTxns.length != _txns.length) _load();
    });
    final hasFilters = _typeFilter != 'all' || _catFilter != null || _range != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: hasFilters,
              smallSize: 8,
              child: const Icon(Icons.tune_rounded),
            ),
            onPressed: _openFilters,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _txns.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: BubbleCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          size: 36,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                      const SizedBox(height: 8),
                      const Text('No transactions match'),
                    ],
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 8, 16, FloatingNav.reservedHeight(context) + 80),
              itemCount: _txns.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => BubbleCard(
                padding: EdgeInsets.zero,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AddTxnScreen(edit: _txns[i]),
                  ));
                  _load();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TxnTile(txn: _txns[i], state: state),
                ),
              ),
            ),
    );
  }

  Future<void> _openFilters() async {
    final state = context.read<AppState>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
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
                const SizedBox(height: 16),
                const Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    side: BorderSide.none,
                  ),
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: TxnType.debit, label: Text('Expense')),
                    ButtonSegment(value: TxnType.credit, label: Text('Income')),
                  ],
                  selected: {_typeFilter},
                  onSelectionChanged: (s) => setSt(() => _typeFilter = s.first),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int?>(
                  initialValue: _catFilter,
                  decoration: const InputDecoration(labelText: 'Category'),
                  borderRadius: BorderRadius.circular(18),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All categories')),
                    ...state.categories.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setSt(() => _catFilter = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range_rounded),
                        label: Text(_range == null
                            ? 'Date range'
                            : '${_range!.start.day}/${_range!.start.month} – ${_range!.end.day}/${_range!.end.month}'),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: ctx,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setSt(() => _range = picked);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => setSt(() => _range = null),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSt(() {
                            _typeFilter = 'all';
                            _catFilter = null;
                            _range = null;
                          });
                        },
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _load();
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
