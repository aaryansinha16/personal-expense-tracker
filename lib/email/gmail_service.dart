import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../db/database.dart';
import '../db/models.dart';
import '../services/transaction_deduper.dart';
import '../services/ai_triage.dart';
import 'parser.dart';
import 'sender_registry.dart';

class GmailImportResult {
  final int scanned;
  final int imported;
  final int queued;
  final int deduped;
  final int skipped;
  final String? error;
  const GmailImportResult({
    required this.scanned,
    required this.imported,
    required this.skipped,
    this.queued = 0,
    this.deduped = 0,
    this.error,
  });
}

/// Gmail OAuth + message polling. Android auth is matched by package name and
/// keystore SHA-1 configured in the user's Google Cloud Console OAuth client;
/// no client ID is bundled with the app.
class GmailService {
  static final GmailService instance = GmailService._();
  GmailService._();

  final _signIn = GoogleSignIn(
    scopes: <String>[gmail.GmailApi.gmailReadonlyScope],
  );

  GoogleSignInAccount? get currentUser => _signIn.currentUser;

  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _signIn.signIn();
      return account;
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() => _signIn.signOut();

  Future<GoogleSignInAccount?> signInSilently() => _signIn.signInSilently();

  /// Pulls matching messages from Gmail and pipes them into the parser.
  /// Each new transaction is inserted. Returns counts for the status UI.
  Future<GmailImportResult> scanInbox({DateTime? since, int maxMessages = 100}) async {
    final account = _signIn.currentUser ?? await _signIn.signInSilently();
    if (account == null) {
      return const GmailImportResult(scanned: 0, imported: 0, skipped: 0, error: 'Not signed in');
    }
    final client = await _signIn.authenticatedClient();
    if (client == null) {
      return const GmailImportResult(scanned: 0, imported: 0, skipped: 0, error: 'Auth failed');
    }

    try {
      final api = gmail.GmailApi(client);
      final query = _buildQuery(since);

      // List matching message IDs.
      final list = await api.users.messages.list(
        'me',
        q: query,
        maxResults: maxMessages,
      );
      final msgs = list.messages ?? const [];

      int imported = 0;
      int queued = 0;
      int deduped = 0;
      int skipped = 0;
      final db = AppDb.instance;

      for (final m in msgs) {
        final id = m.id;
        if (id == null) continue;
        if (await db.isEmailProcessed(id)) {
          skipped++;
          continue;
        }

        final full = await api.users.messages.get('me', id, format: 'full');
        final headers = full.payload?.headers ?? const [];
        String sender = '';
        String subject = '';
        for (final h in headers) {
          final name = (h.name ?? '').toLowerCase();
          if (name == 'from') {
            sender = h.value ?? '';
          } else if (name == 'subject') {
            subject = h.value ?? '';
          }
        }
        final body = _extractBody(full.payload);
        final parsed = EmailParser.parse(sender, subject, body);

        if (parsed != null) {
          final categoryId = await _categoryFor(db, parsed.categoryHint);
          final candidate = Txn(
            amount: parsed.amount,
            type: parsed.type,
            categoryId: categoryId,
            merchant: parsed.merchant,
            date: _messageDate(full),
            source: TxnSource.email,
            note: parsed.orderId != null ? 'order:${parsed.orderId}' : null,
          );
          final dup = await TransactionDeduper.findDuplicate(candidate);
          if (dup != null) {
            deduped++;
          } else {
            await db.insertTxn(candidate);
            imported++;
          }
        } else if (_shouldQueueForReview(sender, subject, body)) {
          // Known-sender email that failed parsing — queue with a reason so
          // the user can triage instead of losing it silently.
          await db.insertPendingEmail(PendingEmail(
            messageId: id,
            sender: sender,
            subject: subject.isEmpty ? null : subject,
            body: body,
            receivedAt: _messageDate(full),
            reason: _rejectReason(sender, subject, body),
          ));
          queued++;
        } else {
          skipped++;
        }
        await db.markEmailProcessed(id);
      }

      return GmailImportResult(
        scanned: msgs.length,
        imported: imported,
        queued: queued,
        deduped: deduped,
        skipped: skipped,
      );
    } catch (e) {
      return GmailImportResult(scanned: 0, imported: 0, skipped: 0, error: e.toString());
    } finally {
      client.close();
    }
  }

  /// Hard cap on how far back we ever scan.
  static const Duration _maxLookback = Duration(days: 90);

  /// Fetch raw messages as TriageItems for the AI pipeline. Does NOT
  /// insert anything into the DB; the caller is responsible for that via
  /// AppState.applyAiDecisions.
  Future<List<TriageItem>> fetchRawForAi({
    DateTime? since,
    int maxMessages = 200,
    void Function(int fetched, int total)? onProgress,
    int concurrency = 10,
  }) async {
    final account = _signIn.currentUser ?? await _signIn.signInSilently();
    if (account == null) {
      throw StateError('Not signed in to Gmail');
    }
    final client = await _signIn.authenticatedClient();
    if (client == null) throw StateError('Gmail auth failed');

    try {
      final api = gmail.GmailApi(client);
      final db = AppDb.instance;

      // 1) Resume any items cached from a previous failed sync. Zero cost,
      // zero Gmail API calls.
      final cached = <TriageItem>[];
      final cachedIds = <String>{};
      for (final row in await db.listPendingRawItems()) {
        if ((row['source'] as String?) != 'email') continue;
        final sid = row['source_id'] as String;
        cachedIds.add(sid);
        cached.add(TriageItem(
          queueId: -1,
          source: 'email',
          sender: row['sender'] as String,
          subject: row['subject'] as String?,
          body: row['body'] as String,
          sourceId: sid,
          sourceDate: DateTime.fromMillisecondsSinceEpoch(row['received_at'] as int),
        ));
      }

      // 2) List fresh Gmail IDs and skip ones we already have cached or
      // already processed.
      final list = await api.users.messages.list(
        'me',
        q: _buildQuery(since),
        maxResults: maxMessages,
      );
      final msgs = list.messages ?? const [];
      final needed = <String>[];
      for (final m in msgs) {
        final id = m.id;
        if (id == null) continue;
        if (cachedIds.contains(id)) continue;
        if (await db.isEmailProcessed(id)) continue;
        needed.add(id);
      }
      final totalFresh = needed.length;
      final totalOverall = totalFresh + cached.length;

      if (totalFresh == 0) {
        onProgress?.call(cached.length, totalOverall);
        return cached;
      }

      // 3) Fetch bodies in parallel windows, caching each as we go.
      final items = <TriageItem>[...cached];
      var fetched = 0;
      for (var start = 0; start < totalFresh; start += concurrency) {
        final end = (start + concurrency).clamp(0, totalFresh);
        final chunk = needed.sublist(start, end);
        final fulls = await Future.wait(
          chunk.map((id) => api.users.messages.get('me', id, format: 'full')),
        );
        for (var i = 0; i < fulls.length; i++) {
          final full = fulls[i];
          final id = chunk[i];
          final headers = full.payload?.headers ?? const [];
          String sender = '';
          String subject = '';
          for (final h in headers) {
            final name = (h.name ?? '').toLowerCase();
            if (name == 'from') {
              sender = h.value ?? '';
            } else if (name == 'subject') {
              subject = h.value ?? '';
            }
          }
          final body = _extractBody(full.payload);
          final date = _messageDate(full);
          items.add(TriageItem(
            queueId: -1,
            source: 'email',
            sender: sender,
            subject: subject.isEmpty ? null : subject,
            body: body,
            sourceId: id,
            sourceDate: date,
          ));
          // Cache as we go — survives app-kill mid-fetch.
          await db.insertPendingRawItem(
            source: 'email',
            sourceId: id,
            sender: sender,
            subject: subject.isEmpty ? null : subject,
            body: body,
            receivedAt: date,
          );
        }
        fetched += chunk.length;
        onProgress?.call(cached.length + fetched, totalOverall);
      }

      return items;
    } finally {
      client.close();
    }
  }

  String _buildQuery(DateTime? since) {
    final base = SenderRegistry.instance.gmailQuery();
    final cap = DateTime.now().subtract(_maxLookback);
    final effective = (since == null || since.isBefore(cap)) ? cap : since;
    final ts = (effective.millisecondsSinceEpoch ~/ 1000);
    return '$base after:$ts';
  }

  DateTime _messageDate(gmail.Message full) {
    final ms = full.internalDate;
    if (ms != null) {
      final n = int.tryParse(ms);
      if (n != null) return DateTime.fromMillisecondsSinceEpoch(n);
    }
    return DateTime.now();
  }

  /// Decide whether a rejected email is worth surfacing to the user vs
  /// dropping silently. We queue when the sender is a known merchant /
  /// bank and the body contains a currency amount (i.e. it COULD have been
  /// a transaction) so the user can triage Axis-like cases.
  bool _shouldQueueForReview(String sender, String subject, String body) {
    final domain = _extractDomain(sender);
    final knownSender = SenderRegistry.instance.match(domain) != null;
    if (!knownSender) return false;
    // Must at least contain a rupee amount to be worth queueing.
    return RegExp(r'(?:rs\.?|inr|₹)\s*[0-9]', caseSensitive: false)
        .hasMatch('$subject\n$body');
  }

  String _rejectReason(String sender, String subject, String body) {
    final search = '$subject\n$body'.toLowerCase();
    if (RegExp(r'\botp\b|verification\s*code').hasMatch(search)) {
      return 'looks like an OTP';
    }
    if (search.contains('unsubscribe') ||
        RegExp(r'\b(offer|deal|discount|sale|flat\s+\d+%)\b').hasMatch(search)) {
      return 'promotional content';
    }
    if (RegExp(r'\b(shipped|out\s+for\s+delivery|delivered)\b').hasMatch(search)) {
      return 'delivery update';
    }
    if (RegExp(r'\b(upcoming|will\s+be\s+debited|scheduled)\b').hasMatch(search)) {
      return 'upcoming payment notice';
    }
    if (!RegExp(r'\b(paid|payment|debited|credited|refund|purchase|charged)\b')
        .hasMatch(search)) {
      return 'no transaction verb';
    }
    return 'parser rejected';
  }

  String _extractDomain(String sender) {
    final m = RegExp(r'<([^>]+@([^>]+))>').firstMatch(sender);
    if (m != null) return m.group(2)!.trim().toLowerCase();
    final m2 = RegExp(r'([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+)').firstMatch(sender);
    if (m2 != null) return m2.group(2)!.trim().toLowerCase();
    return sender.toLowerCase();
  }

  String _extractBody(gmail.MessagePart? part) {
    if (part == null) return '';
    final mime = part.mimeType ?? '';
    if ((mime == 'text/plain' || mime == 'text/html') && part.body?.data != null) {
      final raw = _decode(part.body!.data!);
      // HTML bodies are mostly markup — strip tags so Claude sees actual
      // text within the 1500-char window.
      return mime == 'text/html' ? _stripHtml(raw) : raw;
    }
    final sub = part.parts ?? const [];
    for (final p in sub) {
      if ((p.mimeType ?? '') == 'text/plain') {
        final b = _extractBody(p);
        if (b.isNotEmpty) return b;
      }
    }
    for (final p in sub) {
      if ((p.mimeType ?? '') == 'text/html') {
        final b = _extractBody(p);
        if (b.isNotEmpty) return b;
      }
    }
    for (final p in sub) {
      final b = _extractBody(p);
      if (b.isNotEmpty) return b;
    }
    return '';
  }

  static String _stripHtml(String s) {
    if (!s.contains('<')) return s;
    var out = s
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&rsquo;': "'",
      '&lsquo;': "'",
      '&rupee;': '₹',
      '&#8377;': '₹',
    };
    entities.forEach((k, v) => out = out.replaceAll(k, v));
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _decode(String urlSafeB64) {
    // Gmail base64url encoding may omit padding.
    var s = urlSafeB64.replaceAll('-', '+').replaceAll('_', '/');
    final pad = s.length % 4;
    if (pad > 0) s = s.padRight(s.length + (4 - pad), '=');
    try {
      return utf8.decode(base64.decode(s), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  Future<int?> _categoryFor(AppDb db, String? hint) async {
    if (hint == null) return null;
    final cats = await db.listCategories();
    return cats
        .firstWhere(
          (c) => c.name == hint,
          orElse: () =>
              cats.firstWhere((c) => c.name == 'Other', orElse: () => cats.first),
        )
        .id;
  }
}
