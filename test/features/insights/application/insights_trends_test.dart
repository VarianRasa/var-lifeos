import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/application/insights_trends.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('buildCompletionTrend returns stable sorted daily points', () {
    final today = DateTime(2026, 6, 18);
    final start = today.addDays(-2);
    final nodes = [
      MindmapNode.create(
        id: 'day-3-open',
        type: NodeType.task,
        title: 'Open',
        day: today,
        priority: NodePriority.high,
        dueDate: today.addDays(-1),
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'day-1-done',
        type: NodeType.task,
        title: 'Done',
        day: start,
        status: NodeStatus.done,
        now: DateTime(2026, 6, 16, 8),
      ),
      MindmapNode.create(
        id: 'ignored-note',
        type: NodeType.note,
        title: 'Note',
        day: today,
        now: DateTime(2026, 6, 18, 9),
      ),
    ];

    final trend = buildCompletionTrend(
      start: start,
      end: today,
      today: today,
      nodes: nodes,
    );

    expect(trend.points.map((point) => point.day), [
      DateTime(2026, 6, 16),
      DateTime(2026, 6, 17),
      DateTime(2026, 6, 18),
    ]);
    expect(trend.points.first.completedTasks, 1);
    expect(trend.points[1].openTasks, 0);
    expect(trend.points.last.openTasks, 1);
    expect(trend.points.last.overdueTasks, 1);
    expect(trend.points.last.highPriorityOpenTasks, 1);
  });

  test('classifyInsightTrend detects direction labels', () {
    expect(classifyInsightTrend(const [1, 2, 3]), InsightTrendDirection.up);
    expect(classifyInsightTrend(const [3, 2, 1]), InsightTrendDirection.down);
    expect(classifyInsightTrend(const [2, 2, 2]), InsightTrendDirection.flat);
    expect(
      classifyInsightTrend(const [1, 3, 2, 4, 2]),
      InsightTrendDirection.volatile,
    );
  });

  test('buildCompletionTrend summarizes workload direction', () {
    final today = DateTime(2026, 6, 18);
    final nodes = [
      MindmapNode.create(
        id: 'a',
        type: NodeType.task,
        title: 'A',
        day: today.addDays(-2),
        status: NodeStatus.done,
        now: DateTime(2026, 6, 16, 8),
      ),
      MindmapNode.create(
        id: 'b',
        type: NodeType.task,
        title: 'B',
        day: today.addDays(-1),
        status: NodeStatus.done,
        now: DateTime(2026, 6, 17, 8),
      ),
      MindmapNode.create(
        id: 'c',
        type: NodeType.task,
        title: 'C',
        day: today.addDays(-1),
        status: NodeStatus.done,
        now: DateTime(2026, 6, 17, 9),
      ),
      MindmapNode.create(
        id: 'd',
        type: NodeType.task,
        title: 'D',
        day: today,
        status: NodeStatus.done,
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'e',
        type: NodeType.task,
        title: 'E',
        day: today,
        status: NodeStatus.done,
        now: DateTime(2026, 6, 18, 9),
      ),
      MindmapNode.create(
        id: 'f',
        type: NodeType.task,
        title: 'F',
        day: today,
        status: NodeStatus.done,
        now: DateTime(2026, 6, 18, 10),
      ),
    ];

    final trend = buildCompletionTrend(
      start: today.addDays(-2),
      end: today,
      today: today,
      nodes: nodes,
    );

    expect(trend.completionDirection, InsightTrendDirection.up);
    expect(trend.openWorkDirection, InsightTrendDirection.flat);
  });
}
