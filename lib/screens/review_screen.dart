import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/models.dart';
import '../email/parser.dart' as email_parser;
import '../providers/app_state.dart';
import '../sms/parser.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';
import '../widgets/floating_nav.dart';
import 'add_txn_screen.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final total = state.pendingSms.length + state.pendingEmails.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Review')),
      body: total == 0
          ? _emptyState(context)
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                FloatingNav.reservedHeight(context) + 24,
              ),
              children: [
                if (state.pendingSms.isNotEmpty) ...[
                  SectionHeader(title: 'SMS · ${state.pendingSms.length}'),
                  for (final s in state.pendingSms) ...[
                    _smsCard(context, s),
                    const SizedBox(height: 10),
                  ],
                ],
                if (state.pendingEmails.isNotEmpty) ...[
                  SectionHeader(title: 'EMAILS · ${state.pendingEmails.length}'),
                  for (final e in state.pendingEmails) ...[
                    _emailCard(context, e),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
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
                'Nothing waiting for review',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smsCard(BuildContext context, PendingSms s) {
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
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurface.withOpacity(0.55)),
              ),
              const Spacer(),
              if (parsed != null)
                Text(
                  '₹${parsed.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: parsed.type == 'credit'
                        ? Colors.green.shade700
                        : Colors.red.shade700,
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
                onPressed: () =>
                    context.read<AppState>().dismissPendingSms(s),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emailCard(BuildContext context, PendingEmail e) {
    final parsed = email_parser.EmailParser.parse(e.sender, e.subject ?? '', e.body);
    final scheme = Theme.of(context).colorScheme;

    return BubbleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PillChip(
                label: _senderLabel(e.sender),
                color: scheme.primary,
                icon: Icons.mail_rounded,
              ),
              const SizedBox(width: 6),
              Text(
                timeShort(e.receivedAt),
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurface.withOpacity(0.55)),
              ),
              const Spacer(),
              if (parsed != null)
                Text(
                  '₹${parsed.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: parsed.type == 'credit'
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (e.subject != null && e.subject!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              e.subject!,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (e.reason != null) ...[
            const SizedBox(height: 6),
            PillChip(
              label: 'Skipped: ${e.reason!}',
              color: Colors.orange.shade700,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _stripHtml(e.body),
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
                  onPressed: () => _openAddFromEmail(context, e, parsed),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Dismiss'),
                onPressed: () =>
                    context.read<AppState>().dismissPendingEmail(e),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openAddFromEmail(BuildContext context, PendingEmail e,
      email_parser.ParsedEmail? parsed) async {
    final state = context.read<AppState>();
    final state2 = state;
    int? categoryId;
    if (parsed?.categoryHint != null) {
      final cat = state.categories.where((c) => c.name == parsed!.categoryHint).toList();
      if (cat.isNotEmpty) categoryId = cat.first.id;
    }
    // Reuse AddTxnScreen. On save, we need to also clear the pending entry.
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddTxnScreen(
        presetAmount: parsed?.amount,
        presetMerchant: parsed?.merchant ?? _senderLabel(e.sender),
        presetType: parsed?.type,
        presetCategoryId: categoryId,
      ),
    ));
    // After return, remove the pending entry regardless — user either saved
    // or went back; in both cases we don't want it lingering. If they went
    // back they can re-add manually; this mirrors the existing SMS flow's
    // one-shot UX.
    await state2.dismissPendingEmail(e);
  }

  String _senderLabel(String fullSender) {
    // Pull either display name or just the domain.
    final m = RegExp(r'^([^<]+)<').firstMatch(fullSender);
    if (m != null) return m.group(1)!.trim();
    final m2 = RegExp(r'@([^\s>]+)').firstMatch(fullSender);
    if (m2 != null) return m2.group(1)!.trim();
    return fullSender;
  }

  String _stripHtml(String s) {
    if (!s.contains('<')) return s;
    return s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
