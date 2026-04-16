import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/models.dart';
import '../email/parser.dart' as email_parser;
import '../providers/app_state.dart';
import '../services/ai_triage.dart';
import '../sms/parser.dart';
import '../utils/formatters.dart';
import '../widgets/bubble_card.dart';
import '../widgets/floating_nav.dart';
import 'add_txn_screen.dart';
import 'ai_settings_screen.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _triaging = false;
  String? _triageStatus;

  Future<void> _runTriage(BuildContext context, AppState state) async {
    final hasKey = await AiTriageService.instance.getApiKey() != null;
    if (!hasKey) {
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Add your Anthropic API key'),
          content: const Text(
            'AI triage sends each pending item to Claude for classification. '
            'You need to add your own API key first.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open settings')),
          ],
        ),
      );
      if (go == true && context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AiSettingsScreen(),
        ));
      }
      return;
    }
    setState(() {
      _triaging = true;
      _triageStatus = null;
    });
    try {
      final res = await state.aiTriageAll();
      if (mounted) {
        setState(() {
          _triageStatus = 'Imported ${res.imported} · dismissed ${res.dismissed} · '
              'kept ${res.kept} · \$${res.usdCost.toStringAsFixed(4)}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _triageStatus = 'AI triage failed: $e');
    } finally {
      if (mounted) setState(() => _triaging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final total = state.pendingSms.length + state.pendingEmails.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Review'),
        actions: [
          if (total > 0)
            IconButton(
              tooltip: 'AI triage all',
              onPressed: _triaging ? null : () => _runTriage(context, state),
              icon: _triaging
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
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
                if (_triageStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BubbleCard(
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_triageStatus!, style: const TextStyle(fontSize: 12.5))),
                        ],
                      ),
                    ),
                  ),
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
