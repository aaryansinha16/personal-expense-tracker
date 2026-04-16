import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/models.dart';
import '../providers/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';

class BudgetSetupScreen extends StatelessWidget {
  const BudgetSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final setup = state.setup;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly budget')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BubbleCard(
            gradient: LinearGradient(
              colors: [scheme.primary.withOpacity(0.88), scheme.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AVAILABLE TO SPEND',
                  style: TextStyle(
                    color: scheme.onPrimary.withOpacity(0.82),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  inr(setup.monthlyDiscretionary),
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Income − Savings − Fixed expenses',
                  style: TextStyle(color: scheme.onPrimary.withOpacity(0.8), fontSize: 12),
                ),
                const SizedBox(height: 14),
                _breakdown(context, 'Income', setup.monthlyIncome),
                _breakdown(context, 'Savings target', -setup.savingsTarget),
                _breakdown(context, 'Fixed expenses', -setup.fixedTotal),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'MONTHLY INCOME'),
          BubbleCard(
            child: _EditableAmount(
              label: 'Income',
              value: setup.monthlyIncome,
              hint: 'e.g. ₹1,00,000',
              onSave: (v) => context.read<AppState>().setIncome(v),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'SAVINGS TARGET'),
          BubbleCard(
            child: _EditableAmount(
              label: 'Savings',
              value: setup.savingsTarget,
              hint: 'e.g. ₹20,000',
              onSave: (v) => context.read<AppState>().setSavingsTarget(v),
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'FIXED EXPENSES',
            trailing: Text(
              inr(setup.fixedTotal),
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          BubbleCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                if (setup.recurring.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    child: Text(
                      'Add Car EMI, rent, tiffin service, etc. They\'ll auto-post each month on their due date.',
                      style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 13),
                    ),
                  )
                else
                  for (final r in setup.recurring) _recurringTile(context, state, r),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.add_rounded, color: scheme.primary),
                  ),
                  title: const Text('Add fixed expense', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => _editRecurring(context, null),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdown(BuildContext context, String label, double v) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: onPrimary.withOpacity(0.88), fontSize: 13))),
          Text(
            (v < 0 ? '− ' : '') + inr(v.abs()),
            style: TextStyle(color: onPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ],
      ),
    );
  }

  Widget _recurringTile(BuildContext context, AppState state, RecurringExpense r) {
    final cat = state.categoryById(r.categoryId);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(cat?.color ?? 0xFF9575CD).withOpacity(0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.event_repeat_rounded, color: Color(cat?.color ?? 0xFF9575CD)),
      ),
      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${inr(r.amount)} · on day ${r.dayOfMonth}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: r.active,
            onChanged: (v) => state.upsertRecurring(r.copyWith(active: v)),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
            onPressed: () => state.deleteRecurring(r.id!),
          ),
        ],
      ),
      onTap: () => _editRecurring(context, r),
    );
  }

  Future<void> _editRecurring(BuildContext context, RecurringExpense? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecurringEditor(existing: existing),
    );
  }
}

class _EditableAmount extends StatefulWidget {
  final String label;
  final double value;
  final String hint;
  final Future<void> Function(double) onSave;

  const _EditableAmount({
    required this.label,
    required this.value,
    required this.hint,
    required this.onSave,
  });

  @override
  State<_EditableAmount> createState() => _EditableAmountState();
}

class _EditableAmountState extends State<_EditableAmount> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value == 0 ? '' : widget.value.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant _EditableAmount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _ctrl.text = widget.value == 0 ? '' : widget.value.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.currency_rupee_rounded),
              hintText: widget.hint,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: () async {
            final v = double.tryParse(_ctrl.text) ?? 0;
            await widget.onSave(v);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${widget.label} updated')),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _RecurringEditor extends StatefulWidget {
  final RecurringExpense? existing;
  const _RecurringEditor({this.existing});

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _amount;
  late TextEditingController _day;
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(text: e?.amount.toString() ?? '');
    _day = TextEditingController(text: (e?.dayOfMonth ?? 1).toString());
    _categoryId = e?.categoryId;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
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
            Text(
              widget.existing == null ? 'New fixed expense' : 'Edit fixed expense',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.label_outline_rounded),
                hintText: 'e.g. Car EMI',
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                return (d == null || d <= 0) ? 'Enter a valid amount' : null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _day,
              decoration: const InputDecoration(
                labelText: 'Day of month (1–31)',
                prefixIcon: Icon(Icons.event_rounded),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                final d = int.tryParse(v ?? '');
                return (d == null || d < 1 || d > 31) ? '1 to 31' : null;
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_rounded),
              ),
              borderRadius: BorderRadius.circular(18),
              items: [
                const DropdownMenuItem(value: null, child: Text('Uncategorized')),
                ...state.categories.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final r = RecurringExpense(
                  id: widget.existing?.id,
                  name: _name.text.trim(),
                  amount: double.parse(_amount.text),
                  categoryId: _categoryId,
                  dayOfMonth: int.parse(_day.text),
                  active: widget.existing?.active ?? true,
                );
                await context.read<AppState>().upsertRecurring(r);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
