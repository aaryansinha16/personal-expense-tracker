import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../sms/parser.dart';
import '../utils/formatters.dart';
import 'add_txn_screen.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.pendingSms;

    return Scaffold(
      appBar: AppBar(title: const Text('Review SMS')),
      body: items.isEmpty
          ? const Center(child: Text('Nothing to review. Clean slate! 🎉'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final s = items[i];
                // Try to pre-parse for hints even if full parse failed.
                final parsed = SmsParser.parse(s.sender, s.body);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text('${s.sender} • ${timeShort(s.receivedAt)}',
                        style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(s.body, maxLines: 4, overflow: TextOverflow.ellipsis),
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Add as transaction',
                          icon: const Icon(Icons.check_circle_outline, color: Colors.green),
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
                        IconButton(
                          tooltip: 'Dismiss',
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => state.dismissPendingSms(s),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
