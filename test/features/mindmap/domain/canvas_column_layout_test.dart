import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_column_layout.dart';

void main() {
  const engine = CanvasColumnLayoutEngine();

  test('lays out expanded column children in declared order', () {
    const column = CanvasGeometry(x: 100, y: 50, width: 320, height: 100);
    const children = <String, CanvasGeometry>{
      'first': CanvasGeometry(x: 0, y: 0, width: 80, height: 30),
      'second': CanvasGeometry(x: 0, y: 0, width: 500, height: 90),
    };

    final layout = engine.layout(
      columnGeometry: column,
      orderedChildIds: const <String>['second', 'first'],
      childGeometries: children,
      isCollapsed: false,
    );

    expect(layout.headerBounds, const Rect.fromLTWH(100, 50, 320, 48));
    expect(layout.bodyBounds, const Rect.fromLTWH(100, 98, 320, 166));
    expect(layout.childBounds, const <String, Rect>{
      'second': Rect.fromLTWH(112, 110, 296, 90),
      'first': Rect.fromLTWH(112, 208, 296, 44),
    });
    expect(layout.columnGeometry.height, 214);
  });

  test('normalizes legacy narrow column and child width', () {
    final layout = engine.layout(
      columnGeometry: const CanvasGeometry(
        x: 10,
        y: 20,
        width: 120,
        height: 100,
      ),
      orderedChildIds: const <String>['child'],
      childGeometries: const <String, CanvasGeometry>{
        'child': CanvasGeometry(x: 0, y: 0, width: 40, height: 44),
      },
      isCollapsed: false,
    );

    expect(layout.columnGeometry.width, 240);
    expect(layout.headerBounds.width, 240);
    expect(layout.bodyBounds.width, 240);
    expect(layout.childBounds['child']!.width, 216);
  });

  test('expanded empty column keeps minimum body and column height', () {
    final layout = engine.layout(
      columnGeometry: const CanvasGeometry(
        x: 10,
        y: 20,
        width: 240,
        height: 20,
      ),
      orderedChildIds: const <String>[],
      childGeometries: const <String, CanvasGeometry>{},
      isCollapsed: false,
    );

    expect(layout.bodyBounds, const Rect.fromLTWH(10, 68, 240, 68));
    expect(layout.columnGeometry.height, 116);
  });

  test('collapsed column exposes only header', () {
    final layout = engine.layout(
      columnGeometry: const CanvasGeometry(
        x: 10,
        y: 20,
        width: 240,
        height: 500,
      ),
      orderedChildIds: const <String>['child'],
      childGeometries: const <String, CanvasGeometry>{
        'child': CanvasGeometry(x: 0, y: 0, width: 100, height: 100),
      },
      isCollapsed: true,
    );

    expect(layout.headerBounds, const Rect.fromLTWH(10, 20, 240, 48));
    expect(layout.bodyBounds, Rect.zero);
    expect(layout.childBounds, isEmpty);
    expect(layout.columnGeometry.height, 48);
  });

  test('finds insertion index from scene offset', () {
    final layout = engine.layout(
      columnGeometry: const CanvasGeometry(
        x: 100,
        y: 50,
        width: 320,
        height: 100,
      ),
      orderedChildIds: const <String>['first', 'second'],
      childGeometries: const <String, CanvasGeometry>{
        'first': CanvasGeometry(x: 0, y: 0, width: 10, height: 44),
        'second': CanvasGeometry(x: 0, y: 0, width: 10, height: 80),
      },
      isCollapsed: false,
    );

    expect(layout.insertionIndex(const Offset(150, 110)), 0);
    expect(layout.insertionIndex(const Offset(150, 140)), 1);
    expect(layout.insertionIndex(const Offset(150, 230)), 2);
  });

  test('creates detached geometry centered on drop position', () {
    final geometry = engine.detachGeometry(
      childGeometry: const CanvasGeometry(
        x: 112,
        y: 110,
        width: 296,
        height: 90,
        rotation: 0.25,
      ),
      dropPosition: const Offset(600, 400),
    );

    expect(
      geometry,
      const CanvasGeometry(
        x: 452,
        y: 355,
        width: 296,
        height: 90,
        rotation: 0.25,
      ),
    );
  });
}
