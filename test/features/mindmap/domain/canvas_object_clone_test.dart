import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_object_clone.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);
  final now = DateTime.utc(2026, 8, 2, 12);

  CanvasObject object(
    String id,
    CanvasObjectType type, {
    String? parentFrameId,
    String? parentColumnId,
    String? referencedBoardId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => CanvasObject(
    id: id,
    type: type,
    geometry: const CanvasGeometry(x: 1, y: 2, width: 3, height: 4),
    parentFrameId: parentFrameId,
    parentColumnId: parentColumnId,
    referencedBoardId: referencedBoardId,
    payload: payload,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  test('remaps IDs and valid object relationships', () {
    var id = 0;
    final clones = cloneCanvasObjects(
      <CanvasObject>[
        object('frame', CanvasObjectType.frame),
        object('frame-child', CanvasObjectType.shape, parentFrameId: 'frame'),
        object(
          'column',
          CanvasObjectType.column,
          payload: const <String, Object?>{
            'title': 'Doing',
            'isCollapsed': false,
            'orderedChildIds': <String>['column-child', 'missing'],
          },
        ),
        object(
          'column-child',
          CanvasObjectType.stickyNote,
          parentColumnId: 'column',
        ),
        object(
          'connector',
          CanvasObjectType.connector,
          payload: const <String, Object?>{
            'sourceObjectId': 'frame-child',
            'targetObjectId': 'column-child',
          },
        ),
      ],
      idFactory: () => 'clone-${id++}',
      now: now,
    );

    expect(clones.map((item) => item.id), <String>[
      'clone-0',
      'clone-1',
      'clone-2',
      'clone-3',
      'clone-4',
    ]);
    expect(clones[1].parentFrameId, 'clone-0');
    expect(clones[3].parentColumnId, 'clone-2');
    expect(clones[2].orderedColumnChildIds, <String>['clone-3']);
    expect(clones[4].payload['sourceObjectId'], 'clone-1');
    expect(clones[4].payload['targetObjectId'], 'clone-3');
    expect(clones.every((item) => item.createdAt == now), isTrue);
    expect(clones.every((item) => item.updatedAt == now), isTrue);
  });

  test('drops parent relationships whose mapped parents have wrong types', () {
    var id = 0;
    final clones = cloneCanvasObjects(
      <CanvasObject>[
        object('not-frame', CanvasObjectType.shape),
        object(
          'frame-child',
          CanvasObjectType.shape,
          parentFrameId: 'not-frame',
        ),
        object('not-column', CanvasObjectType.frame),
        object(
          'column-child',
          CanvasObjectType.shape,
          parentColumnId: 'not-column',
        ),
      ],
      idFactory: () => 'clone-${id++}',
      now: now,
    );

    expect(clones[1].parentFrameId, isNull);
    expect(clones[3].parentColumnId, isNull);
  });

  test('rejects duplicate source IDs', () {
    expect(
      () => cloneCanvasObjects(
        <CanvasObject>[
          object('duplicate', CanvasObjectType.shape),
          object('duplicate', CanvasObjectType.text),
        ],
        idFactory: () => 'clone',
        now: now,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Duplicate canvas object source ID.',
        ),
      ),
    );
  });

  test('rejects duplicate generated IDs', () {
    expect(
      () => cloneCanvasObjects(
        <CanvasObject>[
          object('first', CanvasObjectType.shape),
          object('second', CanvasObjectType.text),
        ],
        idFactory: () => 'duplicate',
        now: now,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Duplicate canvas object generated ID.',
        ),
      ),
    );
  });

  test('excludes board references and removes invalid relationships', () {
    var id = 0;
    final clones = cloneCanvasObjects(
      <CanvasObject>[
        object(
          'orphan-frame-child',
          CanvasObjectType.shape,
          parentFrameId: 'gone',
        ),
        object(
          'orphan-column-child',
          CanvasObjectType.shape,
          parentColumnId: 'gone',
        ),
        object(
          'orphan-connector',
          CanvasObjectType.connector,
          payload: const <String, Object?>{
            'sourceObjectId': 'orphan-frame-child',
            'targetObjectId': 'gone',
          },
        ),
        object(
          'reference',
          CanvasObjectType.boardReference,
          referencedBoardId: 'board',
        ),
      ],
      idFactory: () => 'clone-${id++}',
      now: now,
      excludeBoardReferences: true,
    );

    expect(clones.map((item) => item.type), <CanvasObjectType>[
      CanvasObjectType.shape,
      CanvasObjectType.shape,
    ]);
    expect(clones[0].parentFrameId, isNull);
    expect(clones[1].parentColumnId, isNull);
  });
}
