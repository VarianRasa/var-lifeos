import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_drawing_layer.dart';
import 'package:var_app/features/mindmap/presentation/widgets/brush_palette_bar.dart';
import 'package:var_app/features/mindmap/presentation/widgets/drawing_layer_panel.dart';
import 'package:var_app/features/mindmap/presentation/widgets/drawing_studio_overlay.dart';

void main() {
  group('BrushPaletteBar', () {
    testWidgets('renders brush options and responds to callbacks', (
      tester,
    ) async {
      CanvasBrushType currentBrush = CanvasBrushType.pen;
      double currentSize = 3.0;
      double currentOpacity = 1.0;
      Color currentColor = Colors.black;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushPaletteBar(
              selectedBrush: currentBrush,
              brushSize: currentSize,
              brushOpacity: currentOpacity,
              selectedColor: currentColor,
              onBrushChanged: (b) => currentBrush = b,
              onSizeChanged: (s) => currentSize = s,
              onOpacityChanged: (o) => currentOpacity = o,
              onColorChanged: (c) => currentColor = c,
            ),
          ),
        ),
      );

      // Verify brush choices rendered
      expect(find.text('Pen'), findsOneWidget);
      expect(find.text('Pencil'), findsOneWidget);
      expect(find.text('Marker'), findsOneWidget);
      expect(find.text('Highlighter'), findsOneWidget);
      expect(find.text('Airbrush'), findsOneWidget);
      expect(find.text('Eraser'), findsOneWidget);

      // Tap pencil
      await tester.tap(find.text('Pencil'));
      await tester.pumpAndSettle();
      expect(currentBrush, CanvasBrushType.pencil);

      // Tap highlighter
      await tester.tap(find.text('Highlighter'));
      await tester.pumpAndSettle();
      expect(currentBrush, CanvasBrushType.highlighter);
    });
  });

  group('DrawingLayerPanel', () {
    testWidgets('renders layers, allows adding and toggling visibility', (
      tester,
    ) async {
      final manager = DrawingLayerManager.initial();
      bool addCalled = false;
      String? toggledVisibilityId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingLayerPanel(
              manager: manager,
              onAddLayer: () => addCalled = true,
              onRemoveLayer: (id) {},
              onSelectLayer: (id) {},
              onToggleVisibility: (id) => toggledVisibilityId = id,
              onToggleLock: (id) {},
              onOpacityChanged: (id, opacity) {},
            ),
          ),
        ),
      );

      expect(find.text('Layers'), findsOneWidget);
      expect(find.text('Layer 1'), findsOneWidget);

      // Add layer
      await tester.tap(find.byKey(const Key('add-layer-button')));
      expect(addCalled, isTrue);

      // Toggle visibility
      await tester.tap(
        find.byKey(Key('toggle-visibility-${manager.layers.first.id}')),
      );
      expect(toggledVisibilityId, manager.layers.first.id);
    });
  });

  group('DrawingStudioOverlay', () {
    testWidgets('captures pan strokes, updates drawing, and handles actions', (
      tester,
    ) async {
      final initialManager = DrawingLayerManager.initial();
      DrawingLayerManager? savedManager;
      bool closeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawingStudioOverlay(
              initialManager: initialManager,
              onSave: (m) => savedManager = m,
              onClose: () => closeCalled = true,
            ),
          ),
        ),
      );

      // Canvas gesture area is present
      final canvasFinder = find.byKey(const Key('drawing-canvas-gesture-area'));
      expect(canvasFinder, findsOneWidget);

      // Perform a drag gesture to create a stroke
      await tester.drag(canvasFinder, const Offset(100, 100));
      await tester.pumpAndSettle();

      expect(savedManager, isNotNull);
      expect(savedManager!.activeLayer?.strokes.length, 1);

      // Open layer panel
      await tester.tap(find.byKey(const Key('toggle-layer-panel-button')));
      await tester.pumpAndSettle();
      expect(find.byType(DrawingLayerPanel), findsOneWidget);

      // Add a new layer from layer panel
      await tester.tap(find.byKey(const Key('add-layer-button')));
      await tester.pumpAndSettle();
      expect(savedManager!.layers.length, 2);

      // Toggle visibility of the active layer
      final secondLayerId = savedManager!.layers.last.id;
      await tester.tap(find.byKey(Key('toggle-visibility-$secondLayerId')));
      await tester.pumpAndSettle();
      expect(savedManager!.getLayer(secondLayerId)?.isVisible, isFalse);

      // Close studio
      await tester.tap(find.byKey(const Key('exit-studio-button')));
      expect(closeCalled, isTrue);
    });
  });
}
