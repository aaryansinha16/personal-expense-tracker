import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../db/database.dart';
import '../db/models.dart';
import 'parser.dart';
import 'sender_registry.dart';

class GmailImportResult {
  final int scanned;
  final int imported;
  final int skipped;
  final String? error;
  const GmailImportResult({
    required this.scanned,
    required this.imported,
    required this.skipped,
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
        final parsed = _parseFull(full);

        if (parsed != null) {
          final categoryId = await _categoryFor(db, parsed.categoryHint);
          await db.insertTxn(Txn(
            amount: parsed.amount,
            type: parsed.type,
            categoryId: categoryId,
            merchant: parsed.merchant,
            date: _messageDate(full),
            source: TxnSource.email,
            note: parsed.orderId != null ? 'order:${parsed.orderId}' : null,
          ));
          imported++;
        } else {
          skipped++;
        }
        await db.markEmailProcessed(id);
      }

      return GmailImportResult(
        scanned: msgs.length,
        imported: imported,
        skipped: skipped,
      );
    } catch (e) {
      return GmailImportResult(scanned: 0, imported: 0, skipped: 0, error: e.toString());
    } finally {
      client.close();
    }
  }

  String _buildQuery(DateTime? since) {
    final base = SenderRegistry.instance.gmailQuery();
    if (since == null) return base;
    final ts = (since.millisecondsSinceEpoch ~/ 1000);
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

  ParsedEmail? _parseFull(gmail.Message full) {
    final headers = full.payload?.headers ?? const [];
    String sender = '';
    String subject = '';
    for (final h in headers) {
      final name = (h.name ?? '').toLowerCase();
      if (name == 'from') sender = h.value ?? '';
      else if (name == 'subject') subject = h.value ?? '';
    }
    final body = _extractBody(full.payload);
    return EmailParser.parse(sender, subject, body);
  }

  String _extractBody(gmail.MessagePart? part) {
    if (part == null) return '';
    // Prefer text/plain, then text/html, then recurse into parts.
    final mime = part.mimeType ?? '';
    if ((mime == 'text/plain' || mime == 'text/html') && part.body?.data != null) {
      return _decode(part.body!.data!);
    }
    final sub = part.parts ?? const [];
    // Prefer plain
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
