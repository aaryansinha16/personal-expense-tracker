import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications.
class NotificationsService {
  static final NotificationsService instance = NotificationsService._();
  NotificationsService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> showTransactionAlert({
    required String title,
    required String body,
    int id = 1,
  }) async {
    const android = AndroidNotificationDetails(
      'txn_alerts',
      'Transaction alerts',
      channelDescription: 'New auto-imported transactions',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: android),
    );
  }

  Future<void> showBudgetAlert({required String body, int id = 2}) async {
    const android = AndroidNotificationDetails(
      'budget_alerts',
      'Budget alerts',
      channelDescription: 'Overspend and budget threshold warnings',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      id,
      'Daily budget alert',
      body,
      const NotificationDetails(android: android),
    );
  }
}
