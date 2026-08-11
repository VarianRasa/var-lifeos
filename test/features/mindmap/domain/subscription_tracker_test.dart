import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/subscription_tracker.dart';

void main() {
  group('SubscriptionTracker Domain', () {
    test('calculates monthly and yearly costs accurately', () {
      final now = DateTime.now();
      final today = now.dateOnly;

      final nodes = [
        MindmapNode(
          id: 'sub1',
          day: today,
          type: NodeType.expense,
          title: 'Netflix',
          createdAt: now,
          updatedAt: now,
          data: {
            'subscription': {
              'name': 'Netflix',
              'cost': 180000.0,
              'cycle': 'monthly',
              'nextBillingDate': dayKey(today.add(const Duration(days: 3))),
            },
          },
        ),
        MindmapNode(
          id: 'sub2',
          day: today,
          type: NodeType.expense,
          title: 'GitHub Copilot',
          createdAt: now,
          updatedAt: now,
          data: {
            'subscription': {
              'name': 'GitHub Copilot',
              'cost': 1200000.0,
              'cycle': 'yearly',
              'nextBillingDate': dayKey(today.add(const Duration(days: 30))),
            },
          },
        ),
      ];

      final summary = SubscriptionTrackerSummary.fromNodes(nodes, today);

      expect(summary.items.length, equals(2));
      // 180,000 + (1,200,000 / 12 = 100,000) = 280,000
      expect(summary.totalMonthlyCost, equals(280000.0));
      expect(summary.totalYearlyCost, equals(3360000.0));
      expect(summary.dueSoonItems.length, equals(1));
      expect(summary.dueSoonItems.first.name, equals('Netflix'));
    });
  });
}
