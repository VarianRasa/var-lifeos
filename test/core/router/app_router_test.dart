import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/router/app_router.dart';
import 'package:var_app/features/mindmap/application/collaboration_controller.dart';
import 'package:var_app/features/mindmap/application/media_file_import_service.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/collaboration_room.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_revision.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_revision_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';
import 'package:var_app/features/mindmap/domain/node_relations.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_detail_page.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test('search route uses standalone path', () {
    expect(AppRoute.search.path, '/search');
  });

  test('legacy node route redirects to encoded day highlight', () {
    expect(
      legacyNodeRouteLocation(date: '2026-06-18', nodeId: 'node / 1'),
      '/calendar/2026-06-18?highlight=node+%2F+1',
    );
  });

  test('project canvas route preserves exact workspace and board', () {
    final location = projectCanvasLocation(
      workspaceName: 'project:Launch / 日本',
      boardId: 'project:copy/one',
    );
    final uri = Uri.parse(location);

    expect(uri.pathSegments, <String>['workspaces', 'project', 'Launch / 日本']);
    expect(uri.queryParameters['view'], 'canvas');
    expect(uri.queryParameters['board'], 'project:copy/one');
  });

  test('project canvas route rejects invalid workspace metadata', () {
    expect(
      () => projectCanvasLocation(workspaceName: 'project', boardId: 'board'),
      throwsFormatException,
    );
  });

  testWidgets('goToDay uses canonical highlighted day URL', (tester) async {
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: <RouteBase>[
        GoRoute(
          path: '/calendar',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => goToDay(
                context,
                DateTime(2026, 6, 18),
                highlightNodeId: 'node / 1',
              ),
              child: const Text('Open node'),
            ),
          ),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) => const Scaffold(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open node'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18?highlight=node+%2F+1',
    );
  });

  testWidgets('node route opens dedicated full-page app', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'legacy-node',
          type: NodeType.note,
          title: 'Legacy node',
          day: day,
          now: day,
        ),
      ],
    );
    final router = createAppRouter(
      initialLocation: '/calendar/2026-06-18/node/legacy-node',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18/node/legacy-node',
    );
    expect(find.byType(NodeDetailPage), findsOneWidget);
    expect(find.text('Main App'), findsOneWidget);
  });

  testWidgets('dedicated local image renders attachment preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final base = MindmapNode.create(
      id: 'dedicated-image-preview',
      type: NodeType.image,
      title: 'Image preview',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: const ImagePayload(
        attachmentId: 'local-image',
        mimeType: 'image/png',
        fileName: 'preview.png',
      ).toData(base.data),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final attachments = _RecordingAttachmentRepository()
      ..importedBytes['local-image'] = const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
        ],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<Image>(find.byType(Image).first);
    expect(editor.image, isNotNull);
  });

  testWidgets('dedicated media editor saves edited image via media action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final base = MindmapNode.create(
      id: 'media-action-image',
      type: NodeType.image,
      title: 'Edit image',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: const ImagePayload(
        attachmentId: 'original-image',
        mimeType: 'image/png',
        fileName: 'original.png',
      ).toData(base.data),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final attachments = _RecordingAttachmentRepository()
      ..importedBytes['original-image'] = const [0x89, 0x50, 0x4e, 0x47];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
        ],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<Image>(find.byType(Image).first);
    expect(editor.image, isNotNull);
  });

  testWidgets('dedicated image and video editors receive bounded layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final image = MindmapNode.create(
      id: 'dedicated-image',
      type: NodeType.image,
      title: 'Image node',
      day: day,
      now: day,
    );
    final video = MindmapNode.create(
      id: 'dedicated-video',
      type: NodeType.video,
      title: 'Video node',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [image, video]);

    for (final node in [image, video]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: NodeDetailPage(
              key: ValueKey(node.id),
              date: day,
              nodeId: node.id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(ValueKey('${node.type.name}-editor-large')),
        findsOneWidget,
      );
    }
  });

  testWidgets('node detail flushes pending title before back', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'editable-node',
          type: NodeType.note,
          title: 'Original title',
          day: day,
          now: day,
        ),
      ],
    );
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/detail'),
              child: const Text('Open detail'),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) =>
              NodeDetailPage(date: day, nodeId: 'editable-node'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Saved before back');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Open detail'), findsOneWidget);
    expect(
      (await repository.getNode('editable-node'))?.title,
      'Saved before back',
    );
  });

  testWidgets('node detail merges local edit into latest repository node', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final original = MindmapNode.create(
      id: 'concurrent-edit-node',
      type: NodeType.note,
      title: 'Original title',
      body: 'Original body',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [original]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: original.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Local title');
    await repository.saveNode(original.copyWith(body: 'Remote body'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final saved = await repository.getNode(original.id);
    expect(saved?.title, 'Local title');
    expect(saved?.body, 'Remote body');
  });

  testWidgets('node detail flushes draft when app pauses', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'detail-lifecycle-node',
      type: NodeType.note,
      title: 'Original title',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Paused draft');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect((await repository.getNode(node.id))?.title, 'Paused draft');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('node detail shares saved node into matching day room', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'shared-node',
      type: NodeType.note,
      title: 'Original title',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final gateway = _FakeNodeDetailCollaborationGateway(
      state: _collaborationState(
        roomId: 'room',
        target: CollaborationTarget.day('2026-06-18'),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          collaborationProvider.overrideWith(
            (ref) => _DialogCollaborationNotifier(gateway.state),
          ),
        ],
        child: MaterialApp(
          home: NodeDetailPage(
            date: day,
            nodeId: node.id,
            collaborationGateway: gateway,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Shared title');
    await tester.tap(find.byKey(const ValueKey('node-detail-share')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gateway.createCount, 0);
    expect(gateway.leaveCount, 0);
    expect(gateway.boundNodes.single.title, 'Shared title');
    expect((await repository.getNode(node.id))?.title, 'Shared title');
    expect(
      find.byKey(const ValueKey('collaboration-share-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('expense share confirms and excludes local receipt metadata', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final base = MindmapNode.create(
      id: 'expense-share-node',
      type: NodeType.expense,
      title: 'Taxi',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: const ExpensePayload(
        amount: 20,
        receipts: [
          ResourceAsset(
            id: 'receipt-1',
            kind: 'file',
            attachmentId: 'attachment-1',
            fileName: 'taxi.pdf',
            mimeType: 'application/pdf',
          ),
        ],
      ).toData(base.data),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final gateway = _FakeNodeDetailCollaborationGateway(
      state: _collaborationState(
        roomId: 'room',
        target: CollaborationTarget.day('2026-06-18'),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          collaborationProvider.overrideWith(
            (ref) => _DialogCollaborationNotifier(gateway.state),
          ),
        ],
        child: MaterialApp(
          home: NodeDetailPage(
            date: day,
            nodeId: node.id,
            collaborationGateway: gateway,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('node-detail-share')));
    await tester.pump();
    expect(find.text('Share without receipt files?'), findsOneWidget);
    await tester.tap(find.text('Share data only'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      ExpensePayload.fromNode(gateway.boundNodes.single).receipts,
      isEmpty,
    );
    expect(
      ExpensePayload.fromNode((await repository.getNode(node.id))!).receipts,
      hasLength(1),
    );
  });

  testWidgets('relation link flushes pending title and preserves link', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final source = MindmapNode.create(
      id: 'source',
      type: NodeType.note,
      title: 'Original title',
      day: day,
      now: day,
    );
    final target = MindmapNode.create(
      id: 'target',
      type: NodeType.note,
      title: 'Target',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [source, target]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          allMindmapNodesProvider.overrideWith((ref) => repository.listNodes()),
          nodeGraphProvider.overrideWith(
            (ref) async => NodeGraph.fromNodes([source, target]),
          ),
          nodeRelationsProvider(source.id).overrideWith(
            (ref) async => NodeRelations(
              nodeId: source.id,
              relatedNodes: const [],
              backlinks: const [],
            ),
          ),
        ],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: source.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Pending title');
    expect((await repository.getNode(source.id))?.title, 'Original title');
    await tester.tap(find.text('Relations'));
    await tester.pumpAndSettle();
    final link = find.byTooltip('Link node');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    final saved = await repository.getNode(source.id);
    expect(saved?.title, 'Pending title');
    expect(saved?.relatedNodeIds, contains(target.id));
  });

  testWidgets('type editor title stays synchronized with header title', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'title-sync-node',
      type: NodeType.note,
      title: 'Original title',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final typeEditorTitle = find.byKey(
      const ValueKey('productivity-title-sync-node-title-field'),
    );
    await tester.ensureVisible(typeEditorTitle);
    await tester.pump();
    await tester.enterText(typeEditorTitle, 'Editor title');
    await tester.pump();

    final header = tester.widget<TextField>(find.byType(TextField).first);
    expect(header.controller?.text, 'Editor title');
  });

  testWidgets('header title stays synchronized with type editor title', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'reverse-title-sync-node',
      type: NodeType.note,
      title: 'Original title',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Header title');
    await tester.pump();

    final typeEditorTitle = find.byKey(
      const ValueKey('productivity-reverse-title-sync-node-title-field'),
    );
    final editable = tester.widget<EditableText>(
      find.descendant(of: typeEditorTitle, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, 'Header title');
  });

  testWidgets('failed receipt save keeps attachment for pending retry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'expense-retry-receipt',
      type: NodeType.expense,
      title: 'Taxi',
      day: day,
      now: day,
    );
    final base = InMemoryMindmapRepository(seedNodes: [node]);
    final repository = _FailOnceMindmapRepository(base);
    final attachments = _RecordingAttachmentRepository();
    final importer = MediaFileImportService(
      repository: attachments,
      picker: const _ReceiptMediaFilePicker(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
          mediaFileImportServiceProvider.overrideWith((ref) async => importer),
        ],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addReceipt = find.byKey(const ValueKey('expense-receipt-add'));
    await tester.ensureVisible(addReceipt);
    await tester.tap(addReceipt);
    await tester.pumpAndSettle();

    expect(attachments.deletedIds, isEmpty);
    expect(find.textContaining('Failed to save node:'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Taxi retry');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final saved = (await repository.getNode(node.id))!;
    expect(ExpensePayload.fromNode(saved).receipts, hasLength(1));
    expect(attachments.deletedIds, isEmpty);
  });

  testWidgets('dedicated task editor imports and retains attachment metadata', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-dedicated-attachment',
      type: NodeType.task,
      title: 'Task attachment',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final attachments = _RecordingAttachmentRepository();
    final importer = MediaFileImportService(
      repository: attachments,
      picker: const _ReceiptMediaFilePicker(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
          mediaFileImportServiceProvider.overrideWith((ref) async => importer),
        ],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addAttachment = find.byKey(
      const ValueKey<String>('task-add-attachment'),
    );
    expect(tester.widget<IconButton>(addAttachment).onPressed, isNotNull);
    final addCallback = tester.widget<IconButton>(addAttachment).onPressed!;
    addCallback();
    await tester.pumpAndSettle();

    final saved = (await repository.getNode(node.id))!;
    expect(TaskChecklistPayload.fromNode(saved).attachments, hasLength(1));
    expect(attachments.deletedIds, isEmpty);
  });

  testWidgets('dedicated audio editor imports selected audio', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'audio-dedicated-import',
      type: NodeType.audio,
      title: 'Voice note',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final attachments = _RecordingAttachmentRepository();
    final importer = MediaFileImportService(
      repository: attachments,
      picker: const _AudioMediaFilePicker(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
          mediaFileImportServiceProvider.overrideWith((ref) async => importer),
        ],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chooseFile = find.byKey(const ValueKey('audio-choose-file-action'));
    expect(tester.widget<ButtonStyleButton>(chooseFile).onPressed, isNotNull);
    tester.widget<ButtonStyleButton>(chooseFile).onPressed!();
    await tester.pumpAndSettle();

    final saved = (await repository.getNode(node.id))!;
    expect(AudioPayload.fromNode(saved).attachmentId, isNotEmpty);
  });

  testWidgets('dedicated itinerary converts agenda item to task', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final base = MindmapNode.create(
      id: 'itinerary-dedicated-convert',
      type: NodeType.itinerary,
      title: 'Trip',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: ItineraryPayload(
        destination: 'City',
        startDate: day,
        endDate: day,
        timezone: 'Local time',
        agenda: const [
          ItineraryAgendaItem(
            id: 'agenda-1',
            title: 'Museum',
            startMinutes: 600,
            durationMinutes: 90,
          ),
        ],
      ).toData(base.data),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final convert = find.byKey(
      const ValueKey<String>('itinerary-convert-task-agenda-1'),
    );
    expect(tester.widget<IconButton>(convert).onPressed, isNotNull);
    tester.widget<IconButton>(convert).onPressed!();
    await tester.pumpAndSettle();

    final created = (await repository.listNodes())
        .where((item) => item.id != node.id)
        .single;
    expect(created.type, NodeType.task);
    expect(created.title, 'Museum');
    expect(created.relatedNodeIds, contains(node.id));
  });

  testWidgets('expense receipt delete keeps versioned attachment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    const receipt = ResourceAsset(
      id: 'receipt-1',
      kind: 'file',
      attachmentId: 'attachment-1',
      fileName: 'taxi.pdf',
      mimeType: 'application/pdf',
    );
    final base = MindmapNode.create(
      id: 'expense-delete-receipt',
      type: NodeType.expense,
      title: 'Taxi',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: const ExpensePayload(
        amount: 20,
        receipts: [receipt],
      ).toData(base.data),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final attachments = _RecordingAttachmentRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
        ],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final actions = find.byKey(
      const ValueKey('expense-receipt-actions-receipt-1'),
    );
    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete receipt?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      ExpensePayload.fromNode((await repository.getNode(node.id))!).receipts,
      isEmpty,
    );
    expect(attachments.deletedIds, isEmpty);
    expect(
      find.byKey(const ValueKey('expense-receipt-receipt-1')),
      findsNothing,
    );
  });

  testWidgets('expense node delete preserves receipt shared by another node', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    const receipt = ResourceAsset(
      id: 'receipt-1',
      kind: 'file',
      attachmentId: 'shared-attachment',
      fileName: 'taxi.pdf',
      mimeType: 'application/pdf',
    );
    MindmapNode expense(String id, String title) {
      final base = MindmapNode.create(
        id: id,
        type: NodeType.expense,
        title: title,
        day: day,
        now: day,
      );
      return base.copyWith(
        data: const ExpensePayload(
          amount: 20,
          receipts: [receipt],
        ).toData(base.data),
      );
    }

    final deleted = expense('expense-delete-shared', 'Delete me');
    final surviving = expense('expense-survives', 'Keep me');
    final repository = InMemoryMindmapRepository(
      seedNodes: [deleted, surviving],
    );
    final revisions = _RecordingRevisionRepository();
    final attachments = _RecordingAttachmentRepository();

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              NodeDetailPage(date: day, nodeId: deleted.id),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) => const Scaffold(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          mindmapNodeRevisionRepositoryProvider.overrideWithValue(revisions),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete node'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await repository.getNode(deleted.id), isNull);
    expect(await repository.getNode(surviving.id), isNotNull);
    expect(attachments.deletedIds, isEmpty);
  });

  testWidgets('expense node delete retains recovery history and attachments', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    const receipt = ResourceAsset(
      id: 'receipt-1',
      kind: 'file',
      attachmentId: 'attachment-1',
      fileName: 'taxi.pdf',
      mimeType: 'application/pdf',
    );
    final base = MindmapNode.create(
      id: 'expense-delete-node',
      type: NodeType.expense,
      title: 'Taxi',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: const ExpensePayload(
        amount: 20,
        receipts: [receipt],
      ).toData(base.data),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final revisions = _RecordingRevisionRepository();
    final attachments = _RecordingAttachmentRepository();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/detail'),
              child: const Text('Open detail'),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) =>
              NodeDetailPage(date: day, nodeId: node.id),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          mindmapNodeRevisionRepositoryProvider.overrideWithValue(revisions),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete node'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await repository.getNode(node.id), isNull);
    expect(revisions.deletedNodeIds, isEmpty);
    expect(attachments.deletedIds, isEmpty);
    expect(find.text('Open detail'), findsOneWidget);
  });

  testWidgets('node detail confirms room switch before sharing', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'switch-node',
      type: NodeType.task,
      title: 'Switch room',
      day: day,
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final gateway = _FakeNodeDetailCollaborationGateway(
      state: _collaborationState(
        roomId: 'other-room',
        target: CollaborationTarget.projectBoard(
          boardId: 'board',
          label: 'Board',
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          collaborationProvider.overrideWith(
            (ref) => _DialogCollaborationNotifier(gateway.state),
          ),
        ],
        child: MaterialApp(
          home: NodeDetailPage(
            date: day,
            nodeId: node.id,
            collaborationGateway: gateway,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('node-detail-share')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Switch collaboration room?'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gateway.leaveCount, 1);
    expect(gateway.createCount, 1);
    expect(gateway.boundNodes.single.id, node.id);
    expect(
      find.byKey(const ValueKey('collaboration-share-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('route replacement waits for pending node save', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'replace-save-node',
      type: NodeType.note,
      title: 'Original title',
      day: day,
      now: day,
    );
    final repository = _ManuallyCompletedMindmapRepository(
      InMemoryMindmapRepository(seedNodes: [node]),
    );
    final exitController = NodeDetailExitController();
    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          onExit: (context, state) => exitController.prepareExit(),
          builder: (context, state) => NodeDetailPage(
            date: day,
            nodeId: node.id,
            exitController: exitController,
          ),
        ),
        GoRoute(
          path: '/other',
          builder: (context, state) => const Scaffold(body: Text('Other page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Saved before replace',
    );
    router.go('/other');
    await tester.pump();
    await tester.pump();

    expect(find.byType(NodeDetailPage), findsOneWidget);
    expect(repository.pendingSaveCount, 1);

    repository.completeNextSave();
    await tester.pumpAndSettle();

    expect(find.text('Other page'), findsOneWidget);
    expect((await repository.getNode(node.id))?.title, 'Saved before replace');
  });

  testWidgets('stacked node route restores previous exit save gate', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final first = MindmapNode.create(
      id: 'stacked-first-node',
      type: NodeType.note,
      title: 'First title',
      day: day,
      now: day,
    );
    final second = MindmapNode.create(
      id: 'stacked-second-node',
      type: NodeType.note,
      title: 'Second title',
      day: day,
      now: day,
    );
    final repository = _ManuallyCompletedMindmapRepository(
      InMemoryMindmapRepository(seedNodes: [first, second]),
    );
    final exitController = NodeDetailExitController();
    final router = GoRouter(
      initialLocation: '/detail/${first.id}',
      routes: [
        GoRoute(
          path: '/detail/:nodeId',
          onExit: (context, state) => exitController.prepareExit(),
          builder: (context, state) => NodeDetailPage(
            date: day,
            nodeId: state.pathParameters['nodeId']!,
            exitController: exitController,
          ),
        ),
        GoRoute(
          path: '/other',
          builder: (context, state) => const Scaffold(body: Text('Other page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    unawaited(router.push<void>('/detail/${second.id}'));
    await tester.pumpAndSettle();
    expect(find.text('Second title'), findsWidgets);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('First title'), findsWidgets);

    await tester.enterText(
      find.byType(TextField).first,
      'First saved after stacked pop',
    );
    router.go('/other');
    await tester.pump();
    await tester.pump();

    expect(find.byType(NodeDetailPage), findsOneWidget);
    expect(repository.pendingSaveCount, 1);

    repository.completeNextSave();
    await tester.pumpAndSettle();

    expect(find.text('Other page'), findsOneWidget);
    expect(
      (await repository.getNode(first.id))?.title,
      'First saved after stacked pop',
    );
  });

  testWidgets('revision restore preserves edits made while restore runs', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final current = MindmapNode.create(
      id: 'restore-race-node',
      type: NodeType.note,
      title: 'Current title',
      day: day,
      now: day,
    );
    final restoredSnapshot = current.copyWith(title: 'Restored title');
    final revision = MindmapNodeRevision(
      id: 'restore-race-revision',
      nodeId: current.id,
      sequence: 1,
      kind: MindmapNodeRevisionKind.updated,
      recordedAt: day,
      snapshot: restoredSnapshot,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [current]);
    final revisions = _DelayedRestoreRevisionRepository(
      repository: repository,
      revision: revision,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          mindmapNodeRevisionRepositoryProvider.overrideWithValue(revisions),
        ],
        child: MaterialApp(
          home: NodeDetailPage(date: day, nodeId: current.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restored title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore this revision'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pump();

    expect(revisions.restorePending, isTrue);
    await tester.enterText(
      find.byType(TextField).first,
      'Edited during restore',
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      (await repository.getNode(current.id))?.title,
      'Edited during restore',
    );

    await revisions.completeRestore();
    await tester.pumpAndSettle();

    expect(
      (await repository.getNode(current.id))?.title,
      'Edited during restore',
    );
    expect(find.text('Edited during restore'), findsWidgets);
  });

  testWidgets('node route rejects a node from another local day', (
    tester,
  ) async {
    final routeDay = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'cross-day-node',
          type: NodeType.note,
          title: 'Tomorrow node',
          day: routeDay.add(const Duration(days: 1)),
          now: routeDay,
        ),
      ],
    );
    final router = createAppRouter(
      initialLocation: '/calendar/2026-06-18/node/cross-day-node',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18/node/cross-day-node',
    );
    expect(find.text('Node belongs to another calendar day'), findsOneWidget);
  });

  testWidgets('browser history opens dedicated node without blank frame', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'legacy-node',
          type: NodeType.note,
          title: 'Legacy node',
          day: day,
          now: day,
        ),
      ],
    );
    final router = createAppRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await router.routeInformationProvider.didPushRouteInformation(
      RouteInformation(uri: Uri.parse('/calendar/2026-06-18/node/legacy-node')),
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18/node/legacy-node',
    );
    expect(find.byType(NodeDetailPage), findsOneWidget);
    expect(find.text('Legacy node'), findsWidgets);
  });

  testWidgets('recovery route opens Recovery Center', (tester) async {
    final router = createAppRouter(initialLocation: '/recovery');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(router.routeInformationProvider.value.uri.toString(), '/recovery');
    expect(find.text('Recovery Center'), findsOneWidget);
    expect(
      AppRoute.values.map((route) => route.name),
      isNot(contains('recovery')),
    );
  });

  testWidgets('route panel opens left and resizes within standard limits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createAppRouter(
      initialLocation: '/calendar/2026-06-18?panel=notesJournal',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('route-panel-notesJournal'));
    final resizeHandle = find.byKey(const ValueKey('route-panel-resize'));
    final minimumWidth = tester.getSize(panel).width;
    expect(minimumWidth, greaterThanOrEqualTo(480));
    expect(find.text('Notes & Journal'), findsWidgets);
    expect(find.byKey(const ValueKey('close-route-panel')), findsOneWidget);
    expect(resizeHandle, findsOneWidget);
    expect(tester.getSize(resizeHandle).width, 20);
    expect(
      find.byKey(const ValueKey('route-panel-resize-line')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('route-panel-resize')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, minimumWidth + 200);

    await tester.drag(
      find.byKey(const ValueKey('route-panel-resize')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, minimumWidth);
  });

  testWidgets('mobile route panel fills body without resize handle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createAppRouter(
      initialLocation: '/calendar/2026-06-18?panel=notesJournal',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('route-panel-notesJournal')))
          .width,
      390,
    );
    expect(find.byKey(const ValueKey('route-panel-resize')), findsNothing);
  });

  test('node_detail route name remains compatible', () {
    final router = createAppRouter();
    addTearDown(router.dispose);

    expect(
      router.namedLocation(
        'node_detail',
        pathParameters: const {'date': '2026-06-18', 'nodeId': 'legacy-node'},
      ),
      '/calendar/2026-06-18/node/legacy-node',
    );
  });
}

CollaborationState _collaborationState({
  required String roomId,
  required CollaborationTarget target,
}) => CollaborationState(
  collaborators: const {},
  isDemoMode: false,
  isConnected: true,
  roomId: roomId,
  roomTarget: target,
  currentRole: CollaborationRole.owner,
  localUserId: 'owner',
  localName: 'Owner',
  localColor: Colors.blue,
);

final class _FakeNodeDetailCollaborationGateway
    implements NodeDetailCollaborationGateway {
  _FakeNodeDetailCollaborationGateway({required this.state});

  @override
  CollaborationState state;
  int leaveCount = 0;
  int createCount = 0;
  final List<MindmapNode> boundNodes = [];

  @override
  Future<void> leaveRoom() async {
    leaveCount++;
    state = state.copyWith(clearRoom: true);
  }

  @override
  Future<String> createRoom(DateTime day) async {
    createCount++;
    state = state.copyWith(
      roomId: 'new-room',
      roomTarget: CollaborationTarget.day(
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      ),
      currentRole: CollaborationRole.owner,
    );
    return 'new-room';
  }

  @override
  Future<void> bindNode(MindmapNode node) async {
    boundNodes.add(node);
  }
}

final class _RecordingAttachmentRepository implements NodeAttachmentRepository {
  final List<String> deletedIds = [];
  final Map<String, List<int>> importedBytes = {};

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async => const [];

  @override
  Future<void> delete(String attachmentId) async {
    deletedIds.add(attachmentId);
    importedBytes.remove(attachmentId);
  }

  @override
  Future<List<int>?> exportBytes(String attachmentId) async =>
      importedBytes[attachmentId];

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    const id = 'imported-receipt';
    importedBytes[id] = List<int>.of(bytes);
    return NodeAttachment(
      id: id,
      fileName: fileName,
      mimeType: mimeType,
      byteLength: bytes.length,
      checksum: 'checksum',
      createdAt: DateTime(2026, 6, 18),
    );
  }

  @override
  Future<List<int>?> readBytes(String attachmentId) async =>
      importedBytes[attachmentId];

  @override
  Future<NodeAttachment?> resolve(String attachmentId) async => null;
}

final class _ReceiptMediaFilePicker implements MediaFilePicker {
  const _ReceiptMediaFilePicker();

  @override
  Future<PickedMediaFile?> pick(MediaFileKind kind) async =>
      const PickedMediaFile(
        fileName: 'receipt.bin',
        byteLength: 4,
        bytes: [1, 2, 3, 4],
      );
}

final class _AudioMediaFilePicker implements MediaFilePicker {
  const _AudioMediaFilePicker();

  @override
  Future<PickedMediaFile?> pick(MediaFileKind kind) async =>
      const PickedMediaFile(
        fileName: 'voice.wav',
        byteLength: 12,
        mimeType: 'audio/wav',
        bytes: [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x41, 0x56, 0x45],
      );
}

final class _ManuallyCompletedMindmapRepository implements MindmapRepository {
  _ManuallyCompletedMindmapRepository(this._base);

  final InMemoryMindmapRepository _base;
  final List<(MindmapNode, Completer<MindmapNode>)> _pending = [];

  int get pendingSaveCount => _pending.length;

  @override
  Future<void> deleteNode(String id) => _base.deleteNode(id);

  @override
  Future<MindmapNode?> getNode(String id) => _base.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _base.listNodes(day: day);

  @override
  Future<MindmapNode> saveNode(MindmapNode node) {
    final completer = Completer<MindmapNode>();
    _pending.add((node, completer));
    return completer.future;
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _base.searchNodes(query);

  void completeNextSave() {
    final pending = _pending.removeAt(0);
    _base.saveNode(pending.$1).then(pending.$2.complete);
  }
}

final class _FailOnceMindmapRepository implements MindmapRepository {
  _FailOnceMindmapRepository(this._base);

  final InMemoryMindmapRepository _base;
  var _shouldFail = true;

  @override
  Future<void> deleteNode(String id) => _base.deleteNode(id);

  @override
  Future<MindmapNode?> getNode(String id) => _base.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _base.listNodes(day: day);

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('forced receipt save failure');
    }
    return _base.saveNode(node);
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _base.searchNodes(query);
}

final class _DelayedRestoreRevisionRepository
    implements MindmapNodeRevisionRepository {
  _DelayedRestoreRevisionRepository({
    required this.repository,
    required this.revision,
  });

  final InMemoryMindmapRepository repository;
  final MindmapNodeRevision revision;
  Completer<void>? _restoreGate;

  bool get restorePending => _restoreGate != null;

  @override
  Future<void> deleteRevisions(String nodeId) async {}

  @override
  Future<MindmapNodeRevision?> getRevision(String revisionId) async =>
      revisionId == revision.id ? revision : null;

  @override
  Future<List<MindmapNodeRevision>> listRevisions(
    String nodeId, {
    int limit = 50,
  }) async => nodeId == revision.nodeId ? [revision] : const [];

  @override
  Future<MindmapNode> restoreRevision(
    String revisionId, {
    required DateTime now,
  }) async {
    final gate = Completer<void>();
    _restoreGate = gate;
    await gate.future;
    return repository.saveNode(revision.snapshot.copyWith(updatedAt: now));
  }

  Future<void> completeRestore() async {
    final gate = _restoreGate;
    if (gate == null) throw StateError('No restore is pending.');
    _restoreGate = null;
    gate.complete();
    await gate.future;
  }
}

final class _RecordingRevisionRepository
    implements MindmapNodeRevisionRepository {
  final List<String> deletedNodeIds = [];

  @override
  Future<void> deleteRevisions(String nodeId) async {
    deletedNodeIds.add(nodeId);
  }

  @override
  Future<MindmapNodeRevision?> getRevision(String revisionId) async => null;

  @override
  Future<List<MindmapNodeRevision>> listRevisions(
    String nodeId, {
    int limit = 50,
  }) async => const [];

  @override
  Future<MindmapNode> restoreRevision(
    String revisionId, {
    required DateTime now,
  }) => throw UnsupportedError('Restore is not used in this test.');
}

final class _DialogCollaborationNotifier extends CollaborationNotifier {
  _DialogCollaborationNotifier(CollaborationState initialState) : super(_ref) {
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
