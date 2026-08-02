import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/application/mood_productivity_correlation.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test(
    'MoodProductivityAnalytics aggregates completed tasks and mood scores',
    () {
      final day = DateTime(2026, 7, 21);
      final nodes = [
        MindmapNode.create(
          id: 'mood-1',
          title: 'Mood check',
          day: day,
          type: NodeType.mood,
          data: {
            'mood': {'rating': 4.0},
          },
        ),
        MindmapNode.create(
          id: 'task-1',
          title: 'Finished Task',
          day: day,
          type: NodeType.task,
          status: NodeStatus.done,
        ),
      ];

      final result = MoodProductivityAnalytics.compute(nodes);
      expect(result.length, 1);
      expect(result.first.moodScore, 4.0);
      expect(result.first.completedTasks, 1);
    },
  );
}
