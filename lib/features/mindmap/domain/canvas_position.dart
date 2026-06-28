/// Canvas-space coordinate for a node inside a day's mindmap.
library;

final class CanvasPosition {
  const CanvasPosition(this.dx, this.dy);

  final double dx;
  final double dy;

  Map<String, Object?> toJson() => {'dx': dx, 'dy': dy};

  factory CanvasPosition.fromJson(Map<String, Object?> json) {
    return CanvasPosition(
      (json['dx'] as num? ?? 0).toDouble(),
      (json['dy'] as num? ?? 0).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CanvasPosition && other.dx == dx && other.dy == dy;
  }

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'CanvasPosition(dx: $dx, dy: $dy)';
}
