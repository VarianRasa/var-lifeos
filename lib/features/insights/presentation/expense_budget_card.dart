import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../mindmap/domain/mindmap_node.dart';
import '../application/expense_budget_analytics.dart';

class ExpenseBudgetCard extends StatelessWidget {
  const ExpenseBudgetCard({super.key, required this.nodes});

  final List<MindmapNode> nodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final summaries = ExpenseBudgetAnalytics.computeMonthly(
      nodes: nodes,
      month: now,
    );

    return Card(
      key: const ValueKey('expense-budget-card'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Expense & Budget · ${DateFormat('MMMM yyyy').format(now)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (summaries.isEmpty)
              Text(
                'No transactions this month.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final summary in summaries) ...[
                _CurrencySummary(summary: summary),
                const SizedBox(height: 14),
              ],
          ],
        ),
      ),
    );
  }
}

class _CurrencySummary extends StatelessWidget {
  const _CurrencySummary({required this.summary});

  final ExpenseCurrencySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = summary.totalBudget > 0
        ? (summary.expenses / summary.totalBudget).clamp(0.0, 1.0)
        : 0.0;
    return Semantics(
      label:
          '${summary.currency} income ${summary.income.toStringAsFixed(2)}, expenses ${summary.expenses.toStringAsFixed(2)}, net ${summary.net.toStringAsFixed(2)}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.currency,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text('Income ${summary.income.toStringAsFixed(2)}'),
                Text('Expenses ${summary.expenses.toStringAsFixed(2)}'),
                Text(
                  'Net ${summary.net.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: summary.net < 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (summary.totalBudget > 0) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: usage,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: summary.expenses > summary.totalBudget
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ],
            const SizedBox(height: 10),
            for (final category
                in summary.categories
                    .where((item) => item.totalSpent > 0)
                    .take(5)) ...[
              _CategoryBudgetRow(summary: category, currency: summary.currency),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryBudgetRow extends StatelessWidget {
  const _CategoryBudgetRow({required this.summary, required this.currency});

  final CategoryBudgetSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = summary.usagePercent;
    final isOver = summary.isOverBudget;
    final color = isOver
        ? theme.colorScheme.error
        : (usage >= 0.8 ? Colors.amber : theme.colorScheme.primary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              summary.category,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$currency ${summary.totalSpent.toStringAsFixed(0)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: isOver
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (summary.budgetLimit > 0) ...[
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: usage.clamp(0.0, 1.0),
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ],
      ],
    );
  }
}
