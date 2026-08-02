import 'package:var_app/features/mindmap/domain/canvas_board.dart';

const int canvasBenchmarkObjectCount = 10000;

CanvasBoard createCanvasBenchmarkBoard({
  int objectCount = canvasBenchmarkObjectCount,
}) {
  final timestamp = DateTime.utc(2026, 1, 1);
  return CanvasBoard(
    id: 'canvas-benchmark-$objectCount',
    kind: CanvasBoardKind.project,
    title: 'Canvas benchmark',
    objects: <CanvasObject>[
      for (var index = 0; index < objectCount; index++)
        CanvasObject(
          id: 'benchmark-$index',
          type: CanvasObjectType.stickyNote,
          geometry: CanvasGeometry(
            x: (index % 100) * 240.0,
            y: (index ~/ 100) * 180.0,
            width: 180,
            height: 120,
          ),
          payload: <String, Object?>{'text': 'Benchmark $index'},
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
    ],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
