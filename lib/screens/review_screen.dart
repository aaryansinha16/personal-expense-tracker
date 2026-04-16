import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../sms/parser.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';
import 'add_txn_screen.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.pendingSms;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Review')),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: BubbleCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 44, color: Colors.green.shade500),
                      const SizedBox(height: 10),
                      const Text(
                        'All caught up',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'No SMS waiting for review',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 180),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final s = items[i];
                final parsed = SmsParser.parse(s.sender, s.body);
                final scheme = Theme.of(context).colorScheme;

                return BubbleCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          PillChip(
                            label: s.sender,
                            color: scheme.primary,
                            icon: Icons.sms_rounded,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timeShort(s.receivedAt),
                            style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.55)),
                          ),
                          const Spacer(),
                          if (parsed != null)
                            Text(
                              '₹${parsed.amount.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: parsed.type == 'credit' ? Colors.green.shade700 : Colors.red.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Add'),
                              onPressed: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => AddTxnScreen(
                                    fromPending: s,
                                    presetAmount: parsed?.amount,
                                    presetMerchant: parsed?.merchant,
                                    presetType: parsed?.type,
                                  ),
                                ));
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Dismiss'),
                            onPressed: () => context.read<AppState>().dismissPendingSms(s),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
