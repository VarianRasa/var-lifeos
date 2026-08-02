import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/domain/executive_dashboard_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('ExecutiveDashboardSummary', () {
    test('groups nodes by detected area and calculates health index', () {
      final now = DateTime.now();
      final nodes = [
        MindmapNode(
          id: '1',
          type: NodeType.task,
          title: 'Work Project Task',
          day: now,
          createdAt: now,
          updatedAt: now,
          isDone: true,
        ),
        MindmapNode(
          id: '2',
          type: NodeType.goal,
          title: 'Health Fitness Goal',
          day: now,
          createdAt: now,
          updatedAt: now,
          progress: 0.8,
        ),
        MindmapNode(
          id: '3',
          type: NodeType.habit,
          title: 'Daily Book Reading Growth',
          day: now,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final summary = ExecutiveDashboardSummary.fromNodes(nodes);

      expect(summary.areaMetrics[LifeOsArea.work]?.completedTasks, 1);
      expect(summary.areaMetrics[LifeOsArea.health]?.activeGoals, 1);
      expect(summary.areaMetrics[LifeOsArea.health]?.averageGoalProgress, 0.8);
      expect(summary.areaMetrics[LifeOsArea.growth]?.activeHabits, 1);
      expect(summary.healthIndexScore, greaterThan(0));
    });
  });
}
