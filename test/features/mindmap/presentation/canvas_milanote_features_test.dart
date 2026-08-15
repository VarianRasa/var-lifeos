import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';
import 'package:var_app/features/mindmap/presentation/widgets/milanote_element_palette.dart';
import 'package:var_app/features/mindmap/presentation/widgets/milanote_visual_card.dart';

void main() {
  testWidgets('MilanoteVisualCard supports inline editing and color palette', (
    tester,
  ) async {
    final day = DateTime(2026, 8, 15);
    final node = MindmapNode.create(
      id: 'milanote-test',
      type: NodeType.note,
      title: 'Milanote Inspiration',
      body: 'Color moodboard description',
      day: day,
      data: const {
        'isMilanote': true,
        'color': 0xFFFFE082,
        'caption': 'Color moodboard description',
      },
    );

    String? updatedTitle;
    String? updatedBody;
    Color? updatedColor;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MilanoteVisualCard(
            node: node,
            onUpdate: (title, body) {
              updatedTitle = title;
              updatedBody = body;
            },
            onColorChange: (c) => updatedColor = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Milanote Inspiration'), findsOneWidget);
    expect(find.text('Color moodboard description'), findsOneWidget);

    // Tap title to inline edit
    await tester.tap(find.text('Milanote Inspiration'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New Card Title');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(updatedTitle, 'New Card Title');
    expect(updatedBody, isNotNull);
    expect(updatedColor, isNull);
  });

  testWidgets(
    'MindmapCanvas toggles Milanote element palette and triggers quick add',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final day = DateTime(2026, 8, 15);
      NodeType? addedType;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              nodes: [
                MindmapNode.create(
                  id: 'visual-card-node',
                  type: NodeType.note,
                  title: 'Visual Sticky',
                  day: day,
                  position: const CanvasPosition(0, 0),
                  data: const {'isMilanote': true},
                ),
              ],
              onNodeQuickCreate: (type, title, {priority, tags}) =>
                  addedType = type,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify visual card is rendered in canvas
      expect(find.byType(MilanoteVisualCard), findsOneWidget);
      expect(find.text('Visual Sticky'), findsOneWidget);

      // Open controls and toggle palette
      await tester.tap(find.byTooltip('Show canvas controls'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mindmap-milanote-palette')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('mindmap-milanote-palette-toggle')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mindmap-milanote-palette')),
        findsOneWidget,
      );
      expect(find.byType(MilanoteElementPalette), findsOneWidget);

      // Tap on 'Board' (kanban)
      await tester.tap(find.text('Board'));
      await tester.pumpAndSettle();

      expect(addedType, NodeType.kanban);
      expect(
        find.byKey(const ValueKey('mindmap-milanote-palette')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'MilanoteElementPalette supports drag gesture and displays feedback preview',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MilanoteElementPalette(onSelectType: (_) {})),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Draggable<NodeType>), findsNWidgets(7));
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Sketch'), findsOneWidget);
      expect(find.text('Gendo AI'), findsOneWidget);

      final cardFinder = find.text('Card');
      final gesture = await tester.startGesture(tester.getCenter(cardFinder));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(50, 50));
      await tester.pump();

      // Feedback avatar is rendered while dragging
      expect(find.byType(Material), findsWidgets);

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
