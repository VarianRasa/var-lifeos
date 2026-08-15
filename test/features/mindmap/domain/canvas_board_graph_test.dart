import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_graph.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);

  CanvasObject reference(String id, String targetId) => CanvasObject(
    id: id,
    type: CanvasObjectType.boardReference,
    geometry: const CanvasGeometry(x: 0, y: 0, width: 280, height: 180),
    referencedBoardId: targetId,
    createdAt: now,
    updatedAt: now,
  );

  CanvasBoard board(
    String id, {
    String workspace = 'Work',
    String? parentId,
    DateTime? trashedAt,
    List<CanvasObject> objects = const <CanvasObject>[],
  }) => CanvasBoard(
    id: id,
    kind: CanvasBoardKind.project,
    title: id,
    workspaceName: workspace,
    parentBoardId: parentId,
    trashedAt: trashedAt,
    objects: objects,
    createdAt: now,
    updatedAt: now,
  );

  test('returns canonical ancestors from parent to root', () {
    final graph = CanvasBoardGraph(<CanvasBoard>[
      board('root'),
      board('parent', parentId: 'root'),
      board('child', parentId: 'parent'),
    ]);

    expect(graph.ancestorsOf('child').map((item) => item.id), <String>[
      'parent',
      'root',
    ]);
  });

  test('allows same workspace non-ancestor reference', () {
    final graph = CanvasBoardGraph(<CanvasBoard>[
      board('source'),
      board('target'),
    ]);

    expect(
      graph.canReference(sourceBoardId: 'source', targetBoardId: 'target'),
      isTrue,
    );
    expect(
      () => graph.validateReference(
        sourceBoardId: 'source',
        targetBoardId: 'target',
      ),
      returnsNormally,
    );
  });

  test('rejects self and ancestor references', () {
    final graph = CanvasBoardGraph(<CanvasBoard>[
      board('root'),
      board('child', parentId: 'root'),
    ]);

    expect(
      () => graph.validateReference(
        sourceBoardId: 'child',
        targetBoardId: 'child',
      ),
      throwsStateError,
    );
    expect(
      () => graph.validateReference(
        sourceBoardId: 'child',
        targetBoardId: 'root',
      ),
      throwsStateError,
    );
  });

  test('rejects cross workspace, missing, and trashed targets', () {
    final graph = CanvasBoardGraph(<CanvasBoard>[
      board('source'),
      board('other', workspace: 'Other'),
      board('trashed', trashedAt: now),
    ]);

    for (final target in <String>['other', 'missing', 'trashed']) {
      expect(
        () => graph.validateReference(
          sourceBoardId: 'source',
          targetBoardId: target,
        ),
        throwsStateError,
      );
    }
  });

  test('rejects malformed canonical parent cycle', () {
    expect(
      () => CanvasBoardGraph(<CanvasBoard>[
        board('a', parentId: 'b'),
        board('b', parentId: 'a'),
      ]),
      throwsFormatException,
    );
  });

  test('indexes duplicate references without rejecting graph', () {
    final graph = CanvasBoardGraph(<CanvasBoard>[
      board('target'),
      board(
        'source',
        objects: <CanvasObject>[
          reference('reference-a', 'target'),
          reference('reference-b', 'target'),
        ],
      ),
    ]);

    expect(graph.referencingObjectIds('target'), <String>[
      'reference-a',
      'reference-b',
    ]);
  });
}
