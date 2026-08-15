import 'package:flutter/material.dart';
import '../../domain/canvas_drawing_layer.dart';
import 'brush_palette_bar.dart';
import 'drawing_layer_panel.dart';

/// Fullscreen drawing studio overlay for stylus/mouse drawing with multi-layer support.
class DrawingStudioOverlay extends StatefulWidget {
  const DrawingStudioOverlay({
    super.key,
    required this.initialManager,
    required this.onSave,
    required this.onClose,
  });

  final DrawingLayerManager initialManager;
  final ValueChanged<DrawingLayerManager> onSave;
  final VoidCallback onClose;

  @override
  State<DrawingStudioOverlay> createState() => _DrawingStudioOverlayState();
}

class _DrawingStudioOverlayState extends State<DrawingStudioOverlay> {
  late DrawingLayerManager _manager;
  CanvasBrushType _selectedBrush = CanvasBrushType.pen;
  double _brushSize = 3.0;
  double _brushOpacity = 1.0;
  Color _selectedColor = Colors.black;

  List<DrawingPoint> _currentStrokePoints = <DrawingPoint>[];
  bool _showLayerPanel = false;

  @override
  void initState() {
    super.initState();
    _manager = widget.initialManager;
  }

  void _onPanStart(DragStartDetails details) {
    final active = _manager.activeLayer;
    if (active == null || active.isLocked || !active.isVisible) return;

    setState(() {
      _currentStrokePoints = [
        DrawingPoint(
          dx: details.localPosition.dx,
          dy: details.localPosition.dy,
          pressure: 1.0,
        ),
      ];
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final active = _manager.activeLayer;
    if (active == null || active.isLocked || !active.isVisible) return;

    setState(() {
      _currentStrokePoints = [
        ..._currentStrokePoints,
        DrawingPoint(
          dx: details.localPosition.dx,
          dy: details.localPosition.dy,
          pressure: 1.0,
        ),
      ];
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStrokePoints.isEmpty) return;
    final active = _manager.activeLayer;
    if (active == null || active.isLocked || !active.isVisible) {
      setState(() => _currentStrokePoints = <DrawingPoint>[]);
      return;
    }

    final newStroke = CanvasDrawingStroke(
      id: 'stroke-${DateTime.now().microsecondsSinceEpoch}',
      layerId: active.id,
      brushType: _selectedBrush,
      color: _selectedColor.toARGB32(),
      size: _brushSize,
      opacity: _brushOpacity,
      points: _currentStrokePoints,
    );

    setState(() {
      _manager = _manager.addStroke(newStroke);
      _currentStrokePoints = <DrawingPoint>[];
    });
    widget.onSave(_manager);
  }

  void _addLayer() {
    final newId = 'layer-${DateTime.now().millisecondsSinceEpoch}';
    final newLayer = CanvasDrawingLayer(
      id: newId,
      name: 'Layer ${_manager.layers.length + 1}',
    );
    setState(() {
      _manager = _manager.addLayer(newLayer, makeActive: true);
    });
    widget.onSave(_manager);
  }

  void _removeLayer(String layerId) {
    setState(() {
      _manager = _manager.removeLayer(layerId);
    });
    widget.onSave(_manager);
  }

  void _selectLayer(String layerId) {
    setState(() {
      _manager = DrawingLayerManager(
        activeLayerId: layerId,
        layers: _manager.layers,
      );
    });
  }

  void _toggleVisibility(String layerId) {
    setState(() {
      _manager = _manager.toggleVisibility(layerId);
    });
    widget.onSave(_manager);
  }

  void _toggleLock(String layerId) {
    setState(() {
      _manager = _manager.toggleLock(layerId);
    });
    widget.onSave(_manager);
  }

  void _setLayerOpacity(String layerId, double opacity) {
    setState(() {
      _manager = _manager.setOpacity(layerId, opacity);
    });
    widget.onSave(_manager);
  }

  void _setLayerBlendMode(String layerId, String blendMode) {
    setState(() {
      _manager = _manager.setBlendMode(layerId, blendMode);
    });
    widget.onSave(_manager);
  }

  void _undo() {
    if (!_manager.canUndo) return;
    setState(() {
      _manager = _manager.undo();
    });
    widget.onSave(_manager);
  }

  void _redo() {
    if (!_manager.canRedo) return;
    setState(() {
      _manager = _manager.redo();
    });
    widget.onSave(_manager);
  }

  void _clearActiveLayer() {
    setState(() {
      _manager = _manager.clearActiveLayer();
    });
    widget.onSave(_manager);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final activeLayer = _manager.activeLayer;
    final currentStroke = _currentStrokePoints.isNotEmpty && activeLayer != null
        ? CanvasDrawingStroke(
            id: 'current-preview',
            layerId: activeLayer.id,
            brushType: _selectedBrush,
            color: _selectedColor.toARGB32(),
            size: _brushSize,
            opacity: _brushOpacity,
            points: _currentStrokePoints,
          )
        : null;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Gesture detector canvas
          GestureDetector(
            key: const Key('drawing-canvas-gesture-area'),
            behavior: HitTestBehavior.opaque,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: CustomPaint(
              painter: _StudioDrawingPainter(
                manager: _manager,
                activeStroke: currentStroke,
              ),
              size: Size.infinite,
            ),
          ),

          // Top Header Action Bar
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Undo / Redo / Clear actions
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withValues(
                      alpha: 0.9,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('undo-button'),
                        icon: const Icon(Icons.undo, size: 20),
                        tooltip: 'Undo',
                        onPressed: _manager.canUndo ? _undo : null,
                      ),
                      IconButton(
                        key: const Key('redo-button'),
                        icon: const Icon(Icons.redo, size: 20),
                        tooltip: 'Redo',
                        onPressed: _manager.canRedo ? _redo : null,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const Key('clear-layer-button'),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                        tooltip: 'Clear Active Layer',
                        onPressed:
                            (activeLayer?.strokes.isNotEmpty ?? false) &&
                                !(activeLayer?.isLocked ?? false)
                            ? _clearActiveLayer
                            : null,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const Key('toggle-layer-panel-button'),
                        icon: Icon(
                          _showLayerPanel
                              ? Icons.layers
                              : Icons.layers_outlined,
                          size: 20,
                        ),
                        tooltip: 'Layers',
                        color: _showLayerPanel ? colorScheme.primary : null,
                        onPressed: () =>
                            setState(() => _showLayerPanel = !_showLayerPanel),
                      ),
                    ],
                  ),
                ),

                // Exit studio button
                IconButton.filledTonal(
                  key: const Key('exit-studio-button'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Exit Studio',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // Layer Panel (Floating on right side)
          if (_showLayerPanel)
            Positioned(
              top: 72,
              right: 16,
              child: DrawingLayerPanel(
                manager: _manager,
                onAddLayer: _addLayer,
                onRemoveLayer: _removeLayer,
                onSelectLayer: _selectLayer,
                onToggleVisibility: _toggleVisibility,
                onToggleLock: _toggleLock,
                onOpacityChanged: _setLayerOpacity,
                onBlendModeChanged: _setLayerBlendMode,
              ),
            ),

          // Bottom Brush Palette Bar
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Center(
              child: BrushPaletteBar(
                selectedBrush: _selectedBrush,
                brushSize: _brushSize,
                brushOpacity: _brushOpacity,
                selectedColor: _selectedColor,
                onBrushChanged: (b) => setState(() => _selectedBrush = b),
                onSizeChanged: (s) => setState(() => _brushSize = s),
                onOpacityChanged: (o) => setState(() => _brushOpacity = o),
                onColorChanged: (c) => setState(() => _selectedColor = c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

BlendMode _resolveBlendMode(String mode) {
  switch (mode) {
    case 'multiply':
      return BlendMode.multiply;
    case 'screen':
      return BlendMode.screen;
    case 'overlay':
      return BlendMode.overlay;
    case 'darken':
      return BlendMode.darken;
    case 'lighten':
      return BlendMode.lighten;
    case 'colorDodge':
      return BlendMode.colorDodge;
    case 'colorBurn':
      return BlendMode.colorBurn;
    case 'srcOver':
    default:
      return BlendMode.srcOver;
  }
}

class _StudioDrawingPainter extends CustomPainter {
  _StudioDrawingPainter({required this.manager, this.activeStroke});

  final DrawingLayerManager manager;
  final CanvasDrawingStroke? activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    for (final layer in manager.layers) {
      if (!layer.isVisible) continue;

      final layerPaint = Paint()
        ..color = Colors.white.withValues(alpha: layer.opacity.clamp(0.0, 1.0))
        ..blendMode = _resolveBlendMode(layer.blendMode);

      canvas.saveLayer(Offset.zero & size, layerPaint);

      for (final stroke in layer.strokes) {
        _drawStroke(canvas, stroke);
      }

      if (activeStroke != null && activeStroke!.layerId == layer.id) {
        _drawStroke(canvas, activeStroke!);
      }

      canvas.restore();
    }
  }

  void _drawStroke(Canvas canvas, CanvasDrawingStroke stroke) {
    if (stroke.points.isEmpty) return;

    if (stroke.brushType == CanvasBrushType.eraser) {
      final eraserPaint = Paint()
        ..blendMode = BlendMode.clear
        ..strokeWidth = stroke.size
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          Offset(stroke.points[0].dx, stroke.points[0].dy),
          stroke.size / 2,
          eraserPaint..style = PaintingStyle.fill,
        );
      } else {
        final path = Path()..moveTo(stroke.points[0].dx, stroke.points[0].dy);
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, eraserPaint);
      }
      return;
    }

    final baseColor = Color(stroke.color);
    final paint = Paint()
      ..color = baseColor.withValues(alpha: stroke.opacity.clamp(0.0, 1.0))
      ..strokeWidth = stroke.size
      ..strokeCap = stroke.brushType == CanvasBrushType.highlighter
          ? StrokeCap.square
          : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    switch (stroke.brushType) {
      case CanvasBrushType.pencil:
        paint.strokeWidth = (stroke.size * 0.75).clamp(1.0, 50.0);
        paint.color = baseColor.withValues(
          alpha: (stroke.opacity * 0.8).clamp(0.0, 1.0),
        );
        break;
      case CanvasBrushType.marker:
        paint.strokeWidth = stroke.size * 1.5;
        break;
      case CanvasBrushType.highlighter:
        paint.strokeWidth = stroke.size * 2.5;
        paint.color = baseColor.withValues(
          alpha: (stroke.opacity * 0.35).clamp(0.0, 1.0),
        );
        paint.blendMode = BlendMode.srcOver;
        break;
      case CanvasBrushType.airbrush:
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, stroke.size * 0.5);
        break;
      case CanvasBrushType.ink:
        paint.strokeWidth = stroke.size * 1.2;
        paint.strokeCap = StrokeCap.round;
        break;
      case CanvasBrushType.charcoal:
        paint.strokeWidth = stroke.size * 1.8;
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, stroke.size * 0.2);
        paint.color = baseColor.withValues(
          alpha: (stroke.opacity * 0.65).clamp(0.0, 1.0),
        );
        break;
      default:
        break;
    }

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        Offset(stroke.points[0].dx, stroke.points[0].dy),
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
    } else if (stroke.points.length == 2) {
      canvas.drawLine(
        Offset(stroke.points[0].dx, stroke.points[0].dy),
        Offset(stroke.points[1].dx, stroke.points[1].dy),
        paint,
      );
    } else {
      // Catmull-Rom / Bezier spline curve smoothing for high-fidelity stroke rendering
      final path = Path()..moveTo(stroke.points[0].dx, stroke.points[0].dy);
      for (var i = 1; i < stroke.points.length - 1; i++) {
        final p0 = stroke.points[i];
        final p1 = stroke.points[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        final midY = (p0.dy + p1.dy) / 2;
        path.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
      }
      final last = stroke.points.last;
      path.lineTo(last.dx, last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StudioDrawingPainter oldDelegate) {
    return true;
  }
}
