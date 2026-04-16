import '../db/database.dart';
import 'sender_rules.dart';

class EmailSender {
  final int id;
  final String domainSuffix;
  final String displayName;
  final String? categoryHint;
  final bool isDefault;
  final bool enabled;

  const EmailSender({
    required this.id,
    required this.domainSuffix,
    required this.displayName,
    required this.categoryHint,
    required this.isDefault,
    required this.enabled,
  });

  factory EmailSender.fromMap(Map<String, Object?> m) => EmailSender(
        id: m['id'] as int,
        domainSuffix: (m['domain_suffix'] as String).toLowerCase(),
        displayName: m['display_name'] as String,
        categoryHint: m['category_hint'] as String?,
        isDefault: ((m['is_default'] as int?) ?? 0) == 1,
        enabled: ((m['enabled'] as int?) ?? 1) == 1,
      );
}

/// In-memory, refresh-on-write sender list. Backed by the `email_senders`
/// SQLite table. Seeds built-in defaults from [SenderRules.defaults] on the
/// first call — subsequent app updates that ship new defaults automatically
/// upsert them without overwriting the user's toggles.
class SenderRegistry {
  static final SenderRegistry instance = SenderRegistry._();
  SenderRegistry._();

  final AppDb _db = AppDb.instance;
  List<EmailSender> _all = const [];

  List<EmailSender> get all => List.unmodifiable(_all);

  /// Enabled senders only. Used by the parser and the Gmail scanner.
  List<EmailSender> get enabled => _all.where((s) => s.enabled).toList();

  bool _initialized = false;

  Future<void> load() async {
    // First-time: seed all shipped defaults. If a default already exists
    // in the table (user has toggled it), the ignore conflict policy keeps
    // their choice.
    for (final r in SenderRules.defaults) {
      await _db.seedDefaultSenderIfMissing(
        domainSuffix: r.domainSuffix,
        displayName: r.displayName,
        categoryHint: r.category,
      );
    }
    await _refresh();
    _initialized = true;
  }

  Future<void> _refresh() async {
    final rows = await _db.listEmailSenders();
    _all = rows.map(EmailSender.fromMap).toList();
  }

  /// Match an email domain against the enabled rules. Longer suffixes win
  /// so a `hdfcbank.net` row is preferred over a more generic match.
  /// Falls back to the static seed list when the registry hasn't been
  /// loaded yet — makes the parser usable in tests and during cold-start.
  EmailSender? match(String domain) {
    final d = domain.toLowerCase();
    if (_initialized) {
      EmailSender? best;
      for (final s in _all) {
        if (!s.enabled) continue;
        final suffix = s.domainSuffix;
        if (d == suffix || d.endsWith('.$suffix') || d.endsWith(suffix)) {
          if (best == null || suffix.length > best.domainSuffix.length) {
            best = s;
          }
        }
      }
      return best;
    }
    // Fallback: static seed list.
    SenderRule? best;
    for (final r in SenderRules.defaults) {
      final suffix = r.domainSuffix;
      if (d == suffix || d.endsWith('.$suffix') || d.endsWith(suffix)) {
        if (best == null || suffix.length > best.domainSuffix.length) {
          best = r;
        }
      }
    }
    if (best == null) return null;
    return EmailSender(
      id: -1,
      domainSuffix: best.domainSuffix,
      displayName: best.displayName,
      categoryHint: best.category,
      isDefault: true,
      enabled: true,
    );
  }

  /// Gmail query built from ENABLED senders only, plus OTP/verification
  /// exclusions.
  String gmailQuery() {
    final suffixes = _initialized
        ? _all.where((s) => s.enabled).map((s) => s.domainSuffix).toList()
        : SenderRules.defaults.map((r) => r.domainSuffix).toList();
    if (suffixes.isEmpty) {
      return '-subject:otp -subject:"verification code"';
    }
    final fromClauses = suffixes.map((s) => 'from:$s').join(' OR ');
    return '($fromClauses) -subject:otp -subject:"verification code"';
  }

  Future<void> toggle(int id, bool value) async {
    await _db.setEmailSenderEnabled(id, value);
    await _refresh();
  }

  Future<void> upsert({
    int? id,
    required String domainSuffix,
    required String displayName,
    String? categoryHint,
  }) async {
    await _db.upsertEmailSender(
      id: id,
      domainSuffix: domainSuffix.toLowerCase().trim(),
      displayName: displayName.trim(),
      categoryHint: categoryHint,
      isDefault: false,
      enabled: true,
    );
    await _refresh();
  }

  Future<void> remove(int id) async {
    await _db.deleteEmailSender(id);
    await _refresh();
  }
}
