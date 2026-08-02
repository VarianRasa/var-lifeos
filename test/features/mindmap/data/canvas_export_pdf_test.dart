import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/canvas_export_pdf.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('generateCanvasPdf builds valid PDF bytes with group pages', () async {
    final day = DateTime(2026, 7, 28);
    final nodes = [
      MindmapNode.create(
        id: 'node-1',
        type: NodeType.task,
        title: 'Grouped Task 1',
        day: day,
        data: const {'groupId': 'group-1', 'groupTitle': 'Phase 1'},
        now: day,
      ),
      MindmapNode.create(
        id: 'node-2',
        type: NodeType.note,
        title: 'Grouped Note 2',
        day: day,
        data: const {'groupId': 'group-1', 'groupTitle': 'Phase 1'},
        now: day,
      ),
      MindmapNode.create(
        id: 'node-3',
        type: NodeType.idea,
        title: 'Standalone Idea',
        day: day,
        now: day,
      ),
    ];

    final pdfBytes = await generateCanvasPdf(
      nodes: nodes,
      title: 'Test Presentation Canvas',
    );

    expect(pdfBytes, isNotEmpty);
    expect(pdfBytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]); // %PDF header
  });

  test('generateCanvasPdf includes native column titles', () async {
    final now = DateTime(2026, 8, 2);
    final bytes = await generateCanvasPdf(
      nodes: const <MindmapNode>[],
      title: 'Native board',
      board: CanvasBoard(
        id: 'board',
        kind: CanvasBoardKind.project,
        title: 'Board',
        objects: <CanvasObject>[
          CanvasObject(
            id: 'column',
            type: CanvasObjectType.column,
            geometry: const CanvasGeometry(x: 0, y: 0, width: 300, height: 400),
            payload: const <String, Object?>{
              'title': 'Review queue',
              'isCollapsed': false,
              'orderedChildIds': <String>[],
            },
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(String.fromCharCodes(bytes), contains('/Count 2'));
  });
}
