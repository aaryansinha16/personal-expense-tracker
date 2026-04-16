import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/ai_pipeline.dart';
import '../services/sync_prefs.dart';
import '../sms/sms_service.dart';
import '../widgets/bubble_card.dart';

class SmsSyncScreen extends StatefulWidget {
  const SmsSyncScreen({super.key});

  @override
  State<SmsSyncScreen> createState() => _SmsSyncScreenState();
}

class _SmsSyncScreenState extends State<SmsSyncScreen> {
  final _sms = SmsService();
  bool _busy = false;
  String? _lastStatus;

  Future<void> _scan(DateTime since) async {
    setState(() {
      _busy = true;
      _lastStatus = null;
    });
    final ok = await _sms.requestPermissions();
    if (!ok) {
      if (mounted) {
        setState(() {
          _busy = false;
          _lastStatus = 'SMS permission denied.';
        });
      }
      return;
    }
    final useAi = await SyncPrefs.aiMode();
    try {
      if (useAi) {
        await _aiScan(since);
      } else {
        final res = await _sms.scanInbox(since: since);
        if (mounted) {
          await context.read<AppState>().refreshAll();
          setState(() {
            _lastStatus =
                'Scanned ${res.scanned} · imported ${res.imported} · '
                    'queued ${res.queued} · deduped ${res.deduped}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastStatus = 'Scan failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _aiScan(DateTime since) async {
    final items = await _sms.fetchRawForAi(since: since);
    if (!mounted) return;

    // Pre-flight confirmation with cost estimate.
    final estInr = AiPipeline.estimateInrRounded(smsCount: items.length, emailCount: 0);
    final estUsd = AiPipeline.estimateUsd(smsCount: items.length, emailCount: 0);
    final proceed = await _confirmCost(items.length, estInr, estUsd);
    if (!proceed) {
      setState(() => _lastStatus = 'Cancelled.');
      return;
    }

    setState(() => _lastStatus = 'Starting AI classification…');
    final state = context.read<AppState>();
    final res = await state.runAiSync(
      fetch: () async => items,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _lastStatus =
                'Batch ${p.batchIndex}/${p.totalBatches} · '
                    '${p.itemsDone}/${p.itemsTotal} items · '
                    '\$${p.usdSpent.toStringAsFixed(4)}';
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        _lastStatus =
            'Done · ${res.imported} imported · ${res.dismissed} dismissed · '
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
          '$count items will be sent to Claude Haiku.\n\n'
          'Estimated cost: ~\$${usd.toStringAsFixed(3)} (~₹$inr).\n\n'
          'Dedup and category assignment are handled automatically. '
          'Low-confidence items land in Review.',
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
    bool deletePending = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setSt) {
        return AlertDialog(
          title: const Text('Reset SMS sync?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Clears the history of which SMS have been processed, so the next scan will re-read everything.',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteTxns,
                onChanged: (v) => setSt(() => deleteTxns = v ?? true),
                title: const Text('Also delete SMS-imported transactions'),
                subtitle: const Text(
                  'Manually-added transactions are kept.',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deletePending,
                onChanged: (v) => setSt(() => deletePending = v ?? true),
                title: const Text('Also clear the Review queue'),
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

    final res = await context.read<AppState>().resetSmsSync(
          deleteSmsTxns: deleteTxns,
          deletePending: deletePending,
        );
    if (mounted) {
      setState(() {
        _lastStatus =
            'Reset · ${res.processedDeleted} processed entries, ${res.smsTxnsDeleted} txns, ${res.pendingDeleted} queued cleared';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('SMS sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'SCAN INBOX'),
          BubbleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reads your SMS inbox for bank and UPI transactions.',
                  style: TextStyle(color: scheme.onSurface.withOpacity(0.7), fontSize: 13.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _presetButton('Last 7 days', const Duration(days: 7)),
                    _presetButton('Last 30 days', const Duration(days: 30)),
                    _presetButton('Last 90 days', const Duration(days: 90)),
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
                if (_lastStatus != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_lastStatus!, style: const TextStyle(fontSize: 12.5)),
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
                      const Text('Reset sync history',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        'Clear processed hashes so the next scan re-reads everything.',
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
      ),
    );
  }

  Widget _presetButton(String label, Duration? lookback) {
    return OutlinedButton(
      onPressed: _busy
          ? null
          : () {
              final since = lookback == null
                  ? DateTime(2000)
                  : DateTime.now().subtract(lookback);
              _scan(since);
            },
      child: Text(label),
    );
  }
}
