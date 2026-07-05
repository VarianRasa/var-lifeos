/// Goal-centered dependency map derived from graph relations.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';
import 'graph_overview.dart';

final class GoalDependencyMap {
  GoalDependencyMap({required List<GoalDependencyItem> goals})
    : goals = List.unmodifiable(goals);

  final List<GoalDependencyItem> goals;
}

final class GoalDependencyItem {
  GoalDependencyItem({
    required this.goal,
    required List<MindmapNode> dependencies,
    required this.missingNextAction,
    required this.stalled,
    required this.progress,
  }) : dependencies = List.unmodifiable(dependencies);

  final MindmapNode goal;
  final List<MindmapNode> dependencies;
  final bool missingNextAction;
  final bool stalled;
  final double progress;
}

GoalDependencyMap buildGoalDependencyMap(NodeGraph graph, {DateTime? now}) {
  final items = <GoalDependencyItem>[];
  for (final graphNode in graph.nodes) {
    final goal = graphNode.node;
    if (goal.type != NodeType.goal) continue;
    final dependencies = graph.neighborsFor(goal.id)..sort(_compareNodes);
    final hasOpenTask = dependencies.any(
      (node) => node.type == NodeType.task && node.status != NodeStatus.done,
    );
    items.add(
      GoalDependencyItem(
        goal: goal,
        dependencies: dependencies,
        missingNextAction: !hasOpenTask,
        stalled: isGraphNodeStale(goal, now: now) && goal.progress < 1,
        progress: goal.progress,
      ),
    );
  }
  items.sort((a, b) => a.goal.title.compareTo(b.goal.title));
  return GoalDependencyMap(goals: items);
}

int _compareNodes(MindmapNode a, MindmapNode b) {
  final type = a.type.index.compareTo(b.type.index);
  if (type != 0) return type;
  final title = a.title.compareTo(b.title);
  if (title != 0) return title;
  return a.id.compareTo(b.id);
}
