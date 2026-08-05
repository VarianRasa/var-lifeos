class SnapGuideline {
  final double position;
  final bool isVertical;

  const SnapGuideline({
    required this.position,
    required this.isVertical,
  });
}

class SnapResult {
  final double snappedX;
  final double snappedY;
  final List<SnapGuideline> guidelines;

  const SnapResult({
    required this.snappedX,
    required this.snappedY,
    this.guidelines = const [],
  });
}

class CanvasSnapAlign {
  static const double threshold = 8.0;

  static SnapResult computeSnap({
    required double targetX,
    required double targetY,
    required List<({double x, double y})> otherNodes,
  }) {
    double finalX = targetX;
    double finalY = targetY;
    final guidelines = <SnapGuideline>[];

    for (final node in otherNodes) {
      if ((targetX - node.x).abs() <= threshold) {
        finalX = node.x;
        guidelines.add(SnapGuideline(position: node.x, isVertical: true));
      }
      if ((targetY - node.y).abs() <= threshold) {
        finalY = node.y;
        guidelines.add(SnapGuideline(position: node.y, isVertical: false));
      }
    }

    return SnapResult(
      snappedX: finalX,
      snappedY: finalY,
      guidelines: guidelines,
    );
  }
}
