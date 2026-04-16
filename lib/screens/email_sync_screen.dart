import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

import '../email/gmail_service.dart';
import '../providers/app_state.dart';
import '../services/ai_pipeline.dart';
import '../services/sync_prefs.dart';
import '../widgets/bubble_card.dart';

class EmailSyncScreen extends StatefulWidget {
  const EmailSyncScreen({super.key});

  @override
  State<EmailSyncScreen> createState() => _EmailSyncScreenState();
}

class _EmailSyncScreenState extends State<EmailSyncScreen> {
  final _gmail = GmailService.instance;
  GoogleSignInAccount? _account;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final a = await _gmail.signInSilently();
      if (mounted) setState(() => _account = a);
    });
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final a = await _gmail.signIn();
    if (mounted) {
      setState(() {
        _account = a;
        _busy = false;
        if (a == null) _status = 'Sign-in cancelled or failed.';
      });
    }
  }

  Future<void> _disconnect() async {
    await _gmail.signOut();
    if (mounted) setState(() => _account = null);
  }

  Future<void> _scan(DateTime since) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final useAi = await SyncPrefs.aiMode();
    try {
      if (useAi) {
        await _aiScan(since);
      } else {
        final res = await _gmail.scanInbox(since: since);
        if (mounted) {
          await context.read<AppState>().refreshAll();
          setState(() {
            _status = res.error != null
                ? 'Error: ${res.error}'
                : 'Scanned ${res.scanned} · imported ${res.imported} · '
                    'review ${res.queued} · deduped ${res.deduped} · skipped ${res.skipped}';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Scan failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _aiScan(DateTime since) async {
    setState(() => _status = 'Fetching emails…');
    final items = await _gmail.fetchRawForAi(since: since);
    if (!mounted) return;

    final estInr = AiPipeline.estimateInrRounded(smsCount: 0, emailCount: items.length);
    final estUsd = AiPipeline.estimateUsd(smsCount: 0, emailCount: items.length);
    final proceed = await _confirmCost(items.length, estInr, estUsd);
    if (!proceed) {
      setState(() => _status = 'Cancelled.');
      return;
    }

    final state = context.read<AppState>();
    final res = await state.runAiSync(
      fetch: () async => items,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _status = 'Batch ${p.batchIndex}/${p.totalBatches} · '
                '${p.itemsDone}/${p.itemsTotal} items · '
                '\$${p.usdSpent.toStringAsFixed(4)}';
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        _status = 'Done · ${res.imported} imported · ${res.dismissed} dismissed · '
            '${res.kept} kept · \$${res.usdCost.toStringAsFixed(4)}';
      });
    }
  }

  Future<bool> _confirmCost(int count, int inr, double usd) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Run AI classification?'),
        content: Text(
          '$count emails will be sent to Claude Haiku.\n\n'
          'Estimated cost: ~\$${usd.toStringAsFixed(3)} (~₹$inr).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Proceed')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      await _scan(DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _confirmReset() async {
    bool deleteTxns = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setSt) {
        return AlertDialog(
          title: const Text('Reset email sync?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Clears the processed-email history so the next scan re-reads everything.',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteTxns,
                onChanged: (v) => setSt(() => deleteTxns = v ?? true),
                title: const Text('Also delete email-imported transactions'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Reset'),
            ),
          ],
        );
      }),
    );
    if (confirmed != true) return;

    final app = context.read<AppState>();
    final r = await app.resetEmailSync(deleteEmailTxns: deleteTxns);
    if (mounted) {
      setState(() {
        _status = 'Reset · ${r.processedDeleted} hashes, ${r.emailTxnsDeleted} txns cleared';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = _account != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Gmail sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'ACCOUNT'),
          BubbleCard(
            child: connected ? _connectedAccount(context) : _notConnected(context),
          ),
          if (connected) ...[
            const SizedBox(height: 20),
            const SectionHeader(title: 'SCAN'),
            BubbleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reads matching emails from your inbox (merchant senders only).',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.7), fontSize: 13.5),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _preset('Last 7 days', const Duration(days: 7)),
                      _preset('Last 30 days', const Duration(days: 30)),
                      _preset('Last 90 days', const Duration(days: 90)),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickDate,
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: const Text('Pick a date…'),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_status!, style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'DANGER ZONE'),
            BubbleCard(
              onTap: _busy ? null : _confirmReset,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.restart_alt_rounded, color: Colors.red.shade600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Reset email sync history',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          'Clear processed-email hashes so the next scan re-reads everything.',
                          style: TextStyle(
                            color: scheme.onSurface.withOpacity(0.6),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withOpacity(0.5)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _connectedAccount(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.mail_rounded, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_account!.email, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                _account!.displayName ?? 'Connected',
                style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 12.5),
              ),
            ],
          ),
        ),
        TextButton(onPressed: _disconnect, child: const Text('Disconnect')),
      ],
    );
  }

  Widget _notConnected(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Connect a Gmail account to auto-import transactions from merchant emails.',
            style: TextStyle(color: scheme.onSurface.withOpacity(0.7), fontSize: 13.5)),
        const SizedBox(height: 6),
        Text(
          'Read-only access. No emails are sent, no data leaves the device.',
          style: TextStyle(color: scheme.onSurface.withOpacity(0.55), fontSize: 12),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Connect Gmail'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 10),
          Text(_status!, style: TextStyle(fontSize: 12.5, color: scheme.onSurface.withOpacity(0.7))),
        ],
      ],
    );
  }

  Widget _preset(String label, Duration lookback) {
    return OutlinedButton(
      onPressed: _busy ? null : () => _scan(DateTime.now().subtract(lookback)),
      child: Text(label),
    );
  }
}
