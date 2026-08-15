import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_block_document.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/canvas_node_editor.dart';

void main() {
  testWidgets('canvas editor supports drawing history text and clear', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Object draft = const CanvasPayload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: CanvasNodeEditor(
                payload: draft as CanvasPayload,
                onChanged: (value) {
                  draft = value;
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      ),
    );

    for (final tool in canvasTools) {
      expect(
        find.byKey(ValueKey<String>('knowledge-canvas-tool-$tool')),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-tool-pen')),
    );
    await tester.pump();
    final workspace = find.byKey(
      const ValueKey<String>('knowledge-canvas-workspace'),
    );
    final rect = tester.getRect(workspace);
    await tester.dragFrom(
      Offset(rect.left + 40, rect.top + 40),
      const Offset(180, 100),
    );
    await tester.pump();
    expect((draft as CanvasPayload).elements.single, isA<CanvasStroke>());

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-undo')),
    );
    await tester.pump();
    expect((draft as CanvasPayload).elements, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-redo')),
    );
    await tester.pump();
    expect((draft as CanvasPayload).elements, hasLength(1));

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-tool-rectangle')),
    );
    await tester.pump();
    await tester.dragFrom(
      Offset(rect.left + 100, rect.top + 180),
      const Offset(150, 90),
    );
    await tester.pump();
    expect((draft as CanvasPayload).elements.last, isA<CanvasShapeElement>());

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-tool-text')),
    );
    await tester.pump();
    await tester.tapAt(Offset(rect.left + 300, rect.top + 120));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('knowledge-canvas-text-dialog-field')),
      'Canvas label',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-text-dialog-save')),
    );
    await tester.pumpAndSettle();
    expect((draft as CanvasPayload).elements.last, isA<CanvasTextElement>());

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-clear')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-clear-confirm')),
    );
    await tester.pumpAndSettle();
    expect((draft as CanvasPayload).elements, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canvas block editor adds edits converts checks and deletes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Object draft = const CanvasPayload(viewMode: 'blocks');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CanvasNodeEditor(
              payload: draft as CanvasPayload,
              onChanged: (value) {
                draft = value;
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-block-add')),
    );
    await tester.pump();
    expect((draft as CanvasPayload).blocks.blocks, hasLength(1));
    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-block-text-block-1')),
      'First block',
    );
    await tester.pump();
    expect((draft as CanvasPayload).blocks.blocks.single.text, 'First block');
    await tester.tap(find.text('Paragraph').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist').last);
    await tester.pumpAndSettle();
    expect(
      (draft as CanvasPayload).blocks.blocks.single.type,
      CanvasBlockType.checklist,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect((draft as CanvasPayload).blocks.blocks.single.checked, isTrue);
    await tester.tap(find.byTooltip('Delete block'));
    await tester.pump();
    expect((draft as CanvasPayload).blocks.blocks, isEmpty);
  });

  testWidgets('canvas blocks support slash commands search and narrow width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Object draft = const CanvasPayload(viewMode: 'blocks');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CanvasNodeEditor(
              payload: draft as CanvasPayload,
              onChanged: (value) {
                draft = value;
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-block-add')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-block-text-block-1')),
      '/heading',
    );
    await tester.pump();
    expect(
      (draft as CanvasPayload).blocks.blocks.single.type,
      CanvasBlockType.heading,
    );
    expect((draft as CanvasPayload).blocks.blocks.single.text, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-block-text-block-1')),
      'Roadmap',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('knowledge-canvas-block-search')),
      'road',
    );
    await tester.pump();
    expect(find.text('Roadmap'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canvas block editor supports rich blocks image table url', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Object draft = const CanvasPayload(viewMode: 'blocks');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CanvasNodeEditor(
              payload: draft as CanvasPayload,
              onChanged: (value) {
                draft = value;
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-canvas-block-add')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-block-text-block-1')),
      '/table',
    );
    await tester.pumpAndSettle();
    expect(
      (draft as CanvasPayload).blocks.blocks.single.type,
      CanvasBlockType.table,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-block-cell-block-1-0-0')),
      'Header1',
    );
    await tester.pump();
    expect(
      (draft as CanvasPayload).blocks.blocks.single.tableRows.first.first,
      'Header1',
    );

    await tester.tap(find.text('Table').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('UrlPreview').last);
    await tester.pumpAndSettle();
    expect(
      (draft as CanvasPayload).blocks.blocks.single.type,
      CanvasBlockType.urlPreview,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-block-url-block-1')),
      'https://var.app',
    );
    await tester.pump();
    expect(
      (draft as CanvasPayload).blocks.blocks.single.url,
      'https://var.app',
    );
  });

  testWidgets('canvas width slider keeps one continuous drag', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Object draft = const CanvasPayload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: CanvasNodeEditor(
                payload: draft as CanvasPayload,
                onChanged: (value) {
                  draft = value;
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      ),
    );

    final finder = find.byKey(
      const ValueKey<String>('knowledge-canvas-width-slider'),
    );
    final rect = tester.getRect(finder);
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * 0.1, rect.center.dy),
    );
    await gesture.moveTo(Offset(rect.left + rect.width * 0.4, rect.center.dy));
    await tester.pump();
    final first = (draft as CanvasPayload).penWidth;
    await gesture.moveTo(Offset(rect.left + rect.width * 0.8, rect.center.dy));
    await tester.pump();
    final second = (draft as CanvasPayload).penWidth;
    await gesture.up();

    expect(first, greaterThan(1));
    expect(second, greaterThan(first));
    expect(tester.takeException(), isNull);
  });
}
