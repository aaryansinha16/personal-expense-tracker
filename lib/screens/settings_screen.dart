import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/models.dart';
import '../providers/app_state.dart';
import '../utils/formatters.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Categories', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ...state.categories.map((c) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(c.color).withOpacity(0.2),
                  child: Icon(IconData(c.icon, fontFamily: 'MaterialIcons'), color: Color(c.color), size: 20),
                ),
                title: Text(c.name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => state.deleteCategory(c.id!),
                ),
              )),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add category'),
            onTap: () => _addCategoryDialog(context, state),
          ),
          const Divider(),
          const ListTile(
            title: Text('Monthly Budgets', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ...state.budgets.map((b) {
            final cat = state.categoryById(b.categoryId);
            return ListTile(
              title: Text(cat?.name ?? 'Category'),
              subtitle: Text(inr(b.monthlyLimit)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => state.deleteBudget(b.categoryId),
              ),
            );
          }),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Set budget'),
            onTap: () => _addBudgetDialog(context, state),
          ),
          const Divider(),
          const ListTile(
            title: Text('About', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Personal expense tracker. All data stays on your device.'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCategoryDialog(BuildContext context, AppState state) async {
    final ctrl = TextEditingController();
    int iconCode = Icons.category.codePoint;
    int color = 0xFF9575CD;
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
              await state.addCategory(Category(name: ctrl.text.trim(), icon: iconCode, color: color));
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
                items: state.categories
                    .map((cat) => DropdownMenuItem<int?>(value: cat.id, child: Text(cat.name)))
                    .toList(),
                onChanged: (v) => setSt(() => catId = v),
              ),
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
