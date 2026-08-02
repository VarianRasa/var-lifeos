import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/application/expense_budget_analytics.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('ExpenseBudgetAnalytics groups expenses by category', () {
    final day = DateTime(2026, 7, 21);
    final nodes = [
      MindmapNode.create(
        id: 'e1',
        title: 'Lunch',
        day: day,
        type: NodeType.expense,
        data: {
          'expense': {'category': 'Food', 'amount': 15.5},
        },
      ),
      MindmapNode.create(
        id: 'e2',
        title: 'Snack',
        day: day,
        type: NodeType.expense,
        data: {
          'expense': {'category': 'Food', 'amount': 10.0},
        },
      ),
      MindmapNode.create(
        id: 'e3',
        title: 'Bus',
        day: day,
        type: NodeType.expense,
        data: {
          'expense': {'category': 'Transport', 'amount': 20.0},
        },
      ),
    ];

    final breakdown = ExpenseBudgetAnalytics.compute(
      nodes: nodes,
      defaultBudgets: {'Food': 50.0, 'Transport': 30.0},
    );
    final food = breakdown.firstWhere((b) => b.category == 'Food');
    final transport = breakdown.firstWhere((b) => b.category == 'Transport');

    expect(food.totalSpent, 25.5);
    expect(transport.totalSpent, 20.0);
  });
}
