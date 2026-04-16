import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/models.dart';
import '../email/parser.dart';
import '../providers/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';

class ImportEmailScreen extends StatefulWidget {
  final String? initialSender;
  final String? initialSubject;
  final String? initialBody;

  const ImportEmailScreen({
    super.key,
    this.initialSender,
    this.initialSubject,
    this.initialBody,
  });

  @override
  State<ImportEmailScreen> createState() => _ImportEmailScreenState();
}

class _ImportEmailScreenState extends State<ImportEmailScreen> {
  late final TextEditingController _sender;
  late final TextEditingController _subject;
  late final TextEditingController _body;

  ParsedEmail? _parsed;

  @override
  void initState() {
    super.initState();
    _sender = TextEditingController(text: widget.initialSender ?? '');
    _subject = TextEditingController(text: widget.initialSubject ?? '');
    _body = TextEditingController(text: widget.initialBody ?? '');
    _sender.addListener(_reparse);
    _subject.addListener(_reparse);
    _body.addListener(_reparse);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reparse());
  }

  @override
  void dispose() {
    _sender.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _reparse() {
    if (_body.text.trim().isEmpty) {
      if (_parsed != null) setState(() => _parsed = null);
      return;
    }
    final p = EmailParser.parse(_sender.text, _subject.text, _body.text);
    setState(() => _parsed = p);
  }

  Future<void> _save() async {
    final parsed = _parsed;
    if (parsed == null) return;
    final state = context.read<AppState>();
    final categoryId = state.categories
        .firstWhere(
          (c) => c.name == parsed.categoryHint,
          orElse: () => state.categories.firstWhere(
            (c) => c.name == 'Other',
            orElse: () => state.categories.first,
          ),
        )
        .id;

    await state.addTxn(Txn(
      amount: parsed.amount,
      type: parsed.type,
      categoryId: categoryId,
      merchant: parsed.merchant,
      date: DateTime.now(),
      source: TxnSource.email,
      note: parsed.orderId != null ? 'order:${parsed.orderId}' : null,
    ));
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${inr(parsed.amount)} from ${parsed.merchant}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final parsed = _parsed;
    final canSave = parsed != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Import from email')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BubbleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste the email or share it from another app.',
                  style: TextStyle(color: scheme.onSurface.withOpacity(0.7), fontSize: 13.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _sender,
                  decoration: const InputDecoration(
                    labelText: 'From (email or domain)',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                    hintText: 'orders@swiggy.in',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _subject,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: Icon(Icons.subject_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _body,
                  decoration: const InputDecoration(
                    labelText: 'Body',
                    hintText: 'Paste the email body here…',
                  ),
                  maxLines: 10,
                  minLines: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (parsed != null) _preview(context, parsed, state),
          if (parsed == null && _body.text.trim().isNotEmpty) ...[
            BubbleCard(
              color: Colors.orange.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.orange.shade700),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Couldn't detect a transaction. Check the amount is present (₹ or Rs.) and there's a paid/purchase verb.",
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: canSave ? _save : null,
            icon: const Icon(Icons.check_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(canSave ? 'Save transaction' : 'Fill the fields above'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context, ParsedEmail p, AppState state) {
    final scheme = Theme.of(context).colorScheme;
    final cat = state.categories.where((c) => c.name == p.categoryHint).toList();
    final color = cat.isNotEmpty ? Color(cat.first.color) : scheme.primary;
    return BubbleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('DETECTED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: scheme.onSurface.withOpacity(0.6),
                  )),
              const Spacer(),
              PillChip(
                label: p.type == TxnType.credit ? 'Credit' : 'Expense',
                color: p.type == TxnType.credit ? Colors.green.shade700 : Colors.red.shade700,
                icon: p.type == TxnType.credit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            inr(p.amount),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(p.merchant ?? 'Unknown merchant',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (p.categoryHint != null)
            Text('Category: ${p.categoryHint}',
                style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 12.5)),
          if (p.orderId != null)
            Text('Order: ${p.orderId}',
                style: TextStyle(color: scheme.onSurface.withOpacity(0.55), fontSize: 12)),
        ],
      ),
    );
  }
}
