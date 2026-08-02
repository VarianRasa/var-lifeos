import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_scene_bounds.dart';

void main() {
  test('starts with legacy canvas centered on world origin', () {
    const bounds = CanvasSceneBounds.initial();

    expect(bounds.worldRect, const Rect.fromLTWH(-10000, -7000, 20000, 14000));
    expect(bounds.sceneOffset, const Offset(10000, 7000));
    expect(bounds.worldToScene(Offset.zero), const Offset(10000, 7000));
  });

  test('expands right and bottom in fixed chunks without moving origin', () {
    const bounds = CanvasSceneBounds.initial();
    final expanded = bounds.expandToInclude(
      const Rect.fromLTWH(9800, 6800, 500, 500),
    );

    expect(expanded.worldRect.right, 12000);
    expect(expanded.worldRect.bottom, 9000);
    expect(expanded.sceneOffset, bounds.sceneOffset);
  });

  test('expands left and top in fixed chunks and updates scene offset', () {
    const bounds = CanvasSceneBounds.initial();
    final expanded = bounds.expandToInclude(
      const Rect.fromLTWH(-10300, -7300, 100, 100),
    );

    expect(expanded.worldRect.left, -12000);
    expect(expanded.worldRect.top, -9000);
    expect(expanded.sceneOffset, const Offset(12000, 9000));
    expect(expanded.worldToScene(Offset.zero), expanded.sceneOffset);
  });

  test('padding hysteresis does not repeatedly expand inside new edge', () {
    const bounds = CanvasSceneBounds.initial();
    final expanded = bounds.expandToInclude(
      const Rect.fromLTWH(9800, 0, 200, 100),
    );
    final stable = expanded.expandToInclude(
      const Rect.fromLTWH(10600, 0, 200, 100),
    );

    expect(expanded.worldRect.right, 12000);
    expect(stable, expanded);
  });

  test('never shrinks and world scene conversion round trips', () {
    const bounds = CanvasSceneBounds.initial();
    final unchanged = bounds.expandToInclude(const Rect.fromLTWH(0, 0, 10, 10));
    const world = Offset(-1234, 5678);

    expect(unchanged, bounds);
    expect(bounds.sceneToWorld(bounds.worldToScene(world)), world);
  });
}
