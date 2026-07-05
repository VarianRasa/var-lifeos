/// Markdown export for graph diagnostics.
library;

import '../../mindmap/domain/node_graph.dart';
import 'context_graph.dart';
import 'goal_dependency_graph.dart';
import 'graph_overview.dart';
import 'graph_relation_suggestions.dart';
import 'graph_risk_overlay.dart';

String buildGraphMarkdownReport({
  required NodeGraph graph,
  required GraphOverviewSummary overview,
  required ContextGraphSummary contexts,
  required GoalDependencyMap goals,
  required Map<String, List<GraphRiskBadge>> risks,
  required List<GraphRelationSuggestion> suggestions,
}) {
  final buffer = StringBuffer()
    ..writeln('# Graph report')
    ..writeln()
    ..writeln('## Overview')
    ..writeln('- Health: ${overview.healthStatus.label}')
    ..writeln('- Nodes: ${overview.totalNodes}')
    ..writeln('- Relations: ${overview.relationCount}')
    ..writeln('- Connected: ${overview.connectedNodes}')
    ..writeln('- Isolated: ${overview.isolatedNodes}')
    ..writeln('- Hubs: ${overview.hubNodes}')
    ..writeln('- Stale: ${overview.staleNodes}')
    ..writeln('- High-priority open: ${overview.highPriorityOpenNodes}')
    ..writeln()
    ..writeln('## Hubs');
  final hubs =
      graph.nodes
          .where((node) => node.totalDegree >= graphHubDegreeThreshold)
          .toList()
        ..sort((a, b) => b.totalDegree.compareTo(a.totalDegree));
  if (hubs.isEmpty) {
    buffer.writeln('- None');
  } else {
    for (final hub in hubs) {
      buffer.writeln('- ${hub.node.title}: ${hub.totalDegree} links');
    }
  }
  buffer
    ..writeln()
    ..writeln('## Risky nodes');
  if (risks.isEmpty) {
    buffer.writeln('- None');
  } else {
    for (final entry in risks.entries) {
      final title = graph.nodeFor(entry.key)?.node.title ?? entry.key;
      buffer.writeln(
        '- $title: ${entry.value.map((badge) => badge.label).join(', ')}',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Contexts');
  if (contexts.clusters.isEmpty) {
    buffer.writeln('- None');
  } else {
    for (final cluster in contexts.clusters.take(12)) {
      buffer.writeln(
        '- ${cluster.name}: ${cluster.nodeCount} nodes, ${cluster.openTasks} open tasks',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Goals');
  if (goals.goals.isEmpty) {
    buffer.writeln('- None');
  } else {
    for (final goal in goals.goals) {
      buffer.writeln(
        '- ${goal.goal.title}: ${(goal.progress * 100).round()}%, ${goal.dependencies.length} dependencies',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Suggestions');
  if (suggestions.isEmpty) {
    buffer.writeln('- None');
  } else {
    for (final suggestion in suggestions) {
      buffer.writeln(
        '- ${suggestion.source.title} ↔ ${suggestion.target.title} (${suggestion.score}): ${suggestion.reasons.join(', ')}',
      );
    }
  }
  return buffer.toString();
}
