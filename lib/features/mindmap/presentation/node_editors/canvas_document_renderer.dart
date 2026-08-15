import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/node_type_payloads.dart';

class CanvasDocumentView extends StatelessWidget {
  const CanvasDocumentView({
    required this.payload,
    this.selectedElementId,
    this.draftElement,
    super.key,
  });

  final CanvasPayload payload;
  final String? selectedElementId;
  final CanvasElement? draftElement;

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: const ValueKey<String>('canvas-document-renderer'),
    painter: CanvasDocumentPainter(
      payload: payload,
      selectedElementId: selectedElementId,
      draftElement: draftElement,
      colorScheme: Theme.of(context).colorScheme,
      semantic: AppSemanticColors.of(context),
    ),
    size: Size.infinite,
  );
}

class CanvasDocumentPainter extends CustomPainter {
  const CanvasDocumentPainter({
    required this.payload,
    required this.colorScheme,
    required this.semantic,
    this.selectedElementId,
    this.draftElement,
  });

  final CanvasPayload payload;
  final ColorScheme colorScheme;
  final AppSemanticColors semantic;
  final String? selectedElementId;
  final CanvasElement? draftElement;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    _paintBackground(canvas, size);
    for (final element in payload.elements) {
      _paintElement(canvas, size, element);
    }
    if (draftElement case final draft?) {
      _paintElement(canvas, size, draft);
    }
    if (selectedElementId case final selected?) {
      final element = payload.elements
          .where((item) => item.id == selected)
          .firstOrNull;
      if (element != null) _paintSelection(canvas, size, element);
    }
    canvas.restore();
  }

  void _paintBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colorScheme.surfaceContainerLowest,
    );
    final pattern = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    const spacing = 24.0;
    if (payload.background == 'grid') {
      for (var x = spacing; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), pattern);
      }
      for (var y = spacing; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), pattern);
      }
    } else if (payload.background == 'dots') {
      for (var x = spacing; x < size.width; x += spacing) {
        for (var y = spacing; y < size.height; y += spacing) {
          canvas.drawCircle(Offset(x, y), 1.4, pattern);
        }
      }
    }
  }

  void _paintElement(Canvas canvas, Size size, CanvasElement element) {
    final color = canvasColor(element.color, semantic);
    switch (element) {
      case CanvasStroke():
        if (element.points.length < 2) return;
        final path = Path();
        final first = canvasPointToOffset(element.points.first, size);
        path.moveTo(first.dx, first.dy);
        for (final point in element.points.skip(1)) {
          final offset = canvasPointToOffset(point, size);
          path.lineTo(offset.dx, offset.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..strokeWidth = element.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
        );
      case CanvasTextElement():
        final painter = TextPainter(
          text: TextSpan(
            text: element.text,
            style: TextStyle(color: color, fontSize: element.fontSize),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 4,
          ellipsis: '…',
        )..layout(maxWidth: math.max(80, size.width * 0.35));
        painter.paint(canvas, canvasPointToOffset(element.position, size));
      case CanvasStickyElement():
        final rect = Rect.fromLTWH(
          element.position.x * size.width,
          element.position.y * size.height,
          element.width * size.width,
          element.height * size.height,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          Paint()
            ..color = canvasColor(
              element.backgroundColor,
              semantic,
            ).withValues(alpha: 0.32),
        );
        final painter = TextPainter(
          text: TextSpan(
            text: element.text,
            style: TextStyle(color: color, fontSize: 13),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 5,
          ellipsis: '…',
        )..layout(maxWidth: math.max(0, rect.width - 16));
        painter.paint(canvas, rect.topLeft + const Offset(8, 8));
      case CanvasShapeElement():
        final rect = Rect.fromPoints(
          canvasPointToOffset(element.start, size),
          canvasPointToOffset(element.end, size),
        );
        if (element.fillColor.isNotEmpty) {
          final fill = Paint()
            ..color = canvasColor(
              element.fillColor,
              semantic,
            ).withValues(alpha: 0.18);
          element.shape == 'ellipse'
              ? canvas.drawOval(rect, fill)
              : canvas.drawRect(rect, fill);
        }
        final paint = Paint()
          ..color = color
          ..strokeWidth = element.width
          ..style = PaintingStyle.stroke;
        element.shape == 'ellipse'
            ? canvas.drawOval(rect, paint)
            : canvas.drawRect(rect, paint);
      case CanvasArrowElement():
        final start = canvasPointToOffset(element.start, size);
        final end = canvasPointToOffset(element.end, size);
        final paint = Paint()
          ..color = color
          ..strokeWidth = element.width
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(start, end, paint);
        final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
        const head = 10.0;
        canvas
          ..drawLine(
            end,
            end - Offset(math.cos(angle - 0.55), math.sin(angle - 0.55)) * head,
            paint,
          )
          ..drawLine(
            end,
            end - Offset(math.cos(angle + 0.55), math.sin(angle + 0.55)) * head,
            paint,
          );
      case CanvasUnknownElement():
        break;
    }
  }

  void _paintSelection(Canvas canvas, Size size, CanvasElement element) {
    final rect = canvasElementBounds(element, size).inflate(5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = colorScheme.primary
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CanvasDocumentPainter oldDelegate) =>
      oldDelegate.payload != payload ||
      oldDelegate.selectedElementId != selectedElementId ||
      oldDelegate.draftElement != draftElement ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.semantic != semantic;
}

Color canvasColor(String token, AppSemanticColors semantic) => switch (token) {
  'blue' => semantic.info,
  'green' => semantic.success,
  'amber' => semantic.warning,
  'rose' => semantic.nodeColors[NodeType.journal]!,
  'neutral' => semantic.textPrimary,
  _ => semantic.accent,
};

Offset canvasPointToOffset(CanvasPoint point, Size size) =>
    Offset(point.x * size.width, point.y * size.height);

CanvasPoint offsetToCanvasPoint(Offset offset, Size size) => CanvasPoint(
  (offset.dx / size.width).clamp(0, 1),
  (offset.dy / size.height).clamp(0, 1),
);

Rect canvasElementBounds(CanvasElement element, Size size) => switch (element) {
  CanvasStroke() => _pointsBounds(element.points, size),
  CanvasTextElement() => Rect.fromLTWH(
    element.position.x * size.width,
    element.position.y * size.height,
    math.min(180, size.width * 0.35),
    math.max(28, element.fontSize * 2),
  ),
  CanvasStickyElement() => Rect.fromLTWH(
    element.position.x * size.width,
    element.position.y * size.height,
    element.width * size.width,
    element.height * size.height,
  ),
  CanvasShapeElement() => Rect.fromPoints(
    canvasPointToOffset(element.start, size),
    canvasPointToOffset(element.end, size),
  ),
  CanvasArrowElement() => Rect.fromPoints(
    canvasPointToOffset(element.start, size),
    canvasPointToOffset(element.end, size),
  ),
  CanvasUnknownElement() => Rect.zero,
};

CanvasElement? hitTestCanvasElement(
  List<CanvasElement> elements,
  Offset point,
  Size size, {
  double tolerance = 12,
}) {
  for (final element in elements.reversed) {
    if (_hitElement(element, point, size, tolerance)) return element;
  }
  return null;
}

bool _hitElement(
  CanvasElement element,
  Offset point,
  Size size,
  double tolerance,
) => switch (element) {
  CanvasStroke() => _hitPolyline(element.points, point, size, tolerance),
  CanvasArrowElement() =>
    _distanceToSegment(
          point,
          canvasPointToOffset(element.start, size),
          canvasPointToOffset(element.end, size),
        ) <=
        tolerance,
  CanvasShapeElement() => canvasElementBounds(
    element,
    size,
  ).inflate(tolerance).contains(point),
  CanvasTextElement() || CanvasStickyElement() => canvasElementBounds(
    element,
    size,
  ).inflate(tolerance).contains(point),
  CanvasUnknownElement() => false,
};

CanvasElement moveCanvasElement(
  CanvasElement element,
  Offset pixelDelta,
  Size size,
) {
  final bounds = canvasElementBounds(element, size);
  final clampedDx = pixelDelta.dx.clamp(
    -bounds.left,
    size.width - bounds.right,
  );
  final clampedDy = pixelDelta.dy.clamp(
    -bounds.top,
    size.height - bounds.bottom,
  );
  final dx = clampedDx / size.width;
  final dy = clampedDy / size.height;
  CanvasPoint move(CanvasPoint point) =>
      CanvasPoint(point.x + dx, point.y + dy);
  return switch (element) {
    CanvasStroke() => element.copyWith(
      points: <CanvasPoint>[for (final point in element.points) move(point)],
    ),
    CanvasTextElement() => element.copyWith(position: move(element.position)),
    CanvasStickyElement() => element.copyWith(position: move(element.position)),
    CanvasShapeElement() => element.copyWith(
      start: move(element.start),
      end: move(element.end),
    ),
    CanvasArrowElement() => element.copyWith(
      start: move(element.start),
      end: move(element.end),
    ),
    CanvasUnknownElement() => element,
  };
}

Rect _pointsBounds(List<CanvasPoint> points, Size size) {
  if (points.isEmpty) return Rect.zero;
  final offsets = points.map((point) => canvasPointToOffset(point, size));
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final point in offsets) {
    left = math.min(left, point.dx);
    top = math.min(top, point.dy);
    right = math.max(right, point.dx);
    bottom = math.max(bottom, point.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

bool _hitPolyline(
  List<CanvasPoint> points,
  Offset target,
  Size size,
  double tolerance,
) {
  for (var index = 1; index < points.length; index++) {
    if (_distanceToSegment(
          target,
          canvasPointToOffset(points[index - 1], size),
          canvasPointToOffset(points[index], size),
        ) <=
        tolerance) {
      return true;
    }
  }
  return false;
}

double _distanceToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
  if (lengthSquared == 0) return (point - start).distance;
  final projection =
      ((point.dx - start.dx) * segment.dx +
          (point.dy - start.dy) * segment.dy) /
      lengthSquared;
  final t = projection.clamp(0.0, 1.0);
  final closest = Offset(start.dx + segment.dx * t, start.dy + segment.dy * t);
  return (point - closest).distance;
}
