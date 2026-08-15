/// Life OS Weekly Pulse Report Engine.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class LifeOsWeeklyPulseReport {
  const LifeOsWeeklyPulseReport({
    required this.start,
    required this.end,
    required this.completedTasksCount,
    required this.habitsKeptCount,
    required this.averageMoodScore,
    required this.activeGoalsCount,
    required this.markdownSummary,
  });

  final DateTime start;
  final DateTime end;
  final int completedTasksCount;
  final int habitsKeptCount;
  final double averageMoodScore;
  final int activeGoalsCount;
  final String markdownSummary;

  factory LifeOsWeeklyPulseReport.generate({
    required DateTime start,
    required DateTime end,
    required Iterable<MindmapNode> nodes,
    required String winsText,
    required String lessonsText,
    required String nextFocusText,
    required double moodRating,
  }) {
    final startNorm = start.dateOnly;
    final endNorm = end.dateOnly;

    var completedTasks = 0;
    var habitsKept = 0;
    var activeGoals = 0;

    for (final node in nodes) {
      if (node.isArchived) continue;

      if (node.type == NodeType.task &&
          (node.isDone || node.status == NodeStatus.done)) {
        final updated = node.updatedAt.dateOnly;
        if (!updated.isBefore(startNorm) && !updated.isAfter(endNorm)) {
          completedTasks++;
        }
      } else if (node.type == NodeType.habit) {
        habitsKept++;
      } else if (node.type == NodeType.goal && !node.isDone) {
        activeGoals++;
      }
    }

    final buf = StringBuffer()
      ..writeline('# 🚀 Life OS Weekly Pulse Report')
      ..writeline(
        '**Period:** ${startNorm.year}-${startNorm.month.toString().padLeft(2, '0')}-${startNorm.day.toString().padLeft(2, '0')} to ${endNorm.year}-${endNorm.month.toString().padLeft(2, '0')}-${endNorm.day.toString().padLeft(2, '0')}\n',
      )
      ..writeline('## 📊 Weekly Stats')
      ..writeline('- **Completed Tasks:** $completedTasks')
      ..writeline('- **Active Habits Kept:** $habitsKept')
      ..writeline('- **Active Goals in Progress:** $activeGoals')
      ..writeline(
        '- **Weekly Mood Score:** ${moodRating.toStringAsFixed(1)} / 5.0\n',
      )
      ..writeline('## 🏆 Wins & Accomplishments')
      ..writeline(winsText.trim().isEmpty ? '- No wins recorded' : winsText)
      ..writeline('\n## 💡 Key Lessons & Reflection')
      ..writeline(
        lessonsText.trim().isEmpty ? '- No lessons recorded' : lessonsText,
      )
      ..writeline('\n## 🎯 Next Week Core Focus')
      ..writeline(
        nextFocusText.trim().isEmpty
            ? '- Continue regular cadence'
            : nextFocusText,
      );

    return LifeOsWeeklyPulseReport(
      start: start,
      end: end,
      completedTasksCount: completedTasks,
      habitsKeptCount: habitsKept,
      averageMoodScore: moodRating,
      activeGoalsCount: activeGoals,
      markdownSummary: buf.toString(),
    );
  }
}

extension on StringBuffer {
  void writeline(String text) {
    writeln(text);
  }
}
