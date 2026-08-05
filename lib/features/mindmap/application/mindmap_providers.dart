/// Riverpod graph for local-first mindmap data.
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import '../../../core/config/runtime_config.dart';
import '../../../core/utils/date_utils.dart';
import '../../insights/domain/insights_summary.dart';
import '../../search/application/indexed_canvas_board_repository.dart';
import '../../search/application/indexed_mindmap_repository.dart';
import '../../search/application/search_document_projector.dart';
import '../../search/application/search_providers.dart';
import '../data/aes_gcm_sembast_codec.dart';
import '../data/canvas_board_repositories.dart';
import '../data/canvas_board_template_repositories.dart';
import '../data/collaboration_canvas_board_repository.dart';
import '../data/collaboration_mindmap_repository.dart';
import '../data/local_database_mindmap_repository.dart';
import '../data/local_node_attachment_repository.dart';
import '../data/mindmap_database_opener.dart';
import '../data/persistent_mindmap_repository.dart';
import '../data/seed_mindmap_nodes.dart';
import '../data/sembast_collaboration_board_sync_store.dart';
import '../data/sembast_collaboration_sync_store.dart';
import '../data/sembast_drawing_draft_store.dart';
import '../data/sembast_mindmap_node_database.dart';
import '../data/shared_preferences_mindmap_node_store.dart';
import '../data/xor_sembast_codec.dart';
import '../domain/automation_suggestion.dart';
import '../domain/canvas_board.dart';
import '../domain/canvas_board_repository.dart';
import '../domain/canvas_board_template.dart';
import '../domain/canvas_board_template_repository.dart';
import '../domain/day_node_summary.dart';
import '../domain/life_os_summary.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_node_revision.dart';
import '../domain/mindmap_node_revision_repository.dart';
import '../domain/mindmap_repository.dart';
import '../domain/node_attachment.dart';
import '../domain/node_graph.dart';
import '../domain/node_knowledge_index.dart';
import '../domain/node_relations.dart';
import '../domain/smart_node_view.dart';
import '../domain/workspace_context.dart';
import 'board_template_service.dart';
import 'collaboration_session.dart';
import 'database_lock_provider.dart';
import 'media_file_import_service.dart';
import 'recurring_routine_application.dart';

final mindmapNodeStoreProvider = Provider<MindmapNodeStore>((ref) {
  return SharedPreferencesMindmapNodeStore();
});

final mindmapDatabaseProvider = Provider<Future<Database>>((ref) {
  final lock = ref.watch(databaseLockProvider);
  if (lock.isLocked) {
    final completer = Completer<Database>();
    ref.onDispose(() {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Database is locked'));
      }
    });
    return completer.future;
  }
  if (lock.unlockedPin != null) {
    if (lock.keyBytes != null) {
      return openMindmapDatabase(codec: getAesGcmSembastCodec(lock.keyBytes!));
    }
    return openMindmapDatabase(codec: getXorSembastCodec(lock.unlockedPin!));
  }
  return openMindmapDatabase();
});

final mindmapNodeDatabaseProvider = Provider<MindmapNodeDatabase>((ref) {
  return SembastMindmapNodeDatabase(
    database: ref.watch(mindmapDatabaseProvider),
  );
});

final collaborationBoardSyncStoreProvider =
    Provider<SembastCollaborationBoardSyncStore>((ref) {
      final nodeDatabase = ref.watch(mindmapNodeDatabaseProvider);
      return SembastCollaborationBoardSyncStore(
        database: nodeDatabase is SembastMindmapNodeDatabase
            ? nodeDatabase.database
            : ref.watch(mindmapDatabaseProvider),
      );
    });

final canvasBoardRepositoryProvider = Provider<CanvasBoardRepository>((ref) {
  final base = SembastCanvasBoardRepository(
    database: ref.watch(mindmapDatabaseProvider),
  );
  final indexed = IndexedCanvasBoardRepository(
    base: base,
    coordinator: ref.watch(searchIndexCoordinatorProvider.future),
    projector: const SearchDocumentProjector(),
  );
  return CollaborationCanvasBoardRepository(
    base: indexed,
    store: ref.watch(collaborationBoardSyncStoreProvider),
    sessionReader: ref.watch(activeCollaborationSessionProvider.notifier),
  );
});

final canvasBoardTemplateRepositoryProvider =
    Provider<CanvasBoardTemplateRepository>((ref) {
      return SembastCanvasBoardTemplateRepository(
        database: ref.watch(mindmapDatabaseProvider),
      );
    });

final boardTemplateServiceProvider = Provider<BoardTemplateService>((ref) {
  return BoardTemplateService(
    boardRepository: ref.watch(canvasBoardRepositoryProvider),
    templateRepository: ref.watch(canvasBoardTemplateRepositoryProvider),
  );
});

final availableBoardTemplatesProvider = FutureProvider.autoDispose
    .family<List<CanvasBoardTemplate>, String>((ref, workspaceName) async {
      final boards = await ref.watch(
        workspaceBoardGraphProvider(workspaceName).future,
      );
      return ref
          .watch(boardTemplateServiceProvider)
          .availableUserTemplates(workspaceName, workspaceBoards: boards);
    });

final drawingDraftStoreProvider = Provider<SembastDrawingDraftStore>((ref) {
  return SembastDrawingDraftStore(database: ref.watch(mindmapDatabaseProvider));
});

final drawingDraftCheckpointsProvider = FutureProvider.autoDispose((ref) async {
  final store = ref.watch(drawingDraftStoreProvider);
  final subscription = store.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return store.list();
});

final mindmapNodeRevisionRepositoryProvider =
    Provider<MindmapNodeRevisionRepository>((ref) {
      return ref.watch(mindmapNodeDatabaseProvider);
    });

final nodeRevisionsProvider = FutureProvider.autoDispose
    .family<List<MindmapNodeRevision>, String>((ref, nodeId) {
      return ref
          .watch(mindmapNodeRevisionRepositoryProvider)
          .listRevisions(nodeId);
    });

final collaborationSyncStoreProvider = Provider<SembastCollaborationSyncStore>((
  ref,
) {
  final nodeDatabase = ref.watch(mindmapNodeDatabaseProvider);
  return SembastCollaborationSyncStore(
    database: nodeDatabase is SembastMindmapNodeDatabase
        ? nodeDatabase.database
        : ref.watch(mindmapDatabaseProvider),
  );
});

final mindmapRepositoryProvider = Provider<MindmapRepository>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  final base = LocalDatabaseMindmapRepository(
    database: ref.watch(mindmapNodeDatabaseProvider),
    legacyStore: ref.watch(mindmapNodeStoreProvider),
    seedNodes: config.demoSeedEnabled ? buildSeedMindmapNodes() : const [],
  );
  final indexed = IndexedMindmapRepository(
    base: base,
    coordinator: ref.watch(searchIndexCoordinatorProvider.future),
    projector: const SearchDocumentProjector(),
  );
  return CollaborationMindmapRepository(
    base: indexed,
    store: ref.watch(collaborationSyncStoreProvider),
    revisionRepository: ref.watch(mindmapNodeRevisionRepositoryProvider),
    sessionReader: ref.watch(activeCollaborationSessionProvider.notifier),
  );
});

final nodeAttachmentRepositoryProvider =
    FutureProvider<NodeAttachmentRepository>((ref) {
      return openLocalNodeAttachmentRepository();
    });

final nodeAttachmentPreviewBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, attachmentId) async {
      final id = attachmentId.trim();
      if (id.isEmpty) return null;
      final repository = await ref.watch(
        nodeAttachmentRepositoryProvider.future,
      );
      final bytes = await repository.readBytes(id);
      if (bytes == null) return null;
      return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    });

final mediaFileImportServiceProvider = FutureProvider<MediaFileImportService>((
  ref,
) async {
  return MediaFileImportService(
    repository: await ref.watch(nodeAttachmentRepositoryProvider.future),
    picker: const FilePickerMediaFilePicker(),
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

final dailyCanvasBoardProvider = FutureProvider.autoDispose
    .family<CanvasBoard, DateTime>((ref, day) async {
      final normalizedDay = day.dateOnly;
      final repository = ref.watch(canvasBoardRepositoryProvider);
      final persisted = await repository.getBoard(
        dailyCanvasBoardId(normalizedDay),
      );
      if (persisted != null) return persisted;
      final nodes = await ref.watch(nodesForDayProvider(normalizedDay).future);
      return CanvasBoard.daily(
        day: normalizedDay,
        nodes: nodes,
        now: DateTime.now(),
      );
    });

final dailyCanvasBoardsProvider = FutureProvider.autoDispose
    .family<List<CanvasBoard>, DateTime>((ref, day) async {
      final normalizedDay = day.dateOnly;
      final key = dayKey(normalizedDay);
      final repository = ref.watch(canvasBoardRepositoryProvider);
      final dayBoards = await repository.getBoardsForDay(key);
      final primaryBoard = await ref.watch(dailyCanvasBoardProvider(normalizedDay).future);
      
      if (dayBoards.isEmpty) {
        return [primaryBoard];
      }
      if (!dayBoards.any((b) => b.id == primaryBoard.id)) {
        return [primaryBoard, ...dayBoards];
      }
      return dayBoards;
    });

final canvasBoardByIdProvider = FutureProvider.autoDispose
    .family<CanvasBoard?, String>((ref, boardId) {
      return ref.watch(canvasBoardRepositoryProvider).getBoard(boardId);
    });

final workspaceBoardGraphProvider = FutureProvider.autoDispose
    .family<List<CanvasBoard>, String>((ref, workspaceName) {
      return ref
          .watch(canvasBoardRepositoryProvider)
          .listWorkspaceBoards(
            workspaceName,
            includeArchived: true,
            includeTrashed: true,
          );
    });

final projectCanvasBoardProvider = FutureProvider.autoDispose
    .family<CanvasBoard?, String>((ref, workspaceName) {
      return ref
          .watch(canvasBoardRepositoryProvider)
          .getBoard(projectCanvasBoardId(workspaceName));
    });

final projectCanvasBoardsProvider = FutureProvider.autoDispose
    .family<List<CanvasBoard>, String>((ref, workspaceName) {
      return ref
          .watch(canvasBoardRepositoryProvider)
          .listBoards(
            kind: CanvasBoardKind.project,
            workspaceName: workspaceName,
            includeArchived: true,
          );
    });

final activeProjectCanvasBoardsProvider = FutureProvider.autoDispose((ref) {
  return ref
      .watch(canvasBoardRepositoryProvider)
      .listBoards(kind: CanvasBoardKind.project);
});

final allMindmapNodesProvider = FutureProvider<List<MindmapNode>>((ref) {
  final repository = ref.watch(mindmapRepositoryProvider);
  return repository.listNodes();
});

final startupSearchIndexRebuildProvider = FutureProvider<void>((ref) async {
  const projector = SearchDocumentProjector();
  final nodes = await ref.watch(allMindmapNodesProvider.future);
  final boards = await ref
      .watch(canvasBoardRepositoryProvider)
      .listBoards(includeArchived: true);
  final documents = [
    for (final node in nodes)
      ...projector.projectNode(
        node,
        workspaceId: node.project.trim().isNotEmpty
            ? 'project:${node.project}'
            : node.area.trim().isNotEmpty
            ? 'area:${node.area}'
            : 'daily',
      ),
    for (final board in boards) ...projector.projectBoard(board),
  ];
  await (await ref.watch(
    searchIndexCoordinatorProvider.future,
  )).rebuild(documents);
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
  final links = NodeKnowledgeIndex(nodes).linksFor(nodeId);

  return NodeRelations(
    nodeId: nodeId,
    relatedNodes: links.outgoingNodes,
    backlinks: [for (final backlink in links.backlinks) backlink.node],
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
