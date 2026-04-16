import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/db/models.dart';
import 'package:expense_tracker/services/daily_budget.dart';
import 'package:expense_tracker/services/monthly_setup.dart';

MonthlySetup _setup({double income = 100000, double savings = 20000, double fixed = 38000}) {
  return MonthlySetup(
    monthlyIncome: income,
    savingsTarget: savings,
    // single synthetic recurring entry so fixedTotal = fixed
    recurring: [
      RecurringExpense(id: 1, name: 'Fixed', amount: fixed, dayOfMonth: 1, active: true),
    ],
  );
}

Txn _txn(double amount, DateTime date, {String? note}) => Txn(
      amount: amount,
      type: TxnType.debit,
      date: date,
      source: TxnSource.manual,
      note: note,
    );

void main() {
  group('DailyBudget', () {
    final today = DateTime(2026, 4, 15, 12); // April 15 2026 — 30-day month

    test('computes today_allowed for a fresh month', () {
      final s = _setup();
      // Day 1 of month, nothing spent — all 30 days ahead
      final day1 = DateTime(2026, 4, 1, 9);
      final b = DailyBudgetCalc.fromMonth(setup: s, monthDebits: [], now: day1);
      expect(b.monthlyDiscretionary, 42000);
      expect(b.daysInMonth, 30);
      expect(b.daysLeftInclusive, 30);
      expect(b.todayAllowed, closeTo(1400, 0.01));
      expect(b.spentToday, 0);
      expect(b.isOverspent, false);
    });

    test('rolls underspend forward', () {
      final s = _setup();
      // Days 1..14 each spent 1000 — under the ₹1400/day budget
      final txns = [for (var d = 1; d <= 14; d++) _txn(1000, DateTime(2026, 4, d, 12))];
      final b = DailyBudgetCalc.fromMonth(setup: s, monthDebits: txns, now: today);
      // remaining = 42000 - 14000 = 28000; days_left_inclusive = 16
      expect(b.remainingForMonth, closeTo(28000, 0.01));
      expect(b.daysLeftInclusive, 16);
      expect(b.todayAllowed, closeTo(28000 / 16, 0.01)); // 1750
    });

    test('flags overspend and drops future budget', () {
      final s = _setup();
      // Days 1..14 spent exactly 1400 each (on-budget)
      final past = [for (var d = 1; d <= 14; d++) _txn(1400, DateTime(2026, 4, d, 12))];
      // Today (day 15) spent ₹3000 but allowed is 1400 — overspent
      final todayTxn = _txn(3000, DateTime(2026, 4, 15, 14));
      final b = DailyBudgetCalc.fromMonth(
        setup: s,
        monthDebits: [...past, todayTxn],
        now: today,
      );
      expect(b.todayAllowed, closeTo(1400, 0.01));
      expect(b.spentToday, 3000);
      expect(b.isOverspent, true);
      // After today: 42000 - 19600 - 3000 = 19400 across 15 future days = 1293.33
      expect(b.projectedFutureDailyAllowance, closeTo(19400 / 15, 0.01));
    });

    test('excludes recurring-tagged transactions from spend', () {
      final s = _setup();
      // Rent auto-posted on day 1 for ₹20000 should NOT count as discretionary
      final rent = _txn(20000, DateTime(2026, 4, 1, 10), note: 'recurring:1');
      final lunch = _txn(500, DateTime(2026, 4, 2, 13)); // normal
      final b = DailyBudgetCalc.fromMonth(
        setup: s,
        monthDebits: [rent, lunch],
        now: today,
      );
      // Only ₹500 counts; remaining = 42000 - 500 = 41500 across 16 days
      expect(b.remainingForMonth, closeTo(41500, 0.01));
    });

    test('not configured when income is zero', () {
      final s = _setup(income: 0);
      final b = DailyBudgetCalc.fromMonth(setup: s, monthDebits: [], now: today);
      expect(b.isConfigured, false);
    });

    test('handles negative discretionary gracefully', () {
      // savings+fixed > income → discretionary clamps to 0
      final s = _setup(income: 30000, savings: 20000, fixed: 20000);
      final b = DailyBudgetCalc.fromMonth(setup: s, monthDebits: [], now: today);
      expect(b.monthlyDiscretionary, 0);
      expect(b.todayAllowed, 0);
    });
  });
}
