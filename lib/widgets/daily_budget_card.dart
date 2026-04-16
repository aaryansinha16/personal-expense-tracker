import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/daily_budget.dart';
import '../utils/formatters.dart';
import 'bubble_card.dart';

class DailyBudgetCard extends StatelessWidget {
  final DailyBudget budget;
  final VoidCallback? onTapSetup;
  final VoidCallback? onRedistribute;

  const DailyBudgetCard({
    super.key,
    required this.budget,
    this.onTapSetup,
    this.onRedistribute,
  });

  @override
  Widget build(BuildContext context) {
    if (!budget.isConfigured) return _setupPrompt(context);

    final scheme = Theme.of(context).colorScheme;
    final allowed = budget.todayAllowed;
    final spent = budget.spentToday;
    final over = budget.isOverspent;
    final fraction = budget.todayFraction.clamp(0.0, 1.2).toDouble();

    Color accent;
    if (over) {
      accent = const Color(0xFFE04B4B);
    } else if (fraction > 0.8) {
      accent = const Color(0xFFE59A2E);
    } else {
      accent = const Color(0xFF2FB672);
    }

    return BubbleCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TODAY',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: scheme.onSurface.withOpacity(0.55),
                ),
              ),
              const Spacer(),
              PillChip(
                label: over ? 'Overspent' : (fraction > 0.8 ? 'Nearly done' : 'On track'),
                color: accent,
                icon: over
                    ? Icons.trending_up_rounded
                    : (fraction > 0.8 ? Icons.flash_on_rounded : Icons.check_circle_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: _ProgressRing(
                  fraction: fraction,
                  color: accent,
                  label: '${(fraction * 100).clamp(0, 999).round()}%',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(
                            text: inr(spent),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: accent,
                              letterSpacing: -0.4,
                            ),
                          ),
                          TextSpan(
                            text: '  /  ${inr(allowed)}',
                            style: TextStyle(
                              fontSize: 15,
                              color: scheme.onSurface.withOpacity(0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      over
                          ? 'Over by ${inr(spent - allowed)}'
                          : 'Left today: ${inr(math.max(0, allowed - spent))}',
                      style: TextStyle(color: scheme.onSurface.withOpacity(0.65), fontSize: 12.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${inr(budget.remainingForMonth - spent)} left · ${budget.daysLeftExclusive} days to go',
                      style: TextStyle(color: scheme.onSurface.withOpacity(0.55), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (over && onRedistribute != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Adjust future days'),
                    onPressed: onRedistribute,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _setupPrompt(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BubbleCard(
      onTap: onTapSetup,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.account_balance_wallet_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set up your monthly budget',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Income, savings, and fixed expenses',
                  style: TextStyle(color: scheme.onSurface.withOpacity(0.6), fontSize: 12.5),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withOpacity(0.5)),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final double fraction;
  final Color color;
  final String label;

  const _ProgressRing({required this.fraction, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: 1,
            strokeWidth: 8,
            color: color.withOpacity(0.13),
          ),
        ),
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            strokeWidth: 8,
            color: color,
            strokeCap: StrokeCap.round,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: color,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
