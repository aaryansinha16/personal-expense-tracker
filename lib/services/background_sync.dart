import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../email/gmail_service.dart';
import '../email/sender_registry.dart';
import 'notifications.dart';

const _gmailSyncTask = 'gmail-periodic-sync';
const _gmailSyncUniqueName = 'gmail-periodic';

/// Entry point invoked by the WorkManager engine in a background isolate.
/// Keep it self-contained — it runs without the Flutter UI.
@pragma('vm:entry-point')
void bgDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName != _gmailSyncTask) return true;
    try {
      await SenderRegistry.instance.load();
      await NotificationsService.instance.init();

      final since = DateTime.now().subtract(const Duration(hours: 2));
      final res = await GmailService.instance.scanInbox(
        since: since,
        maxMessages: 40,
      );
      if (res.imported > 0) {
        await NotificationsService.instance.showTransactionAlert(
          title: '${res.imported} new transaction${res.imported == 1 ? '' : 's'}',
          body: 'Auto-imported from Gmail. '
              '${res.queued > 0 ? '${res.queued} waiting in Review.' : ''}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('bgDispatcher error: $e');
      }
    }
    return true;
  });
}

class BackgroundSync {
  static final BackgroundSync instance = BackgroundSync._();
  BackgroundSync._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(bgDispatcher, isInDebugMode: false);
    _initialized = true;
  }

  Future<void> enablePeriodicSync({
    Duration frequency = const Duration(minutes: 15),
  }) async {
    await initialize();
    // Android minimum periodic frequency is 15 minutes; values lower than
    // that are clamped up by the platform.
    final freq = frequency < const Duration(minutes: 15)
        ? const Duration(minutes: 15)
        : frequency;
    await Workmanager().registerPeriodicTask(
      _gmailSyncUniqueName,
      _gmailSyncTask,
      frequency: freq,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  Future<void> disable() async {
    await Workmanager().cancelByUniqueName(_gmailSyncUniqueName);
  }
}
