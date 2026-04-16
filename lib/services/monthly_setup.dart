import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';
import '../db/models.dart';

class MonthlySetup {
  static const _kIncome = 'monthly_income';
  static const _kSavings = 'monthly_savings_target';

  final double monthlyIncome;
  final double savingsTarget;
  final List<RecurringExpense> recurring;

  MonthlySetup({
    required this.monthlyIncome,
    required this.savingsTarget,
    required this.recurring,
  });

  double get fixedTotal => recurring.where((r) => r.active).fold(0, (s, r) => s + r.amount);

  /// Discretionary budget for the month.
  double get monthlyDiscretionary =>
      (monthlyIncome - savingsTarget - fixedTotal).clamp(0, double.infinity).toDouble();

  bool get isConfigured => monthlyIncome > 0;
}

class MonthlySetupService {
  static final MonthlySetupService instance = MonthlySetupService._();
  MonthlySetupService._();

  Future<MonthlySetup> load() async {
    final prefs = await SharedPreferences.getInstance();
    final income = prefs.getDouble(MonthlySetup._kIncome) ?? 0;
    final savings = prefs.getDouble(MonthlySetup._kSavings) ?? 0;
    final recurring = await AppDb.instance.listRecurringExpenses();
    return MonthlySetup(
      monthlyIncome: income,
      savingsTarget: savings,
      recurring: recurring,
    );
  }

  Future<void> setIncome(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(MonthlySetup._kIncome, v);
  }

  Future<void> setSavingsTarget(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(MonthlySetup._kSavings, v);
  }

  /// For each active recurring expense whose day_of_month has passed in the
  /// current month, insert a transaction if one hasn't been posted already
  /// this month. Safe to call repeatedly.
  Future<int> autoPostDueRecurring({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final monthStart = DateTime(today.year, today.month, 1);
    final monthEnd = DateTime(today.year, today.month + 1, 1).subtract(const Duration(milliseconds: 1));
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;

    final db = AppDb.instance;
    final recurring = await db.listRecurringExpenses(onlyActive: true);
    final existing = await db.listTxns(from: monthStart, to: monthEnd);

    int posted = 0;
    for (final r in recurring) {
      final effectiveDay = r.dayOfMonth > daysInMonth ? daysInMonth : r.dayOfMonth;
      final due = DateTime(today.year, today.month, effectiveDay);
      if (due.isAfter(today)) continue;

      final alreadyPosted = existing.any((t) =>
          t.source == TxnSource.manual &&
          t.note == _noteTag(r.id!) &&
          t.date.year == today.year &&
          t.date.month == today.month);
      if (alreadyPosted) continue;

      await db.insertTxn(Txn(
        amount: r.amount,
        type: TxnType.debit,
        categoryId: r.categoryId,
        merchant: r.name,
        date: due,
        source: TxnSource.manual,
        note: _noteTag(r.id!),
      ));
      posted++;
    }
    return posted;
  }

  static String _noteTag(int recurringId) => 'recurring:$recurringId';
}
