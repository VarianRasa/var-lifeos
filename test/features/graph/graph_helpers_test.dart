import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/graph/application/context_graph.dart';
import 'package:var_app/features/graph/application/goal_dependency_graph.dart';
import 'package:var_app/features/graph/application/graph_filters.dart';
import 'package:var_app/features/graph/application/graph_index.dart';
import 'package:var_app/features/graph/application/graph_markdown_export.dart';
import 'package:var_app/features/graph/application/graph_overview.dart';
import 'package:var_app/features/graph/application/graph_relation_suggestions.dart';
import 'package:var_app/features/graph/application/graph_relationship_insights.dart';
import 'package:var_app/features/graph/application/graph_risk_overlay.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';

void main() {
  test('filters relation states and keeps stable ordering', () {
    final graph = _graph();

    final nodes = filteredGraphNodes(
      graph.nodes,
      const GraphFilterState(relationState: GraphRelationState.hub),
    );

    expect(nodes.map((node) => node.id), ['goal']);
  });

  test('builds graph index adjacency maps', () {
    final index = buildGraphIndex(_graph());

    expect(index.outgoingFor('goal').length, 3);
    expect(index.incomingFor('task').length, 1);
    expect(index.neighborsFor('task'), contains('goal'));
  });

  test('builds context clusters', () {
    final summary = buildContextGraphSummary(
      _graph().nodes.map((node) => node.node),
      mode: ContextGraphMode.projects,
      now: DateTime(2026, 6, 18),
    );

    expect(summary.clusters.first.name, 'Launch');
    expect(summary.clusters.first.nodeCount, 4);
    expect(summary.clusters.first.openTasks, 1);
  });

  test('builds goal dependency map and risk badges', () {
    final graph = _graph();

    final goals = buildGoalDependencyMap(graph, now: DateTime(2026, 6, 18));
    final risks = buildGraphRiskOverlay(graph, now: DateTime(2026, 6, 18));

    expect(goals.goals.single.dependencies.length, 3);
    expect(goals.goals.single.missingNextAction, isFalse);
    expect(risks['task']!.map((badge) => badge.label), contains('Overdue'));
  });

  test('builds relationship insights and suggestions', () {
    final graph = _graph();

    final insights = buildGraphRelationshipInsights(
      graph,
      now: DateTime(2026, 6, 18),
    );
    final suggestions = buildGraphRelationSuggestions(graph);

    expect(insights.map((insight) => insight.title), contains('Hub nodes'));
    expect(suggestions.first.reasons, contains('same project'));
  });

  test('exports markdown report sections', () {
    final graph = _graph();
    final overview = buildGraphOverview(graph, now: DateTime(2026, 6, 18));
    final contexts = buildContextGraphSummary(
      graph.nodes.map((node) => node.node),
      mode: ContextGraphMode.projects,
      now: DateTime(2026, 6, 18),
    );

    final report = buildGraphMarkdownReport(
      graph: graph,
      overview: overview,
      contexts: contexts,
      goals: buildGoalDependencyMap(graph, now: DateTime(2026, 6, 18)),
      risks: buildGraphRiskOverlay(graph, now: DateTime(2026, 6, 18)),
      suggestions: buildGraphRelationSuggestions(graph),
    );

    expect(report, contains('# Graph report'));
    expect(report, contains('## Overview'));
    expect(report, contains('## Suggestions'));
  });
}

NodeGraph _graph() {
  final now = DateTime(2026, 6, 18, 9);
  return NodeGraph.fromNodes([
    MindmapNode.create(
      id: 'goal',
      type: NodeType.goal,
      title: 'Launch goal',
      day: DateTime(2026, 6, 18),
      project: 'Launch',
      progress: 0.4,
      relatedNodeIds: const ['task', 'note', 'habit'],
      now: now,
    ),
    MindmapNode.create(
      id: 'task',
      type: NodeType.task,
      title: 'Launch task',
      day: DateTime(2026, 6, 18),
      project: 'Launch',
      area: 'Work',
      tags: const ['release'],
      priority: NodePriority.high,
      dueDate: DateTime(2026, 6, 1),
      now: now,
    ),
    MindmapNode.create(
      id: 'note',
      type: NodeType.note,
      title: 'Launch note',
      day: DateTime(2026, 6, 18),
      project: 'Launch',
      area: 'Work',
      tags: const ['release'],
      now: now,
    ),
    MindmapNode.create(
      id: 'habit',
      type: NodeType.task,
      title: 'Launch habit',
      day: DateTime(2026, 6, 17),
      project: 'Launch',
      status: NodeStatus.done,
      now: now,
    ),
    MindmapNode.create(
      id: 'isolated',
      type: NodeType.task,
      title: 'Detached priority',
      day: DateTime(2026, 6, 18),
      priority: NodePriority.urgent,
      now: DateTime(2026, 5, 1),
    ),
  ]);
}
