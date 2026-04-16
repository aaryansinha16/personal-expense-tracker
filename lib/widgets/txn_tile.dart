import 'package:flutter/material.dart';

import '../db/models.dart';
import '../providers/app_state.dart';
import '../utils/formatters.dart';
import 'category_icon.dart';

class TxnTile extends StatelessWidget {
  final Txn txn;
  final AppState state;
  final VoidCallback? onTap;

  const TxnTile({super.key, required this.txn, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat = state.categoryById(txn.categoryId);
    final isCredit = txn.type == TxnType.credit;
    return ListTile(
      onTap: onTap,
      leading: CategoryIcon(category: cat),
      title: Text(
        txn.merchant ?? txn.note ?? cat?.name ?? 'Transaction',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${cat?.name ?? 'Uncategorized'} • ${timeShort(txn.date)}${txn.source == TxnSource.sms ? ' • SMS' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${isCredit ? '+' : '-'} ${inr(txn.amount)}',
        style: TextStyle(
          color: isCredit ? Colors.green.shade700 : Colors.red.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
