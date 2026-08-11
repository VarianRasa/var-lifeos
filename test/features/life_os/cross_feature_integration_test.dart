import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/calendar/application/energy_task_scheduler.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('Cross Feature Integration - Energy Scheduler with Mood', () {
    test(
      'low energy mood (<2.5) reduces peak task workload and delays start time',
      () {
        final now = DateTime.now();
        final day = now.dateOnly;

        final tasks = [
          MindmapNode(
            id: 't1',
            day: day,
            type: NodeType.task,
            title: 'Urgent Task 1',
            priority: NodePriority.urgent,
            createdAt: now,
            updatedAt: now,
          ),
          MindmapNode(
            id: 't2',
            day: day,
            type: NodeType.task,
            title: 'Urgent Task 2',
            priority: NodePriority.urgent,
            createdAt: now,
            updatedAt: now,
          ),
          MindmapNode(
            id: 't3',
            day: day,
            type: NodeType.task,
            title: 'Urgent Task 3',
            priority: NodePriority.urgent,
            createdAt: now,
            updatedAt: now,
          ),
        ];

        final normalBriefing = generateDailyMorningBriefing(
          dayNodes: tasks,
          moodScore: 4.5,
        );
        expect(normalBriefing.peakFocusTasks.length, equals(3));
        expect(
          normalBriefing.peakFocusTasks.first.recommendedStartMinute,
          equals(540),
        ); // 09:00 AM

        final lowEnergyBriefing = generateDailyMorningBriefing(
          dayNodes: tasks,
          moodScore: 1.5,
        );
        // Peak task capped at 2 under low energy
        expect(lowEnergyBriefing.peakFocusTasks.length, equals(2));
        expect(
          lowEnergyBriefing.peakFocusTasks.first.recommendedStartMinute,
          equals(600),
        ); // 10:00 AM
        expect(
          lowEnergyBriefing.briefingHeadline,
          contains('Low Energy Mode active'),
        );
      },
    );
  });
}
