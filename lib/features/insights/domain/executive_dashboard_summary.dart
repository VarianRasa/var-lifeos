/// Executive Dashboard summary model for multi-area Life OS tracking.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';

enum LifeOsArea { work, health, growth, personal }

extension LifeOsAreaX on LifeOsArea {
  String get label => switch (this) {
    LifeOsArea.work => 'Work & Career',
    LifeOsArea.health => 'Health & Vitality',
    LifeOsArea.growth => 'Growth & Learning',
    LifeOsArea.personal => 'Personal & Life',
  };
}

final class AreaMetrics {
  const AreaMetrics({
    required this.area,
    required this.totalNodes,
    required this.completedTasks,
    required this.totalTasks,
    required this.activeGoals,
    required this.averageGoalProgress,
    required this.activeHabits,
  });

  final LifeOsArea area;
  final int totalNodes;
  final int completedTasks;
  final int totalTasks;
  final int activeGoals;
  final double averageGoalProgress;
  final int activeHabits;

  double get taskCompletionRate {
    if (totalTasks == 0) return 0;
    return (completedTasks / totalTasks).clamp(0.0, 1.0);
  }
}

final class ExecutiveDashboardSummary {
  const ExecutiveDashboardSummary({
    required this.healthIndexScore,
    required this.areaMetrics,
    required this.totalActiveGoals,
    required this.totalHabits,
    required this.totalOverdueTasks,
  });

  factory ExecutiveDashboardSummary.fromNodes(Iterable<MindmapNode> nodes) {
    final Map<LifeOsArea, List<MindmapNode>> grouped = {
      for (final area in LifeOsArea.values) area: <MindmapNode>[],
    };

    var totalOverdue = 0;
    final now = DateTime.now();

    for (final node in nodes) {
      if (node.isArchived) continue;

      if (node.type == NodeType.task &&
          node.dueDate != null &&
          node.dueDate!.isBefore(now) &&
          !node.isDone &&
          node.status != NodeStatus.done) {
        totalOverdue++;
      }

      final area = _detectArea(node);
      grouped[area]!.add(node);
    }

    final areaMetricsMap = <LifeOsArea, AreaMetrics>{};
    var totalGoals = 0;
    var totalHabits = 0;

    for (final area in LifeOsArea.values) {
      final areaNodes = grouped[area]!;
      var tasks = 0;
      var completedTasks = 0;
      var goals = 0;
      var goalProgressSum = 0.0;
      var habits = 0;

      for (final n in areaNodes) {
        if (n.type == NodeType.task) {
          tasks++;
          if (n.isDone || n.status == NodeStatus.done) completedTasks++;
        } else if (n.type == NodeType.goal) {
          goals++;
          totalGoals++;
          goalProgressSum += n.progress;
        } else if (n.type == NodeType.habit) {
          habits++;
          totalHabits++;
        }
      }

      areaMetricsMap[area] = AreaMetrics(
        area: area,
        totalNodes: areaNodes.length,
        completedTasks: completedTasks,
        totalTasks: tasks,
        activeGoals: goals,
        averageGoalProgress: goals == 0
            ? 0
            : (goalProgressSum / goals).clamp(0.0, 1.0),
        activeHabits: habits,
      );
    }

    // Health Index calculation (0 - 100)
    var overallGoalProgressSum = 0.0;
    var totalTaskCompletionRate = 0.0;
    for (final m in areaMetricsMap.values) {
      overallGoalProgressSum += m.averageGoalProgress;
      totalTaskCompletionRate += m.taskCompletionRate;
    }

    final avgGoalProg = overallGoalProgressSum / 4.0;
    final avgTaskRate = totalTaskCompletionRate / 4.0;
    final penalty = (totalOverdue * 5).clamp(0, 30);

    final rawHealth = ((avgGoalProg * 50) + (avgTaskRate * 50) - penalty).clamp(
      0.0,
      100.0,
    );

    return ExecutiveDashboardSummary(
      healthIndexScore: rawHealth.round(),
      areaMetrics: areaMetricsMap,
      totalActiveGoals: totalGoals,
      totalHabits: totalHabits,
      totalOverdueTasks: totalOverdue,
    );
  }

  final int healthIndexScore;
  final Map<LifeOsArea, AreaMetrics> areaMetrics;
  final int totalActiveGoals;
  final int totalHabits;
  final int totalOverdueTasks;

  static LifeOsArea _detectArea(MindmapNode node) {
    final titleAndTags = '${node.title} ${node.tags.join(' ')}'.toLowerCase();

    if (titleAndTags.contains('work') ||
        titleAndTags.contains('career') ||
        titleAndTags.contains('job') ||
        titleAndTags.contains('project') ||
        titleAndTags.contains('business') ||
        titleAndTags.contains('proyek')) {
      return LifeOsArea.work;
    }
    if (titleAndTags.contains('health') ||
        titleAndTags.contains('workout') ||
        titleAndTags.contains('fitness') ||
        titleAndTags.contains('sehat') ||
        titleAndTags.contains('gym') ||
        titleAndTags.contains('sleep') ||
        titleAndTags.contains('diet')) {
      return LifeOsArea.health;
    }
    if (titleAndTags.contains('learn') ||
        titleAndTags.contains('growth') ||
        titleAndTags.contains('study') ||
        titleAndTags.contains('book') ||
        titleAndTags.contains('course') ||
        titleAndTags.contains('belajar') ||
        titleAndTags.contains('skill')) {
      return LifeOsArea.growth;
    }
    return LifeOsArea.personal;
  }
}
