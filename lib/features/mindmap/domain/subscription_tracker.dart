/// Recurring Subscription & Bill tracker domain model.
library;

import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

enum SubscriptionBillingCycle {
  monthly('Monthly'),
  yearly('Yearly'),
  weekly('Weekly');

  const SubscriptionBillingCycle(this.label);
  final String label;
}

final class SubscriptionItem {
  const SubscriptionItem({
    required this.nodeId,
    required this.name,
    required this.cost,
    required this.cycle,
    required this.nextBillingDate,
    required this.category,
    this.autoRenew = true,
  });

  final String nodeId;
  final String name;
  final double cost;
  final SubscriptionBillingCycle cycle;
  final DateTime nextBillingDate;
  final String category;
  final bool autoRenew;

  double get monthlyCostEquivalent => switch (cycle) {
    SubscriptionBillingCycle.monthly => cost,
    SubscriptionBillingCycle.yearly => cost / 12.0,
    SubscriptionBillingCycle.weekly => cost * 4.33,
  };

  bool isDueWithinDays(DateTime today, int days) {
    final diff = nextBillingDate.dateOnly.difference(today.dateOnly).inDays;
    return diff >= 0 && diff <= days;
  }
}

final class SubscriptionTrackerSummary {
  const SubscriptionTrackerSummary({
    required this.items,
    required this.totalMonthlyCost,
    required this.totalYearlyCost,
    required this.dueSoonItems,
  });

  final List<SubscriptionItem> items;
  final double totalMonthlyCost;
  final double totalYearlyCost;
  final List<SubscriptionItem> dueSoonItems;

  factory SubscriptionTrackerSummary.fromNodes(
    Iterable<MindmapNode> nodes,
    DateTime today,
  ) {
    final items = <SubscriptionItem>[];

    for (final node in nodes) {
      if (node.isArchived) continue;
      final payload = node.data['subscription'];
      if (payload is Map) {
        final map = payload.cast<String, Object?>();
        final cost = (map['cost'] as num?)?.toDouble() ?? 0.0;
        final name = (map['name'] as String?) ?? node.title;
        final category = (map['category'] as String?) ?? 'Software';
        final cycleName = map['cycle'] as String?;
        final cycle = SubscriptionBillingCycle.values.firstWhere(
          (c) => c.name == cycleName,
          orElse: () => SubscriptionBillingCycle.monthly,
        );
        final nextDate =
            DateTime.tryParse(
              map['nextBillingDate'] as String? ?? '',
            )?.dateOnly ??
            node.day;

        items.add(
          SubscriptionItem(
            nodeId: node.id,
            name: name,
            cost: cost,
            cycle: cycle,
            nextBillingDate: nextDate,
            category: category,
            autoRenew: map['autoRenew'] as bool? ?? true,
          ),
        );
      }
    }

    double monthlyTotal = 0;
    for (final item in items) {
      monthlyTotal += item.monthlyCostEquivalent;
    }

    final dueSoon = items.where((i) => i.isDueWithinDays(today, 7)).toList();

    return SubscriptionTrackerSummary(
      items: items,
      totalMonthlyCost: monthlyTotal,
      totalYearlyCost: monthlyTotal * 12.0,
      dueSoonItems: dueSoon,
    );
  }
}
