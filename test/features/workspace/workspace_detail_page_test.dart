import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/theme/app_theme.dart';
import 'package:var_app/features/mindmap/application/collaboration_controller.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/data/canvas_board_template_repositories.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_repository.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template_repository.dart';
import 'package:var_app/features/mindmap/domain/collaboration_room.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';
import 'package:var_app/features/workspace/data/workspace_title_repository.dart';
import 'package:var_app/features/workspace/workspace_detail_page.dart';

void main() {
  late InMemoryMindmapRepository repository;
  late DateTime today;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    today = DateTime(2026, 7, 1);
    repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-open',
          type: NodeType.task,
          title: 'Design homepage',
          day: today,
          project: 'Alpha',
          status: NodeStatus.open,
          now: DateTime(2026, 7, 1, 8),
        ),
        MindmapNode.create(
          id: 'task-doing',
          type: NodeType.task,
          title: 'Build API',
          day: today,
          project: 'Alpha',
          status: NodeStatus.doing,
          dueDate: today.add(const Duration(days: 3)),
          now: DateTime(2026, 7, 1, 9),
        ),
        MindmapNode.create(
          id: 'task-done',
          type: NodeType.task,
          title: 'Write tests',
          day: today.subtract(const Duration(days: 2)),
          project: 'Alpha',
          status: NodeStatus.done,
          isDone: true,
          now: DateTime(2026, 7, 1, 10),
        ),
        MindmapNode.create(
          id: 'task-other',
          type: NodeType.task,
          title: 'Other project task',
          day: today,
          project: 'Beta',
          now: DateTime(2026, 7, 1, 11),
        ),
      ],
    );
  });

  Widget buildPage({
    String typeName = 'project',
    String name = 'Alpha',
    CanvasBoardRepository? canvasRepository,
    CanvasBoardTemplateRepository? templateRepository,
    CollaborationActions? collaborationActions,
    CollaborationState? collaborationState,
    bool initialCanvas = false,
    String? initialBoardId,
  }) {
    final resolvedCanvasRepository =
        canvasRepository ?? InMemoryCanvasBoardRepository();
    return ProviderScope(
      overrides: [
        mindmapRepositoryProvider.overrideWithValue(repository),
        canvasBoardRepositoryProvider.overrideWithValue(
          resolvedCanvasRepository,
        ),
        canvasBoardTemplateRepositoryProvider.overrideWithValue(
          templateRepository ?? InMemoryCanvasBoardTemplateRepository(),
        ),
        if (collaborationActions != null)
          collaborationActionsProvider.overrideWithValue(collaborationActions),
        if (collaborationState != null)
          collaborationProvider.overrideWith(
            (ref) => _FakeCollaborationNotifier(collaborationState),
          ),
        currentDateProvider.overrideWithValue(today),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => WorkspaceDetailPage(
                typeName: typeName,
                name: name,
                initialCanvas: initialCanvas,
                initialBoardId: initialBoardId,
              ),
            ),
            GoRoute(
              path: '/calendar/:day',
              builder: (context, state) =>
                  const Scaffold(body: Text('Calendar Day View')),
            ),
          ],
        ),
      ),
    );
  }

  group('WorkspaceDetailPage', () {
    testWidgets('shows workspace title and list view by default', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Title should contain the workspace name
      expect(find.textContaining('Alpha'), findsWidgets);

      // List view is the default - should show active and completed sections
      expect(find.textContaining('Active'), findsWidgets);
      expect(find.textContaining('Completed'), findsOneWidget);

      // Should show the tasks belonging to this workspace only
      expect(find.text('Design homepage'), findsOneWidget);
      expect(find.text('Build API'), findsOneWidget);
      expect(find.text('Write tests'), findsOneWidget);
      // Should NOT show tasks from other workspaces
      expect(find.text('Other project task'), findsNothing);
    });

    testWidgets('shows persisted custom workspace title', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkspaceDetailPage)),
      );
      await container
          .read(workspaceTitleProvider.notifier)
          .setTitle(WorkspaceContextType.project, 'Alpha', 'Launch HQ');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Launch HQ'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Project Alpha'), findsNothing);
    });
    testWidgets('shows segmented button with List, Kanban, Gantt', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('List'), findsOneWidget);
      expect(find.text('Kanban'), findsOneWidget);
      expect(find.text('Gantt'), findsOneWidget);
    });

    testWidgets('opens exact shared project canvas from route state', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      final board = CanvasBoard(
        id: 'project:import:shared',
        kind: CanvasBoardKind.project,
        title: 'Shared board',
        workspaceName: 'project:Alpha',
        createdAt: today,
        updatedAt: today,
      );
      await canvasRepository.saveBoard(board);

      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          initialCanvas: true,
          initialBoardId: board.id,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MindmapCanvas), findsOneWidget);
      expect(find.byTooltip('Share board'), findsOneWidget);
      final canvas = tester.widget<MindmapCanvas>(find.byType(MindmapCanvas));
      expect(canvas.board?.id, board.id);
    });

    testWidgets('shares exact selected board after persisting it', (
      tester,
    ) async {
      final baseRepository = InMemoryCanvasBoardRepository();
      final canvasRepository = _TrackingCanvasBoardRepository(baseRepository);
      final actions = _FakeCollaborationActions(
        onCreateProjectRoom: ({required boardId, required label}) async {
          expect(await baseRepository.getBoard(boardId), isNotNull);
          expect(canvasRepository.savedBoardIds, contains(boardId));
          return 'room';
        },
      );
      final board = CanvasBoard(
        id: 'project:import:share-me',
        kind: CanvasBoardKind.project,
        title: 'Share me',
        workspaceName: 'project:Alpha',
        createdAt: today,
        updatedAt: today,
      );
      await baseRepository.saveBoard(board);

      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          collaborationActions: actions,
          initialCanvas: true,
          initialBoardId: board.id,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('workspace-share-board')));
      await tester.pump();
      await tester.pump();

      expect(actions.createdBoardIds, <String>[board.id]);
      expect(actions.createdLabels, <String>[board.title]);
      expect(canvasRepository.savedBoardIds, contains(board.id));
      expect(
        find.byKey(const ValueKey('collaboration-share-dialog')),
        findsOneWidget,
      );
    });

    testWidgets('share loading blocks duplicate room creation', (tester) async {
      final roomCompleter = Completer<String>();
      final actions = _FakeCollaborationActions(
        onCreateProjectRoom: ({required boardId, required label}) =>
            roomCompleter.future,
      );
      final board = CanvasBoard(
        id: 'project:share:pending',
        kind: CanvasBoardKind.project,
        title: 'Pending share',
        workspaceName: 'project:Alpha',
        createdAt: today,
        updatedAt: today,
      );
      final canvasRepository = InMemoryCanvasBoardRepository();
      await canvasRepository.saveBoard(board);

      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          collaborationActions: actions,
          initialCanvas: true,
          initialBoardId: board.id,
        ),
      );
      await tester.pumpAndSettle();

      final share = find.byKey(const ValueKey('workspace-share-board'));
      await tester.tap(share);
      await tester.pump();
      await tester.tap(share);
      await tester.pump();

      expect(actions.createdBoardIds, <String>[board.id]);
      final button = tester.widget<IconButton>(share);
      expect(button.onPressed, isNull);

      roomCompleter.complete('room');
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('collaboration-share-dialog')),
        findsOneWidget,
      );
    });

    testWidgets('share shows typed collaboration error', (tester) async {
      final actions = _FakeCollaborationActions(
        onCreateProjectRoom: ({required boardId, required label}) =>
            throw const CollaborationException(
              CollaborationErrorCode.permissionDenied,
              'Verified owner access required.',
            ),
      );

      await tester.pumpWidget(
        buildPage(collaborationActions: actions, initialCanvas: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-share-board')));
      await tester.pumpAndSettle();

      expect(find.text('Verified owner access required.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('collaboration-share-dialog')),
        findsNothing,
      );
    });

    testWidgets('switches to persistent project canvas', (tester) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();

      expect(find.byType(MindmapCanvas), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mindmap-node-task-open')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mindmap-node-task-other')),
        findsNothing,
      );
    });

    testWidgets('project canvas persists viewport without activity history', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      await tester.pumpWidget(
        buildPage(canvasRepository: canvasRepository, initialCanvas: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Show canvas controls'));
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pump(const Duration(milliseconds: 650));

      final boards = await canvasRepository.listBoards(includeArchived: true);
      expect(boards, hasLength(1));
      expect(boards.single.viewport.scale, greaterThan(1));
      expect(boards.single.activity, isEmpty);
    });

    testWidgets('project canvas assistant previews applies and undoes', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      await tester.pumpWidget(
        buildPage(canvasRepository: canvasRepository, initialCanvas: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Show canvas controls'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mindmap-canvas-assistant')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('canvas-assistant-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('canvas-assistant-summary')),
        findsOneWidget,
      );
      expect(find.textContaining('3 analyzed objects'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('canvas-assistant-apply')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('canvas-assistant-apply')),
      );
      await tester.tap(find.byKey(const ValueKey('canvas-assistant-apply')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('canvas-assistant-dialog')),
        findsNothing,
      );
      final boards = await canvasRepository.listBoards(includeArchived: true);
      expect(boards, hasLength(1));
      final applied = boards.single;
      expect(applied, isNotNull);
    });

    testWidgets('project canvas assistant rejects stale analysis', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      final initial = CanvasBoard(
        id: projectCanvasBoardId('project:Alpha'),
        kind: CanvasBoardKind.project,
        title: 'Alpha',
        workspaceName: 'project:Alpha',
        objects: <CanvasObject>[
          CanvasObject(
            id: 'idea-a',
            type: CanvasObjectType.stickyNote,
            geometry: const CanvasGeometry(x: 0, y: 0, width: 240, height: 160),
            payload: const <String, Object?>{'text': 'Launch research'},
            createdAt: today,
            updatedAt: today,
          ),
          CanvasObject(
            id: 'idea-b',
            type: CanvasObjectType.stickyNote,
            geometry: const CanvasGeometry(
              x: 300,
              y: 0,
              width: 240,
              height: 160,
            ),
            payload: const <String, Object?>{'text': 'Launch planning'},
            createdAt: today,
            updatedAt: today,
          ),
        ],
        createdAt: today,
        updatedAt: today,
      );
      await canvasRepository.saveBoard(initial);
      await tester.pumpWidget(
        buildPage(canvasRepository: canvasRepository, initialCanvas: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show canvas controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mindmap-canvas-assistant')));
      await tester.pumpAndSettle();

      await canvasRepository.saveBoard(
        initial.copyWith(
          updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('canvas-assistant-apply')),
      );
      await tester.tap(find.byKey(const ValueKey('canvas-assistant-apply')));
      await tester.pumpAndSettle();

      expect(
        find.text('Board changed. Run assistant analysis again.'),
        findsOneWidget,
      );
      final persisted = await canvasRepository.getBoard(initial.id);
      expect(
        persisted!.activity.where(
          (activity) => activity.type == CanvasActivityType.assistantApplied,
        ),
        isEmpty,
      );
    });

    testWidgets('project canvas enables image import tool', (tester) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show canvas controls'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mindmap-canvas-create-menu')),
      );
      await tester.pumpAndSettle();
      final imageItem = tester.widget<PopupMenuItem<CanvasObjectType>>(
        find.byKey(const ValueKey('mindmap-canvas-create-image')),
      );
      expect(imageItem.enabled, isTrue);
    });

    testWidgets('project canvas exposes workflow templates', (tester) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('workspace-canvas-template-menu')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Project planning'), findsOneWidget);
      expect(find.text('Brainstorm'), findsOneWidget);
      expect(find.text('Retrospective'), findsOneWidget);
    });

    testWidgets('nested template gallery shows eight built-ins and searches', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-create-nested-board')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih template'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace-template-gallery')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'workspace-template-built-in-',
              ),
        ),
        findsNWidgets(8),
      );
      for (final name in const <String>[
        'Project Plan',
        'Kanban',
        'Brainstorm',
        'Content Calendar',
        'Weekly Planner',
        'Research Board',
        'Moodboard',
        'Goal Tracker',
      ]) {
        expect(
          find.descendant(
            of: find.bySemanticsLabel('Template $name'),
            matching: find.text(name),
          ),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Template $name'), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Search board templates'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('workspace-template-search')),
        'weekly',
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekly Planner'), findsOneWidget);
      expect(find.text('Project Plan'), findsNothing);
    });

    testWidgets('user template previews live source and creates nested board', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      final templateRepository = InMemoryCanvasBoardTemplateRepository();
      final source = CanvasBoard(
        id: 'source-board',
        kind: CanvasBoardKind.project,
        title: 'Source',
        workspaceName: 'project:Alpha',
        objects: <CanvasObject>[
          CanvasObject(
            id: 'source-note',
            type: CanvasObjectType.stickyNote,
            geometry: const CanvasGeometry(
              x: 40,
              y: 60,
              width: 220,
              height: 120,
            ),
            payload: const <String, Object?>{'text': 'Live source note'},
            createdAt: today,
            updatedAt: today,
          ),
        ],
        createdAt: today,
        updatedAt: today,
      );
      await canvasRepository.saveBoard(source);
      await templateRepository.saveTemplate(
        CanvasBoardTemplate(
          id: 'user-template',
          name: 'My live template',
          sourceBoardId: source.id,
          createdAt: today,
          updatedAt: today,
        ),
      );

      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          templateRepository: templateRepository,
          initialCanvas: true,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkspaceDetailPage)),
      );
      final boardStates = <AsyncValue<List<CanvasBoard>>>[];
      final subscription = container.listen(
        projectCanvasBoardsProvider('project:Alpha'),
        (_, next) => boardStates.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await tester.pumpAndSettle();
      boardStates.clear();
      await tester.tap(
        find.byKey(const ValueKey('workspace-create-nested-board')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih template'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('workspace-template-user-user-template')),
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-template-user-user-template')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-template-preview')),
        findsOneWidget,
      );
      expect(find.text('Live source note'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('workspace-template-use-user-template')),
      );
      await tester.pumpAndSettle();

      final boards = await canvasRepository.listWorkspaceBoards(
        'project:Alpha',
      );
      final child = boards.singleWhere((board) => board.parentBoardId != null);
      expect(child.title, 'My live template');
      expect(child.objects.single.payload['text'], 'Live source note');
      expect(
        boardStates.where(
          (state) => state.value?.any((board) => board.id == child.id) ?? false,
        ),
        isNotEmpty,
      );
      final parent = boards.singleWhere(
        (board) =>
            board.objects.any((object) => object.referencedBoardId == child.id),
      );
      expect(
        parent.objects.where((object) => object.referencedBoardId == child.id),
        hasLength(1),
      );
    });

    testWidgets('user template resolves source changes when confirmed', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      final templateRepository = InMemoryCanvasBoardTemplateRepository();
      final source = CanvasBoard(
        id: 'race-source',
        kind: CanvasBoardKind.project,
        title: 'Race source',
        workspaceName: 'project:Alpha',
        objects: <CanvasObject>[_stickyNote('old-note', 'Old content', today)],
        createdAt: today,
        updatedAt: today,
      );
      await canvasRepository.saveBoard(source);
      await templateRepository.saveTemplate(
        CanvasBoardTemplate(
          id: 'race-template',
          name: 'Race template',
          sourceBoardId: source.id,
          createdAt: today,
          updatedAt: today,
        ),
      );
      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          templateRepository: templateRepository,
          initialCanvas: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-create-nested-board')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih template'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('workspace-template-user-race-template')),
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-template-user-race-template')),
      );
      await tester.pumpAndSettle();

      await canvasRepository.saveBoard(
        source.copyWith(
          objects: <CanvasObject>[
            _stickyNote('new-note', 'New content', today),
          ],
          updatedAt: today.add(const Duration(minutes: 1)),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-template-use-race-template')),
      );
      await tester.pumpAndSettle();

      final boards = await canvasRepository.listWorkspaceBoards(
        'project:Alpha',
      );
      final child = boards.singleWhere((board) => board.parentBoardId != null);
      expect(child.objects.single.payload['text'], 'New content');
    });

    testWidgets('trashed user source before confirm creates no partial board', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      final templateRepository = InMemoryCanvasBoardTemplateRepository();
      final source = CanvasBoard(
        id: 'trash-race-source',
        kind: CanvasBoardKind.project,
        title: 'Trash race source',
        workspaceName: 'project:Alpha',
        objects: <CanvasObject>[
          _stickyNote('trash-note', 'Trash content', today),
        ],
        createdAt: today,
        updatedAt: today,
      );
      await canvasRepository.saveBoard(source);
      await templateRepository.saveTemplate(
        CanvasBoardTemplate(
          id: 'trash-race-template',
          name: 'Trash race template',
          sourceBoardId: source.id,
          createdAt: today,
          updatedAt: today,
        ),
      );
      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          templateRepository: templateRepository,
          initialCanvas: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-create-nested-board')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih template'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(
          const ValueKey('workspace-template-user-trash-race-template'),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey('workspace-template-user-trash-race-template'),
        ),
      );
      await tester.pumpAndSettle();
      final before = await canvasRepository.listWorkspaceBoards(
        'project:Alpha',
      );
      await canvasRepository.saveBoard(
        source.copyWith(trashedAt: today, updatedAt: today),
      );

      await tester.tap(
        find.byKey(
          const ValueKey('workspace-template-use-trash-race-template'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Template source is unavailable.'), findsOneWidget);
      final after = await canvasRepository.listWorkspaceBoards(
        'project:Alpha',
        includeTrashed: true,
      );
      expect(after.where((board) => board.parentBoardId != null), isEmpty);
      expect(
        after
            .expand((board) => board.objects)
            .where((object) => object.type == CanvasObjectType.boardReference),
        isEmpty,
      );
      expect(after.length, before.length);
    });

    testWidgets('deleted user source before confirm creates no partial board', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      final templateRepository = InMemoryCanvasBoardTemplateRepository();
      final source = CanvasBoard(
        id: 'delete-race-source',
        kind: CanvasBoardKind.project,
        title: 'Delete race source',
        workspaceName: 'project:Alpha',
        objects: <CanvasObject>[
          _stickyNote('delete-note', 'Delete content', today),
        ],
        createdAt: today,
        updatedAt: today,
      );
      await canvasRepository.saveBoard(source);
      await templateRepository.saveTemplate(
        CanvasBoardTemplate(
          id: 'delete-race-template',
          name: 'Delete race template',
          sourceBoardId: source.id,
          createdAt: today,
          updatedAt: today,
        ),
      );
      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          templateRepository: templateRepository,
          initialCanvas: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-create-nested-board')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih template'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(
          const ValueKey('workspace-template-user-delete-race-template'),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey('workspace-template-user-delete-race-template'),
        ),
      );
      await tester.pumpAndSettle();
      final before = await canvasRepository.listWorkspaceBoards(
        'project:Alpha',
      );
      await canvasRepository.deleteBoard(source.id);

      await tester.tap(
        find.byKey(
          const ValueKey('workspace-template-use-delete-race-template'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Template source is unavailable.'), findsOneWidget);
      final after = await canvasRepository.listWorkspaceBoards('project:Alpha');
      expect(after.where((board) => board.parentBoardId != null), isEmpty);
      expect(
        after
            .expand((board) => board.objects)
            .where((object) => object.type == CanvasObjectType.boardReference),
        isEmpty,
      );
      expect(after.length, before.length - 1);
    });

    testWidgets('unavailable user source shows error without partial board', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      final templateRepository = InMemoryCanvasBoardTemplateRepository();
      await templateRepository.saveTemplate(
        CanvasBoardTemplate(
          id: 'missing-template',
          name: 'Missing source',
          sourceBoardId: 'missing-board',
          createdAt: today,
          updatedAt: today,
        ),
      );

      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          templateRepository: templateRepository,
          initialCanvas: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-create-nested-board')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih template'));
      await tester.pumpAndSettle();

      expect(find.text('Missing source'), findsNothing);
      expect(find.text('Template source is unavailable.'), findsOneWidget);
      final after = await canvasRepository.listWorkspaceBoards('project:Alpha');
      expect(after.where((board) => board.parentBoardId != null), isEmpty);
    });

    testWidgets('project canvas exposes portable board transfer', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('workspace-board-transfer-menu')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Import board package'), findsOneWidget);
      expect(find.text('Export board package'), findsOneWidget);
    });

    testWidgets('project canvas shows persisted activity timeline', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      const workspaceName = 'project:Alpha';
      final board = CanvasBoard(
        id: projectCanvasBoardId(workspaceName),
        kind: CanvasBoardKind.project,
        title: 'Activity board',
        workspaceName: workspaceName,
        activity: <CanvasActivity>[
          CanvasActivity(
            id: 'activity-1',
            type: CanvasActivityType.objectsAdded,
            summary: 'Added 2 canvas objects',
            occurredAt: DateTime(2026, 7, 28, 9, 30),
            objectIds: const <String>['one', 'two'],
          ),
        ],
        createdAt: today,
        updatedAt: today,
      );
      await canvasRepository.saveBoard(board);
      await tester.pumpWidget(
        buildPage(canvasRepository: canvasRepository, initialCanvas: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-canvas-activity-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Canvas activity'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-canvas-activity-list')),
        findsOneWidget,
      );
      expect(find.text('Added 2 canvas objects'), findsOneWidget);
      expect(find.text('2026-07-28 09:30'), findsOneWidget);
    });

    testWidgets('board-room identity reaches canvas voting marker', (
      tester,
    ) async {
      final board = CanvasBoard(
        id: projectCanvasBoardId('project:Alpha'),
        kind: CanvasBoardKind.project,
        title: 'Alpha',
        workspaceName: 'project:Alpha',
        votingSession: CanvasVotingSession(
          status: CanvasVotingStatus.active,
          sessionId: 'vote-session',
          maxVotesPerParticipant: 2,
          allocations: const <String, Set<String>>{
            'room-user': <String>{'node:task-open'},
          },
        ),
        createdAt: today,
        updatedAt: today,
      );
      final canvasRepository = InMemoryCanvasBoardRepository();
      await canvasRepository.saveBoard(board);

      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          collaborationState: _collaborationState(
            boardId: board.id,
            role: CollaborationRole.editor,
          ),
          initialCanvas: true,
        ),
      );
      await tester.pumpAndSettle();

      final canvas = tester.widget<MindmapCanvas>(find.byType(MindmapCanvas));
      expect(canvas.votingParticipantId, 'room-user');
    });

    testWidgets('viewer cannot invoke workshop or voting controls', (
      tester,
    ) async {
      final board = CanvasBoard(
        id: projectCanvasBoardId('project:Alpha'),
        kind: CanvasBoardKind.project,
        title: 'Alpha',
        workspaceName: 'project:Alpha',
        votingSession: CanvasVotingSession(
          status: CanvasVotingStatus.active,
          sessionId: 'vote-session',
          maxVotesPerParticipant: 2,
        ),
        createdAt: today,
        updatedAt: today,
      );
      final canvasRepository = InMemoryCanvasBoardRepository();
      await canvasRepository.saveBoard(board);

      await tester.pumpWidget(
        buildPage(
          canvasRepository: canvasRepository,
          collaborationState: _collaborationState(
            boardId: board.id,
            role: CollaborationRole.viewer,
          ),
          initialCanvas: true,
        ),
      );
      await tester.pumpAndSettle();

      final canvas = tester.widget<MindmapCanvas>(find.byType(MindmapCanvas));
      expect(canvas.onCanvasVoteChanged, isNull);
      await tester.tap(
        find.byKey(const ValueKey('workspace-canvas-voting-menu')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PopupMenuItem<Object?>>(
              find.byKey(const ValueKey('workspace-voting-end')),
            )
            .enabled,
        isFalse,
      );
    });

    testWidgets('project canvas manages voting session and results', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('workspace-canvas-voting-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-voting-start')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace-voting-limit-field')),
        '2',
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-voting-start-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 votes left'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('workspace-canvas-voting-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-voting-reveal')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-canvas-voting-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-voting-results')));
      await tester.pumpAndSettle();

      expect(find.text('Voting results'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-voting-results-list')),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-canvas-activity-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Started voting with 2 votes per participant'),
        findsOneWidget,
      );
    });

    testWidgets('project canvas runs workshop timer and summary', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start workshop'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace-workshop-duration')),
        '5',
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-workshop-start-confirm')),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('workspace-workshop-timer')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Extend 5 minutes'), findsOneWidget);
      await tester.tap(find.text('End workshop'));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show summary'));
      await tester.pumpAndSettle();
      expect(find.text('Workshop summary'), findsOneWidget);
      expect(find.text('Participants: 1'), findsOneWidget);
    });

    testWidgets('project canvas runs facilitated workshop stages', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-workshop-start-facilitated')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-workshop-template-brainstorm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace-workshop-stage-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('Stage 1/6: Welcome'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advance stage'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Stage 2/6: Silent brainstorm'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Reveal contributions'), findsOneWidget);
      await tester.tap(find.text('Reveal contributions'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('workspace-canvas-activity-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Revealed Silent brainstorm'), findsOneWidget);
    });

    testWidgets('creates and selects saved workshop template', (tester) async {
      await tester.pumpWidget(buildPage(initialCanvas: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-workshop-start-facilitated')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-workshop-template-create')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workshop-template-name')),
        'Quick alignment',
      );
      await tester.enterText(
        find.byKey(const ValueKey('workshop-template-stage-title-0')),
        'Align',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('workshop-template-save')),
      );
      await tester.tap(find.byKey(const ValueKey('workshop-template-save')));
      await tester.pumpAndSettle();

      expect(find.text('Quick alignment'), findsOneWidget);
      expect(find.text('1 stages'), findsOneWidget);
      await tester.tap(find.text('Quick alignment'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stage 1/1: Align'), findsOneWidget);
    });

    testWidgets('facilitated workshop agenda survives page reload', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();

      await tester.pumpWidget(
        buildPage(canvasRepository: canvasRepository, initialCanvas: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-workshop-start-facilitated')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-workshop-template-brainstorm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advance stage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reveal contributions'));
      await tester.pumpAndSettle();

      final persisted = await canvasRepository.getBoard(
        projectCanvasBoardId('project:Alpha'),
      );
      expect(persisted, isNotNull);
      expect(persisted!.workshopSession.activeStageIndex, 1);
      expect(
        persisted.workshopSession.revealedStageIds,
        contains(persisted.workshopSession.activeStage!.id),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        buildPage(canvasRepository: canvasRepository, initialCanvas: true),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Stage 2/6: Silent brainstorm'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-workshop-menu')));
      await tester.pumpAndSettle();
      final revealItem = tester.widget<PopupMenuItem<Object?>>(
        find.byKey(const ValueKey('workspace-workshop-reveal-stage-item')),
      );
      expect(revealItem.enabled, isFalse);
    });

    testWidgets('project board dashboard previews and manages boards', (
      tester,
    ) async {
      final canvasRepository = InMemoryCanvasBoardRepository();
      const workspaceName = 'project:Alpha';
      final primary = CanvasBoard(
        id: projectCanvasBoardId(workspaceName),
        kind: CanvasBoardKind.project,
        title: 'Main board',
        workspaceName: workspaceName,
        objects: <CanvasObject>[
          CanvasObject(
            id: 'sticky-main',
            type: CanvasObjectType.stickyNote,
            geometry: const CanvasGeometry(x: 0, y: 0, width: 120, height: 80),
            createdAt: today,
            updatedAt: today,
          ),
        ],
        createdAt: today,
        updatedAt: today,
      );
      final recent = CanvasBoard(
        id: '${projectCanvasBoardId(workspaceName)}:recent',
        kind: CanvasBoardKind.project,
        title: 'Recent board',
        workspaceName: workspaceName,
        createdAt: today,
        updatedAt: today.add(const Duration(hours: 1)),
      );
      await canvasRepository.saveBoard(primary);
      await canvasRepository.saveBoard(recent);

      await tester.pumpWidget(
        buildPage(canvasRepository: canvasRepository, initialCanvas: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('workspace-board-dashboard-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace-board-dashboard-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('workspace-board-preview-${primary.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('workspace-board-preview-${recent.id}')),
        findsOneWidget,
      );
      expect(find.text('Recent board'), findsOneWidget);
      expect(find.text('Main board'), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey('workspace-board-actions-${recent.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace-board-title-field')),
        'Ideas board',
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-board-rename-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ideas board'), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey('workspace-board-actions-${recent.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate').last);
      await tester.pumpAndSettle();
      expect(find.text('Ideas board copy'), findsOneWidget);
      final afterDuplicate = await canvasRepository.listBoards(
        workspaceName: workspaceName,
      );
      expect(afterDuplicate, hasLength(3));
      final duplicate = afterDuplicate.singleWhere(
        (board) => board.title == 'Ideas board copy',
      );

      await tester.tap(
        find.byKey(ValueKey('workspace-board-actions-${duplicate.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();
      expect(
        (await canvasRepository.getBoard(duplicate.id))!.isArchived,
        isTrue,
      );
    });

    testWidgets(
      'dashboard creates top-level built-in and user template boards',
      (tester) async {
        final canvasRepository = InMemoryCanvasBoardRepository();
        final templateRepository = InMemoryCanvasBoardTemplateRepository();
        const workspaceName = 'project:Alpha';
        final source = CanvasBoard(
          id: 'gallery-source',
          kind: CanvasBoardKind.project,
          title: 'Gallery source',
          workspaceName: workspaceName,
          objects: <CanvasObject>[
            _stickyNote('source-note', 'Source note', today),
          ],
          createdAt: today,
          updatedAt: today,
        );
        await canvasRepository.saveBoard(source);
        await templateRepository.saveTemplate(
          CanvasBoardTemplate(
            id: 'dashboard-user-template',
            name: 'Dashboard user template',
            sourceBoardId: source.id,
            createdAt: today,
            updatedAt: today,
          ),
        );
        await tester.pumpWidget(
          buildPage(
            canvasRepository: canvasRepository,
            templateRepository: templateRepository,
            initialCanvas: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('workspace-board-dashboard-button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find
              .byKey(const ValueKey('workspace-board-dashboard-new'))
              .hitTestable(),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('workspace-template-built-in-projectPlan')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('workspace-template-use-built-in')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find
              .byKey(const ValueKey('workspace-board-dashboard-new'))
              .hitTestable(),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(
            const ValueKey('workspace-template-user-dashboard-user-template'),
          ),
        );
        await tester.tap(
          find.byKey(
            const ValueKey('workspace-template-user-dashboard-user-template'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey('workspace-template-use-dashboard-user-template'),
          ),
        );
        await tester.pumpAndSettle();

        final created = (await canvasRepository.listWorkspaceBoards(
          workspaceName,
        )).where((board) => board.id != source.id).toList();
        expect(created, hasLength(3));
        expect(created.where((board) => board.parentBoardId != null), isEmpty);
        expect(
          created.any(
            (board) => board.objects.any(
              (object) => object.payload['text'] == 'Source note',
            ),
          ),
          isTrue,
        );
      },
    );

    testWidgets('compact workspace detail exposes view menu without overflow', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('workspace-view-menu')), findsOneWidget);
      expect(find.byType(SegmentedButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('workspace-view-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Kanban'), findsOneWidget);
      expect(find.text('Gantt'), findsOneWidget);
    });

    testWidgets('workspace detail header keeps report action at medium width', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(768, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kanban'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace-detail-header')),
        findsOneWidget,
      );
      expect(find.text('Copy report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in <double>[320, 768, 1024, 1440]) {
      testWidgets('workspace detail renders at ${width.round()} with 2x text', (
        tester,
      ) async {
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: buildPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('workspace list constrains expanded content width', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('workspace-detail-list-content')),
            )
            .width,
        1120,
      );
    });

    testWidgets('Kanban cards expose move semantics and 44 target', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kanban'));
      await tester.pumpAndSettle();

      final move = find.bySemanticsLabel('Move Design homepage, To Do');
      expect(move, findsOneWidget);
      expect(tester.getSize(move).height, greaterThanOrEqualTo(44));
      semantics.dispose();
    });

    testWidgets('Kanban drag preserves status and progress mutation contract', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kanban'));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Design homepage')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
      final doingTarget = find.ancestor(
        of: find.text('In Progress'),
        matching: find.byType(DragTarget<String>),
      );
      await gesture.moveTo(tester.getCenter(doingTarget));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = await repository.getNode('task-open');
      expect(moved?.status, NodeStatus.doing);
      expect(moved?.progress, 0.1);
    });

    testWidgets('Gantt remains scrollable and semantic at 320', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-view-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gantt').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Gantt chart, 3 tasks'), findsOneWidget);
      final horizontal = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('workspace-gantt-horizontal-scroll')),
      );
      final vertical = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('workspace-gantt-vertical-scroll')),
      );
      expect(horizontal.scrollDirection, Axis.horizontal);
      expect(vertical.scrollDirection, Axis.vertical);
      expect(
        tester.getSize(find.byKey(const ValueKey('workspace-gantt-chart'))),
        const Size(1260, 152),
      );
    });

    testWidgets(
      'workspace canvas chrome preserves viewport and object geometry',
      (tester) async {
        final canvasRepository = InMemoryCanvasBoardRepository();
        final initial = CanvasBoard(
          id: projectCanvasBoardId('project:Alpha'),
          kind: CanvasBoardKind.project,
          title: 'Alpha',
          workspaceName: 'project:Alpha',
          viewport: const CanvasViewport(x: 40, y: 60, scale: 1.25),
          objects: <CanvasObject>[
            CanvasObject(
              id: 'geometry-lock',
              type: CanvasObjectType.stickyNote,
              geometry: const CanvasGeometry(
                x: 120,
                y: 240,
                width: 220,
                height: 140,
              ),
              createdAt: today,
              updatedAt: today,
            ),
          ],
          createdAt: today,
          updatedAt: today,
        );
        await canvasRepository.saveBoard(initial);
        await tester.pumpWidget(
          buildPage(canvasRepository: canvasRepository, initialCanvas: true),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Show canvas controls'));
        await tester.pumpAndSettle();

        final canvas = tester.widget<MindmapCanvas>(find.byType(MindmapCanvas));
        final persisted = await canvasRepository.getBoard(initial.id);
        expect(canvas.board?.viewport.x, closeTo(initial.viewport.x, 0.001));
        expect(canvas.board?.viewport.y, closeTo(initial.viewport.y, 0.001));
        expect(
          canvas.board?.viewport.scale,
          closeTo(initial.viewport.scale, 0.001),
        );
        expect(
          canvas.board?.objects
              .singleWhere((object) => object.id == 'geometry-lock')
              .geometry
              .toJson(),
          initial.objects.single.geometry.toJson(),
        );
        expect(persisted?.viewport.x, closeTo(initial.viewport.x, 0.001));
        expect(persisted?.viewport.y, closeTo(initial.viewport.y, 0.001));
        expect(
          persisted?.viewport.scale,
          closeTo(initial.viewport.scale, 0.001),
        );
        expect(
          persisted?.objects
              .singleWhere((object) => object.id == 'geometry-lock')
              .geometry
              .toJson(),
          initial.objects.single.geometry.toJson(),
        );
      },
    );

    testWidgets('switches to Kanban view and shows columns', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Tap Kanban button
      await tester.tap(find.text('Kanban'));
      await tester.pumpAndSettle();

      // Kanban columns should be visible
      expect(find.text('To Do'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Tasks should appear in correct columns
      expect(find.text('Design homepage'), findsOneWidget); // open -> To Do
      expect(find.text('Build API'), findsOneWidget); // doing -> In Progress
      expect(find.text('Write tests'), findsOneWidget); // done -> Done
    });

    testWidgets('switches to Gantt view and shows legend', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Tap Gantt button
      await tester.tap(find.text('Gantt'));
      await tester.pumpAndSettle();

      // Gantt legend should be visible
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.bySemanticsLabel('Gantt chart, 3 tasks'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Build API, 2026-07-01 to 2026-07-04, 0 percent'),
        findsOneWidget,
      );
    });

    testWidgets('shows stats card in list view', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Stats card should show labels
      expect(find.text('Total'), findsOneWidget);
      expect(
        find.text('Active'),
        findsWidgets,
      ); // Active appears in section header too
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
    });

    testWidgets('shows empty state for workspace with no nodes', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildPage(typeName: 'project', name: 'Nonexistent'),
      );
      await tester.pumpAndSettle();

      expect(find.text('No tasks yet'), findsOneWidget);
    });

    testWidgets('Kanban card shows due date when present', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kanban'));
      await tester.pumpAndSettle();

      // Build API has a due date, should show it
      expect(find.text('2026-07-04'), findsOneWidget);
    });
  });
}

CanvasObject _stickyNote(String id, String text, DateTime now) => CanvasObject(
  id: id,
  type: CanvasObjectType.stickyNote,
  geometry: const CanvasGeometry(x: 40, y: 60, width: 220, height: 120),
  payload: <String, Object?>{'text': text},
  createdAt: now,
  updatedAt: now,
);

CollaborationState _collaborationState({
  required String boardId,
  required CollaborationRole role,
}) => CollaborationState(
  collaborators: const <String, Collaborator>{},
  isDemoMode: false,
  isConnected: true,
  roomId: 'room-id',
  roomTarget: CollaborationTarget.projectBoard(
    boardId: boardId,
    label: 'Alpha',
  ),
  currentRole: role,
  localUserId: 'room-user',
  localName: 'Room user',
  localColor: Colors.blue,
);

final class _FakeCollaborationNotifier extends CollaborationNotifier {
  _FakeCollaborationNotifier(CollaborationState initialState) : super(_ref) {
    state = initialState;
  }

  static final _ref = _UnsupportedRef();
}

final class _UnsupportedRef implements Ref {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Provider access is not expected in this widget test.',
  );
}

final class _TrackingCanvasBoardRepository implements CanvasBoardRepository {
  _TrackingCanvasBoardRepository(this._base);

  final CanvasBoardRepository _base;
  final List<String> savedBoardIds = <String>[];

  @override
  Future<void> deleteBoard(String boardId) => _base.deleteBoard(boardId);

  @override
  Future<void> deleteBoardsAtomically(Iterable<String> boardIds) =>
      _base.deleteBoardsAtomically(boardIds);

  @override
  Future<void> deleteObjects(String boardId, Iterable<String> objectIds) =>
      _base.deleteObjects(boardId, objectIds);

  @override
  Future<CanvasBoard?> getBoard(String boardId) => _base.getBoard(boardId);

  @override
  Future<List<CanvasBoard>> listBoards({
    CanvasBoardKind? kind,
    String? workspaceName,
    bool includeArchived = false,
  }) => _base.listBoards(
    kind: kind,
    workspaceName: workspaceName,
    includeArchived: includeArchived,
  );

  @override
  Future<List<CanvasBoard>> listWorkspaceBoards(
    String workspaceName, {
    bool includeArchived = false,
    bool includeTrashed = false,
  }) => _base.listWorkspaceBoards(
    workspaceName,
    includeArchived: includeArchived,
    includeTrashed: includeTrashed,
  );

  @override
  Future<List<CanvasBoard>> getBoardsForDay(String dayKey) =>
      _base.getBoardsForDay(dayKey);

  @override
  Future<CanvasBoard> saveBoard(CanvasBoard board) async {
    savedBoardIds.add(board.id);
    return _base.saveBoard(board);
  }

  @override
  Future<void> saveBoardsAtomically(Iterable<CanvasBoard> boards) async {
    final values = boards.toList(growable: false);
    savedBoardIds.addAll(values.map((board) => board.id));
    await _base.saveBoardsAtomically(values);
  }

  @override
  Future<void> saveBoardsAtomicallyIfUnchanged({
    required Map<String, CanvasBoard> expectedBoards,
    required Iterable<CanvasBoard> boards,
    Iterable<String> deleteBoardIds = const <String>[],
  }) async {
    final values = boards.toList(growable: false);
    await _base.saveBoardsAtomicallyIfUnchanged(
      expectedBoards: expectedBoards,
      boards: values,
      deleteBoardIds: deleteBoardIds,
    );
    savedBoardIds.addAll(values.map((board) => board.id));
  }

  @override
  Future<void> saveObjects(String boardId, Iterable<CanvasObject> objects) =>
      _base.saveObjects(boardId, objects);
}

final class _FakeCollaborationActions implements CollaborationActions {
  _FakeCollaborationActions({this.onCreateProjectRoom});

  final Future<String> Function({
    required String boardId,
    required String label,
  })?
  onCreateProjectRoom;
  final List<String> createdBoardIds = <String>[];
  final List<String> createdLabels = <String>[];

  @override
  Future<void> acceptInvite(String link) async {}

  @override
  Future<CollaborationInvite> createInvite(
    String email,
    CollaborationRole role,
    Duration validity,
  ) => throw UnimplementedError();

  @override
  Future<String> createProjectRoom({
    required String boardId,
    required String label,
  }) async {
    createdBoardIds.add(boardId);
    createdLabels.add(label);
    return onCreateProjectRoom?.call(boardId: boardId, label: label) ?? 'room';
  }

  @override
  Future<void> leaveRoom() async {}

  @override
  Future<void> openRoomChecked(
    String urlOrId, {
    CollaborationTarget? expectedTarget,
    bool navigate = true,
  }) async {}

  @override
  Future<void> removeMember(String uid) async {}

  @override
  Future<void> retryOutboxNow() async {}

  @override
  Future<void> updateMemberRole(String uid, CollaborationRole role) async {}
}
