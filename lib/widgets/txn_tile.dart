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
    final fromAcct = state.accountById(txn.accountId);
    final toAcct = state.accountById(txn.toAccountId);
    final isTransfer = txn.isTransfer;
    final isCredit = txn.type == TxnType.credit;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amountColor = isTransfer
        ? scheme.onSurface.withOpacity(0.65)
        : isCredit
            ? (theme.brightness == Brightness.light
                ? const Color(0xFF1B8E5A)
                : const Color(0xFF5FD39A))
            : (theme.brightness == Brightness.light
                ? const Color(0xFFD63B3B)
                : const Color(0xFFFF8080));

    final subtitle = _buildSubtitle(cat, fromAcct, toAcct);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (isTransfer)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.swap_horiz_rounded, color: scheme.primary),
                )
              else
                CategoryIcon(category: cat),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTransfer
                          ? _transferTitle(fromAcct, toAcct)
                          : (txn.merchant ?? txn.note ?? cat?.name ?? 'Transaction'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
                isTransfer
                    ? '⇄ ${inr(txn.amount)}'
                    : '${isCredit ? '+' : '-'}${inr(txn.amount)}',
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

  String _transferTitle(Account? from, Account? to) {
    final fromName = from?.name ?? 'Unknown';
    final toName = to?.name ?? 'Unknown';
    return '$fromName → $toName';
  }

  String _buildSubtitle(Category? cat, Account? from, Account? to) {
    final parts = <String>[];
    if (txn.isTransfer) {
      parts.add('Transfer');
    } else {
      parts.add(cat?.name ?? 'Uncategorized');
    }
    if (!txn.isTransfer && from != null) parts.add(from.name);
    parts.add(timeShort(txn.date));
    if (txn.source == TxnSource.sms) parts.add('SMS');
    if (txn.source == TxnSource.email) parts.add('Email');
    return parts.join(' · ');
  }
}
