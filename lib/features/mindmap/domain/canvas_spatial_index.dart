final class CanvasBounds {
  const CanvasBounds(this.left, this.top, this.right, this.bottom);

  factory CanvasBounds.fromLTWH(
    double left,
    double top,
    double width,
    double height,
  ) => CanvasBounds(left, top, left + width, top + height);

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool overlaps(CanvasBounds other) =>
      left < other.right &&
      right > other.left &&
      top < other.bottom &&
      bottom > other.top;

  bool contains(CanvasPoint point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  CanvasBounds inflate(double value) =>
      CanvasBounds(left - value, top - value, right + value, bottom + value);
}

final class CanvasPoint {
  const CanvasPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is CanvasPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

final class CanvasSpatialIndex<T> {
  CanvasSpatialIndex({this.cellSize = 256})
    : assert(cellSize > 0 && cellSize.isFinite);

  final double cellSize;
  final Map<(int, int), Set<T>> _cells = <(int, int), Set<T>>{};
  final Map<T, CanvasBounds> _bounds = <T, CanvasBounds>{};

  int get length => _bounds.length;

  void insert(T value, CanvasBounds bounds) {
    remove(value);
    _bounds[value] = bounds;
    for (final cell in _cellsFor(bounds)) {
      (_cells[cell] ??= <T>{}).add(value);
    }
  }

  void remove(T value) {
    final bounds = _bounds.remove(value);
    if (bounds == null) return;
    for (final cell in _cellsFor(bounds)) {
      final values = _cells[cell];
      values?.remove(value);
      if (values?.isEmpty ?? false) _cells.remove(cell);
    }
  }

  void clear() {
    _cells.clear();
    _bounds.clear();
  }

  Set<T> query(CanvasBounds area) {
    final result = <T>{};
    for (final cell in _cellsFor(area)) {
      final values = _cells[cell];
      if (values != null) result.addAll(values);
    }
    result.removeWhere((value) => !(_bounds[value]?.overlaps(area) ?? false));
    return result;
  }

  Iterable<(int, int)> _cellsFor(CanvasBounds bounds) sync* {
    final minX = (bounds.left / cellSize).floor();
    final maxX = (bounds.right / cellSize).floor();
    final minY = (bounds.top / cellSize).floor();
    final maxY = (bounds.bottom / cellSize).floor();
    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        yield (x, y);
      }
    }
  }
}
