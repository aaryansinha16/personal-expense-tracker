import '../db/database.dart';
import '../db/models.dart';

/// Decides whether an incoming transaction is the same underlying event as
/// something already in the database.
///
/// Pure logic lives in [isDuplicate] so it's unit-testable without a DB.
class TransactionDeduper {
  /// Returns the existing duplicate from `existing` if one exists, else null.
  static Txn? pickDuplicate(Txn candidate, Iterable<Txn> existing) {
    for (final e in existing) {
      if (!_sameCalendarDay(e.date, candidate.date)) continue;
      if (_isDuplicate(e, candidate)) return e;
    }
    return null;
  }

  /// DB-backed convenience: narrow the search with a ±1 day SQL window then
  /// defer to [pickDuplicate] for the actual decision.
  static Future<Txn?> findDuplicate(Txn candidate) async {
    final db = AppDb.instance;
    final start = candidate.date.subtract(const Duration(days: 1));
    final end = candidate.date.add(const Duration(days: 1));
    final d = await db.db;
    final rows = await d.query(
      'transactions',
      where: 'amount = ? AND date >= ? AND date <= ?',
      whereArgs: [
        candidate.amount,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
    );
    return pickDuplicate(candidate, rows.map(Txn.fromMap));
  }

  static bool _isDuplicate(Txn a, Txn b) {
    if (a.id != null && b.id != null && a.id == b.id) return false;
    if (a.amount != b.amount) return false;

    final sameType = a.type == b.type;
    final accountMatch =
        a.account != null && b.account != null && a.account == b.account;
    final merchantMatch = _merchantMatches(a.merchant, b.merchant);

    // CC-bill-pair: one side is a bank debit, the other a CC credit. Same
    // amount, same day, different types, and one is tagged as a card
    // payment (via merchant or sms-parser flag encoded in note). Collapse
    // the pair by treating the credit as a duplicate of the debit.
    if (!sameType) {
      final debit = a.type == TxnType.debit ? a : b;
      final credit = a.type == TxnType.credit ? a : b;
      if (_looksLikeCardPayment(credit) && debit.amount == credit.amount) {
        return true;
      }
      return false;
    }

    // Strong: same account + same amount + same day.
    if (accountMatch) return true;

    // Strong: same merchant + same amount + same day + same type.
    if (merchantMatch) return true;

    // Cross-source heuristic: different sources, same amount + day + type,
    // amount above a coincidence threshold.
    if (a.source != b.source && b.amount >= 100) return true;

    return false;
  }

  static bool _looksLikeCardPayment(Txn t) {
    final m = t.merchant?.toLowerCase() ?? '';
    final n = t.note?.toLowerCase() ?? '';
    if (n.contains('card-payment') || n.contains('card payment')) return true;
    if (m.contains('credit card') || m.contains('card payment')) return true;
    // Merchant is often a card issuer display name when isCardPayment was
    // set in the parser.
    const cardIssuers = ['hdfc card', 'sbi card', 'icici card', 'axis card', 'amex', 'onecard', 'cred'];
    return cardIssuers.any(m.contains);
  }

  static bool _sameCalendarDay(DateTime x, DateTime y) =>
      x.year == y.year && x.month == y.month && x.day == y.day;

  static bool _merchantMatches(String? a, String? b) {
    if (a == null || b == null) return false;
    final na = _normalize(a);
    final nb = _normalize(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.length >= 4 && nb.contains(na)) return true;
    if (nb.length >= 4 && na.contains(nb)) return true;
    return false;
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .trim();
  }
}
