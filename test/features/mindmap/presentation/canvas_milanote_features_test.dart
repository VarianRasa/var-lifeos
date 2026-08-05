import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_trash_bin.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/widgets/canvas_connector_line_widget.dart';
import 'package:var_app/features/mindmap/presentation/widgets/multi_select_action_bar.dart';

void main() {
  test('CanvasTrashBin stores deleted node and restores it', () {
    final bin = CanvasTrashBin();
    final now = DateTime(2026, 1, 1);
    final node = MindmapNode(
      id: 'deleted-1',
      type: NodeType.note,
      title: 'Deleted Note',
      day: now,
      createdAt: now,
      updatedAt: now,
    );

    bin.moveNodeToTrash(node);
    expect(bin.items.length, equals(1));

    final restored = bin.restoreNode('deleted-1');
    expect(restored?.id, equals('deleted-1'));
    expect(bin.items.isEmpty, isTrue);
  });

  testWidgets('MultiSelectActionBar renders selected count badge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MultiSelectActionBar(selectedCount: 4),
        ),
      ),
    );

    expect(find.text('4 selected'), findsOneWidget);
  });

  testWidgets('CanvasConnectorLineWidget renders label text', (
    WidgetTester tester,
  ) async {
    const line = ConnectorLineData(
      start: Offset(10, 10),
      end: Offset(100, 100),
      label: 'depends on',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CanvasConnectorLineWidget(line: line),
        ),
      ),
    );

    expect(find.text('depends on'), findsOneWidget);
  });
}
