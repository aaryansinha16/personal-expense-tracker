import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database.dart';
import '../db/models.dart';
import '../providers/app_state.dart';
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
    // Refresh on global state changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && state.recentTxns.length != _txns.length) _load();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: _txns.isEmpty
          ? const Center(child: Text('No transactions match'))
          : ListView.builder(
              itemCount: _txns.length,
              itemBuilder: (_, i) => TxnTile(
                txn: _txns[i],
                state: state,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AddTxnScreen(edit: _txns[i]),
                  ));
                  _load();
                },
              ),
            ),
    );
  }

  Future<void> _openFilters() async {
    final state = context.read<AppState>();
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: TxnType.debit, label: Text('Expense')),
                    ButtonSegment(value: TxnType.credit, label: Text('Income')),
                  ],
                  selected: {_typeFilter},
                  onSelectionChanged: (s) => setSt(() => _typeFilter = s.first),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _catFilter,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All categories')),
                    ...state.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (v) => setSt(() => _catFilter = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range),
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
                      icon: const Icon(Icons.clear),
                      onPressed: () => setSt(() => _range = null),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _load();
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
