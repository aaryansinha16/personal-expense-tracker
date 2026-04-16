import '../db/models.dart';
import 'monthly_setup.dart';

class DailyBudget {
  final double monthlyDiscretionary;
  final double spentBeforeToday;
  final double spentToday;
  final int daysInMonth;
  final int day; // today's day-of-month
  final MonthlySetup setup;

  DailyBudget({
    required this.monthlyDiscretionary,
    required this.spentBeforeToday,
    required this.spentToday,
    required this.daysInMonth,
    required this.day,
    required this.setup,
  });

  int get daysLeftInclusive => daysInMonth - day + 1;
  int get daysLeftExclusive => daysInMonth - day;

  /// Pool left for today plus all future days of the month.
  double get remainingForMonth =>
      (monthlyDiscretionary - spentBeforeToday).clamp(0, double.infinity).toDouble();

  /// How much is allowed to spend today.
  double get todayAllowed {
    if (daysLeftInclusive <= 0) return 0;
    return remainingForMonth / daysLeftInclusive;
  }

  double get remainingToday => (todayAllowed - spentToday);

  bool get isOverspent => spentToday > todayAllowed && todayAllowed > 0;

  /// If the user keeps today's spending, this is what future days allow.
  /// Equivalent to: pool left AFTER today divided by days left AFTER today.
  double get projectedFutureDailyAllowance {
    if (daysLeftExclusive <= 0) return 0;
    final afterToday = (monthlyDiscretionary - spentBeforeToday - spentToday)
        .clamp(0, double.infinity)
        .toDouble();
    return afterToday / daysLeftExclusive;
  }

  /// Fraction of today's allowance used (0..∞).
  double get todayFraction {
    if (todayAllowed <= 0) return 0;
    return spentToday / todayAllowed;
  }

  bool get isConfigured => setup.isConfigured;
}

class DailyBudgetCalc {
  /// Computes DailyBudget from a MonthlySetup and a full month's transactions.
  /// `txns` is expected to be debit transactions within the target month;
  /// the calc filters by day boundaries.
  ///
  /// `excludeRecurring` drops transactions tagged `recurring:<id>` so fixed
  /// expenses don't double-dip — they're already subtracted in
  /// MonthlySetup.monthlyDiscretionary.
  static DailyBudget fromMonth({
    required MonthlySetup setup,
    required List<Txn> monthDebits,
    DateTime? now,
    bool excludeRecurring = true,
  }) {
    final today = now ?? DateTime.now();
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final startOfToday = DateTime(today.year, today.month, today.day);
    final endOfToday = startOfToday.add(const Duration(days: 1, milliseconds: -1));

    double spentBefore = 0;
    double spentToday = 0;
    for (final t in monthDebits) {
      if (excludeRecurring && (t.note?.startsWith('recurring:') ?? false)) continue;
      if (t.date.isBefore(startOfToday)) {
        spentBefore += t.amount;
      } else if (!t.date.isAfter(endOfToday)) {
        spentToday += t.amount;
      }
    }

    return DailyBudget(
      monthlyDiscretionary: setup.monthlyDiscretionary,
      spentBeforeToday: spentBefore,
      spentToday: spentToday,
      daysInMonth: daysInMonth,
      day: today.day,
      setup: setup,
    );
  }
}
