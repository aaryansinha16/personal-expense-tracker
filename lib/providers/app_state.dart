import 'package:flutter/foundation.dart' hide Category;

import '../db/database.dart';
import '../db/models.dart';
import '../email/sender_registry.dart';
import '../services/ai_pipeline.dart';
import '../services/ai_triage.dart';
import '../services/daily_budget.dart';
import '../services/insights.dart';
import '../services/monthly_setup.dart';
import '../services/transaction_deduper.dart';

class AppState extends ChangeNotifier {
  final AppDb _db = AppDb.instance;
  final MonthlySetupService _setupSvc = MonthlySetupService.instance;

  List<Category> categories = [];
  List<Txn> recentTxns = [];
  List<Budget> budgets = [];
  List<PendingSms> pendingSms = [];
  List<PendingEmail> pendingEmails = [];
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
    pendingEmails = await _db.listPendingEmails();
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

  Future<void> resolvePendingEmail(PendingEmail e, {required Txn txn}) async {
    await _db.insertTxn(txn);
    await _db.deletePendingEmail(e.id!);
    await refreshAll();
  }

  Future<void> dismissPendingEmail(PendingEmail e) async {
    await _db.deletePendingEmail(e.id!);
    await refreshAll();
  }

  /// Run AI triage across all pending SMS + email items. Applies decisions:
  /// - High-confidence is_transaction: true → insert as txn (after dedup).
  /// - High/medium-confidence is_transaction: false → dismiss from queue.
  /// - Low confidence → leave in queue with the reasoning attached so the
  ///   user sees why AI was unsure.
  /// Apply a batch of AI decisions (each tied to a TriageItem) to the DB.
  /// Returns counts and total USD cost. Used by both the manual "AI triage
  /// all" button on Review and the AI-first sync pipeline.
  Future<AiTriageApplyResult> applyAiDecisions(
    List<TriageItem> items,
    List<AiDecision> decisions, {
    required double usdSpent,
    bool removeFromQueue = true,
  }) async {
    int imported = 0;
    int dismissed = 0;
    int kept = 0;

    // Only iterate up to the number of decisions we actually got — if the
    // pipeline errored mid-way, items beyond this are left UNTOUCHED (no
    // processed_sms / processed_emails marker), so they'll be re-fetched on
    // the next sync.
    for (var i = 0; i < decisions.length && i < items.length; i++) {
      final it = items[i];
      final d = decisions[i];
      final lowConfidence = d.confidence == 'low';
      final txnDate = it.sourceDate ?? DateTime.now();

      if (lowConfidence) {
        kept++;
        // For fresh pulls with a sourceId, route the item into the review
        // queue so the user can still act on it.
        if (it.queueId < 0 && it.sourceId != null) {
          if (it.source == 'email') {
            await _db.insertPendingEmail(PendingEmail(
              messageId: it.sourceId,
              sender: it.sender,
              subject: it.subject,
              body: it.body,
              receivedAt: txnDate,
              reason: 'AI low-confidence: ${d.reasoning ?? ''}',
            ));
          } else {
            await _db.insertPendingSms(PendingSms(
              sender: it.sender,
              body: it.body,
              receivedAt: txnDate,
            ));
          }
        }
      } else if (d.isTransaction && d.amount != null && d.amount! > 0) {
        final categoryId = _findCategoryId(d.category);
        final candidate = Txn(
          amount: d.amount!,
          type: d.type == 'credit' ? TxnType.credit : TxnType.debit,
          categoryId: categoryId,
          merchant: d.merchant,
          date: txnDate,
          source: it.source == 'sms' ? TxnSource.sms : TxnSource.email,
          account: it.sourceAccount,
          note: d.reasoning,
        );
        final dup = await TransactionDeduper.findDuplicate(candidate);
        if (dup == null) {
          await _db.insertTxn(candidate);
          imported++;
        } else {
          dismissed++;
        }
      } else {
        dismissed++;
      }

      // Now — and only now — mark the source processed so it won't be
      // re-fetched, and remove from the queue if it originated there.
      if (removeFromQueue && it.queueId >= 0) {
        if (it.source == 'sms') {
          await _db.deletePendingSms(it.queueId);
        } else if (it.source == 'email') {
          await _db.deletePendingEmail(it.queueId);
        }
      }
      if (it.sourceId != null) {
        if (it.source == 'sms') {
          await _db.markSmsProcessed(it.sourceId!);
        } else if (it.source == 'email') {
          await _db.markEmailProcessed(it.sourceId!);
        }
      }
    }

    await refreshAll();
    return AiTriageApplyResult(
      imported: imported,
      dismissed: dismissed,
      kept: kept,
      usdCost: usdSpent,
    );
  }

  /// AI-first sync for a single source. Fetches raw items from [fetch],
  /// runs them through the pipeline, applies decisions. Caller displays
  /// progress via [onProgress]. If the pipeline returned a partial result
  /// because of an error, the error text surfaces in [AiTriageApplyResult].
  Future<AiTriageApplyResult> runAiSync({
    required Future<List<TriageItem>> Function() fetch,
    required void Function(PipelineProgress) onProgress,
  }) async {
    final items = await fetch();
    if (items.isEmpty) {
      return AiTriageApplyResult(imported: 0, dismissed: 0, kept: 0, usdCost: 0);
    }
    final categoryNames = categories.map((c) => c.name).toList();
    final pipeline = AiPipeline();
    final result = await pipeline.classifyAll(
      items,
      categories: categoryNames,
      onProgress: onProgress,
    );
    final applied = await applyAiDecisions(
      items,
      result.decisions,
      usdSpent: result.usdSpent,
      removeFromQueue: false,
    );
    return AiTriageApplyResult(
      imported: applied.imported,
      dismissed: applied.dismissed,
      kept: applied.kept,
      usdCost: applied.usdCost,
      error: result.error,
      itemsUnprocessed: items.length - result.decisions.length,
    );
  }

  Future<AiTriageApplyResult> aiTriageAll() async {
    final items = <TriageItem>[];
    for (final s in pendingSms) {
      items.add(TriageItem(
        queueId: s.id!,
        source: 'sms',
        sender: s.sender,
        body: s.body,
      ));
    }
    for (final e in pendingEmails) {
      items.add(TriageItem(
        queueId: e.id!,
        source: 'email',
        sender: e.sender,
        subject: e.subject,
        body: e.body,
      ));
    }
    if (items.isEmpty) {
      return AiTriageApplyResult(imported: 0, dismissed: 0, kept: 0, usdCost: 0);
    }

    final categoryNames = categories.map((c) => c.name).toList();
    final pipeline = AiPipeline();
    final result = await pipeline.classifyAll(items, categories: categoryNames);

    return applyAiDecisions(
      items,
      result.decisions,
      usdSpent: result.usdSpent,
    );
  }

  int? _findCategoryId(String? name) {
    if (name == null) return null;
    final match = categories.where((c) => c.name.toLowerCase() == name.toLowerCase()).toList();
    if (match.isNotEmpty) return match.first.id;
    return null;
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

class AiTriageApplyResult {
  final int imported;
  final int dismissed;
  final int kept;
  final double usdCost;
  final String? error;
  final int itemsUnprocessed;
  AiTriageApplyResult({
    required this.imported,
    required this.dismissed,
    required this.kept,
    required this.usdCost,
    this.error,
    this.itemsUnprocessed = 0,
  });
}
