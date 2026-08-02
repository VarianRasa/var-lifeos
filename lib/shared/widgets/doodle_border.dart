import 'dart:math' as math;

import 'package:flutter/material.dart';

Path buildDoodleBorderPath(Rect rect, {double radius = 20, double wobble = 2}) {
  if (rect.isEmpty) return Path();

  final r = math.min(radius, rect.shortestSide / 2).toDouble();
  final w = math.min(wobble, rect.shortestSide / 8).toDouble();
  final center = rect.center;

  return Path()
    ..moveTo(rect.left + r, rect.top + w)
    ..quadraticBezierTo(
      center.dx,
      rect.top - w,
      rect.right - r,
      rect.top + w * 0.3,
    )
    ..quadraticBezierTo(
      rect.right + w,
      rect.top + r,
      rect.right - w * 0.3,
      center.dy,
    )
    ..quadraticBezierTo(
      rect.right + w,
      rect.bottom - r,
      rect.right - r,
      rect.bottom - w,
    )
    ..quadraticBezierTo(
      center.dx,
      rect.bottom + w,
      rect.left + r,
      rect.bottom - w * 0.4,
    )
    ..quadraticBezierTo(
      rect.left - w,
      rect.bottom - r,
      rect.left + w * 0.4,
      center.dy,
    )
    ..quadraticBezierTo(
      rect.left - w,
      rect.top + r,
      rect.left + r,
      rect.top + w,
    )
    ..close();
}

class DoodleShapeBorder extends OutlinedBorder {
  const DoodleShapeBorder({
    super.side = BorderSide.none,
    this.radius = 20,
    this.wobble = 2,
  });

  final double radius;
  final double wobble;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  OutlinedBorder copyWith({BorderSide? side}) {
    return DoodleShapeBorder(
      side: side ?? this.side,
      radius: radius,
      wobble: wobble,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return buildDoodleBorderPath(
      rect.deflate(side.width),
      radius: radius,
      wobble: wobble,
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return buildDoodleBorderPath(rect, radius: radius, wobble: wobble);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;

    final paint = side.toPaint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      buildDoodleBorderPath(
        rect.deflate(side.width / 2),
        radius: radius,
        wobble: wobble,
      ),
      paint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return DoodleShapeBorder(
      side: side.scale(t),
      radius: radius * t,
      wobble: wobble * t,
    );
  }
}

class DoodleInputBorder extends InputBorder {
  const DoodleInputBorder({
    super.borderSide = BorderSide.none,
    this.radius = 18,
    this.wobble = 1.8,
  });

  final double radius;
  final double wobble;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  bool get isOutline => true;

  @override
  DoodleInputBorder copyWith({BorderSide? borderSide}) {
    return DoodleInputBorder(
      borderSide: borderSide ?? this.borderSide,
      radius: radius,
      wobble: wobble,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return buildDoodleBorderPath(
      rect.deflate(borderSide.width),
      radius: radius,
      wobble: wobble,
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return buildDoodleBorderPath(rect, radius: radius, wobble: wobble);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none || borderSide.width == 0) return;

    final paint = borderSide.toPaint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      buildDoodleBorderPath(
        rect.deflate(borderSide.width / 2),
        radius: radius,
        wobble: wobble,
      ),
      paint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return DoodleInputBorder(
      borderSide: borderSide.scale(t),
      radius: radius * t,
      wobble: wobble * t,
    );
  }
}

class DoodleBorderPainter extends CustomPainter {
  const DoodleBorderPainter({
    required this.color,
    this.width = 1.4,
    this.radius = 18,
    this.wobble = 2,
  });

  final Color color;
  final double width;
  final double radius;
  final double wobble;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || width == 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width;
    canvas.drawPath(
      buildDoodleBorderPath(Offset.zero & size, radius: radius, wobble: wobble),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant DoodleBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.width != width ||
        oldDelegate.radius != radius ||
        oldDelegate.wobble != wobble;
  }
}

class DoodleUnderlineDecoration extends Decoration {
  const DoodleUnderlineDecoration({
    required this.color,
    this.strokeWidth = 2,
    this.wobble = 1.2,
  });

  final Color color;
  final double strokeWidth;
  final double wobble;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _DoodleUnderlinePainter(
      color: color,
      strokeWidth: strokeWidth,
      wobble: wobble,
    );
  }
}

class _DoodleUnderlinePainter extends BoxPainter {
  const _DoodleUnderlinePainter({
    required this.color,
    required this.strokeWidth,
    required this.wobble,
  });

  final Color color;
  final double strokeWidth;
  final double wobble;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;

    final y = offset.dy + size.height - strokeWidth;
    final start = Offset(offset.dx + 2, y + wobble * 0.2);
    final mid = Offset(offset.dx + size.width / 2, y - wobble);
    final end = Offset(offset.dx + size.width - 2, y + wobble * 0.4);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth;

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }
}
