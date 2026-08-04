import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/mindmap_node_data.dart';

class ConnectionRenderItem {
  const ConnectionRenderItem({
    required this.id,
    required this.start,
    required this.end,
    required this.metadata,
  });

  final String id;
  final Offset start;
  final Offset end;
  final ConnectionMetadata metadata;
}

Color resolveConnectionColor(String colorName, BuildContext? context) {
  if (colorName.startsWith('#')) {
    final hexStr = colorName.replaceAll('#', '');
    final val = int.tryParse(hexStr.length == 6 ? 'FF$hexStr' : hexStr, radix: 16);
    if (val != null) return Color(val);
  }
  switch (colorName.toLowerCase()) {
    case 'blue':
    case 'indigo':
      return const Color(0xFF2694FE);
    case 'green':
    case 'emerald':
    case 'teal':
      return const Color(0xFF0D8626);
    case 'red':
    case 'rose':
      return const Color(0xFFF5394F);
    case 'yellow':
    case 'amber':
    case 'orange':
      return const Color(0xFFF2C00B);
    case 'purple':
    case 'violet':
      return const Color(0xFFF297FF);
    case 'pink':
      return const Color(0xFFFF99C3);
    case 'slate':
    case 'gray':
    default:
      return const Color(0xFFAAAFB5);
  }
}

(Offset c1, Offset c2) computeBezierControlPoints(Offset start, Offset end) {
  final dx = (end.dx - start.dx).abs();
  final dy = (end.dy - start.dy).abs();
  final curvature = math.max(dx, dy) * 0.5;
  if (dx > dy) {
    final sign = end.dx >= start.dx ? 1.0 : -1.0;
    return (
      Offset(start.dx + curvature * sign, start.dy),
      Offset(end.dx - curvature * sign, end.dy),
    );
  } else {
    final sign = end.dy >= start.dy ? 1.0 : -1.0;
    return (
      Offset(start.dx, start.dy + curvature * sign),
      Offset(end.dx, end.dy - curvature * sign),
    );
  }
}

Offset computeBezierPoint(Offset start, Offset c1, Offset c2, Offset end, double t) {
  final u = 1 - t;
  final tt = t * t;
  final uu = u * u;
  final uuu = uu * u;
  final ttt = tt * t;

  final x = uuu * start.dx + 3 * uu * t * c1.dx + 3 * u * tt * c2.dx + ttt * end.dx;
  final y = uuu * start.dy + 3 * uu * t * c1.dy + 3 * u * tt * c2.dy + ttt * end.dy;
  return Offset(x, y);
}

double computeBezierAngle(Offset start, Offset c1, Offset c2, Offset end, double t) {
  final u = 1 - t;
  final dx = 3 * u * u * (c1.dx - start.dx) + 6 * u * t * (c2.dx - c1.dx) + 3 * t * t * (end.dx - c2.dx);
  final dy = 3 * u * u * (c1.dy - start.dy) + 6 * u * t * (c2.dy - c1.dy) + 3 * t * t * (end.dy - c2.dy);
  return math.atan2(dy, dx);
}

Path createDashedPath(Path source, {required double dashLength, required double spaceLength}) {
  final Path dest = Path();
  for (final metric in source.computeMetrics()) {
    double distance = 0.0;
    bool draw = true;
    while (distance < metric.length) {
      final double length = draw ? dashLength : spaceLength;
      if (draw) {
        dest.addPath(
          metric.extractPath(distance, math.min(distance + length, metric.length)),
          Offset.zero,
        );
      }
      distance += length;
      draw = !draw;
    }
  }
  return dest;
}

class MindmapConnectionPainter extends CustomPainter {
  const MindmapConnectionPainter({
    required this.connections,
    this.context,
  });

  final List<ConnectionRenderItem> connections;
  final BuildContext? context;

  @override
  void paint(Canvas canvas, Size size) {
    for (final item in connections) {
      _paintConnection(canvas, item);
    }
  }

  void _paintConnection(Canvas canvas, ConnectionRenderItem item) {
    final color = resolveConnectionColor(item.metadata.color, context);
    final (c1, c2) = computeBezierControlPoints(item.start, item.end);

    final path = Path()
      ..moveTo(item.start.dx, item.start.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, item.end.dx, item.end.dy);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final lineStyle = item.metadata.lineStyle;
    if (lineStyle == 'dashed') {
      canvas.drawPath(createDashedPath(path, dashLength: 6, spaceLength: 4), paint);
    } else if (lineStyle == 'dotted') {
      canvas.drawPath(createDashedPath(path, dashLength: 2, spaceLength: 4), paint);
    } else {
      canvas.drawPath(path, paint);
    }

    final arrowStyle = item.metadata.arrowStyle;
    if (arrowStyle == 'end' || arrowStyle == 'both') {
      final angle = computeBezierAngle(item.start, c1, c2, item.end, 1.0);
      _drawArrowHead(canvas, item.end, angle, color);
    }
    if (arrowStyle == 'both') {
      final angle = computeBezierAngle(item.start, c1, c2, item.end, 0.0) + math.pi;
      _drawArrowHead(canvas, item.start, angle, color);
    }

    final label = item.metadata.label;
    if (label != null && label.trim().isNotEmpty) {
      _drawLabel(canvas, item.start, c1, c2, item.end, label, color);
    }
  }

  void _drawArrowHead(Canvas canvas, Offset point, double angle, Color color) {
    const size = 8.0;
    final path = Path()
      ..moveTo(point.dx, point.dy)
      ..lineTo(
        point.dx - size * math.cos(angle - math.pi / 6),
        point.dy - size * math.sin(angle - math.pi / 6),
      )
      ..lineTo(
        point.dx - size * math.cos(angle + math.pi / 6),
        point.dy - size * math.sin(angle + math.pi / 6),
      )
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  void _drawLabel(
    Canvas canvas,
    Offset start,
    Offset c1,
    Offset c2,
    Offset end,
    String text,
    Color color,
  ) {
    final mid = computeBezierPoint(start, c1, c2, end, 0.5);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromCenter(
      center: mid,
      width: textPainter.width + 10,
      height: textPainter.height + 4,
    );

    final bgPaint = Paint()
      ..color = const Color(0xFF111112)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(mid.dx - textPainter.width / 2, mid.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant MindmapConnectionPainter oldDelegate) {
    return oldDelegate.connections != connections;
  }
}
