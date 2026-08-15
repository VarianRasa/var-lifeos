import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_drawing_layer.dart';

void main() {
  group('CanvasBrushType', () {
    test('contains expected enum values', () {
      expect(
        CanvasBrushType.values,
        containsAll([
          CanvasBrushType.pencil,
          CanvasBrushType.pen,
          CanvasBrushType.marker,
          CanvasBrushType.highlighter,
          CanvasBrushType.airbrush,
          CanvasBrushType.eraser,
        ]),
      );
    });
  });

  group('DrawingPoint', () {
    test('serialization round-trip', () {
      final now = DateTime.now().toUtc();
      final point = DrawingPoint(
        dx: 12.5,
        dy: 45.0,
        pressure: 0.8,
        tilt: 0.25,
        timestamp: now,
      );

      final json = point.toJson();
      final restored = DrawingPoint.fromJson(json);

      expect(restored.dx, point.dx);
      expect(restored.dy, point.dy);
      expect(restored.pressure, point.pressure);
      expect(restored.tilt, point.tilt);
      expect(
        restored.timestamp.millisecondsSinceEpoch,
        point.timestamp.millisecondsSinceEpoch,
      );
    });

    test('defaults and clamp pressure', () {
      final point = DrawingPoint(dx: 10, dy: 20, pressure: 1.5);

      expect(point.pressure, 1.0);
      expect(point.tilt, isNull);
    });
  });

  group('CanvasDrawingStroke', () {
    test('serialization round-trip', () {
      final stroke = CanvasDrawingStroke(
        id: 'stroke-1',
        layerId: 'layer-1',
        brushType: CanvasBrushType.marker,
        color: 0xFFFF0000,
        size: 4.5,
        opacity: 0.9,
        points: [
          DrawingPoint(dx: 1.0, dy: 2.0, pressure: 0.5),
          DrawingPoint(dx: 3.0, dy: 4.0, pressure: 0.7),
        ],
        smoothing: 0.3,
      );

      final json = stroke.toJson();
      final restored = CanvasDrawingStroke.fromJson(json);

      expect(restored.id, stroke.id);
      expect(restored.layerId, stroke.layerId);
      expect(restored.brushType, CanvasBrushType.marker);
      expect(restored.color, 0xFFFF0000);
      expect(restored.size, 4.5);
      expect(restored.opacity, 0.9);
      expect(restored.points.length, 2);
      expect(restored.smoothing, 0.3);
    });
  });

  group('CanvasDrawingLayer', () {
    test('serialization round-trip', () {
      final layer = CanvasDrawingLayer(
        id: 'layer-1',
        name: 'Background Sketch',
        isVisible: true,
        isLocked: false,
        opacity: 0.85,
        blendMode: 'srcOver',
        strokes: [
          CanvasDrawingStroke(
            id: 'stroke-1',
            layerId: 'layer-1',
            brushType: CanvasBrushType.pencil,
            color: 0xFF000000,
            size: 2.0,
            opacity: 1.0,
            points: [DrawingPoint(dx: 0, dy: 0)],
          ),
        ],
      );

      final json = layer.toJson();
      final restored = CanvasDrawingLayer.fromJson(json);

      expect(restored.id, layer.id);
      expect(restored.name, layer.name);
      expect(restored.isVisible, isTrue);
      expect(restored.isLocked, isFalse);
      expect(restored.opacity, 0.85);
      expect(restored.blendMode, 'srcOver');
      expect(restored.strokes.length, 1);
    });
  });

  group('DrawingLayerManager', () {
    test('initializes with default layer if empty', () {
      final manager = DrawingLayerManager.initial();
      expect(manager.layers.isNotEmpty, isTrue);
      expect(manager.activeLayerId, isNotNull);
      expect(manager.activeLayer?.id, manager.activeLayerId);
    });

    test('addLayer adds new layer and sets active', () {
      var manager = DrawingLayerManager.initial();
      const newLayer = CanvasDrawingLayer(id: 'layer-2', name: 'Inking');

      manager = manager.addLayer(newLayer, makeActive: true);
      expect(manager.layers.length, 2);
      expect(manager.activeLayerId, 'layer-2');
    });

    test('removeLayer removes layer and updates activeLayerId', () {
      const layer1 = CanvasDrawingLayer(id: 'l1', name: 'Layer 1');
      const layer2 = CanvasDrawingLayer(id: 'l2', name: 'Layer 2');
      var manager = DrawingLayerManager(
        activeLayerId: 'l2',
        layers: [layer1, layer2],
      );

      manager = manager.removeLayer('l2');
      expect(manager.layers.length, 1);
      expect(manager.activeLayerId, 'l1');
    });

    test('reorderLayers changes layer order', () {
      const layer1 = CanvasDrawingLayer(id: 'l1', name: 'Layer 1');
      const layer2 = CanvasDrawingLayer(id: 'l2', name: 'Layer 2');
      var manager = DrawingLayerManager(
        activeLayerId: 'l1',
        layers: [layer1, layer2],
      );

      manager = manager.reorderLayers(
        0,
        2,
      ); // Flutter ReorderableList convention or move
      expect(manager.layers.first.id, 'l2');
      expect(manager.layers.last.id, 'l1');
    });

    test('toggleVisibility and setOpacity update layer properties', () {
      const layer1 = CanvasDrawingLayer(
        id: 'l1',
        name: 'Layer 1',
        isVisible: true,
        opacity: 1.0,
      );
      var manager = DrawingLayerManager(activeLayerId: 'l1', layers: [layer1]);

      manager = manager.toggleVisibility('l1');
      expect(manager.getLayer('l1')?.isVisible, isFalse);

      manager = manager.setOpacity('l1', 0.5);
      expect(manager.getLayer('l1')?.opacity, 0.5);
    });

    test('addStroke adds to active layer and records undo history', () {
      const layer1 = CanvasDrawingLayer(id: 'l1', name: 'Layer 1');
      var manager = DrawingLayerManager(activeLayerId: 'l1', layers: [layer1]);

      final stroke = CanvasDrawingStroke(
        id: 's1',
        layerId: 'l1',
        brushType: CanvasBrushType.pen,
        color: 0xFFFFFFFF,
        size: 3.0,
        opacity: 1.0,
        points: [DrawingPoint(dx: 10, dy: 10)],
      );

      manager = manager.addStroke(stroke);
      expect(manager.activeLayer?.strokes.length, 1);
      expect(manager.canUndo, isTrue);

      manager = manager.undo();
      expect(manager.activeLayer?.strokes.length, 0);
      expect(manager.canRedo, isTrue);

      manager = manager.redo();
      expect(manager.activeLayer?.strokes.length, 1);
    });

    test('clearActiveLayer clears strokes on active layer and is undoable', () {
      final stroke = CanvasDrawingStroke(
        id: 's1',
        layerId: 'l1',
        brushType: CanvasBrushType.pen,
        color: 0xFFFFFFFF,
        size: 3.0,
        opacity: 1.0,
        points: [DrawingPoint(dx: 10, dy: 10)],
      );
      final layer1 = CanvasDrawingLayer(
        id: 'l1',
        name: 'Layer 1',
        strokes: [stroke],
      );
      var manager = DrawingLayerManager(activeLayerId: 'l1', layers: [layer1]);

      manager = manager.clearActiveLayer();
      expect(manager.activeLayer?.strokes.isEmpty, isTrue);

      manager = manager.undo();
      expect(manager.activeLayer?.strokes.length, 1);
    });

    test('serialization round-trip', () {
      final stroke = CanvasDrawingStroke(
        id: 's1',
        layerId: 'l1',
        brushType: CanvasBrushType.airbrush,
        color: 0xFF00FF00,
        size: 10.0,
        opacity: 0.5,
        points: [DrawingPoint(dx: 5, dy: 5)],
      );
      final layer = CanvasDrawingLayer(
        id: 'l1',
        name: 'Art',
        strokes: [stroke],
      );
      final manager = DrawingLayerManager(activeLayerId: 'l1', layers: [layer]);

      final json = manager.toJson();
      final restored = DrawingLayerManager.fromJson(json);

      expect(restored.activeLayerId, manager.activeLayerId);
      expect(restored.layers.length, 1);
      expect(restored.layers.first.strokes.length, 1);
    });
  });
}
