import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/models.dart';
import '../providers/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';
import '../widgets/floating_nav.dart';
import 'ai_settings_screen.dart';
import 'budget_setup_screen.dart';
import 'email_senders_screen.dart';
import 'email_sync_screen.dart';
import 'import_email_screen.dart';
import 'sms_sync_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, FloatingNav.reservedHeight(context) + 24),
        children: [
          const SectionHeader(title: 'MONTHLY BUDGET'),
          BubbleCard(
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const BudgetSetupScreen(),
            )),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.account_balance_wallet_rounded, color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Income, savings & fixed expenses',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                state.setup.isConfigured
                    ? '${inr(state.setup.monthlyDiscretionary)} available this month'
                    : 'Not set up yet',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'SMS SYNC'),
          BubbleCard(
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SmsSyncScreen(),
            )),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.sms_rounded, color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Inbox scan & reset',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Re-scan from a specific date or clear sync history',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'EMAIL'),
          BubbleCard(
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const EmailSyncScreen(),
            )),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.cloud_sync_rounded, color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Gmail auto-sync',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Connect a Google account and scan merchant emails',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 8),
          BubbleCard(
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ImportEmailScreen(),
            )),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.mail_rounded, color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Import from email',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Paste an email, or share one from another app',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 8),
          BubbleCard(
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const EmailSendersScreen(),
            )),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.alternate_email_rounded,
                    color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Email senders',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'See + edit the merchant allowlist used by Gmail sync',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'AI TRIAGE'),
          BubbleCard(
            padding: EdgeInsets.zero,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AiSettingsScreen(),
            )),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('AI classifier',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Use Claude to bulk-classify Review queue items',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'CATEGORIES'),
          BubbleCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final c in state.categories) _categoryTile(context, state, c),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: const Text('Add category', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => _addCategoryDialog(context, state),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'MONTHLY BUDGETS'),
          BubbleCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                if (state.budgets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    child: Text('No budgets set', style: TextStyle(color: Colors.grey)),
                  )
                else
                  for (final b in state.budgets) _budgetTile(context, state, b),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: const Text('Set budget', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => _addBudgetDialog(context, state),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'ABOUT'),
          BubbleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Expense Tracker', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'All data stays on your device. No cloud sync.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTile(BuildContext context, AppState state, Category c) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(c.color).withOpacity(0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(IconData(c.icon, fontFamily: 'MaterialIcons'), color: Color(c.color), size: 22),
      ),
      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
        onPressed: () => state.deleteCategory(c.id!),
      ),
    );
  }

  Widget _budgetTile(BuildContext context, AppState state, Budget b) {
    final cat = state.categoryById(b.categoryId);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(cat?.color ?? 0xFF9575CD).withOpacity(0.16),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.pie_chart_rounded, color: Color(cat?.color ?? 0xFF9575CD), size: 20),
      ),
      title: Text(cat?.name ?? 'Category', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(inr(b.monthlyLimit)),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
        onPressed: () => state.deleteBudget(b.categoryId),
      ),
    );
  }

  Future<void> _addCategoryDialog(BuildContext context, AppState state) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New category'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await state.addCategory(Category(
                name: ctrl.text.trim(),
                icon: Icons.category.codePoint,
                color: 0xFF9575CD,
              ));
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addBudgetDialog(BuildContext context, AppState state) async {
    int? catId = state.categories.isNotEmpty ? state.categories.first.id : null;
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setSt) {
        return AlertDialog(
          title: const Text('Set monthly budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int?>(
                initialValue: catId,
                decoration: const InputDecoration(labelText: 'Category'),
                borderRadius: BorderRadius.circular(18),
                items: state.categories
                    .map((cat) => DropdownMenuItem<int?>(value: cat.id, child: Text(cat.name)))
                    .toList(),
                onChanged: (v) => setSt(() => catId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'Monthly limit (₹)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final v = double.tryParse(ctrl.text);
                if (catId == null || v == null || v <= 0) return;
                await state.upsertBudget(catId!, v);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }
}
