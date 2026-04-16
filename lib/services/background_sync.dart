import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../email/gmail_service.dart';
import '../email/sender_registry.dart';
import 'notifications.dart';

/// Auto-sync-on-resume. When the user brings the app to the foreground
/// after at least [minGap], we silently run a short Gmail scan and fire a
/// notification if anything new landed.
///
/// This replaces WorkManager. Modern Android aggressively restricts true
/// background work for a Flutter app, and on-resume has the added benefit
/// of being deterministic and battery-friendly.
class BackgroundSync with WidgetsBindingObserver {
  static final BackgroundSync instance = BackgroundSync._();
  BackgroundSync._();

  static const _kLastSyncAt = 'pref_last_auto_sync_ms';
  static const _minGap = Duration(minutes: 15);

  bool _enabled = false;
  bool _attached = false;
  bool _running = false;

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
      await prefs.setInt(_kLastSyncAt, now);
    } catch (_) {
      // silent — the next resume will try again.
    } finally {
      _running = false;
    }
  }
}
