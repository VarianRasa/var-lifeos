import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/board_template_service.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/data/canvas_board_template_repositories.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);
  var id = 0;

  CanvasObject object(
    String objectId,
    CanvasObjectType type, {
    String? parentFrameId,
    String? referencedBoardId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => CanvasObject(
    id: objectId,
    type: type,
    geometry: const CanvasGeometry(x: 0, y: 0, width: 200, height: 100),
    parentFrameId: parentFrameId,
    referencedBoardId: referencedBoardId,
    payload: payload,
    createdAt: now,
    updatedAt: now,
  );

  CanvasBoard board(
    String boardId, {
    CanvasBoardKind kind = CanvasBoardKind.project,
    String? workspaceName = 'Work',
    bool isArchived = false,
    DateTime? trashedAt,
    List<CanvasObject> objects = const <CanvasObject>[],
  }) => CanvasBoard(
    id: boardId,
    kind: kind,
    title: boardId,
    workspaceName: workspaceName,
    isArchived: isArchived,
    trashedAt: trashedAt,
    objects: objects,
    createdAt: now,
    updatedAt: now,
  );

  BoardTemplateService service(
    InMemoryCanvasBoardRepository boards,
    InMemoryCanvasBoardTemplateRepository templates,
  ) => BoardTemplateService(
    boardRepository: boards,
    templateRepository: templates,
    idFactory: () => 'generated-${id++}',
  );

  setUp(() => id = 0);

  test('saves only active project source in requested workspace', () async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoardsAtomically(<CanvasBoard>[
      board('active'),
      board('other', workspaceName: 'Other'),
      board('archived', isArchived: true),
      board('trashed', trashedAt: now),
      board('daily', kind: CanvasBoardKind.daily, workspaceName: null),
    ]);
    final subject = service(boards, templates);

    final saved = await subject.saveSourceAsTemplate(
      sourceBoardId: 'active',
      workspaceName: 'Work',
      name: '  My template  ',
      now: now,
    );

    expect(saved.id, 'generated-0');
    expect(saved.name, 'My template');
    expect(saved.sourceBoardId, 'active');
    expect(await templates.listTemplates(), <CanvasBoardTemplate>[saved]);
    for (final sourceId in <String>['other', 'archived', 'trashed', 'daily']) {
      expect(
        () => subject.saveSourceAsTemplate(
          sourceBoardId: sourceId,
          workspaceName: 'Work',
          name: 'Invalid',
          now: now,
        ),
        throwsStateError,
      );
    }
  });

  test(
    'lists active sources by workspace and resolves source updates live',
    () async {
      final boards = InMemoryCanvasBoardRepository();
      final templates = InMemoryCanvasBoardTemplateRepository();
      final first = object('first', CanvasObjectType.shape);
      await boards.saveBoard(board('source', objects: <CanvasObject>[first]));
      final subject = service(boards, templates);
      final saved = await subject.saveSourceAsTemplate(
        sourceBoardId: 'source',
        workspaceName: 'Work',
        name: 'Live',
        now: now,
      );

      expect(
        await subject.availableUserTemplates(
          'Work',
          workspaceBoards: await boards.listWorkspaceBoards(
            'Work',
            includeArchived: true,
            includeTrashed: true,
          ),
        ),
        <CanvasBoardTemplate>[saved],
      );
      await boards.saveBoard(
        board(
          'source',
          objects: <CanvasObject>[object('second', CanvasObjectType.text)],
        ),
      );

      final cloned = await subject.instantiateUserTemplate(
        template: saved,
        workspaceName: 'Work',
        now: now,
      );
      expect(cloned.single.type, CanvasObjectType.text);
    },
  );

  test('filters template when source enters Trash or is deleted', () async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoard(board('source'));
    final subject = service(boards, templates);
    final saved = await subject.saveSourceAsTemplate(
      sourceBoardId: 'source',
      workspaceName: 'Work',
      name: 'Live',
      now: now,
    );

    await boards.saveBoard(board('source', trashedAt: now));
    expect(
      await subject.availableUserTemplates(
        'Work',
        workspaceBoards: await boards.listWorkspaceBoards(
          'Work',
          includeArchived: true,
          includeTrashed: true,
        ),
      ),
      isEmpty,
    );
    await boards.deleteBoard('source');
    expect(
      await subject.availableUserTemplates(
        'Work',
        workspaceBoards: await boards.listWorkspaceBoards(
          'Work',
          includeArchived: true,
          includeTrashed: true,
        ),
      ),
      isEmpty,
    );
    expect(await templates.listTemplates(), <CanvasBoardTemplate>[saved]);
  });

  test('renames and deletes metadata', () async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoard(board('source'));
    final subject = service(boards, templates);
    final saved = await subject.saveSourceAsTemplate(
      sourceBoardId: 'source',
      workspaceName: 'Work',
      name: 'Old',
      now: now,
    );

    final renamed = await subject.renameTemplate(
      templateId: saved.id,
      expectedUpdatedAt: saved.updatedAt,
      name: '  New  ',
      now: now.add(const Duration(minutes: 1)),
    );
    expect(renamed.name, 'New');
    expect(renamed.sourceBoardId, 'source');
    expect(renamed.createdAt, now);
    await subject.deleteTemplate(renamed.id);
    expect(await templates.listTemplates(), isEmpty);
  });

  test('rename rejects displayed snapshot after concurrent rename', () async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    await boards.saveBoard(board('source'));
    final subject = service(boards, templates);
    final saved = await subject.saveSourceAsTemplate(
      sourceBoardId: 'source',
      workspaceName: 'Work',
      name: 'Original',
      now: now,
    );
    final concurrentAt = now.add(const Duration(minutes: 1));
    final concurrent = await templates.renameTemplate(
      templateId: saved.id,
      expectedUpdatedAt: saved.updatedAt,
      name: 'Concurrent',
      updatedAt: concurrentAt,
    );

    await expectLater(
      subject.renameTemplate(
        templateId: saved.id,
        expectedUpdatedAt: saved.updatedAt,
        name: 'Stale UI rename',
        now: now.add(const Duration(minutes: 2)),
      ),
      throwsStateError,
    );

    expect(await templates.listTemplates(), <CanvasBoardTemplate>[concurrent]);
  });

  test('rename rejects unknown ID without creating metadata', () async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    final subject = service(boards, templates);

    await expectLater(
      subject.renameTemplate(
        templateId: 'unknown',
        expectedUpdatedAt: now,
        name: 'Forged',
        now: now,
      ),
      throwsStateError,
    );

    expect(await templates.listTemplates(), isEmpty);
  });

  test(
    'user instantiate excludes references and cleans relations without writes',
    () async {
      final boards = InMemoryCanvasBoardRepository();
      final templates = InMemoryCanvasBoardTemplateRepository();
      await boards.saveBoard(
        board(
          'source',
          objects: <CanvasObject>[
            object('frame', CanvasObjectType.frame),
            object('child', CanvasObjectType.shape, parentFrameId: 'frame'),
            object(
              'reference',
              CanvasObjectType.boardReference,
              referencedBoardId: 'target',
            ),
            object(
              'connector',
              CanvasObjectType.connector,
              payload: const <String, Object?>{
                'sourceObjectId': 'child',
                'targetObjectId': 'reference',
              },
            ),
          ],
        ),
      );
      final subject = service(boards, templates);
      final saved = await subject.saveSourceAsTemplate(
        sourceBoardId: 'source',
        workspaceName: 'Work',
        name: 'Clean',
        now: now,
      );
      final boardCount = (await boards.listBoards(
        includeArchived: true,
      )).length;

      final cloned = await subject.instantiateUserTemplate(
        template: saved,
        workspaceName: 'Work',
        now: now,
      );

      expect(cloned.map((item) => item.type), <CanvasObjectType>[
        CanvasObjectType.frame,
        CanvasObjectType.shape,
      ]);
      expect(cloned[1].parentFrameId, cloned[0].id);
      expect(
        (await boards.listBoards(includeArchived: true)).length,
        boardCount,
      );
    },
  );

  test('built-in instantiate clones definition without writes', () async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    final subject = service(boards, templates);

    final cloned = subject.instantiateBuiltInTemplate(
      template: builtInCanvasBoardTemplates.first,
      now: now,
    );

    expect(cloned, isNotEmpty);
    expect(
      cloned.first.id,
      isNot(builtInCanvasBoardTemplates.first.objects.first.id),
    );
    expect(await boards.listBoards(includeArchived: true), isEmpty);
  });

  test('missing source fails before any board write', () async {
    final boards = InMemoryCanvasBoardRepository();
    final templates = InMemoryCanvasBoardTemplateRepository();
    final subject = service(boards, templates);
    final missing = CanvasBoardTemplate(
      id: 'template',
      name: 'Missing',
      sourceBoardId: 'missing',
      createdAt: now,
      updatedAt: now,
    );
    await templates.saveTemplate(missing);

    await expectLater(
      subject.instantiateUserTemplate(
        template: missing,
        workspaceName: 'Work',
        now: now,
      ),
      throwsStateError,
    );
    expect(await boards.listBoards(includeArchived: true), isEmpty);
  });
}
