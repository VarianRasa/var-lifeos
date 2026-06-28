/// Plan step progress helpers shared by planner surfaces.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';

List<String> planSteps(MindmapNode node) {
  if (node.type != NodeType.plan) return const [];
  return _stringListFromData(_planData(node)['steps']);
}

List<String> completedPlanSteps(MindmapNode node) {
  if (node.type != NodeType.plan) return const [];
  return _stringListFromData(_planData(node)['completedSteps']);
}

String? nextPlanStep(MindmapNode node) {
  final steps = planSteps(node);
  if (steps.isEmpty) return null;

  final completedKeys = {
    for (final step in completedPlanSteps(node)) _normalizedKey(step),
  };
  for (final step in steps) {
    if (!completedKeys.contains(_normalizedKey(step))) return step;
  }
  return null;
}

MindmapNode advancePlanStep(MindmapNode node, {DateTime? now}) {
  if (node.type != NodeType.plan) return node;

  final steps = planSteps(node);
  final nextStep = nextPlanStep(node);
  if (steps.isEmpty || nextStep == null) return node;

  final completed = completedPlanSteps(node);
  final nextCompleted = [...completed, nextStep];
  final stepKeys = {for (final step in steps) _normalizedKey(step)};
  final completedCount = {
    for (final step in nextCompleted)
      if (stepKeys.contains(_normalizedKey(step))) _normalizedKey(step),
  }.length;
  final progress = completedCount / steps.length;
  final isComplete = completedCount == steps.length;
  final planData = _planData(node);

  return node.copyWith(
    data: {
      ...node.data,
      'plan': {...planData, 'steps': steps, 'completedSteps': nextCompleted},
    },
    progress: progress,
    status: isComplete
        ? NodeStatus.done
        : node.status == NodeStatus.open
        ? NodeStatus.doing
        : node.status,
    isDone: isComplete ? true : node.isDone,
    updatedAt: now ?? DateTime.now(),
  );
}

Map<String, Object?> _planData(MindmapNode node) {
  final section = node.data['plan'];
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
