/// Goal milestone helpers shared by Life OS surfaces.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';

List<String> goalMilestones(MindmapNode node) {
  if (node.type != NodeType.goal) return const [];
  return _stringListFromData(_goalData(node)['milestones']);
}

List<String> completedGoalMilestones(MindmapNode node) {
  if (node.type != NodeType.goal) return const [];
  return _stringListFromData(_goalData(node)['completedMilestones']);
}

String? nextGoalMilestone(MindmapNode node) {
  final milestones = goalMilestones(node);
  if (milestones.isEmpty) return null;

  final completedKeys = {
    for (final milestone in completedGoalMilestones(node))
      _normalizedKey(milestone),
  };
  for (final milestone in milestones) {
    if (!completedKeys.contains(_normalizedKey(milestone))) {
      return milestone;
    }
  }
  return null;
}

MindmapNode advanceGoalMilestone(MindmapNode node, {DateTime? now}) {
  if (node.type != NodeType.goal) return node;

  final milestones = goalMilestones(node);
  final nextMilestone = nextGoalMilestone(node);
  if (milestones.isEmpty || nextMilestone == null) return node;

  final completed = completedGoalMilestones(node);
  final nextCompleted = [...completed, nextMilestone];
  final milestoneKeys = {
    for (final milestone in milestones) _normalizedKey(milestone),
  };
  final completedCount = {
    for (final milestone in nextCompleted)
      if (milestoneKeys.contains(_normalizedKey(milestone)))
        _normalizedKey(milestone),
  }.length;

  final goalData = _goalData(node);
  return node.copyWith(
    progress: completedCount / milestones.length,
    data: {
      ...node.data,
      'goal': {
        ...goalData,
        'milestones': milestones,
        'completedMilestones': nextCompleted,
      },
    },
    updatedAt: now ?? DateTime.now(),
  );
}

Map<String, Object?> _goalData(MindmapNode node) {
  final section = node.data['goal'];
  if (section is Map) return section.cast<String, Object?>();
  return const {};
}

List<String> _stringListFromData(Object? value) {
  final rawValues = switch (value) {
    List() => [
      for (final item in value)
        if (item is String) item,
    ],
    String() => value.split(RegExp(r'[,\n]')),
    _ => const <String>[],
  };
  final seen = <String>{};
  final values = <String>[];

  for (final rawValue in rawValues) {
    final value = rawValue.trim();
    if (value.isEmpty || !seen.add(_normalizedKey(value))) continue;
    values.add(value);
  }

  return values;
}

String _normalizedKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
