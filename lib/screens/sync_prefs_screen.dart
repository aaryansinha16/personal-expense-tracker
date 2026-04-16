import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_triage.dart';
import '../services/background_sync.dart';
import '../services/notifications.dart';
import '../services/sync_prefs.dart';
import '../widgets/bubble_card.dart';

class SyncPrefsScreen extends StatefulWidget {
  const SyncPrefsScreen({super.key});

  @override
  State<SyncPrefsScreen> createState() => _SyncPrefsScreenState();
}

class _SyncPrefsScreenState extends State<SyncPrefsScreen> {
  static const _kBgGmail = 'pref_bg_gmail_sync';
  static const _kNotifyTxn = 'pref_notify_txn';
  static const _kNotifyBudget = 'pref_notify_budget';

  bool _bgGmail = false;
  bool _notifyTxn = true;
  bool _notifyBudget = true;
  bool _aiMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ai = await SyncPrefs.aiMode();
    setState(() {
      _bgGmail = prefs.getBool(_kBgGmail) ?? false;
      _notifyTxn = prefs.getBool(_kNotifyTxn) ?? true;
      _notifyBudget = prefs.getBool(_kNotifyBudget) ?? true;
      _aiMode = ai;
    });
  }

  Future<void> _toggleAiMode(bool v) async {
    if (v) {
      final hasKey = await AiTriageService.instance.getApiKey() != null;
      if (!hasKey) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add your Anthropic API key in Settings → AI triage first')),
        );
        return;
      }
    }
    await SyncPrefs.setAiMode(v);
    setState(() => _aiMode = v);
  }

  Future<void> _setBool(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  Future<void> _toggleBgSync(bool v) async {
    setState(() => _bgGmail = v);
    await _setBool(_kBgGmail, v);
    await BackgroundSync.instance.setEnabled(v);
    if (v && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Auto-sync on. Runs a short Gmail scan whenever you open the app '
            '(min 15 min apart).',
          ),
        ),
      );
    }
  }

  Future<void> _testNotification() async {
    await NotificationsService.instance.init();
    await NotificationsService.instance.showTransactionAlert(
      title: 'Expense Tracker',
      body: 'Notifications are working.',
      id: 99,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sync & notifications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'AI CLASSIFICATION'),
          BubbleCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use AI to classify everything',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Every synced SMS and email goes to Claude Haiku for decision. '
                    'Catches cases regex misses (e-mandate pairs, CC bill payments, '
                    'promos with amounts, cross-source duplicates). Requires an API key.',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 12.5, height: 1.35),
                  ),
                  value: _aiMode,
                  onChanged: _toggleAiMode,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Approx cost: ₹29 / 1000 SMS · ₹56 / 1000 emails. '
                    'A full 90-day initial sync is usually under ₹70.',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.55), fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'BACKGROUND SYNC'),
          BubbleCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-scan Gmail when you open the app',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Quick scan of the last 12 hours of mail whenever you '
                    'return to the app, with a 15-minute cooldown. More '
                    'battery-friendly than polling in the background.',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 12.5),
                  ),
                  value: _bgGmail,
                  onChanged: _toggleBgSync,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'SMS is already auto-detected when the app is running. There is no reliable way for a Flutter app to receive SMS in the background on modern Android — keep the app open for live SMS pickup, or scan from Settings → SMS sync after you receive new messages.',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurface.withOpacity(0.55), height: 1.45),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'NOTIFICATIONS'),
          BubbleCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('New transactions',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Notify when background sync imports a new expense.',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 12.5),
                  ),
                  value: _notifyTxn,
                  onChanged: (v) {
                    setState(() => _notifyTxn = v);
                    _setBool(_kNotifyTxn, v);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Daily budget alerts',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Warn when today\'s spend crosses your daily allowance.',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 12.5),
                  ),
                  value: _notifyBudget,
                  onChanged: (v) {
                    setState(() => _notifyBudget = v);
                    _setBool(_kNotifyBudget, v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.notifications_rounded),
            label: const Text('Send a test notification'),
            onPressed: _testNotification,
          ),
        ],
      ),
    );
  }
}
