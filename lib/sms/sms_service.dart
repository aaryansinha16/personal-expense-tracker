import 'dart:convert';

import 'package:another_telephony/telephony.dart';

import '../db/database.dart';
import '../db/models.dart';
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

  /// Scan inbox for historical SMS and import matching ones.
  /// Returns count of new transactions added and SMS pushed to review queue.
  Future<ImportResult> scanInbox({DateTime? since}) async {
    final messages = await _telephony.getInboxSms(
      columns: [
        SmsColumn.ADDRESS,
        SmsColumn.BODY,
        SmsColumn.DATE,
      ],
      filter: since != null
          ? (SmsFilter.where(SmsColumn.DATE)
              .greaterThanOrEqualTo(since.millisecondsSinceEpoch.toString()))
          : null,
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    int imported = 0;
    int queued = 0;
    final db = AppDb.instance;

    for (final m in messages) {
      final sender = m.address ?? '';
      final body = m.body ?? '';
      final ts = m.date ?? DateTime.now().millisecondsSinceEpoch;
      if (body.isEmpty) continue;
      if (!SmsParser.isFinancialSender(sender)) continue;

      final hash = _hashSms(sender, body, ts);
      if (await db.isSmsProcessed(hash)) continue;

      final parsed = SmsParser.parse(sender, body);
      if (parsed == null) {
        await db.insertPendingSms(PendingSms(
          sender: sender,
          body: body,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(ts),
        ));
        queued++;
      } else {
        // Bill-due SMS: we don't record as a txn, just notify later (TODO).
        if (!parsed.isBillDue) {
          final categoryId = await _autoCategoryId(db, parsed.merchant, parsed.type);
          await db.insertTxn(Txn(
            amount: parsed.amount,
            type: parsed.type,
            categoryId: categoryId,
            merchant: parsed.merchant,
            date: DateTime.fromMillisecondsSinceEpoch(ts),
            source: TxnSource.sms,
            rawSms: jsonEncode({'sender': sender, 'body': body}),
            account: parsed.account,
          ));
          imported++;
        }
      }
      await db.markSmsProcessed(hash);
    }

    return ImportResult(imported: imported, queued: queued, scanned: messages.length);
  }

  /// Register a foreground listener for new SMS.
  void startListener({required void Function() onNewTxn}) {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        final sender = message.address ?? '';
        final body = message.body ?? '';
        if (body.isEmpty) return;
        if (!SmsParser.isFinancialSender(sender)) return;

        final ts = message.date ?? DateTime.now().millisecondsSinceEpoch;
        final hash = _hashSms(sender, body, ts);
        final db = AppDb.instance;
        if (await db.isSmsProcessed(hash)) return;

        final parsed = SmsParser.parse(sender, body);
        if (parsed == null) {
          await db.insertPendingSms(PendingSms(
            sender: sender,
            body: body,
            receivedAt: DateTime.fromMillisecondsSinceEpoch(ts),
          ));
        } else if (!parsed.isBillDue) {
          final categoryId = await _autoCategoryId(db, parsed.merchant, parsed.type);
          await db.insertTxn(Txn(
            amount: parsed.amount,
            type: parsed.type,
            categoryId: categoryId,
            merchant: parsed.merchant,
            date: DateTime.fromMillisecondsSinceEpoch(ts),
            source: TxnSource.sms,
            rawSms: jsonEncode({'sender': sender, 'body': body}),
            account: parsed.account,
          ));
        }
        await db.markSmsProcessed(hash);
        onNewTxn();
      },
      listenInBackground: false,
    );
  }

  Future<int?> _autoCategoryId(AppDb db, String? merchant, String type) async {
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
    // Heuristics for common UPI merchants
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
  final int scanned;
  ImportResult({required this.imported, required this.queued, required this.scanned});
}
