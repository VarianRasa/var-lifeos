library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';

class MoodCorrelationPoint {
  const MoodCorrelationPoint({
    required this.day,
    required this.moodScore,
    required this.completedTasks,
  });

  final DateTime day;
  final double moodScore;
  final int completedTasks;
}

class MoodProductivityAnalytics {
  static List<MoodCorrelationPoint> compute(Iterable<MindmapNode> nodes) {
    final map =
        <DateTime, ({double moodSum, int moodCount, int completedTasks})>{};

    for (final node in nodes) {
      if (node.isArchived) continue;
      final day = DateTime(node.day.year, node.day.month, node.day.day);
      final entry = map[day] ?? (moodSum: 0.0, moodCount: 0, completedTasks: 0);

      double addedMood = 0;
      int addedMoodCount = 0;
      int addedTasks = 0;

      if (node.type == NodeType.mood) {
        final rating =
            (node.data['mood'] as Map<String, dynamic>?)?['rating'] ?? 3.0;
        addedMood = (rating as num).toDouble();
        addedMoodCount = 1;
      } else if (node.type == NodeType.journal &&
          node.data['journal'] != null) {
        final rating =
            (node.data['journal'] as Map<String, dynamic>?)?['moodRating'];
        if (rating is num) {
          addedMood = rating.toDouble();
          addedMoodCount = 1;
        }
      }

      if (node.type == NodeType.task && node.status == NodeStatus.done) {
        addedTasks = 1;
      }

      map[day] = (
        moodSum: entry.moodSum + addedMood,
        moodCount: entry.moodCount + addedMoodCount,
        completedTasks: entry.completedTasks + addedTasks,
      );
    }

    final result = <MoodCorrelationPoint>[];
    for (final e in map.entries) {
      if (e.value.moodCount > 0) {
        result.add(
          MoodCorrelationPoint(
            day: e.key,
            moodScore: e.value.moodSum / e.value.moodCount,
            completedTasks: e.value.completedTasks,
          ),
        );
      }
    }

    result.sort((a, b) => a.day.compareTo(b.day));
    return result;
  }
}
