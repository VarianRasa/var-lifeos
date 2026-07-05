import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/application/insight_cache.dart';
import 'package:var_app/features/insights/application/insight_filters.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('buildInsightNodeIndex precomputes shared counts and slices', () {
    final today = DateTime(2026, 7, 2);
    final yesterday = DateTime(2026, 7, 1);
    final nodes = [
      MindmapNode.create(
        id: 'done-task',
        type: NodeType.task,
        title: 'Done task',
        day: today,
        status: NodeStatus.done,
        project: 'Var',
        now: today,
      ),
      MindmapNode.create(
        id: 'late-task',
        type: NodeType.task,
        title: 'Late task',
        day: today,
        priority: NodePriority.high,
        dueDate: yesterday,
        project: 'Var',
        now: today,
      ),
      MindmapNode.create(
        id: 'archived-task',
        type: NodeType.task,
        title: 'Archived',
        day: today,
        isArchived: true,
        now: today,
      ),
      MindmapNode.create(
        id: 'habit',
        type: NodeType.habit,
        title: 'Habit',
        day: today,
        project: 'Var',
        now: today,
      ),
    ];

    final index = buildInsightNodeIndex(
      nodes: nodes,
      filter: const InsightFilterState(project: 'Var'),
      range: InsightDateRange(start: yesterday, end: today),
      today: today,
    );

    expect(index.activeCount, 3);
    expect(index.scopedCount, 3);
    expect(index.completedCount, 1);
    expect(index.openTaskCount, 1);
    expect(index.overdueTaskNodes.map((node) => node.id), ['late-task']);
    expect(index.highPriorityOpenTaskNodes.map((node) => node.id), [
      'late-task',
    ]);
    expect(index.typeCounts[NodeType.task], 2);
    expect(index.typeCounts[NodeType.habit], 1);
  });

  test('buildInsightNodeIndex applies range and filter to scoped slices', () {
    final today = DateTime(2026, 7, 2);
    final oldDay = DateTime(2026, 6, 1);
    final nodes = [
      MindmapNode.create(
        id: 'in-range',
        type: NodeType.task,
        title: 'In range',
        day: today,
        tags: const ['release'],
        now: today,
      ),
      MindmapNode.create(
        id: 'out-of-range',
        type: NodeType.task,
        title: 'Out of range',
        day: oldDay,
        tags: const ['release'],
        now: oldDay,
      ),
    ];

    final index = buildInsightNodeIndex(
      nodes: nodes,
      filter: const InsightFilterState(tag: 'release'),
      range: InsightDateRange(start: today, end: today),
      today: today,
    );

    expect(index.activeCount, 2);
    expect(index.scopedNodes.map((node) => node.id), ['in-range']);
    expect(index.openTaskNodes.map((node) => node.id), ['in-range']);
  });
}
