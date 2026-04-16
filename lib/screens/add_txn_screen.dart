import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/models.dart';
import '../providers/app_state.dart';

class AddTxnScreen extends StatefulWidget {
  final Txn? edit;
  final PendingSms? fromPending;
  final double? presetAmount;
  final String? presetMerchant;
  final String? presetType;
  final int? presetCategoryId;

  const AddTxnScreen({
    super.key,
    this.edit,
    this.fromPending,
    this.presetAmount,
    this.presetMerchant,
    this.presetType,
    this.presetCategoryId,
  });

  @override
  State<AddTxnScreen> createState() => _AddTxnScreenState();
}

class _AddTxnScreenState extends State<AddTxnScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _type;
  late TextEditingController _amount;
  late TextEditingController _merchant;
  late TextEditingController _note;
  int? _categoryId;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _type = e?.type ?? widget.presetType ?? TxnType.debit;
    _amount = TextEditingController(text: e?.amount.toString() ?? widget.presetAmount?.toString() ?? '');
    _merchant = TextEditingController(text: e?.merchant ?? widget.presetMerchant ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _categoryId = e?.categoryId ?? widget.presetCategoryId;
    _date = e?.date ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.edit == null ? 'Add transaction' : 'Edit transaction'),
        actions: [
          if (widget.edit != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await state.deleteTxn(widget.edit!.id!);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: TxnType.debit, label: Text('Expense'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: TxnType.credit, label: Text('Income'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Amount (₹)', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _merchant,
              decoration: const InputDecoration(labelText: 'Merchant / description', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: state.categories
                  .map((c) => DropdownMenuItem<int>(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text('${_date.day}/${_date.month}/${_date.year}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(widget.edit == null ? 'Save' : 'Update', style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final amount = double.parse(_amount.text);
    final merchant = _merchant.text.trim().isEmpty ? null : _merchant.text.trim();
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();

    if (widget.edit != null) {
      await state.updateTxn(widget.edit!.copyWith(
        amount: amount,
        type: _type,
        categoryId: _categoryId,
        merchant: merchant,
        date: _date,
        note: note,
      ));
    } else if (widget.fromPending != null) {
      await state.resolvePendingSms(
        widget.fromPending!,
        txn: Txn(
          amount: amount,
          type: _type,
          categoryId: _categoryId,
          merchant: merchant,
          date: _date,
          source: TxnSource.sms,
          rawSms: widget.fromPending!.body,
          note: note,
        ),
      );
    } else {
      await state.addTxn(Txn(
        amount: amount,
        type: _type,
        categoryId: _categoryId,
        merchant: merchant,
        date: _date,
        source: TxnSource.manual,
        note: note,
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }
}
