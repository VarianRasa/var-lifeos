import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/application/insight_risk_engine.dart';
import 'package:var_app/features/mindmap/domain/automation_event.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('buildInsightRisks detects overdue and priority overload', () {
    final today = DateTime(2026, 7, 18);
    final nodes = [
      for (var index = 0; index < 6; index++)
        MindmapNode.create(
          id: 'late-$index',
          type: NodeType.task,
          title: 'Late $index',
          day: today.addDays(-2),
          dueDate: today.addDays(-1),
          priority: NodePriority.high,
        ),
    ];

    final risks = buildInsightRisks(today: today, nodes: nodes);

    expect(risks.map((risk) => risk.id), contains('overdue-cluster'));
    expect(risks.map((risk) => risk.id), contains('high-priority-overload'));
    expect(
      risks.firstWhere((risk) => risk.id == 'overdue-cluster').severity,
      InsightRiskSeverity.critical,
    );
  });

  test('buildInsightRisks detects missing review and habit risk', () {
    final today = DateTime(2026, 7, 18);
    final nodes = [
      MindmapNode.create(
        id: 'habit',
        type: NodeType.habit,
        title: 'Workout',
        day: today,
        data: {
          'habit': {
            'completions': [dayKey(today.addDays(-1))],
          },
        },
      ),
    ];

    final risks = buildInsightRisks(today: today, nodes: nodes);

    expect(risks.map((risk) => risk.id), contains('no-review-this-week'));
    expect(risks.map((risk) => risk.id), contains('habit-streak-at-risk'));
  });

  test('buildInsightRisks detects stale project and unscheduled tasks', () {
    final today = DateTime(2026, 7, 18);
    final nodes = [
      MindmapNode.create(
        id: 'stale',
        type: NodeType.task,
        title: 'Stale task',
        day: today.addDays(-20),
        project: 'Archive',
        now: DateTime(2026, 6, 20),
      ),
      for (var index = 0; index < 8; index++)
        MindmapNode.create(
          id: 'unscheduled-$index',
          type: NodeType.task,
          title: 'Task $index',
          day: today,
        ),
    ];

    final risks = buildInsightRisks(today: today, nodes: nodes);

    expect(risks.map((risk) => risk.id), contains('stale-project-archive'));
    expect(risks.map((risk) => risk.id), contains('unscheduled-task-load'));
  });

  test('buildInsightRisks detects repeated snoozing', () {
    final today = DateTime(2026, 7, 18);
    final nodes = [
      createAutomationEventNode(
        id: 'snooze',
        type: AutomationEventType.snoozeRoutines,
        title: 'Snoozed',
        message: 'Snoozed routines',
        day: today,
        occurredAt: DateTime(2026, 7, 18, 8),
        affectedLabels: const ['A', 'B', 'C'],
      ),
    ];

    final risks = buildInsightRisks(today: today, nodes: nodes);

    expect(risks.map((risk) => risk.id), contains('repeated-snoozing'));
  });

  test('buildInsightRisks detects workload up with completion down', () {
    final today = DateTime(2026, 7, 18);
    final nodes = [
      for (var index = 0; index < 4; index++)
        MindmapNode.create(
          id: 'recent-open-$index',
          type: NodeType.task,
          title: 'Recent open $index',
          day: today,
        ),
      for (var index = 0; index < 3; index++)
        MindmapNode.create(
          id: 'previous-done-$index',
          type: NodeType.task,
          title: 'Previous done $index',
          day: today.addDays(-8),
          status: NodeStatus.done,
        ),
    ];

    final risks = buildInsightRisks(today: today, nodes: nodes);

    expect(
      risks.map((risk) => risk.id),
      contains('workload-up-completion-down'),
    );
  });
}
