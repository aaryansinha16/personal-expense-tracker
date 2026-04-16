import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/db/models.dart';
import 'package:expense_tracker/services/transaction_deduper.dart';

Txn _mk({
  required double amount,
  required DateTime date,
  required String source,
  String type = TxnType.debit,
  String? account,
  String? merchant,
  int? id,
}) =>
    Txn(
      id: id,
      amount: amount,
      type: type,
      date: date,
      source: source,
      account: account,
      merchant: merchant,
    );

void main() {
  group('TransactionDeduper.pickDuplicate', () {
    test('same account + amount + day → duplicate', () {
      final base = DateTime(2026, 4, 13, 1, 46);
      final existing = _mk(
        id: 1,
        amount: 500,
        date: base,
        source: TxnSource.sms,
        account: '2383',
      );
      final candidate = _mk(
        amount: 500,
        date: base.add(const Duration(minutes: 2)),
        source: TxnSource.email,
        account: '2383',
      );
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNotNull);
    });

    test('same normalized merchant + amount + day + type → duplicate', () {
      final base = DateTime(2026, 4, 13, 10);
      final existing = _mk(
        id: 1,
        amount: 500,
        date: base,
        source: TxnSource.sms,
        merchant: 'CANVA* I04848',
      );
      final candidate = _mk(
        amount: 500,
        date: base.add(const Duration(hours: 1)),
        source: TxnSource.email,
        merchant: 'Canva Pty Ltd',
      );
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNotNull);
    });

    test('cross-source same amount/day/type above threshold → duplicate', () {
      final base = DateTime(2026, 4, 13, 12);
      final existing = _mk(id: 1, amount: 500, date: base, source: TxnSource.sms);
      final candidate = _mk(
        amount: 500,
        date: base.add(const Duration(hours: 3)),
        source: TxnSource.email,
      );
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNotNull);
    });

    test('different type → not duplicate', () {
      final base = DateTime(2026, 4, 13, 12);
      final existing = _mk(
        id: 1,
        amount: 500,
        date: base,
        source: TxnSource.sms,
        type: TxnType.debit,
      );
      final candidate = _mk(
        amount: 500,
        date: base.add(const Duration(hours: 2)),
        source: TxnSource.email,
        type: TxnType.credit,
      );
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNull);
    });

    test('different day → not duplicate', () {
      final existing = _mk(
        id: 1,
        amount: 500,
        date: DateTime(2026, 4, 13),
        source: TxnSource.sms,
        account: '2383',
      );
      final candidate = _mk(
        amount: 500,
        date: DateTime(2026, 4, 14),
        source: TxnSource.sms,
        account: '2383',
      );
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNull);
    });

    test('small amounts with no identity info → not duplicate', () {
      final base = DateTime(2026, 4, 13, 12);
      final existing = _mk(id: 1, amount: 50, date: base, source: TxnSource.sms);
      final candidate = _mk(
        amount: 50,
        date: base.add(const Duration(hours: 5)),
        source: TxnSource.email,
      );
      // Below the ₹100 cross-source threshold, no account or merchant match.
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNull);
    });

    test('different amount → not duplicate', () {
      final base = DateTime(2026, 4, 13, 12);
      final existing = _mk(id: 1, amount: 500, date: base, source: TxnSource.sms);
      final candidate = _mk(
        amount: 501,
        date: base,
        source: TxnSource.email,
      );
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNull);
    });
  });
}
