import 'package:flutter/material.dart';

class MinimapNodeDot {
  final double x;
  final double y;
  final Color color;

  const MinimapNodeDot({
    required this.x,
    required this.y,
    this.color = Colors.blue,
  });
}

class CanvasMinimapWidget extends StatelessWidget {
  final List<MinimapNodeDot> nodeDots;
  final Rect viewportRect;
  final ValueChanged<Offset>? onTapMinimap;

  const CanvasMinimapWidget({
    super.key,
    required this.nodeDots,
    required this.viewportRect,
    this.onTapMinimap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 140,
      height: 100,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: GestureDetector(
        onTapDown: (details) => onTapMinimap?.call(details.localPosition),
        child: CustomPaint(
          painter: _MinimapPainter(
            dots: nodeDots,
            viewport: viewportRect,
            accentColor: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final List<MinimapNodeDot> dots;
  final Rect viewport;
  final Color accentColor;

  _MinimapPainter({
    required this.dots,
    required this.viewport,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (final dot in dots) {
      dotPaint.color = dot.color;
      final dx = (dot.x / 2000 * size.width).clamp(2.0, size.width - 2);
      final dy = (dot.y / 2000 * size.height).clamp(2.0, size.height - 2);
      canvas.drawCircle(Offset(dx, dy), 2, dotPaint);
    }

    final vpPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    final vpBorder = Paint()
      ..color = accentColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(
      (viewport.left / 2000 * size.width).clamp(0.0, size.width - 30),
      (viewport.top / 2000 * size.height).clamp(0.0, size.height - 20),
      30,
      20,
    );

    canvas.drawRect(rect, vpPaint);
    canvas.drawRect(rect, vpBorder);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) => true;
}
