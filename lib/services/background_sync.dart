import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../email/gmail_service.dart';
import '../email/sender_registry.dart';
import '../providers/app_state.dart';
import 'ai_triage.dart';
import 'notifications.dart';
import 'sync_prefs.dart';

/// Auto-sync-on-resume. When the user brings the app to the foreground
/// after at least [minGap], we silently run a short Gmail scan and fire a
/// notification if anything new landed. Honors the AI-mode toggle — if
/// AI classification is enabled, this uses the pipeline; otherwise regex.
class BackgroundSync with WidgetsBindingObserver {
  static final BackgroundSync instance = BackgroundSync._();
  BackgroundSync._();

  static const _kLastSyncAt = 'pref_last_auto_sync_ms';
  static const _minGap = Duration(minutes: 15);

  bool _enabled = false;
  bool _attached = false;
  bool _running = false;
  AppState? _appState;

  void bindAppState(AppState state) => _appState = state;

  Future<void> initialize() async {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    if (on) await initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runIfDue();
    }
  }

  Future<void> _runIfDue() async {
    if (!_enabled || _running) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastSyncAt) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != 0 && (now - last) < _minGap.inMilliseconds) return;

    _running = true;
    try {
      await SenderRegistry.instance.load();
      await NotificationsService.instance.init();
      final since = DateTime.now().subtract(const Duration(hours: 12));

      final aiMode = await SyncPrefs.aiMode();
      final hasAiKey = await AiTriageService.instance.getApiKey() != null;
      final appState = _appState;

      if (aiMode && hasAiKey && appState != null) {
        // AI path — fetch raw + classify in batches.
        final items = await GmailService.instance.fetchRawForAi(since: since);
        if (items.isNotEmpty) {
          final res = await appState.runAiSync(
            fetch: () async => items,
            onProgress: (_) {},
          );
          if (res.imported > 0) {
            await NotificationsService.instance.showTransactionAlert(
              title: '${res.imported} new transaction${res.imported == 1 ? '' : 's'}',
              body: 'Auto-imported via AI classifier.'
                  '${res.kept > 0 ? ' ${res.kept} low-confidence items in Review.' : ''}',
            );
          }
        }
      } else {
        // Regex path.
        final res = await GmailService.instance.scanInbox(
          since: since,
          maxMessages: 40,
        );
        if (res.imported > 0) {
          await NotificationsService.instance.showTransactionAlert(
            title: '${res.imported} new transaction${res.imported == 1 ? '' : 's'}',
            body: 'Auto-imported from Gmail.'
                '${res.queued > 0 ? ' ${res.queued} waiting in Review.' : ''}',
          );
        }
      }

      await prefs.setInt(_kLastSyncAt, now);
    } catch (_) {
      // silent — the next resume will try again. Items survive in
      // pending_raw_items so nothing is lost.
    } finally {
      _running = false;
    }
  }
}
