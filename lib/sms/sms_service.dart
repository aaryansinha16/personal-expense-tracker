import 'dart:convert';

import 'package:another_telephony/telephony.dart';

import '../db/database.dart';
import '../db/models.dart';
import '../services/ai_triage.dart';
import '../services/notifications.dart';
import '../services/transaction_deduper.dart';
import 'parser.dart';

String _hashSms(String sender, String body, int? date) {
  // djb2-ish
  final s = '$sender|$body|${date ?? ''}';
  var h = 5381;
  for (var i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.codeUnitAt(i)) & 0x7fffffff;
  }
  return h.toRadixString(16);
}

class SmsService {
  final Telephony _telephony = Telephony.instance;

  Future<bool> requestPermissions() async {
    final ok = await _telephony.requestPhoneAndSmsPermissions;
    return ok ?? false;
  }

  /// Hard cap on how far back we ever scan, regardless of user input.
  static const Duration _maxLookback = Duration(days: 90);

  /// Fetch raw SMS messages from the inbox for the last 90 days (or [since],
  /// whichever is more recent). Used by AI-first sync which classifies
  /// entirely on the LLM side.
  Future<List<SmsMessage>> fetchRaw({DateTime? since}) async {
    final cap = DateTime.now().subtract(_maxLookback);
    final effectiveSince = (since == null || since.isBefore(cap)) ? cap : since;
    return _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(SmsColumn.DATE)
          .greaterThanOrEqualTo(effectiveSince.millisecondsSinceEpoch.toString()),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
  }

  /// Build TriageItems from raw SMS for the AI pipeline, using only the
  /// cheap financial pre-filter (amount + a verb OR a known sender). Does
  /// NOT insert anything; caller handles that via AppState.applyAiDecisions.
  Future<List<TriageItem>> fetchRawForAi({DateTime? since}) async {
    final messages = await fetchRaw(since: since);
    final db = AppDb.instance;
    final items = <TriageItem>[];
    for (final m in messages) {
      final sender = m.address ?? '';
      final body = m.body ?? '';
      if (body.isEmpty) continue;
      final knownSender = SmsParser.isFinancialSender(sender);
      final looksFinancial = SmsParser.looksFinancial(body);
      if (!knownSender && !looksFinancial) continue;
      final ts = m.date ?? DateTime.now().millisecondsSinceEpoch;
      final hash = _hashSms(sender, body, ts);
      if (await db.isSmsProcessed(hash)) continue;
      items.add(TriageItem(
        queueId: -1,
        source: 'sms',
        sender: sender,
        body: body,
      ));
      await db.markSmsProcessed(hash);
    }
    return items;
  }

  /// Scan inbox for historical SMS and import matching ones.
  /// [since] filters by date (inclusive). Clamped at 90 days back.
  Future<ImportResult> scanInbox({DateTime? since}) async {
    final messages = await fetchRaw(since: since);

    int imported = 0;
    int queued = 0;
    int deduped = 0;
    final db = AppDb.instance;

    for (final m in messages) {
      final sender = m.address ?? '';
      final body = m.body ?? '';
      final ts = m.date ?? DateTime.now().millisecondsSinceEpoch;
      if (body.isEmpty) continue;

      final knownSender = SmsParser.isFinancialSender(sender);
      final looksFinancial = SmsParser.looksFinancial(body);
      if (!knownSender && !looksFinancial) continue;

      final hash = _hashSms(sender, body, ts);
      if (await db.isSmsProcessed(hash)) continue;

      final parsed = knownSender ? SmsParser.parse(sender, body) : null;

      if (parsed != null && parsed.isCardPayment) {
        // CC "payment received" SMS is the other side of a bank debit we
        // already recorded. Skip entirely.
        await db.markSmsProcessed(hash);
        continue;
      }

      if (parsed == null || parsed.isBillDue) {
        await db.insertPendingSms(PendingSms(
          sender: sender,
          body: body,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(ts),
        ));
        queued++;
      } else {
        final categoryId = await _autoCategoryId(db, parsed.merchant, parsed.type);
        final candidate = Txn(
          amount: parsed.amount,
          type: parsed.type,
          categoryId: categoryId,
          merchant: parsed.merchant,
          date: DateTime.fromMillisecondsSinceEpoch(ts),
          source: TxnSource.sms,
          rawSms: jsonEncode({'sender': sender, 'body': body}),
          account: parsed.account,
        );
        final dup = await TransactionDeduper.findDuplicate(candidate);
        if (dup != null) {
          deduped++;
        } else {
          await db.insertTxn(candidate);
          imported++;
        }
      }
      await db.markSmsProcessed(hash);
    }

    return ImportResult(
      imported: imported,
      queued: queued,
      deduped: deduped,
      scanned: messages.length,
    );
  }

  /// Register a foreground listener for new SMS.
  void startListener({required void Function() onNewTxn}) {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        final sender = message.address ?? '';
        final body = message.body ?? '';
        if (body.isEmpty) return;

        final knownSender = SmsParser.isFinancialSender(sender);
        final looksFinancial = SmsParser.looksFinancial(body);
        if (!knownSender && !looksFinancial) return;

        final ts = message.date ?? DateTime.now().millisecondsSinceEpoch;
        final hash = _hashSms(sender, body, ts);
        final db = AppDb.instance;
        if (await db.isSmsProcessed(hash)) return;

        final parsed = knownSender ? SmsParser.parse(sender, body) : null;

        if (parsed != null && parsed.isCardPayment) {
          await db.markSmsProcessed(hash);
          return;
        }

        if (parsed == null || parsed.isBillDue) {
          await db.insertPendingSms(PendingSms(
            sender: sender,
            body: body,
            receivedAt: DateTime.fromMillisecondsSinceEpoch(ts),
          ));
        } else {
          final categoryId = await _autoCategoryId(db, parsed.merchant, parsed.type);
          final candidate = Txn(
            amount: parsed.amount,
            type: parsed.type,
            categoryId: categoryId,
            merchant: parsed.merchant,
            date: DateTime.fromMillisecondsSinceEpoch(ts),
            source: TxnSource.sms,
            rawSms: jsonEncode({'sender': sender, 'body': body}),
            account: parsed.account,
          );
          final dup = await TransactionDeduper.findDuplicate(candidate);
          if (dup == null) {
            await db.insertTxn(candidate);
            // Best-effort notification. Failure is silent so the import
            // still succeeds if notifications aren't granted yet.
            try {
              await NotificationsService.instance.showTransactionAlert(
                title: '₹${parsed.amount.toStringAsFixed(0)} ${parsed.type == TxnType.debit ? 'spent' : 'received'}',
                body: parsed.merchant ?? 'New transaction from SMS',
              );
            } catch (_) {}
          }
        }
        await db.markSmsProcessed(hash);
        onNewTxn();
      },
      listenInBackground: false,
    );
  }

  Future<int?> _autoCategoryId(
    AppDb db,
    String? merchant,
    String type,
  ) async {
    final cats = await db.listCategories();
    if (type == TxnType.credit) {
      return cats.firstWhere(
        (c) => c.name == 'Income',
        orElse: () => cats.firstWhere((c) => c.name == 'Other', orElse: () => cats.first),
      ).id;
    }
    if (merchant == null) return null;
    final low = merchant.toLowerCase();
    final mm = await db.listMerchantMap();
    for (final m in mm) {
      if (low.contains(m.pattern)) return m.categoryId;
    }
    final rules = <RegExp, String>{
      RegExp(r'swiggy|zomato|dominos|mcd|kfc|pizza|eatsure'): 'Food & Dining',
      RegExp(r'bigbasket|blinkit|zepto|grofers|instamart|dmart'): 'Groceries',
      RegExp(r'uber|ola|rapido|irctc|redbus|indigo|metro'): 'Transport',
      RegExp(r'amazon|flipkart|myntra|ajio|meesho|nykaa'): 'Shopping',
      RegExp(r'netflix|spotify|hotstar|prime|jio ?saavn|youtube'): 'Entertainment',
      RegExp(r'electricity|bescom|tneb|msedcl|airtel|jio|vodafone|vi |gas'): 'Bills & Utilities',
      RegExp(r'pharmacy|apollo|medplus|1mg|pharmeasy|hospital|clinic'): 'Health',
    };
    for (final e in rules.entries) {
      if (e.key.hasMatch(low)) {
        return cats.firstWhere((c) => c.name == e.value, orElse: () => cats.first).id;
      }
    }
    return null;
  }
}

class ImportResult {
  final int imported;
  final int queued;
  final int deduped;
  final int scanned;
  ImportResult({
    required this.imported,
    required this.queued,
    required this.scanned,
    this.deduped = 0,
  });
}
