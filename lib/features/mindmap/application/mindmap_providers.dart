/// Riverpod graph for local-first mindmap data.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import '../../../core/config/runtime_config.dart';
import '../../../core/utils/date_utils.dart';
import '../../insights/domain/insights_summary.dart';
import '../data/local_database_mindmap_repository.dart';
import '../data/mindmap_database_opener.dart';
import '../data/persistent_mindmap_repository.dart';
import '../data/seed_mindmap_nodes.dart';
import '../data/sembast_mindmap_node_database.dart';
import '../data/shared_preferences_mindmap_node_store.dart';
import '../domain/automation_suggestion.dart';
import '../domain/day_node_summary.dart';
import '../domain/life_os_summary.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_repository.dart';
import '../domain/node_graph.dart';
import '../domain/node_relations.dart';
import '../domain/smart_node_view.dart';
import '../domain/workspace_context.dart';
import 'recurring_routine_application.dart';

final mindmapNodeStoreProvider = Provider<MindmapNodeStore>((ref) {
  return SharedPreferencesMindmapNodeStore();
});

final mindmapDatabaseProvider = Provider<Future<Database>>((ref) {
  return openMindmapDatabase();
});

final mindmapNodeDatabaseProvider = Provider<MindmapNodeDatabase>((ref) {
  return SembastMindmapNodeDatabase(
    database: ref.watch(mindmapDatabaseProvider),
  );
});

final mindmapRepositoryProvider = Provider<MindmapRepository>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  return LocalDatabaseMindmapRepository(
    database: ref.watch(mindmapNodeDatabaseProvider),
    legacyStore: ref.watch(mindmapNodeStoreProvider),
    seedNodes: config.demoSeedEnabled ? buildSeedMindmapNodes() : const [],
  );
});

final nodesForDayProvider = FutureProvider.family<List<MindmapNode>, DateTime>((
  ref,
  day,
) async {
  final repository = ref.watch(mindmapRepositoryProvider);
  final nodes = await repository.listNodes(day: day.dateOnly);
  return _activeNodes(nodes);
});

final allMindmapNodesProvider = FutureProvider<List<MindmapNode>>((ref) {
  final repository = ref.watch(mindmapRepositoryProvider);
  return repository.listNodes();
});

final currentDateProvider = Provider<DateTime>((ref) {
  return DateTime.now().dateOnly;
});

final smartNodeViewsProvider = FutureProvider<SmartNodeViews>((ref) async {
  final today = ref.watch(currentDateProvider);
  final nodes = await ref.watch(allMindmapNodesProvider.future);
  return SmartNodeViews.fromNodes(today: today, nodes: nodes);
});

final automationSuggestionsProvider = FutureProvider<AutomationSuggestions>((
  ref,
) async {
  final today = ref.watch(currentDateProvider);
  final repository = ref.watch(mindmapRepositoryProvider);
  final plan = await previewRecurringRoutines(
    repository: repository,
    day: today,
  );
  return AutomationSuggestions.fromRoutinePlan(day: today, plan: plan);
});

final lifeOsSummaryProvider = FutureProvider<LifeOsSummary>((ref) async {
  final today = ref.watch(currentDateProvider);
  final nodes = await ref.watch(allMindmapNodesProvider.future);
  return LifeOsSummary.fromNodes(today: today, nodes: nodes);
});

final insightsSummaryProvider = FutureProvider<InsightsSummary>((ref) async {
  final today = ref.watch(currentDateProvider);
  final nodes = await ref.watch(allMindmapNodesProvider.future);
  return InsightsSummary.fromNodes(today: today, nodes: nodes);
});

final workspaceContextsProvider = FutureProvider<WorkspaceContexts>((
  ref,
) async {
  final nodes = await ref.watch(allMindmapNodesProvider.future);
  return WorkspaceContexts.fromNodes(nodes);
});

final nodeRelationsProvider = FutureProvider.family<NodeRelations, String>((
  ref,
  nodeId,
) async {
  final nodes = await ref.watch(allMindmapNodesProvider.future);
  final nodesById = {for (final node in nodes) node.id: node};
  final target = nodesById[nodeId];
  if (target == null) return NodeRelations(nodeId: nodeId);

  final relatedNodes = [
    for (final relatedNodeId in target.relatedNodeIds)
      ?nodesById[relatedNodeId],
  ];
  final backlinks = [
    for (final node in nodes)
      if (node.id != nodeId && node.relatedNodeIds.contains(nodeId)) node,
  ];

  return NodeRelations(
    nodeId: nodeId,
    relatedNodes: List.unmodifiable(relatedNodes),
    backlinks: List.unmodifiable(backlinks),
  );
});

final nodeGraphProvider = FutureProvider<NodeGraph>((ref) async {
  final nodes = await ref.watch(allMindmapNodesProvider.future);
  return NodeGraph.fromNodes(nodes);
});

final dayNodeSummaryProvider = FutureProvider.family<DayNodeSummary, DateTime>((
  ref,
  day,
) async {
  final normalizedDay = day.dateOnly;
  final nodes = await ref.watch(nodesForDayProvider(normalizedDay).future);
  return DayNodeSummary.fromNodes(normalizedDay, nodes);
});

List<MindmapNode> _activeNodes(List<MindmapNode> nodes) {
  return List.unmodifiable([
    for (final node in nodes)
      if (!node.isArchived) node,
  ]);
}

/// Invalidate all mindmap-related providers after a mutation.
///
/// Call this from every mutation site (save, delete, move, etc.) so that
/// dependent providers refresh their state. Pass [day] and optionally
/// [extraDay] when the mutation affects specific dates.
void invalidateMindmapState(
  WidgetRef ref, {
  DateTime? day,
  DateTime? extraDay,
}) {
  _invalidateMindmapState(ref.invalidate, day: day, extraDay: extraDay);
}

/// Provider/controller variant of [invalidateMindmapState].
void invalidateMindmapStateFromRef(
  Ref ref, {
  DateTime? day,
  DateTime? extraDay,
}) {
  _invalidateMindmapState(ref.invalidate, day: day, extraDay: extraDay);
}

void _invalidateMindmapState(
  void Function(ProviderOrFamily provider) invalidate, {
  DateTime? day,
  DateTime? extraDay,
}) {
  invalidate(allMindmapNodesProvider);
  if (day != null) {
    invalidate(nodesForDayProvider(day));
    invalidate(dayNodeSummaryProvider(day));
  }
  if (extraDay != null) {
    invalidate(nodesForDayProvider(extraDay));
    invalidate(dayNodeSummaryProvider(extraDay));
  }
  invalidate(lifeOsSummaryProvider);
  invalidate(insightsSummaryProvider);
  invalidate(automationSuggestionsProvider);
  invalidate(smartNodeViewsProvider);
  invalidate(workspaceContextsProvider);
  invalidate(nodeGraphProvider);
}
