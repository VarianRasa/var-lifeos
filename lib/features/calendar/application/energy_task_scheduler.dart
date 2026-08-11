/// Energy-based task scheduling & morning briefing generator.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../domain/time_block.dart';

enum TaskEnergyLevel {
  highPeak('High Energy (Peak Focus)'),
  mediumSteady('Medium Energy (Steady Work)'),
  lowAdmin('Low Energy (Admin & Cleanup)');

  const TaskEnergyLevel(this.label);
  final String label;
}

final class EnergyScheduledTask {
  const EnergyScheduledTask({
    required this.node,
    required this.recommendedEnergy,
    required this.recommendedStartMinute,
  });

  final MindmapNode node;
  final TaskEnergyLevel recommendedEnergy;
  final int recommendedStartMinute;
}

final class DailyMorningBriefing {
  const DailyMorningBriefing({
    required this.peakFocusTasks,
    required this.steadyTasks,
    required this.adminTasks,
    required this.briefingHeadline,
  });

  final List<EnergyScheduledTask> peakFocusTasks;
  final List<EnergyScheduledTask> steadyTasks;
  final List<EnergyScheduledTask> adminTasks;
  final String briefingHeadline;
}

/// Automatically assigns non-overlapping [TimeBlock] allocations for unbudgeted tasks.
Map<String, TimeBlock> autoTimeBlockDay({
  required List<MindmapNode> dayNodes,
  int startWorkMinute = 540, // 09:00 AM
  int endWorkMinute = 1080, // 06:00 PM
}) {
  final briefing = generateDailyMorningBriefing(dayNodes: dayNodes);
  final occupiedBlocks = <TimeBlock>[];

  // Collect existing explicit time blocks
  for (final node in dayNodes) {
    final parsed = parseTimeBlock(node.data['timeBlock']);
    if (parsed.isValid) {
      occupiedBlocks.add(parsed.block!);
    }
  }

  final assignments = <String, TimeBlock>{};

  final allScheduled = [
    ...briefing.peakFocusTasks,
    ...briefing.steadyTasks,
    ...briefing.adminTasks,
  ];

  for (final item in allScheduled) {
    final parsed = parseTimeBlock(item.node.data['timeBlock']);
    if (parsed.isValid) continue; // Already scheduled explicitly

    // Duration default 45 mins for peak, 30 for steady/admin
    final duration = item.recommendedEnergy == TaskEnergyLevel.highPeak
        ? 45
        : 30;

    var candidateStart = item.recommendedStartMinute;
    if (candidateStart < startWorkMinute) candidateStart = startWorkMinute;

    while (candidateStart + duration <= 1440) {
      final candidateEnd = candidateStart + duration;

      final overlaps = occupiedBlocks.any(
        (b) => candidateStart < b.endMinute && candidateEnd > b.startMinute,
      );

      if (!overlaps) {
        final newBlock = TimeBlock(
          startMinute: candidateStart,
          endMinute: candidateEnd,
        );
        occupiedBlocks.add(newBlock);
        assignments[item.node.id] = newBlock;
        break;
      }

      candidateStart += 15; // Shift by 15 mins grid
    }
  }

  return assignments;
}

DailyMorningBriefing generateDailyMorningBriefing({
  required List<MindmapNode> dayNodes,
  double? moodScore,
}) {
  final openTasks = dayNodes
      .where((n) => !n.isArchived && !n.isDone && n.status != NodeStatus.done)
      .toList();

  final peak = <EnergyScheduledTask>[];
  final steady = <EnergyScheduledTask>[];
  final admin = <EnergyScheduledTask>[];

  // Adjust start times and workload if low energy/mood detected
  final isLowEnergy = moodScore != null && moodScore < 2.5;
  var morningMinute = isLowEnergy
      ? 600
      : 540; // Start at 10:00 AM if low energy
  var afternoonMinute = 840; // 02:00 PM
  var eveningMinute = 1020; // 05:00 PM

  for (final node in openTasks) {
    // If low energy, limit heavy peak tasks
    final isHighPriority =
        node.priority == NodePriority.urgent ||
        node.priority == NodePriority.high ||
        node.type == NodeType.plan ||
        node.type == NodeType.goal;

    if (isHighPriority && (!isLowEnergy || peak.length < 2)) {
      peak.add(
        EnergyScheduledTask(
          node: node,
          recommendedEnergy: TaskEnergyLevel.highPeak,
          recommendedStartMinute: morningMinute,
        ),
      );
      morningMinute += 60;
    } else if (node.type == NodeType.task ||
        node.type == NodeType.kanban ||
        isHighPriority) {
      steady.add(
        EnergyScheduledTask(
          node: node,
          recommendedEnergy: TaskEnergyLevel.mediumSteady,
          recommendedStartMinute: afternoonMinute,
        ),
      );
      afternoonMinute += 45;
    } else {
      admin.add(
        EnergyScheduledTask(
          node: node,
          recommendedEnergy: TaskEnergyLevel.lowAdmin,
          recommendedStartMinute: eveningMinute,
        ),
      );
      eveningMinute += 30;
    }
  }

  final totalTasks = openTasks.length;
  final energyNote = isLowEnergy ? ' (Low Energy Mode active)' : '';
  final headline = totalTasks == 0
      ? 'All clear for today! No open tasks scheduled.$energyNote'
      : 'You have $totalTasks open tasks today. Focus on ${peak.length} Peak Focus priorities in the morning.$energyNote';

  return DailyMorningBriefing(
    peakFocusTasks: peak,
    steadyTasks: steady,
    adminTasks: admin,
    briefingHeadline: headline,
  );
}
