import 'dart:ui';

final class CanvasSceneBounds {
  const CanvasSceneBounds._(this.worldRect);

  const CanvasSceneBounds.initial()
    : worldRect = const Rect.fromLTWH(-10000, -7000, 20000, 14000);

  static const double chunk = 2000;
  static const double padding = 600;

  final Rect worldRect;

  Offset get sceneOffset => Offset(-worldRect.left, -worldRect.top);

  Size get sceneSize => worldRect.size;

  Offset worldToScene(Offset world) => world + sceneOffset;

  Offset sceneToWorld(Offset scene) => scene - sceneOffset;

  CanvasSceneBounds expandToInclude(Rect content) {
    var left = worldRect.left;
    var top = worldRect.top;
    var right = worldRect.right;
    var bottom = worldRect.bottom;
    while (content.left - padding < left) {
      left -= chunk;
    }
    while (content.top - padding < top) {
      top -= chunk;
    }
    while (content.right + padding > right) {
      right += chunk;
    }
    while (content.bottom + padding > bottom) {
      bottom += chunk;
    }
    if (left == worldRect.left &&
        top == worldRect.top &&
        right == worldRect.right &&
        bottom == worldRect.bottom) {
      return this;
    }
    return CanvasSceneBounds._(Rect.fromLTRB(left, top, right, bottom));
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasSceneBounds && other.worldRect == worldRect;

  @override
  int get hashCode => worldRect.hashCode;
}
