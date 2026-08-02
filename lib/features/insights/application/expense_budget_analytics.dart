library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';

class CategoryBudgetSummary {
  const CategoryBudgetSummary({
    required this.category,
    required this.totalSpent,
    required this.budgetLimit,
  });

  final String category;
  final double totalSpent;
  final double budgetLimit;

  double get usagePercent =>
      budgetLimit > 0 ? (totalSpent / budgetLimit).clamp(0.0, 2.0) : 0.0;

  bool get isOverBudget => budgetLimit > 0 && totalSpent > budgetLimit;
}

class ExpenseBudgetAnalytics {
  static List<CategoryBudgetSummary> compute({
    required Iterable<MindmapNode> nodes,
    Map<String, double> defaultBudgets = const {
      'Food': 500000,
      'Transport': 300000,
      'Bills': 1000000,
      'Shopping': 400000,
      'General': 200000,
    },
  }) {
    final spending = <String, double>{};

    for (final node in nodes) {
      if (node.isArchived || node.type != NodeType.expense) continue;
      final payload = node.data['expense'] as Map<String, dynamic>?;
      if (payload != null) {
        final amount = (payload['amount'] as num?)?.toDouble() ?? 0.0;
        final category = (payload['category'] as String?)?.trim();
        final catKey = (category != null && category.isNotEmpty)
            ? category
            : 'General';
        spending[catKey] = (spending[catKey] ?? 0.0) + amount;
      }
    }

    final allCategories = {...defaultBudgets.keys, ...spending.keys};
    final summaries = <CategoryBudgetSummary>[];

    for (final cat in allCategories) {
      final spent = spending[cat] ?? 0.0;
      final budget = defaultBudgets[cat] ?? 0.0;
      summaries.add(
        CategoryBudgetSummary(
          category: cat,
          totalSpent: spent,
          budgetLimit: budget,
        ),
      );
    }

    summaries.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    return summaries;
  }
}
