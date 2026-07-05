import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/application/context_health.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('scoreContextHealth classifies good watch stale critical', () {
    final today = DateTime(2026, 7, 12);

    expect(
      scoreContextHealth(
        openTasks: 1,
        overdueTasks: 0,
        highPriorityOpenTasks: 0,
        lastActivity: today,
        today: today,
      ),
      ContextHealthStatus.good,
    );
    expect(
      scoreContextHealth(
        openTasks: 6,
        overdueTasks: 0,
        highPriorityOpenTasks: 0,
        lastActivity: today,
        today: today,
      ),
      ContextHealthStatus.watch,
    );
    expect(
      scoreContextHealth(
        openTasks: 1,
        overdueTasks: 0,
        highPriorityOpenTasks: 0,
        lastActivity: today.addDays(-14),
        today: today,
      ),
      ContextHealthStatus.stale,
    );
    expect(
      scoreContextHealth(
        openTasks: 4,
        overdueTasks: 3,
        highPriorityOpenTasks: 0,
        lastActivity: today,
        today: today,
      ),
      ContextHealthStatus.critical,
    );
  });

  test('buildContextHealthSummary rolls up project and area health', () {
    final today = DateTime(2026, 7, 12);
    final staleDate = today.addDays(-16);
    final nodes = [
      MindmapNode.create(
        id: 'launch-open',
        type: NodeType.task,
        title: 'Launch open',
        day: today,
        project: 'Launch',
        area: 'Work',
        priority: NodePriority.high,
        dueDate: today.addDays(-1),
        now: DateTime(2026, 7, 12, 8),
      ),
      MindmapNode.create(
        id: 'launch-done',
        type: NodeType.task,
        title: 'Launch done',
        day: today,
        project: 'Launch',
        area: 'Work',
        status: NodeStatus.done,
        now: DateTime(2026, 7, 12, 9),
      ),
      MindmapNode.create(
        id: 'stale-open',
        type: NodeType.task,
        title: 'Stale open',
        day: staleDate,
        project: 'Archive',
        area: 'Admin',
        now: DateTime(2026, 6, 25, 9),
      ),
    ];

    final summary = buildContextHealthSummary(today: today, nodes: nodes);
    final launch = summary.items.singleWhere(
      (item) => item.name == 'Launch' && item.isProject,
    );
    final archive = summary.items.singleWhere(
      (item) => item.name == 'Archive' && item.isProject,
    );

    expect(launch.openTasks, 1);
    expect(launch.completedTasks, 1);
    expect(launch.overdueTasks, 1);
    expect(launch.highPriorityOpenTasks, 1);
    expect(launch.status, ContextHealthStatus.watch);
    expect(archive.status, ContextHealthStatus.stale);
    expect(
      summary.neglectedContexts.map((item) => item.name),
      contains('Archive'),
    );
    expect(summary.hotContexts.map((item) => item.name), contains('Launch'));
  });
}
