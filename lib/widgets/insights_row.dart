import 'package:flutter/material.dart';

import '../services/insights.dart';
import 'bubble_card.dart';

class InsightsRow extends StatelessWidget {
  final List<Insight> insights;
  const InsightsRow({super.key, required this.insights});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: insights.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final ins = insights[i];
          final color = Color(ins.color);
          return SizedBox(
            width: 180,
            child: BubbleCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_iconFor(ins.kind), size: 16, color: color),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ins.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ins.value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  if (ins.hint != null)
                    Text(
                      ins.hint!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(InsightKind k) {
    switch (k) {
      case InsightKind.streak:
        return Icons.local_fire_department_rounded;
      case InsightKind.weekendSkew:
        return Icons.weekend_rounded;
      case InsightKind.topCategory:
        return Icons.pie_chart_rounded;
      case InsightKind.biggestDay:
        return Icons.trending_up_rounded;
      case InsightKind.noSpendDays:
        return Icons.beach_access_rounded;
      case InsightKind.underBudgetRate:
        return Icons.track_changes_rounded;
    }
  }
}
