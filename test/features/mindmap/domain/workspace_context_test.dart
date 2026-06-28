import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';

void main() {
  test('WorkspaceContext calculates active progress and risk metrics', () {
    final today = DateTime(2026, 6, 19);
    final nodes = [
      MindmapNode.create(
        id: 'launch-done',
        type: NodeType.task,
        title: 'Launch done',
        day: today,
        project: 'Launch App',
        status: NodeStatus.done,
        priority: NodePriority.high,
        now: DateTime(2026, 6, 19, 8),
      ),
      MindmapNode.create(
        id: 'launch-overdue',
        type: NodeType.task,
        title: 'Launch overdue',
        day: today.subtract(const Duration(days: 2)),
        project: 'Launch App',
        status: NodeStatus.doing,
        priority: NodePriority.high,
        dueDate: today.subtract(const Duration(days: 1)),
        now: DateTime(2026, 6, 19, 9),
      ),
      MindmapNode.create(
        id: 'launch-goal',
        type: NodeType.goal,
        title: 'Launch goal',
        day: today,
        project: 'Launch App',
        progress: 0.5,
        now: DateTime(2026, 6, 19, 10),
      ),
      MindmapNode.create(
        id: 'launch-archived',
        type: NodeType.task,
        title: 'Launch archived',
        day: today,
        project: 'Launch App',
        dueDate: today.subtract(const Duration(days: 1)),
        isArchived: true,
        now: DateTime(2026, 6, 19, 11),
      ),
      MindmapNode.create(
        id: 'health-habit',
        type: NodeType.habit,
        title: 'Workout',
        day: today,
        area: 'Health',
        progress: 0.25,
        now: DateTime(2026, 6, 19, 12),
      ),
    ];

    final contexts = WorkspaceContexts.fromNodes(nodes);
    final project = contexts.contextFor(
      WorkspaceContextType.project,
      'Launch App',
    );
    final area = contexts.contextFor(WorkspaceContextType.area, 'Health');

    expect(project.activeNodeCount, 3);
    expect(project.completedCount, 1);
    expect(project.highPriorityCount, 2);
    expect(project.overdueCount(today), 1);
    expect(project.completionRate, closeTo(1 / 3, 0.001));
    expect(project.averageProgress, closeTo(0.5, 0.001));
    expect(project.healthLabel(today), '1 overdue / 2 high / 50% progress');

    expect(area.activeNodeCount, 1);
    expect(area.averageProgress, 0.25);
    expect(area.healthLabel(today), '25% progress');
  });

  test('WorkspaceContext returns prioritized next actions', () {
    final today = DateTime(2026, 6, 19);
    final nodes = [
      MindmapNode.create(
        id: 'done',
        type: NodeType.task,
        title: 'Done task',
        day: today,
        project: 'Launch App',
        status: NodeStatus.done,
        dueDate: today.subtract(const Duration(days: 3)),
        now: DateTime(2026, 6, 19, 8),
      ),
      MindmapNode.create(
        id: 'archived',
        type: NodeType.task,
        title: 'Archived task',
        day: today,
        project: 'Launch App',
        isArchived: true,
        priority: NodePriority.urgent,
        dueDate: today.subtract(const Duration(days: 2)),
        now: DateTime(2026, 6, 19, 9),
      ),
      MindmapNode.create(
        id: 'overdue-low',
        type: NodeType.task,
        title: 'Overdue low',
        day: today,
        project: 'Launch App',
        priority: NodePriority.low,
        dueDate: today.subtract(const Duration(days: 1)),
        now: DateTime(2026, 6, 19, 10),
      ),
      MindmapNode.create(
        id: 'today-high',
        type: NodeType.task,
        title: 'Today high',
        day: today,
        project: 'Launch App',
        priority: NodePriority.high,
        dueDate: today,
        now: DateTime(2026, 6, 19, 11),
      ),
      MindmapNode.create(
        id: 'no-date-urgent',
        type: NodeType.goal,
        title: 'No date urgent',
        day: today,
        project: 'Launch App',
        priority: NodePriority.urgent,
        now: DateTime(2026, 6, 19, 12),
      ),
    ];

    final project = WorkspaceContexts.fromNodes(
      nodes,
    ).contextFor(WorkspaceContextType.project, 'Launch App');

    expect(project.nextActions(today).map((node) => node.id), [
      'overdue-low',
      'today-high',
      'no-date-urgent',
    ]);
    expect(project.nextActions(today, limit: 2).map((node) => node.id), [
      'overdue-low',
      'today-high',
    ]);
  });
}
