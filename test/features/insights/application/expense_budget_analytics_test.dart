import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/application/expense_budget_analytics.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';

void main() {
  group('ExpenseBudgetAnalytics Engine', () {
    final month = DateTime(2026, 8, 7);

    MindmapNode transaction({
      required String id,
      required double amount,
      required String category,
      required String currency,
      ExpenseTransactionType type = ExpenseTransactionType.expense,
      DateTime? day,
      bool archived = false,
    }) {
      final base = MindmapNode.create(
        id: id,
        type: NodeType.expense,
        title: id,
        day: day ?? month,
        isArchived: archived,
      );
      return base.copyWith(
        data: ExpensePayload(
          amount: amount,
          category: category,
          currency: currency,
          transactionType: type,
        ).toData(base.data),
      );
    }

    test('aggregates canonical expense payloads by normalized category', () {
      final summaries = ExpenseBudgetAnalytics.compute(
        nodes: [
          transaction(
            id: 'lunch',
            amount: 50000,
            category: ' food ',
            currency: 'idr',
          ),
          transaction(
            id: 'dinner',
            amount: 100000,
            category: 'Food',
            currency: 'IDR',
          ),
        ],
      );

      final food = summaries.firstWhere((item) => item.category == 'Food');
      expect(food.totalSpent, 150000);
      expect(food.isOverBudget, isFalse);
    });

    test('monthly summary separates currencies income expenses and net', () {
      final summaries = ExpenseBudgetAnalytics.computeMonthly(
        month: month,
        nodes: [
          transaction(
            id: 'salary',
            amount: 1000,
            category: 'Salary',
            currency: 'USD',
            type: ExpenseTransactionType.income,
          ),
          transaction(
            id: 'food',
            amount: 250,
            category: 'Food',
            currency: 'USD',
          ),
          transaction(
            id: 'travel',
            amount: 300000,
            category: 'Transport',
            currency: 'IDR',
          ),
          transaction(
            id: 'old',
            amount: 500,
            category: 'Food',
            currency: 'USD',
            day: DateTime(2026, 7, 31),
          ),
          transaction(
            id: 'archived',
            amount: 900,
            category: 'Food',
            currency: 'USD',
            archived: true,
          ),
        ],
      );

      expect(summaries, hasLength(2));
      final usd = summaries.firstWhere((item) => item.currency == 'USD');
      final idr = summaries.firstWhere((item) => item.currency == 'IDR');
      expect(usd.income, 1000);
      expect(usd.expenses, 250);
      expect(usd.net, 750);
      expect(
        usd.categories.firstWhere((item) => item.category == 'Food').totalSpent,
        250,
      );
      expect(idr.expenses, 300000);
    });

    test('legacy transaction defaults to expense', () {
      final legacy = MindmapNode.create(
        id: 'legacy',
        type: NodeType.expense,
        title: 'Legacy',
        day: month,
        data: const <String, Object?>{
          'amount': 42,
          'category': 'General',
          'currency': 'USD',
        },
      );

      final summary = ExpenseBudgetAnalytics.computeMonthly(
        nodes: [legacy],
        month: month,
      ).single;

      expect(summary.income, 0);
      expect(summary.expenses, 42);
      expect(summary.net, -42);
    });
  });
}
