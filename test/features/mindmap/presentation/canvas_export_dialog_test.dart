import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/canvas_export_pdf.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/canvas_export_dialog.dart';

void main() {
  test('generateCanvasPdf builds Uint8List document bytes', () async {
    final now = DateTime(2026, 1, 1);
    final List<MindmapNode> nodes = [
      MindmapNode(
        id: 'node1',
        type: NodeType.note,
        title: 'Project Roadmap',
        body: 'Initial visual plan',
        day: now,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final pdfBytes = await generateCanvasPdf(
      nodes: nodes,
      title: 'Mindmap Export',
    );

    expect(pdfBytes, isNotEmpty);
  });

  testWidgets('CanvasExportDialog renders PDF and PNG options', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CanvasExportDialog(title: 'Sprint Board')),
      ),
    );

    expect(find.text('Export Canvas: Sprint Board'), findsOneWidget);
    expect(find.text('PDF Document (.pdf)'), findsOneWidget);
    expect(find.text('PNG High-Res Image (.png)'), findsOneWidget);
  });
}
