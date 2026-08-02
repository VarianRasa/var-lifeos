import 'dart:collection';

import 'canvas_spatial_index.dart';

enum CanvasConnectorPort { top, right, bottom, left }

final class CanvasConnectorAttachment {
  const CanvasConnectorAttachment({required this.point, required this.port});

  final CanvasPoint point;
  final CanvasConnectorPort port;
}

CanvasConnectorAttachment nearestConnectorAttachment(
  CanvasBounds bounds,
  CanvasPoint toward,
) {
  final candidates = <CanvasConnectorAttachment>[
    CanvasConnectorAttachment(
      point: CanvasPoint((bounds.left + bounds.right) / 2, bounds.top),
      port: CanvasConnectorPort.top,
    ),
    CanvasConnectorAttachment(
      point: CanvasPoint(bounds.right, (bounds.top + bounds.bottom) / 2),
      port: CanvasConnectorPort.right,
    ),
    CanvasConnectorAttachment(
      point: CanvasPoint((bounds.left + bounds.right) / 2, bounds.bottom),
      port: CanvasConnectorPort.bottom,
    ),
    CanvasConnectorAttachment(
      point: CanvasPoint(bounds.left, (bounds.top + bounds.bottom) / 2),
      port: CanvasConnectorPort.left,
    ),
  ];
  candidates.sort((left, right) {
    final distanceOrder = _squaredDistance(
      left.point,
      toward,
    ).compareTo(_squaredDistance(right.point, toward));
    return distanceOrder != 0
        ? distanceOrder
        : left.port.index.compareTo(right.port.index);
  });
  return candidates.first;
}

List<CanvasPoint> routeOrthogonalConnector({
  required CanvasPoint start,
  required CanvasPoint end,
  required Iterable<CanvasBounds> obstacles,
  double clearance = 12,
}) {
  final blocked = obstacles.map((bounds) => bounds.inflate(clearance)).toList();
  final candidates = <List<CanvasPoint>>[
    <CanvasPoint>[start, CanvasPoint(end.x, start.y), end],
    <CanvasPoint>[start, CanvasPoint(start.x, end.y), end],
  ];
  final xs = <double>{
    start.x,
    end.x,
    for (final bounds in blocked) bounds.left,
    for (final bounds in blocked) bounds.right,
  }.toList()..sort();
  final ys = <double>{
    start.y,
    end.y,
    for (final bounds in blocked) bounds.top,
    for (final bounds in blocked) bounds.bottom,
  }.toList()..sort();
  for (final y in ys) {
    candidates.add(<CanvasPoint>[
      start,
      CanvasPoint(start.x, y),
      CanvasPoint(end.x, y),
      end,
    ]);
  }
  for (final x in xs) {
    candidates.add(<CanvasPoint>[
      start,
      CanvasPoint(x, start.y),
      CanvasPoint(x, end.y),
      end,
    ]);
  }
  final valid = candidates
      .map(_withoutDuplicatePoints)
      .where((route) => _routeClear(route, blocked))
      .toList();
  if (valid.isEmpty) {
    return _routeWithGridSearch(start, end, blocked);
  }
  valid.sort((left, right) {
    final lengthOrder = _length(left).compareTo(_length(right));
    if (lengthOrder != 0) return lengthOrder;
    final bendOrder = left.length.compareTo(right.length);
    if (bendOrder != 0) return bendOrder;
    return _routeKey(left).compareTo(_routeKey(right));
  });
  return valid.first;
}

List<CanvasPoint> _routeWithGridSearch(
  CanvasPoint start,
  CanvasPoint end,
  List<CanvasBounds> obstacles,
) {
  final xs = <double>{
    start.x,
    end.x,
    for (final obstacle in obstacles) obstacle.left,
    for (final obstacle in obstacles) obstacle.right,
  }.toList()..sort();
  final ys = <double>{
    start.y,
    end.y,
    for (final obstacle in obstacles) obstacle.top,
    for (final obstacle in obstacles) obstacle.bottom,
  }.toList()..sort();
  final points = <CanvasPoint>[
    for (final x in xs)
      for (final y in ys) CanvasPoint(x, y),
  ];
  final pointSet = points.toSet();
  final previous = <CanvasPoint, CanvasPoint?>{start: null};
  final queue = Queue<CanvasPoint>()..add(start);
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    if (current == end) break;
    final neighbors =
        points
            .where(
              (point) =>
                  point != current &&
                  (point.x == current.x || point.y == current.y) &&
                  _routeClear(<CanvasPoint>[current, point], obstacles),
            )
            .toList()
          ..sort((left, right) {
            final distanceOrder = _squaredDistance(
              left,
              end,
            ).compareTo(_squaredDistance(right, end));
            return distanceOrder != 0
                ? distanceOrder
                : _pointKey(left).compareTo(_pointKey(right));
          });
    for (final neighbor in neighbors) {
      if (!pointSet.contains(neighbor) || previous.containsKey(neighbor)) {
        continue;
      }
      previous[neighbor] = current;
      queue.add(neighbor);
    }
  }
  if (!previous.containsKey(end)) {
    final bend = CanvasPoint(end.x, start.y);
    return _withoutDuplicatePoints(<CanvasPoint>[start, bend, end]);
  }
  final reversed = <CanvasPoint>[];
  CanvasPoint? current = end;
  while (current != null) {
    reversed.add(current);
    current = previous[current];
  }
  return _simplifyOrthogonal(reversed.reversed.toList());
}

List<CanvasPoint> _simplifyOrthogonal(List<CanvasPoint> points) {
  final result = <CanvasPoint>[];
  for (final point in points) {
    if (result.length >= 2) {
      final before = result[result.length - 2];
      final previous = result.last;
      if ((before.x == previous.x && previous.x == point.x) ||
          (before.y == previous.y && previous.y == point.y)) {
        result[result.length - 1] = point;
        continue;
      }
    }
    result.add(point);
  }
  return result;
}

List<CanvasPoint> _withoutDuplicatePoints(List<CanvasPoint> points) {
  final result = <CanvasPoint>[];
  for (final point in points) {
    if (result.isEmpty || result.last != point) result.add(point);
  }
  return result;
}

bool _routeClear(List<CanvasPoint> route, List<CanvasBounds> obstacles) {
  for (var index = 1; index < route.length; index++) {
    final start = route[index - 1];
    final end = route[index];
    if (start.x != end.x && start.y != end.y) return false;
    for (final obstacle in obstacles) {
      final segment = CanvasBounds(
        start.x < end.x ? start.x : end.x,
        start.y < end.y ? start.y : end.y,
        start.x > end.x ? start.x : end.x,
        start.y > end.y ? start.y : end.y,
      );
      if (obstacle.contains(start) ||
          obstacle.contains(end) ||
          (segment.left < obstacle.right &&
              segment.right > obstacle.left &&
              segment.top < obstacle.bottom &&
              segment.bottom > obstacle.top)) {
        return false;
      }
    }
  }
  return true;
}

double _length(List<CanvasPoint> route) {
  var result = 0.0;
  for (var index = 1; index < route.length; index++) {
    result += (route[index].x - route[index - 1].x).abs();
    result += (route[index].y - route[index - 1].y).abs();
  }
  return result;
}

double _squaredDistance(CanvasPoint left, CanvasPoint right) {
  final dx = left.x - right.x;
  final dy = left.y - right.y;
  return dx * dx + dy * dy;
}

String _pointKey(CanvasPoint point) => '${point.x},${point.y}';

String _routeKey(List<CanvasPoint> route) => route.map(_pointKey).join(';');
