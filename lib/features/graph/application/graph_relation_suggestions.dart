/// Relationship suggestions for local graph nodes.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';

final class GraphRelationSuggestion {
  const GraphRelationSuggestion({
    required this.source,
    required this.target,
    required this.score,
    required this.reasons,
  });

  final MindmapNode source;
  final MindmapNode target;
  final int score;
  final List<String> reasons;
}

List<GraphRelationSuggestion> buildGraphRelationSuggestions(
  NodeGraph graph, {
  int limit = 8,
}) {
  final suggestions = <GraphRelationSuggestion>[];
  final existing = {
    for (final edge in graph.edges) '${edge.sourceId}->${edge.targetId}',
    for (final edge in graph.edges) '${edge.targetId}->${edge.sourceId}',
  };
  for (var i = 0; i < graph.nodes.length; i++) {
    for (var j = i + 1; j < graph.nodes.length; j++) {
      final a = graph.nodes[i].node;
      final b = graph.nodes[j].node;
      if (existing.contains('${a.id}->${b.id}')) continue;
      final reasons = <String>[];
      var score = 0;
      if (a.project.isNotEmpty && a.project == b.project) {
        score += 4;
        reasons.add('same project');
      }
      if (a.area.isNotEmpty && a.area == b.area) {
        score += 3;
        reasons.add('same area');
      }
      final sharedTags = a.tags.toSet().intersection(b.tags.toSet());
      if (sharedTags.isNotEmpty) {
        score += sharedTags.length * 2;
        reasons.add('shared tags');
      }
      if (_similarTitle(a.title, b.title)) {
        score += 2;
        reasons.add('similar title');
      }
      if (a.day.difference(b.day).inDays.abs() <= 1) {
        score += 1;
        reasons.add('nearby day');
      }
      if (_isolatedPriorityTask(graph, a) || _isolatedPriorityTask(graph, b)) {
        score += 2;
        reasons.add('priority task needs context');
      }
      if (score >= 3) {
        suggestions.add(
          GraphRelationSuggestion(
            source: a.title.compareTo(b.title) <= 0 ? a : b,
            target: a.title.compareTo(b.title) <= 0 ? b : a,
            score: score,
            reasons: List.unmodifiable(reasons),
          ),
        );
      }
    }
  }
  suggestions.sort((a, b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final source = a.source.title.compareTo(b.source.title);
    if (source != 0) return source;
    return a.target.title.compareTo(b.target.title);
  });
  return suggestions.take(limit).toList(growable: false);
}

bool _similarTitle(String a, String b) {
  final left = a
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((v) => v.length > 3)
      .toSet();
  final right = b
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((v) => v.length > 3)
      .toSet();
  return left.intersection(right).isNotEmpty;
}

bool _isolatedPriorityTask(NodeGraph graph, MindmapNode node) {
  final graphNode = graph.nodeFor(node.id);
  return node.type == NodeType.task &&
      graphNode != null &&
      graphNode.totalDegree == 0 &&
      (node.priority == NodePriority.high ||
          node.priority == NodePriority.urgent);
}
