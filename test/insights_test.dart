import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/db/models.dart';
import 'package:expense_tracker/services/insights.dart';
import 'package:expense_tracker/services/monthly_setup.dart';

MonthlySetup _setup() => MonthlySetup(
      monthlyIncome: 100000,
      savingsTarget: 20000,
      recurring: [
        RecurringExpense(id: 1, name: 'Rent', amount: 38000, dayOfMonth: 1, active: true),
      ],
    );

Txn _debit(double amount, DateTime date, {String? note, int? catId}) => Txn(
      amount: amount,
      type: TxnType.debit,
      date: date,
      source: TxnSource.manual,
      note: note,
      categoryId: catId,
    );

void main() {
  // April 2026 — day 15 is a Wednesday. Weekends fall on 4,5,11,12.
  final today = DateTime(2026, 4, 15, 18);

  test('reports streak, no-spend days, top category, biggest day', () {
    final categories = [
      Category(id: 1, name: 'Food', icon: 0, color: 0xFF000001),
      Category(id: 2, name: 'Transport', icon: 0, color: 0xFF000002),
    ];
    final txns = [
      // Days 1..10 each ₹1000 — well under ₹1400/day baseline
      for (var d = 1; d <= 10; d++) _debit(1000, DateTime(2026, 4, d, 12), catId: 1),
      // Day 11 nothing (no-spend)
      // Day 12 ₹4000 — above baseline, breaks streak
      _debit(4000, DateTime(2026, 4, 12, 12), catId: 1),
      // Days 13, 14 each ₹500
      _debit(500, DateTime(2026, 4, 13, 12), catId: 2),
      _debit(500, DateTime(2026, 4, 14, 12), catId: 2),
    ];
    final out = InsightsService.compute(
      monthDebits: txns,
      setup: _setup(),
      now: today,
      categories: categories,
    );

    final streak = out.firstWhere((i) => i.kind == InsightKind.streak);
    // Yesterday day 14 (500 ≤ 1400) ✓, day 13 (500) ✓, day 12 (4000) ✗ → streak is 2
    expect(streak.value, '2 days');

    final top = out.firstWhere((i) => i.kind == InsightKind.topCategory);
    expect(top.value.startsWith('Food'), true);

    final biggest = out.firstWhere((i) => i.kind == InsightKind.biggestDay);
    expect(biggest.value, '₹4000');

    final noSpend = out.firstWhere((i) => i.kind == InsightKind.noSpendDays);
    // daysSoFar = today.day = 15; spending days = 13 (1..10, 12, 13, 14);
    // no-spend = 15 - 13 = 2 (day 11 and today).
    expect(noSpend.value, '2 / 15');
  });

  test('excludes recurring-tagged transactions from insights math', () {
    final txns = [
      _debit(38000, DateTime(2026, 4, 1, 9), note: 'recurring:1'),
      _debit(500, DateTime(2026, 4, 2, 12)),
    ];
    final out = InsightsService.compute(
      monthDebits: txns,
      setup: _setup(),
      now: today,
    );
    final biggest = out.firstWhere((i) => i.kind == InsightKind.biggestDay);
    // If recurring were included, biggest would be ₹38000
    expect(biggest.value, '₹500');
  });
}
