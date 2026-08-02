import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_navigation.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('indexes nodes and native canvas objects deterministically', () {
    final now = DateTime(2026, 7, 29);
    final node = MindmapNode.create(
      id: 'task',
      type: NodeType.task,
      title: 'Launch research',
      body: 'Interview customers',
      day: now,
      project: 'Canvas',
      tags: const <String>['discovery'],
      now: now,
    );
    final board =
        CanvasBoard.daily(
          day: now,
          nodes: <MindmapNode>[node],
          now: now,
        ).copyWith(
          objects: <CanvasObject>[
            ...CanvasBoard.daily(
              day: now,
              nodes: <MindmapNode>[node],
              now: now,
            ).objects,
            CanvasObject(
              id: 'sticky',
              type: CanvasObjectType.stickyNote,
              geometry: const CanvasGeometry(
                x: 600,
                y: 100,
                width: 240,
                height: 180,
              ),
              payload: const <String, Object?>{'text': 'Customer evidence'},
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );

    final index = CanvasNavigationIndex(
      nodes: <MindmapNode>[node],
      board: board,
    );

    expect(index.search('research').single.nodeId, 'task');
    expect(index.search('customer evidence').single.objectId, 'sticky');
    expect(
      index
          .search('customer', category: CanvasSearchCategory.notesAndText)
          .single
          .objectId,
      'sticky',
    );
    expect(
      index
          .search('customer', category: CanvasSearchCategory.nodes)
          .single
          .nodeId,
      'task',
    );
  });

  test('nearest selects candidate in requested spatial direction', () {
    final now = DateTime(2026, 7, 29);
    CanvasObject object(String id, double x, double y) => CanvasObject(
      id: id,
      type: CanvasObjectType.stickyNote,
      geometry: CanvasGeometry(x: x, y: y, width: 100, height: 100),
      payload: <String, Object?>{'text': id},
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'board',
      kind: CanvasBoardKind.project,
      title: 'Board',
      createdAt: now,
      updatedAt: now,
      objects: <CanvasObject>[
        object('left', -300, 0),
        object('right-near', 200, 10),
        object('right-far', 600, 0),
      ],
    );
    final index = CanvasNavigationIndex(
      nodes: const <MindmapNode>[],
      board: board,
    );

    expect(
      index.nearest(from: Offset.zero, direction: const Offset(1, 0))?.objectId,
      'right-near',
    );
    expect(
      index
          .nearest(from: Offset.zero, direction: const Offset(-1, 0))
          ?.objectId,
      'left',
    );
  });

  test('empty index returns no results safely', () {
    final index = CanvasNavigationIndex(
      nodes: const <MindmapNode>[],
      board: null,
    );

    expect(index.search('anything'), isEmpty);
    expect(
      index.nearest(from: Offset.zero, direction: const Offset(1, 0)),
      isNull,
    );
  });
}
