import 'package:shared_preferences/shared_preferences.dart';

/// App-wide sync preferences persisted to shared_preferences.
class SyncPrefs {
  static const _kAiMode = 'pref_ai_sync_mode';

  static Future<bool> aiMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAiMode) ?? false;
  }

  static Future<void> setAiMode(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAiMode, v);
  }
}
