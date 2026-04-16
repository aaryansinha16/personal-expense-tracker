import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/models.dart';
import '../providers/app_state.dart';
import '../widgets/bubble_card.dart';

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
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await state.deleteTxn(widget.edit!.id!);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                  ButtonSegment(value: TxnType.debit, label: Text('Expense'), icon: Icon(Icons.arrow_upward_rounded)),
                  ButtonSegment(value: TxnType.credit, label: Text('Income'), icon: Icon(Icons.arrow_downward_rounded)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee_rounded)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _merchant,
              decoration: const InputDecoration(labelText: 'Merchant / description', prefixIcon: Icon(Icons.storefront_rounded)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_rounded)),
              borderRadius: BorderRadius.circular(18),
              items: state.categories
                  .map((c) => DropdownMenuItem<int>(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            BubbleCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.calendar_today_rounded),
                title: Text('${_date.day}/${_date.month}/${_date.year}'),
                trailing: const Icon(Icons.chevron_right_rounded),
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
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note', prefixIcon: Icon(Icons.notes_rounded)),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(widget.edit == null ? 'Save transaction' : 'Update', style: const TextStyle(fontSize: 15)),
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
