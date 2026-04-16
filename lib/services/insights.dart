import '../db/models.dart';
import 'monthly_setup.dart';

enum InsightKind { streak, weekendSkew, topCategory, biggestDay, noSpendDays, underBudgetRate }

class Insight {
  final InsightKind kind;
  final String label;
  final String value;
  final String? hint;
  final int color;

  Insight({
    required this.kind,
    required this.label,
    required this.value,
    this.hint,
    required this.color,
  });
}

class InsightsService {
  /// Computes the list of insights for the given month's debit transactions.
  /// `recurring` debits (note startsWith "recurring:") are excluded so fixed
  /// expenses don't skew weekend/weekday or "no-spend" counts.
  static List<Insight> compute({
    required List<Txn> monthDebits,
    required MonthlySetup setup,
    DateTime? now,
    List<Category>? categories,
  }) {
    final today = now ?? DateTime.now();
    final disc = monthDebits.where((t) => !(t.note?.startsWith('recurring:') ?? false)).toList();

    final out = <Insight>[];

    // 1. Under-budget streak — days in this month (up to yesterday) where
    //    discretionary spend stayed at or under the per-day baseline.
    if (setup.isConfigured) {
      final perDay = setup.monthlyDiscretionary /
          DateTime(today.year, today.month + 1, 0).day;
      int streak = 0;
      for (var d = today.day - 1; d >= 1; d--) {
        final day = DateTime(today.year, today.month, d);
        final spent = disc
            .where((t) => t.date.year == day.year && t.date.month == day.month && t.date.day == day.day)
            .fold<double>(0, (s, t) => s + t.amount);
        if (spent <= perDay) {
          streak++;
        } else {
          break;
        }
      }
      out.add(Insight(
        kind: InsightKind.streak,
        label: 'UNDER-BUDGET STREAK',
        value: '$streak day${streak == 1 ? '' : 's'}',
        hint: streak == 0 ? 'Break it today to start a streak' : null,
        color: streak > 0 ? 0xFF2FB672 : 0xFF9AA0A6,
      ));
    }

    // 2. Weekday vs weekend average
    final weekdays = <double>[];
    final weekends = <double>[];
    final byDay = <int, double>{};
    for (final t in disc) {
      byDay[t.date.day] = (byDay[t.date.day] ?? 0) + t.amount;
    }
    byDay.forEach((day, amount) {
      final wd = DateTime(today.year, today.month, day).weekday;
      if (wd == DateTime.saturday || wd == DateTime.sunday) {
        weekends.add(amount);
      } else {
        weekdays.add(amount);
      }
    });
    if (weekdays.isNotEmpty && weekends.isNotEmpty) {
      final wdAvg = weekdays.fold<double>(0, (s, v) => s + v) / weekdays.length;
      final weAvg = weekends.fold<double>(0, (s, v) => s + v) / weekends.length;
      if (wdAvg > 0) {
        final ratio = weAvg / wdAvg;
        String val;
        if (ratio >= 1.1) {
          val = '${ratio.toStringAsFixed(1)}× more on weekends';
        } else if (ratio <= 0.9) {
          val = '${(1 / ratio).toStringAsFixed(1)}× more on weekdays';
        } else {
          val = 'Evenly split';
        }
        out.add(Insight(
          kind: InsightKind.weekendSkew,
          label: 'WEEKDAY VS WEEKEND',
          value: val,
          hint: 'Weekday avg ₹${wdAvg.toStringAsFixed(0)} · Weekend avg ₹${weAvg.toStringAsFixed(0)}',
          color: 0xFF6366F1,
        ));
      }
    }

    // 3. Top category with share
    if (disc.isNotEmpty && categories != null && categories.isNotEmpty) {
      final catTotals = <int, double>{};
      for (final t in disc) {
        final id = t.categoryId ?? -1;
        catTotals[id] = (catTotals[id] ?? 0) + t.amount;
      }
      final totalSpent = catTotals.values.fold<double>(0, (s, v) => s + v);
      final top = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      if (top.isNotEmpty && totalSpent > 0) {
        final topEntry = top.first;
        final cat = categories.where((c) => c.id == topEntry.key).toList();
        final name = cat.isNotEmpty ? cat.first.name : 'Uncategorized';
        final share = (topEntry.value / totalSpent * 100).round();
        final color = cat.isNotEmpty ? cat.first.color : 0xFFBDBDBD;
        out.add(Insight(
          kind: InsightKind.topCategory,
          label: 'TOP CATEGORY',
          value: '$name · $share%',
          hint: '₹${topEntry.value.toStringAsFixed(0)} this month',
          color: color,
        ));
      }
    }

    // 4. Biggest-spend day
    if (byDay.isNotEmpty) {
      final biggest = byDay.entries.reduce((a, b) => a.value > b.value ? a : b);
      out.add(Insight(
        kind: InsightKind.biggestDay,
        label: 'BIGGEST DAY',
        value: '₹${biggest.value.toStringAsFixed(0)}',
        hint: _monthDayLabel(DateTime(today.year, today.month, biggest.key)),
        color: 0xFFE59A2E,
      ));
    }

    // 5. No-spend days
    final daysSoFar = today.day;
    final spendingDays = byDay.keys.where((d) => d <= daysSoFar && (byDay[d] ?? 0) > 0).length;
    final noSpend = daysSoFar - spendingDays;
    out.add(Insight(
      kind: InsightKind.noSpendDays,
      label: 'NO-SPEND DAYS',
      value: '$noSpend / $daysSoFar',
      hint: noSpend > 0 ? 'Nice discipline' : 'Try to bank one',
      color: 0xFF2FB672,
    ));

    return out;
  }

  static String _monthDayLabel(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
