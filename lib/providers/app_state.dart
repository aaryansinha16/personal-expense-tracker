import 'package:flutter/foundation.dart' hide Category;

import '../db/database.dart';
import '../db/models.dart';
import '../email/sender_registry.dart';
import '../services/daily_budget.dart';
import '../services/insights.dart';
import '../services/monthly_setup.dart';

class AppState extends ChangeNotifier {
  final AppDb _db = AppDb.instance;
  final MonthlySetupService _setupSvc = MonthlySetupService.instance;

  List<Category> categories = [];
  List<Txn> recentTxns = [];
  List<Budget> budgets = [];
  List<PendingSms> pendingSms = [];
  MonthlySetup setup = MonthlySetup(monthlyIncome: 0, savingsTarget: 0, recurring: []);
  DailyBudget? dailyBudget;
  List<Insight> insights = [];

  Map<String, double> monthTotals = {'debit': 0, 'credit': 0};
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  bool loading = false;

  Future<void> init() async {
    loading = true;
    notifyListeners();
    await SenderRegistry.instance.load();
    await _setupSvc.autoPostDueRecurring();
    await refreshAll();
    loading = false;
    notifyListeners();
  }

  Future<void> refreshAll() async {
    categories = await _db.listCategories();
    budgets = await _db.listBudgets();
    pendingSms = await _db.listPendingSms();
    recentTxns = await _db.listTxns(limit: 30);
    setup = await _setupSvc.load();
    final (from, to) = monthRange(selectedMonth);
    monthTotals = await _db.totalsByType(from, to);

    // Daily budget is always anchored to the real current month, not
    // whatever month is selected for browsing analytics.
    final now = DateTime.now();
    final curStart = DateTime(now.year, now.month, 1);
    final curEnd = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
    final monthDebits = await _db.listTxns(from: curStart, to: curEnd, type: TxnType.debit);
    dailyBudget = DailyBudgetCalc.fromMonth(setup: setup, monthDebits: monthDebits);
    insights = InsightsService.compute(
      monthDebits: monthDebits,
      setup: setup,
      categories: categories,
    );

    notifyListeners();
  }

  Future<void> setIncome(double v) async {
    await _setupSvc.setIncome(v);
    await refreshAll();
  }

  Future<void> setSavingsTarget(double v) async {
    await _setupSvc.setSavingsTarget(v);
    await refreshAll();
  }

  Future<void> upsertRecurring(RecurringExpense r) async {
    await _db.upsertRecurringExpense(r);
    await _setupSvc.autoPostDueRecurring();
    await refreshAll();
  }

  Future<void> deleteRecurring(int id) async {
    await _db.deleteRecurringExpense(id);
    await refreshAll();
  }

  Future<SmsResetResult> resetSmsSync({required bool deleteSmsTxns, required bool deletePending}) async {
    final res = await _db.resetSmsSync(deleteSmsTxns: deleteSmsTxns, deletePending: deletePending);
    await refreshAll();
    return res;
  }

  Future<EmailResetResult> resetEmailSync({required bool deleteEmailTxns}) async {
    final res = await _db.resetEmailSync(deleteEmailTxns: deleteEmailTxns);
    await refreshAll();
    return res;
  }

  Category? categoryById(int? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> setSelectedMonth(DateTime d) async {
    selectedMonth = DateTime(d.year, d.month);
    await refreshAll();
  }

  Future<void> addTxn(Txn t) async {
    await _db.insertTxn(t);
    await refreshAll();
  }

  Future<void> updateTxn(Txn t) async {
    await _db.updateTxn(t);
    await refreshAll();
  }

  Future<void> deleteTxn(int id) async {
    await _db.deleteTxn(id);
    await refreshAll();
  }

  Future<void> upsertBudget(int categoryId, double limit) async {
    await _db.upsertBudget(Budget(categoryId: categoryId, monthlyLimit: limit));
    await refreshAll();
  }

  Future<void> deleteBudget(int categoryId) async {
    await _db.deleteBudget(categoryId);
    await refreshAll();
  }

  Future<void> resolvePendingSms(PendingSms s, {required Txn txn, bool learnMerchant = true}) async {
    await _db.insertTxn(txn);
    if (learnMerchant && txn.merchant != null && txn.categoryId != null) {
      await _db.upsertMerchantMap(MerchantMap(
        pattern: txn.merchant!.toLowerCase(),
        categoryId: txn.categoryId!,
      ));
    }
    await _db.deletePendingSms(s.id!);
    await refreshAll();
  }

  Future<void> dismissPendingSms(PendingSms s) async {
    await _db.deletePendingSms(s.id!);
    await refreshAll();
  }

  Future<void> addCategory(Category c) async {
    await _db.insertCategory(c);
    await refreshAll();
  }

  Future<void> updateCategory(Category c) async {
    await _db.updateCategory(c);
    await refreshAll();
  }

  Future<void> deleteCategory(int id) async {
    await _db.deleteCategory(id);
    await refreshAll();
  }
}

(DateTime, DateTime) monthRange(DateTime month) {
  final from = DateTime(month.year, month.month, 1);
  final to = DateTime(month.year, month.month + 1, 1).subtract(const Duration(milliseconds: 1));
  return (from, to);
}
