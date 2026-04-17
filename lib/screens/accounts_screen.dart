import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database.dart';
import '../db/models.dart';
import '../providers/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';
import '../widgets/floating_nav.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  Map<int, double> _monthSpent = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSpent());
  }

  Future<void> _loadSpent() async {
    final state = context.read<AppState>();
    final (from, to) = monthRange(state.selectedMonth);
    final db = AppDb.instance;
    final map = <int, double>{};
    for (final a in state.accounts) {
      if (a.id == null) continue;
      map[a.id!] = await db.accountSpent(a.id!, from, to);
    }
    if (mounted) setState(() => _monthSpent = map);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts & cards')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add account'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, FloatingNav.reservedHeight(context) + 80),
        children: [
          BubbleCard(
            child: Text(
              'Track which bank / card each transaction came from. '
              'Transfers between your own accounts (e.g. CC cash advance '
              'into a bank account) don\'t count in expense or income totals.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final a in state.accounts) ...[
            _accountCard(context, state, a),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _accountCard(BuildContext context, AppState state, Account a) {
    final scheme = Theme.of(context).colorScheme;
    final spent = _monthSpent[a.id] ?? 0;
    final color = Color(a.color);
    return BubbleCard(
      padding: EdgeInsets.zero,
      onTap: () => _edit(context, a),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_iconFor(a), color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(a),
                    style: TextStyle(
                      color: scheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(inr(spent),
                    style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                Text('this month',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurface.withOpacity(0.55))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(Account a) {
    switch (a.type) {
      case AccountType.creditCard:
        return Icons.credit_card_rounded;
      case AccountType.bank:
        return Icons.account_balance_rounded;
      case AccountType.wallet:
        return Icons.account_balance_wallet_rounded;
      case AccountType.cash:
      default:
        return Icons.payments_rounded;
    }
  }

  String _subtitle(Account a) {
    switch (a.type) {
      case AccountType.creditCard:
        final parts = <String>['Credit card'];
        if (a.issuer != null) parts.add(a.issuer!);
        if (a.last4 != null) parts.add('•• ${a.last4}');
        return parts.join(' · ');
      case AccountType.bank:
        final parts = <String>['Bank'];
        if (a.issuer != null) parts.add(a.issuer!);
        if (a.last4 != null) parts.add('•• ${a.last4}');
        return parts.join(' · ');
      case AccountType.wallet:
        return 'Wallet${a.issuer != null ? ' · ${a.issuer}' : ''}';
      case AccountType.cash:
      default:
        return 'Cash';
    }
  }

  Future<void> _edit(BuildContext context, Account? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccountEditor(existing: existing),
    );
    await _loadSpent();
  }
}

class _AccountEditor extends StatefulWidget {
  final Account? existing;
  const _AccountEditor({this.existing});

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  final _name = TextEditingController();
  final _issuer = TextEditingController();
  final _last4 = TextEditingController();
  final _limit = TextEditingController();
  String _type = AccountType.bank;
  int _color = 0xFF6366F1;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _issuer.text = e.issuer ?? '';
      _last4.text = e.last4 ?? '';
      _limit.text = e.creditLimit?.toStringAsFixed(0) ?? '';
      _type = e.type;
      _color = e.color;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final isCash = widget.existing?.name == 'Cash';
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
          const SizedBox(height: 14),
          Text(widget.existing == null ? 'Add account' : 'Edit account',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            enabled: !isCash,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.label_outline_rounded),
              hintText: 'Axis CC, Kotak Savings, etc.',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Type',
              prefixIcon: Icon(Icons.category_rounded),
            ),
            borderRadius: BorderRadius.circular(18),
            items: const [
              DropdownMenuItem(value: AccountType.cash, child: Text('Cash')),
              DropdownMenuItem(value: AccountType.bank, child: Text('Bank')),
              DropdownMenuItem(value: AccountType.creditCard, child: Text('Credit card')),
              DropdownMenuItem(value: AccountType.wallet, child: Text('Wallet')),
            ],
            onChanged: isCash ? null : (v) => setState(() => _type = v ?? _type),
          ),
          if (_type != AccountType.cash) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _issuer,
              decoration: const InputDecoration(
                labelText: 'Issuer (optional)',
                prefixIcon: Icon(Icons.business_rounded),
                hintText: 'HDFC, Axis, Amex…',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _last4,
              decoration: const InputDecoration(
                labelText: 'Last 4 digits (optional)',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
              keyboardType: TextInputType.number,
              maxLength: 4,
            ),
          ],
          if (_type == AccountType.creditCard) ...[
            TextField(
              controller: _limit,
              decoration: const InputDecoration(
                labelText: 'Credit limit (optional)',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.existing != null && !isCash)
                OutlinedButton.icon(
                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                  label: const Text('Delete'),
                  onPressed: () async {
                    await state.deleteAccount(widget.existing!.id!);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final name = _name.text.trim();
                  if (name.isEmpty) return;
                  final acct = Account(
                    id: widget.existing?.id,
                    name: name,
                    type: _type,
                    issuer: _issuer.text.trim().isEmpty ? null : _issuer.text.trim(),
                    last4: _last4.text.trim().isEmpty ? null : _last4.text.trim(),
                    color: _color,
                    icon: widget.existing?.icon ?? Icons.credit_card.codePoint,
                    creditLimit: _limit.text.trim().isEmpty ? null : double.tryParse(_limit.text),
                    statementDay: widget.existing?.statementDay,
                    dueDay: widget.existing?.dueDay,
                    sortOrder: widget.existing?.sortOrder ?? state.accounts.length,
                  );
                  await state.upsertAccount(acct);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
