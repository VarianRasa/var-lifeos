import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/widgets/daily_timeline_schedule.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

Widget _buildTestApp({
  required DateTime day,
  required List<MindmapNode> nodes,
  required void Function(MindmapNode) onNodeSelected,
  required void Function(MindmapNode, bool) onTaskDoneChanged,
}) {
  final repository = InMemoryMindmapRepository(seedNodes: nodes);
  return ProviderScope(
    overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Scaffold(
        body: DailyTimelineSchedule(
          day: day,
          nodes: nodes,
          onNodeSelected: onNodeSelected,
          onTaskDoneChanged: onTaskDoneChanged,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('core timeline', () {
    testWidgets('renders scheduled task and allows completion toggle', (
      tester,
    ) async {
      final day = DateTime(2026, 6, 25);
      final scheduledNode =
          MindmapNode.create(
            id: 'node-1',
            type: NodeType.task,
            title: 'Scheduled Task 1',
            day: day,
            now: DateTime(2026, 6, 25, 8),
          ).copyWith(
            data: {
              'time_block': {'startTime': '09:00', 'endTime': '10:00'},
            },
          );

      bool doneChanged = false;
      bool selected = false;

      await tester.pumpWidget(
        _buildTestApp(
          day: day,
          nodes: [scheduledNode],
          onNodeSelected: (_) => selected = true,
          onTaskDoneChanged: (_, _) => doneChanged = true,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Scheduled Task 1'), findsOneWidget);
      expect(find.text('09:00 - 10:00 • Task'), findsOneWidget);

      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(doneChanged, isTrue);

      await tester.tap(find.text('Scheduled Task 1'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
    });

    testWidgets('shows unscheduled lane for nodes without time_block', (
      tester,
    ) async {
      final day = DateTime(2026, 6, 25);
      final unscheduled = MindmapNode.create(
        id: 'node-2',
        type: NodeType.note,
        title: 'Unscheduled Note',
        day: day,
        now: DateTime(2026, 6, 25, 8),
      );

      await tester.pumpWidget(
        _buildTestApp(
          day: day,
          nodes: [unscheduled],
          onNodeSelected: (_) {},
          onTaskDoneChanged: (_, _) {},
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Unscheduled'), findsAtLeastNWidgets(1));
      expect(find.text('Unscheduled Note'), findsOneWidget);
    });
  });

  group('malformed', () {
    testWidgets('invalid time_block does not crash', (tester) async {
      final day = DateTime(2026, 6, 25);
      final badNode = MindmapNode.create(
        id: 'bad-1',
        type: NodeType.task,
        title: 'Bad Block',
        day: day,
        now: DateTime(2026, 6, 25, 8),
      ).copyWith(data: {'time_block': 'not_a_map'});

      await tester.pumpWidget(
        _buildTestApp(
          day: day,
          nodes: [badNode],
          onNodeSelected: (_) {},
          onTaskDoneChanged: (_, _) {},
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid schedule'), findsOneWidget);
    });
  });

  group('overlap', () {
    testWidgets('two overlapping blocks render', (tester) async {
      final day = DateTime(2026, 6, 25);
      final node1 =
          MindmapNode.create(
            id: 'o1',
            type: NodeType.task,
            title: 'Overlap 1',
            day: day,
            now: DateTime(2026, 6, 25, 8),
          ).copyWith(
            data: {
              'time_block': {'startTime': '09:00', 'endTime': '10:00'},
            },
          );
      final node2 =
          MindmapNode.create(
            id: 'o2',
            type: NodeType.task,
            title: 'Overlap 2',
            day: day,
            now: DateTime(2026, 6, 25, 8),
          ).copyWith(
            data: {
              'time_block': {'startTime': '09:30', 'endTime': '10:30'},
            },
          );

      await tester.pumpWidget(
        _buildTestApp(
          day: day,
          nodes: [node1, node2],
          onNodeSelected: (_) {},
          onTaskDoneChanged: (_, _) {},
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Overlap 1'), findsOneWidget);
      expect(find.text('Overlap 2'), findsOneWidget);
    });
  });
}
