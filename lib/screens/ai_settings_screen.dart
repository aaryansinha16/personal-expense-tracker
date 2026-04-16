import 'package:flutter/material.dart';

import '../services/ai_triage.dart';
import '../widgets/bubble_card.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _ctrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _hasKey = false;
  bool _busy = false;
  String? _status;
  double _cumUsd = 0;
  int _items = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await AiTriageService.instance.getApiKey();
    _ctrl.text = key == null ? '' : _masked(key);
    _hasKey = key != null;
    _modelCtrl.text = await AiTriageService.instance.getModel();
    _cumUsd = await AiTriageService.instance.getCumulativeUsd();
    _items = await AiTriageService.instance.getItemsTriaged();
    if (mounted) setState(() {});
  }

  Future<void> _saveModel() async {
    await AiTriageService.instance.setModel(_modelCtrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model saved')),
      );
    }
  }

  String _masked(String key) {
    if (key.length <= 10) return '•' * key.length;
    return '${key.substring(0, 5)}${'•' * 10}${key.substring(key.length - 4)}';
  }

  Future<void> _saveKey() async {
    final v = _ctrl.text.trim();
    // If the user left the masked value, ignore (nothing to save).
    if (v.contains('•')) return;
    await AiTriageService.instance.setApiKey(v.isEmpty ? null : v);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final err = await AiTriageService.instance.testConnection();
      setState(() => _status = err == null ? 'Connection OK' : 'Failed — $err');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI triage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BubbleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The app can use Claude (Anthropic) to bulk-classify items in your Review queue — auto-import clear transactions, drop noise, leave ambiguous items for you.',
                  style: TextStyle(color: scheme.onSurface.withOpacity(0.75), fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 10),
                Text(
                  'You provide your own Anthropic API key. Cost is roughly ₹0.02 per 100 items classified. Keys are stored only on this device.',
                  style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'API KEY'),
          BubbleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Anthropic API key',
                    prefixIcon: Icon(Icons.key_rounded),
                    hintText: 'sk-ant-...',
                  ),
                  autocorrect: false,
                  obscureText: false,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _saveKey,
                        child: const Text('Save key'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy || !_hasKey ? null : _test,
                        child: const Text('Test connection'),
                      ),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!, style: TextStyle(color: scheme.onSurface.withOpacity(0.75))),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'MODEL'),
          BubbleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Anthropic model ID',
                    prefixIcon: Icon(Icons.memory_rounded),
                    hintText: 'claude-haiku-4-5',
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _saveModel, child: const Text('Save model')),
                const SizedBox(height: 8),
                Text(
                  'Defaults to claude-haiku-4-5. Override only if you see an '
                  '"invalid_request_error: model not found" — swap to '
                  'claude-3-5-haiku-20241022 as a known-good fallback.',
                  style: TextStyle(color: scheme.onSurface.withOpacity(0.55), fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'USAGE'),
          BubbleCard(
            child: Column(
              children: [
                _row('Items classified', _items.toString()),
                const SizedBox(height: 6),
                _row('Accumulated cost', '\$${_cumUsd.toStringAsFixed(4)}'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'DIAGNOSTICS'),
          FutureBuilder<Map<String, String>>(
            future: AiTriageService.instance.keyDebugInfo(),
            builder: (ctx, snap) {
              final d = snap.data ?? const {};
              return BubbleCard(
                child: Column(
                  children: [
                    _row('Saved key length', d['length'] ?? '…'),
                    const SizedBox(height: 6),
                    _row('Starts with', d['prefix'] ?? '…'),
                    const SizedBox(height: 6),
                    _row('Ends with', d['suffix'] ?? '…'),
                    const SizedBox(height: 6),
                    _row('Model', d['model'] ?? '…'),
                    const SizedBox(height: 10),
                    Text(
                      'Compare these to your key in the Anthropic console. '
                      'Clipboard paste often adds a stray whitespace.',
                      style: TextStyle(
                          color: scheme.onSurface.withOpacity(0.55), fontSize: 11.5),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Get an API key at console.anthropic.com → Settings → API Keys.',
            style: TextStyle(color: scheme.onSurface.withOpacity(0.5), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      children: [
        Text(label),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
