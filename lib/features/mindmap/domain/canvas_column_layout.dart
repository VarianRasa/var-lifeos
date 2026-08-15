import 'dart:ui';

import 'canvas_board.dart';

const double minimumCanvasColumnWidth = 240;

final class CanvasColumnLayout {
  const CanvasColumnLayout({
    required this.headerBounds,
    required this.bodyBounds,
    required this.childBounds,
    required this.columnGeometry,
  });

  final Rect headerBounds;
  final Rect bodyBounds;
  final Map<String, Rect> childBounds;
  final CanvasGeometry columnGeometry;

  int insertionIndex(Offset scenePosition) {
    var index = 0;
    for (final bounds in childBounds.values) {
      if (scenePosition.dy < bounds.center.dy) return index;
      index++;
    }
    return index;
  }
}

final class CanvasColumnLayoutEngine {
  const CanvasColumnLayoutEngine();

  static const double headerHeight = 48;
  static const double padding = 12;
  static const double childGap = 8;
  static const double minimumChildHeight = 44;
  static const double minimumBodyHeight = 68;

  CanvasColumnLayout layout({
    required CanvasGeometry columnGeometry,
    required List<String> orderedChildIds,
    required Map<String, CanvasGeometry> childGeometries,
    required bool isCollapsed,
  }) {
    final normalizedColumnGeometry = columnGeometry.copyWith(
      width: columnGeometry.width < minimumCanvasColumnWidth
          ? minimumCanvasColumnWidth
          : columnGeometry.width,
    );
    final header = Rect.fromLTWH(
      normalizedColumnGeometry.x,
      normalizedColumnGeometry.y,
      normalizedColumnGeometry.width,
      headerHeight,
    );
    if (isCollapsed) {
      return CanvasColumnLayout(
        headerBounds: header,
        bodyBounds: Rect.zero,
        childBounds: const <String, Rect>{},
        columnGeometry: normalizedColumnGeometry.copyWith(height: headerHeight),
      );
    }

    final innerWidth = normalizedColumnGeometry.width - padding * 2;
    final children = <String, Rect>{};
    var y = normalizedColumnGeometry.y + headerHeight + padding;
    for (final childId in orderedChildIds) {
      final geometry = childGeometries[childId];
      if (geometry == null) continue;
      final height = geometry.height < minimumChildHeight
          ? minimumChildHeight
          : geometry.height;
      children[childId] = Rect.fromLTWH(
        normalizedColumnGeometry.x + padding,
        y,
        innerWidth,
        height,
      );
      y += height + childGap;
    }
    final contentHeight = children.isEmpty
        ? minimumBodyHeight
        : y - (normalizedColumnGeometry.y + headerHeight) - childGap + padding;
    final requiredHeight = headerHeight + contentHeight;
    final expandedHeight = normalizedColumnGeometry.height > requiredHeight
        ? normalizedColumnGeometry.height
        : requiredHeight;

    return CanvasColumnLayout(
      headerBounds: header,
      bodyBounds: Rect.fromLTWH(
        normalizedColumnGeometry.x,
        normalizedColumnGeometry.y + headerHeight,
        normalizedColumnGeometry.width,
        expandedHeight - headerHeight,
      ),
      childBounds: Map<String, Rect>.unmodifiable(children),
      columnGeometry: normalizedColumnGeometry.copyWith(height: expandedHeight),
    );
  }

  CanvasGeometry detachGeometry({
    required CanvasGeometry childGeometry,
    required Offset dropPosition,
  }) => childGeometry.copyWith(
    x: dropPosition.dx - childGeometry.width / 2,
    y: dropPosition.dy - childGeometry.height / 2,
  );
}
