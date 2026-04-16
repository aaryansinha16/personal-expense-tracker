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

    test('tiny amounts with no identity info → not duplicate', () {
      final base = DateTime(2026, 4, 13, 12);
      final existing = _mk(id: 1, amount: 5, date: base, source: TxnSource.sms);
      final candidate = _mk(
        amount: 5,
        date: base.add(const Duration(hours: 5)),
        source: TxnSource.email,
      );
      // Below the ₹10 cross-source threshold, no account or merchant match.
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNull);
    });

    test('₹10 cross-source with no identity info → duplicate', () {
      // At the threshold — should collapse. Real user case: a ₹10 UPI
      // transaction arrives as one SMS and one merchant email, both
      // without a usable account/merchant match.
      final base = DateTime(2026, 4, 13, 12);
      final existing = _mk(id: 1, amount: 10, date: base, source: TxnSource.sms);
      final candidate = _mk(
        amount: 10,
        date: base.add(const Duration(minutes: 5)),
        source: TxnSource.email,
      );
      expect(TransactionDeduper.pickDuplicate(candidate, [existing]), isNotNull);
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

    test('CC-bill-pair: bank debit + CC-credit merchant → duplicate', () {
      final base = DateTime(2026, 4, 13, 12);
      final bankDebit = _mk(
        id: 1,
        amount: 15000,
        date: base,
        type: TxnType.debit,
        source: TxnSource.sms,
        merchant: 'cred@axis',
      );
      final ccCredit = _mk(
        amount: 15000,
        date: base.add(const Duration(minutes: 3)),
        type: TxnType.credit,
        source: TxnSource.sms,
        merchant: 'HDFC Card',
      );
      expect(
        TransactionDeduper.pickDuplicate(ccCredit, [bankDebit]),
        isNotNull,
      );
    });

    test('CC-bill-pair: plain credit (not to a card) → not duplicate', () {
      // Someone actually sent you ₹500 — salary, refund from a person, etc.
      // Same day, same amount as a prior debit, different types. Should NOT
      // be classified as a CC pair because the merchant isn't a card.
      final base = DateTime(2026, 4, 13, 12);
      final debit = _mk(
        id: 1,
        amount: 500,
        date: base,
        type: TxnType.debit,
        source: TxnSource.sms,
        merchant: 'Swiggy',
      );
      final credit = _mk(
        amount: 500,
        date: base.add(const Duration(hours: 2)),
        type: TxnType.credit,
        source: TxnSource.sms,
        merchant: 'Salary ACME Inc',
      );
      expect(
        TransactionDeduper.pickDuplicate(credit, [debit]),
        isNull,
      );
    });

    test('same merchant + same day across types stays separate '
        'unless CC pair', () {
      // Catches a regression: same merchant + different type shouldn't
      // dedupe as same-merchant rule (that's same-type only).
      final base = DateTime(2026, 4, 13, 12);
      final debit = _mk(
        id: 1,
        amount: 500,
        date: base,
        type: TxnType.debit,
        source: TxnSource.sms,
        merchant: 'Swiggy',
      );
      final credit = _mk(
        amount: 500,
        date: base,
        type: TxnType.credit,
        source: TxnSource.sms,
        merchant: 'Swiggy',
      );
      expect(
        TransactionDeduper.pickDuplicate(credit, [debit]),
        isNull,
      );
    });
  });
}
