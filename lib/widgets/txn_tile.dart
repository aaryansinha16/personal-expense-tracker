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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amountColor = isCredit
        ? (theme.brightness == Brightness.light ? const Color(0xFF1B8E5A) : const Color(0xFF5FD39A))
        : (theme.brightness == Brightness.light ? const Color(0xFFD63B3B) : const Color(0xFFFF8080));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              CategoryIcon(category: cat),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txn.merchant ?? txn.note ?? cat?.name ?? 'Transaction',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cat?.name ?? 'Uncategorized'} · ${timeShort(txn.date)}${txn.source == TxnSource.sms ? ' · SMS' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isCredit ? '+' : '-'}${inr(txn.amount)}',
                style: TextStyle(
                  color: amountColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
