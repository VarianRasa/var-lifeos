/// Multi-layer drawing structures and management for Creative Studio Canvas.
library;

/// Supported brush styles for freehand drawing.
enum CanvasBrushType {
  pencil,
  pen,
  marker,
  highlighter,
  airbrush,
  ink,
  charcoal,
  eraser;

  static CanvasBrushType fromName(String? name) {
    return CanvasBrushType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => CanvasBrushType.pen,
    );
  }
}

/// A single recorded coordinate in a stroke.
final class DrawingPoint {
  DrawingPoint({
    required this.dx,
    required this.dy,
    double pressure = 1.0,
    this.tilt,
    DateTime? timestamp,
  }) : pressure = pressure.clamp(0.0, 1.0),
       timestamp = timestamp ?? DateTime.now().toUtc();

  final double dx;
  final double dy;
  final double pressure;
  final double? tilt;
  final DateTime timestamp;

  Map<String, Object?> toJson() => <String, Object?>{
    'dx': dx,
    'dy': dy,
    'pressure': pressure,
    if (tilt != null) 'tilt': tilt,
    'timestamp': timestamp.toIso8601String(),
  };

  factory DrawingPoint.fromJson(Map<String, Object?> json) {
    return DrawingPoint(
      dx: (json['dx'] as num? ?? 0.0).toDouble(),
      dy: (json['dy'] as num? ?? 0.0).toDouble(),
      pressure: (json['pressure'] as num? ?? 1.0).toDouble(),
      tilt: (json['tilt'] as num?)?.toDouble(),
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String)?.toUtc()
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DrawingPoint &&
        other.dx == dx &&
        other.dy == dy &&
        other.pressure == pressure &&
        other.tilt == tilt &&
        other.timestamp.millisecondsSinceEpoch ==
            timestamp.millisecondsSinceEpoch;
  }

  @override
  int get hashCode =>
      Object.hash(dx, dy, pressure, tilt, timestamp.millisecondsSinceEpoch);
}

/// A continuous vector stroke consisting of points.
final class CanvasDrawingStroke {
  const CanvasDrawingStroke({
    required this.id,
    required this.layerId,
    this.brushType = CanvasBrushType.pen,
    this.color = 0xFF000000,
    this.size = 2.0,
    this.opacity = 1.0,
    this.points = const <DrawingPoint>[],
    this.smoothing = 0.0,
  });

  final String id;
  final String layerId;
  final CanvasBrushType brushType;
  final int color;
  final double size;
  final double opacity;
  final List<DrawingPoint> points;
  final double smoothing;

  CanvasDrawingStroke copyWith({
    String? id,
    String? layerId,
    CanvasBrushType? brushType,
    int? color,
    double? size,
    double? opacity,
    List<DrawingPoint>? points,
    double? smoothing,
  }) {
    return CanvasDrawingStroke(
      id: id ?? this.id,
      layerId: layerId ?? this.layerId,
      brushType: brushType ?? this.brushType,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      points: points ?? this.points,
      smoothing: smoothing ?? this.smoothing,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'layerId': layerId,
    'brushType': brushType.name,
    'color': color,
    'size': size,
    'opacity': opacity,
    'points': points.map((p) => p.toJson()).toList(growable: false),
    'smoothing': smoothing,
  };

  factory CanvasDrawingStroke.fromJson(Map<String, Object?> json) {
    return CanvasDrawingStroke(
      id: json['id'] as String? ?? '',
      layerId: json['layerId'] as String? ?? '',
      brushType: CanvasBrushType.fromName(json['brushType'] as String?),
      color: (json['color'] as num? ?? 0xFF000000).toInt(),
      size: (json['size'] as num? ?? 2.0).toDouble(),
      opacity: (json['opacity'] as num? ?? 1.0).toDouble(),
      points: (json['points'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<Object?, Object?>>()
          .map((m) => DrawingPoint.fromJson(Map<String, Object?>.from(m)))
          .toList(growable: false),
      smoothing: (json['smoothing'] as num? ?? 0.0).toDouble(),
    );
  }
}

/// An individual drawing layer containing strokes.
final class CanvasDrawingLayer {
  const CanvasDrawingLayer({
    required this.id,
    required this.name,
    this.isVisible = true,
    this.isLocked = false,
    this.opacity = 1.0,
    this.blendMode = 'srcOver',
    this.strokes = const <CanvasDrawingStroke>[],
  });

  final String id;
  final String name;
  final bool isVisible;
  final bool isLocked;
  final double opacity;
  final String blendMode;
  final List<CanvasDrawingStroke> strokes;

  CanvasDrawingLayer copyWith({
    String? id,
    String? name,
    bool? isVisible,
    bool? isLocked,
    double? opacity,
    String? blendMode,
    List<CanvasDrawingStroke>? strokes,
  }) {
    return CanvasDrawingLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
      strokes: strokes ?? this.strokes,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'isVisible': isVisible,
    'isLocked': isLocked,
    'opacity': opacity,
    'blendMode': blendMode,
    'strokes': strokes.map((s) => s.toJson()).toList(growable: false),
  };

  factory CanvasDrawingLayer.fromJson(Map<String, Object?> json) {
    return CanvasDrawingLayer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Layer',
      isVisible: json['isVisible'] as bool? ?? true,
      isLocked: json['isLocked'] as bool? ?? false,
      opacity: (json['opacity'] as num? ?? 1.0).toDouble(),
      blendMode: json['blendMode'] as String? ?? 'srcOver',
      strokes: (json['strokes'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<Object?, Object?>>()
          .map(
            (m) => CanvasDrawingStroke.fromJson(Map<String, Object?>.from(m)),
          )
          .toList(growable: false),
    );
  }
}

/// State and mutation container for canvas drawing layers with undo/redo support.
final class DrawingLayerManager {
  DrawingLayerManager({
    required this.activeLayerId,
    required List<CanvasDrawingLayer> layers,
    List<List<CanvasDrawingLayer>>? undoHistory,
    List<List<CanvasDrawingLayer>>? redoHistory,
  }) : layers = List<CanvasDrawingLayer>.unmodifiable(layers),
       _undoHistory = List<List<CanvasDrawingLayer>>.unmodifiable(
         undoHistory ?? const <List<CanvasDrawingLayer>>[],
       ),
       _redoHistory = List<List<CanvasDrawingLayer>>.unmodifiable(
         redoHistory ?? const <List<CanvasDrawingLayer>>[],
       );

  factory DrawingLayerManager.initial({
    String defaultLayerId = 'layer-default',
    String defaultLayerName = 'Layer 1',
  }) {
    final baseLayer = CanvasDrawingLayer(
      id: defaultLayerId,
      name: defaultLayerName,
    );
    return DrawingLayerManager(
      activeLayerId: defaultLayerId,
      layers: [baseLayer],
    );
  }

  final String activeLayerId;
  final List<CanvasDrawingLayer> layers;
  final List<List<CanvasDrawingLayer>> _undoHistory;
  final List<List<CanvasDrawingLayer>> _redoHistory;

  bool get canUndo => _undoHistory.isNotEmpty;
  bool get canRedo => _redoHistory.isNotEmpty;

  CanvasDrawingLayer? get activeLayer {
    return getLayer(activeLayerId) ?? (layers.isNotEmpty ? layers.first : null);
  }

  CanvasDrawingLayer? getLayer(String layerId) {
    for (final layer in layers) {
      if (layer.id == layerId) {
        return layer;
      }
    }
    return null;
  }

  DrawingLayerManager _withNewLayers(
    List<CanvasDrawingLayer> newLayers, {
    String? newActiveLayerId,
    bool recordHistory = true,
  }) {
    final nextActive =
        newActiveLayerId ??
        (newLayers.any((l) => l.id == activeLayerId)
            ? activeLayerId
            : (newLayers.isNotEmpty ? newLayers.first.id : ''));

    final nextUndo = recordHistory
        ? <List<CanvasDrawingLayer>>[..._undoHistory, layers]
        : _undoHistory;
    final nextRedo = recordHistory
        ? const <List<CanvasDrawingLayer>>[]
        : _redoHistory;

    return DrawingLayerManager(
      activeLayerId: nextActive,
      layers: newLayers,
      undoHistory: nextUndo,
      redoHistory: nextRedo,
    );
  }

  DrawingLayerManager addLayer(
    CanvasDrawingLayer layer, {
    bool makeActive = true,
  }) {
    final updated = [...layers, layer];
    return _withNewLayers(
      updated,
      newActiveLayerId: makeActive ? layer.id : activeLayerId,
    );
  }

  DrawingLayerManager removeLayer(String layerId) {
    if (layers.length <= 1) {
      return this;
    }
    final updated = layers
        .where((l) => l.id != layerId)
        .toList(growable: false);
    return _withNewLayers(updated);
  }

  DrawingLayerManager reorderLayers(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= layers.length) {
      return this;
    }
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 ||
        targetIndex >= layers.length ||
        targetIndex == oldIndex) {
      return this;
    }

    final updated = List<CanvasDrawingLayer>.from(layers);
    final moved = updated.removeAt(oldIndex);
    updated.insert(targetIndex, moved);
    return _withNewLayers(updated);
  }

  DrawingLayerManager toggleVisibility(String layerId) {
    final updated = layers
        .map((l) {
          return l.id == layerId ? l.copyWith(isVisible: !l.isVisible) : l;
        })
        .toList(growable: false);
    return _withNewLayers(updated, recordHistory: false);
  }

  DrawingLayerManager toggleLock(String layerId) {
    final updated = layers
        .map((l) {
          return l.id == layerId ? l.copyWith(isLocked: !l.isLocked) : l;
        })
        .toList(growable: false);
    return _withNewLayers(updated, recordHistory: false);
  }

  DrawingLayerManager setOpacity(String layerId, double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    final updated = layers
        .map((l) {
          return l.id == layerId ? l.copyWith(opacity: clamped) : l;
        })
        .toList(growable: false);
    return _withNewLayers(updated, recordHistory: false);
  }

  DrawingLayerManager setBlendMode(String layerId, String blendMode) {
    final updated = layers
        .map((l) {
          return l.id == layerId ? l.copyWith(blendMode: blendMode) : l;
        })
        .toList(growable: false);
    return _withNewLayers(updated, recordHistory: false);
  }

  DrawingLayerManager addStroke(CanvasDrawingStroke stroke) {
    final current = activeLayer;
    if (current == null || current.isLocked) {
      return this;
    }

    final updatedLayer = current.copyWith(
      strokes: [...current.strokes, stroke],
    );
    final updated = layers
        .map((l) => l.id == current.id ? updatedLayer : l)
        .toList(growable: false);
    return _withNewLayers(updated);
  }

  DrawingLayerManager clearActiveLayer() {
    final current = activeLayer;
    if (current == null || current.isLocked || current.strokes.isEmpty) {
      return this;
    }

    final updatedLayer = current.copyWith(
      strokes: const <CanvasDrawingStroke>[],
    );
    final updated = layers
        .map((l) => l.id == current.id ? updatedLayer : l)
        .toList(growable: false);
    return _withNewLayers(updated);
  }

  DrawingLayerManager undo() {
    if (!canUndo) {
      return this;
    }
    final previousLayers = _undoHistory.last;
    final newUndo = _undoHistory.sublist(0, _undoHistory.length - 1);
    final newRedo = <List<CanvasDrawingLayer>>[..._redoHistory, layers];

    final nextActive = previousLayers.any((l) => l.id == activeLayerId)
        ? activeLayerId
        : (previousLayers.isNotEmpty ? previousLayers.first.id : '');

    return DrawingLayerManager(
      activeLayerId: nextActive,
      layers: previousLayers,
      undoHistory: newUndo,
      redoHistory: newRedo,
    );
  }

  DrawingLayerManager redo() {
    if (!canRedo) {
      return this;
    }
    final nextLayers = _redoHistory.last;
    final newRedo = _redoHistory.sublist(0, _redoHistory.length - 1);
    final newUndo = <List<CanvasDrawingLayer>>[..._undoHistory, layers];

    final nextActive = nextLayers.any((l) => l.id == activeLayerId)
        ? activeLayerId
        : (nextLayers.isNotEmpty ? nextLayers.first.id : '');

    return DrawingLayerManager(
      activeLayerId: nextActive,
      layers: nextLayers,
      undoHistory: newUndo,
      redoHistory: newRedo,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'activeLayerId': activeLayerId,
    'layers': layers.map((l) => l.toJson()).toList(growable: false),
  };

  factory DrawingLayerManager.fromJson(Map<String, Object?> json) {
    final rawLayers = (json['layers'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<Object?, Object?>>()
        .map((m) => CanvasDrawingLayer.fromJson(Map<String, Object?>.from(m)))
        .toList(growable: false);

    final layers = rawLayers.isEmpty
        ? [const CanvasDrawingLayer(id: 'layer-default', name: 'Layer 1')]
        : rawLayers;

    final activeLayerId = json['activeLayerId'] as String? ?? layers.first.id;

    return DrawingLayerManager(activeLayerId: activeLayerId, layers: layers);
  }
}
