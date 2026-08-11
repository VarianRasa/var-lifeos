import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/widgets/daily_timeline_schedule.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  testWidgets(
    'DailyTimelineSchedule renders workload header and timeline entries',
    (tester) async {
      final day = DateTime(2026, 8, 7);
      final scheduledNode = MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Scheduled Task',
        day: day,
        data: const {
          'timeBlockStart': 540, // 09:00 AM
          'timeBlockEnd': 600, // 10:00 AM
        },
      );

      final unscheduledNode = MindmapNode.create(
        id: 'task-2',
        type: NodeType.task,
        title: 'Unscheduled Task',
        day: day,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [currentDateProvider.overrideWithValue(day)],
          child: MaterialApp(
            home: Scaffold(
              body: DailyTimelineSchedule(
                day: day,
                nodes: [scheduledNode, unscheduledNode],
                onNodeSelected: (_) {},
                onTaskDoneChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Daily Workload:'), findsOneWidget);
      expect(find.text('Unscheduled Task'), findsOneWidget);
      expect(find.text('Scheduled Task'), findsOneWidget);
    },
  );
}
