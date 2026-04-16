import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../email/sender_registry.dart';
import '../providers/app_state.dart';
import '../widgets/bubble_card.dart';
import '../widgets/floating_nav.dart';

class EmailSendersScreen extends StatefulWidget {
  const EmailSendersScreen({super.key});

  @override
  State<EmailSendersScreen> createState() => _EmailSendersScreenState();
}

class _EmailSendersScreenState extends State<EmailSendersScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = SenderRegistry.instance;
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    final senders = registry.all.where((s) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return s.domainSuffix.contains(q) ||
          s.displayName.toLowerCase().contains(q) ||
          (s.categoryHint?.toLowerCase().contains(q) ?? false);
    }).toList();

    // Group by category hint; "Uncategorized" bucket at the end.
    final grouped = <String, List<EmailSender>>{};
    for (final s in senders) {
      final key = s.categoryHint ?? 'Uncategorized';
      grouped.putIfAbsent(key, () => []).add(s);
    }
    final categories = grouped.keys.toList()..sort();
    // Move Uncategorized to the end.
    if (categories.remove('Uncategorized')) categories.add('Uncategorized');

    final enabledCount = registry.all.where((s) => s.enabled).length;
    final disabledCount = registry.all.length - enabledCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email senders'),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: FloatingNav.reservedHeight(context) - 60),
        child: FloatingActionButton.extended(
          onPressed: () => _openEditor(context, null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add sender'),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, FloatingNav.reservedHeight(context) + 80),
        children: [
          BubbleCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mail_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${registry.all.length} senders '
                        '· $enabledCount on · $disabledCount off',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'These are the email domains the app recognizes as transaction sources. Toggle one off to stop scanning it; add your own if a merchant isn\'t listed.',
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(0.7),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search by domain, name, or category',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 16),
          ...categories.expand((cat) {
            final rows = grouped[cat]!;
            return [
              SectionHeader(title: cat.toUpperCase()),
              BubbleCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      _senderTile(context, state, rows[i]),
                      if (i < rows.length - 1)
                        const Divider(height: 1, indent: 60, endIndent: 16),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ];
          }),
        ],
      ),
    );
  }

  Widget _senderTile(BuildContext context, AppState state, EmailSender s) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primary.withOpacity(s.enabled ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          s.isDefault ? Icons.verified_rounded : Icons.person_add_alt_rounded,
          color: s.enabled ? scheme.primary : scheme.onSurface.withOpacity(0.4),
          size: 20,
        ),
      ),
      title: Text(
        s.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: s.enabled ? null : scheme.onSurface.withOpacity(0.5),
        ),
      ),
      subtitle: Text(
        s.domainSuffix,
        style: TextStyle(
          color: scheme.onSurface.withOpacity(s.enabled ? 0.6 : 0.35),
          fontSize: 12.5,
        ),
      ),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 0,
        children: [
          Switch(
            value: s.enabled,
            onChanged: (v) async {
              await SenderRegistry.instance.toggle(s.id, v);
              if (mounted) setState(() {});
            },
          ),
          if (!s.isDefault)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
              onPressed: () async {
                await SenderRegistry.instance.remove(s.id);
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
      onTap: s.isDefault ? null : () => _openEditor(context, s),
    );
  }

  Future<void> _openEditor(BuildContext context, EmailSender? existing) async {
    final state = context.read<AppState>();
    final categories = state.categories.map((c) => c.name).toList();

    final domainCtrl = TextEditingController(text: existing?.domainSuffix ?? '');
    final nameCtrl = TextEditingController(text: existing?.displayName ?? '');
    String? selectedCategory = existing?.categoryHint;

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
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
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
                Text(
                  existing == null ? 'Add a sender' : 'Edit sender',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: domainCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Domain suffix',
                    prefixIcon: Icon(Icons.language_rounded),
                    hintText: 'e.g. lenskart.com',
                  ),
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                    hintText: 'Lenskart',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    prefixIcon: Icon(Icons.category_rounded),
                  ),
                  borderRadius: BorderRadius.circular(18),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Uncategorized')),
                    ...categories.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setSt(() => selectedCategory = v),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final domain = domainCtrl.text.trim().toLowerCase();
                    final name = nameCtrl.text.trim();
                    if (domain.isEmpty || name.isEmpty) return;
                    await SenderRegistry.instance.upsert(
                      id: existing?.id,
                      domainSuffix: domain,
                      displayName: name,
                      categoryHint: selectedCategory,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Save'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
