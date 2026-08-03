import 'package:flutter/foundation.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';

class ImageAnnotationController extends ChangeNotifier {
  ImageAnnotationData _data;
  final List<ImageAnnotationStroke> _undoStack = [];
  final List<ImageAnnotationStroke> _redoStack = [];
  bool _isDrawing = false;

  ImageAnnotationController({ImageAnnotationData? initialData})
    : _data = initialData ?? const ImageAnnotationData() {
    _undoStack.addAll(_data.strokes);
  }

  ImageAnnotationData get data => _data;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isDrawing => _isDrawing;

  void updateData(ImageAnnotationData newData) {
    _data = newData;
    _undoStack.clear();
    _undoStack.addAll(_data.strokes);
    _redoStack.clear();
    _isDrawing = false;
    notifyListeners();
  }

  void addPin({
    required double xRatio,
    required double yRatio,
    required String text,
    String? id,
  }) {
    final clampedX = xRatio.clamp(0.0, 1.0);
    final clampedY = yRatio.clamp(0.0, 1.0);

    final pin = ImageAnnotationPin(
      id: id ?? 'pin-${DateTime.now().millisecondsSinceEpoch}',
      xRatio: clampedX,
      yRatio: clampedY,
      text: text,
    );
    _data = ImageAnnotationData(
      pins: [..._data.pins, pin],
      strokes: _data.strokes,
    );
    notifyListeners();
  }

  void removePin(String pinId) {
    _data = ImageAnnotationData(
      pins: _data.pins.where((p) => p.id != pinId).toList(),
      strokes: _data.strokes,
    );
    notifyListeners();
  }

  void startStroke({
    required int colorValue,
    required double strokeWidth,
    required double xRatio,
    required double yRatio,
  }) {
    if (_isDrawing) {
      endStroke();
    }

    final clampedPoint = ImageAnnotationPoint(
      xRatio: xRatio.clamp(0.0, 1.0),
      yRatio: yRatio.clamp(0.0, 1.0),
    );

    final stroke = ImageAnnotationStroke(
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      points: [clampedPoint],
    );
    _data = ImageAnnotationData(
      pins: _data.pins,
      strokes: [..._data.strokes, stroke],
    );
    _isDrawing = true;
    _redoStack.clear();
    notifyListeners();
  }

  void addPointToCurrentStroke({
    required double xRatio,
    required double yRatio,
  }) {
    if (!_isDrawing || _data.strokes.isEmpty) return;

    final clampedPoint = ImageAnnotationPoint(
      xRatio: xRatio.clamp(0.0, 1.0),
      yRatio: yRatio.clamp(0.0, 1.0),
    );

    final lastStroke = _data.strokes.last;
    final updatedStroke = ImageAnnotationStroke(
      colorValue: lastStroke.colorValue,
      strokeWidth: lastStroke.strokeWidth,
      points: [...lastStroke.points, clampedPoint],
    );

    final newStrokes = List<ImageAnnotationStroke>.from(_data.strokes);
    newStrokes[newStrokes.length - 1] = updatedStroke;

    _data = ImageAnnotationData(pins: _data.pins, strokes: newStrokes);
    notifyListeners();
  }

  void endStroke() {
    if (!_isDrawing) return;
    _isDrawing = false;
    if (_data.strokes.isNotEmpty) {
      _undoStack.add(_data.strokes.last);
    }
    notifyListeners();
  }

  void undoStroke() {
    if (_undoStack.isEmpty) return;

    final removed = _undoStack.removeLast();
    _redoStack.add(removed);

    final newStrokes = List<ImageAnnotationStroke>.from(_data.strokes);
    if (newStrokes.isNotEmpty) {
      newStrokes.removeLast();
    }

    _data = ImageAnnotationData(pins: _data.pins, strokes: newStrokes);
    notifyListeners();
  }

  void redoStroke() {
    if (_redoStack.isEmpty) return;

    final restored = _redoStack.removeLast();
    _undoStack.add(restored);

    _data = ImageAnnotationData(
      pins: _data.pins,
      strokes: [..._data.strokes, restored],
    );
    notifyListeners();
  }

  void clear() {
    _data = const ImageAnnotationData();
    _undoStack.clear();
    _redoStack.clear();
    _isDrawing = false;
    notifyListeners();
  }
}
