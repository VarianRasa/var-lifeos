import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/application/insight_filters.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('insightDateRangeForPreset creates supported ranges', () {
    final today = DateTime(2026, 7, 20);

    expect(
      insightDateRangeForPreset(
        preset: InsightRangePreset.today,
        today: today,
      ).start,
      today,
    );
    expect(
      insightDateRangeForPreset(
        preset: InsightRangePreset.sevenDays,
        today: today,
      ).start,
      today.addDays(-6),
    );
    expect(
      insightDateRangeForPreset(
        preset: InsightRangePreset.thirtyDays,
        today: today,
      ).start,
      today.addDays(-29),
    );
    expect(
      insightDateRangeForPreset(
        preset: InsightRangePreset.thisMonth,
        today: today,
      ).start,
      DateTime(2026, 7),
    );
  });

  test('matchesInsightFilter combines predicates', () {
    final today = DateTime(2026, 7, 20);
    final node = MindmapNode.create(
      id: 'node',
      type: NodeType.task,
      title: 'Launch',
      day: today,
      project: 'Launch',
      area: 'Work',
      tags: const ['release'],
      priority: NodePriority.high,
      status: NodeStatus.doing,
    );

    expect(
      matchesInsightFilter(
        node,
        const InsightFilterState(
          project: 'Launch',
          area: 'Work',
          tag: 'release',
          nodeType: NodeType.task,
          priority: NodePriority.high,
          status: NodeStatus.doing,
        ),
        range: InsightDateRange(start: today.addDays(-1), end: today),
      ),
      isTrue,
    );
    expect(
      matchesInsightFilter(node, const InsightFilterState(project: 'Other')),
      isFalse,
    );
    expect(
      matchesInsightFilter(
        node,
        const InsightFilterState(),
        range: InsightDateRange(start: today.addDays(1), end: today.addDays(2)),
      ),
      isFalse,
    );
  });
}
