import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/energy_task_scheduler.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('Daily Energy-Based Task Scheduler Engine', () {
    final today = DateTime(2026, 8, 7);

    test('categorizes high priority tasks into morning peak focus', () {
      final highTask = MindmapNode.create(
        id: 'high-task',
        type: NodeType.task,
        title: 'Refactor Core Engine',
        priority: NodePriority.high,
        day: today,
      );

      final normalTask = MindmapNode.create(
        id: 'normal-task',
        type: NodeType.task,
        title: 'Review PRs',
        priority: NodePriority.medium,
        day: today,
      );

      final briefing = generateDailyMorningBriefing(
        dayNodes: [highTask, normalTask],
      );

      expect(briefing.peakFocusTasks.length, equals(1));
      expect(
        briefing.peakFocusTasks.first.node.title,
        equals('Refactor Core Engine'),
      );
      expect(briefing.steadyTasks.length, equals(1));
      expect(
        briefing.briefingHeadline,
        contains('Focus on 1 Peak Focus priorities'),
      );
    });
  });
}
