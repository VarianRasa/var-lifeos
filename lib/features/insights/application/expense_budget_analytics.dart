library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_type_payloads.dart';

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

class ExpenseCurrencySummary {
  const ExpenseCurrencySummary({
    required this.currency,
    required this.income,
    required this.expenses,
    required this.categories,
  });

  final String currency;
  final double income;
  final double expenses;
  final List<CategoryBudgetSummary> categories;

  double get net => income - expenses;
  double get totalBudget => categories.fold<double>(
    0,
    (total, category) => total + category.budgetLimit,
  );
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
  }) => computeMonthly(
    nodes: nodes,
    month: DateTime.now(),
    defaultBudgets: defaultBudgets,
    filterMonth: false,
  ).expand((summary) => summary.categories).toList();

  static List<ExpenseCurrencySummary> computeMonthly({
    required Iterable<MindmapNode> nodes,
    required DateTime month,
    Map<String, double> defaultBudgets = const {
      'Food': 500000,
      'Transport': 300000,
      'Bills': 1000000,
      'Shopping': 400000,
      'General': 200000,
    },
    bool filterMonth = true,
  }) {
    final monthStart = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final income = <String, double>{};
    final expenses = <String, double>{};
    final spending = <String, Map<String, double>>{};

    for (final node in nodes) {
      if (node.isArchived || node.type != NodeType.expense) continue;
      if (filterMonth &&
          (node.day.isBefore(monthStart) || !node.day.isBefore(nextMonth))) {
        continue;
      }
      final payload = ExpensePayload.fromNode(node);
      final amount = payload.amount ?? 0;
      final currency = payload.currency.trim().toUpperCase().isEmpty
          ? 'USD'
          : payload.currency.trim().toUpperCase();
      if (payload.transactionType == ExpenseTransactionType.income) {
        income[currency] = (income[currency] ?? 0) + amount;
        continue;
      }
      expenses[currency] = (expenses[currency] ?? 0) + amount;
      final category = _normalizedCategory(payload.category);
      final categories = spending.putIfAbsent(currency, () => {});
      categories[category] = (categories[category] ?? 0) + amount;
    }

    final currencies = <String>{
      ...income.keys,
      ...expenses.keys,
      ...spending.keys,
    }.toList()..sort();
    return <ExpenseCurrencySummary>[
      for (final currency in currencies)
        ExpenseCurrencySummary(
          currency: currency,
          income: income[currency] ?? 0,
          expenses: expenses[currency] ?? 0,
          categories: _categories(
            spending[currency] ?? const <String, double>{},
            defaultBudgets,
          ),
        ),
    ];
  }

  static List<CategoryBudgetSummary> _categories(
    Map<String, double> spending,
    Map<String, double> defaultBudgets,
  ) {
    final allCategories = <String>{...defaultBudgets.keys, ...spending.keys};
    return <CategoryBudgetSummary>[
      for (final category in allCategories)
        CategoryBudgetSummary(
          category: category,
          totalSpent: spending[category] ?? 0,
          budgetLimit: defaultBudgets[category] ?? 0,
        ),
    ]..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
  }

  static String _normalizedCategory(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'General';
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}';
  }
}
