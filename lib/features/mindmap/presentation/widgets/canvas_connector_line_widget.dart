import 'package:flutter/material.dart';

enum ConnectorLineStyle { straight, curved, orthogonal }

class ConnectorLineData {
  final Offset start;
  final Offset end;
  final String label;
  final ConnectorLineStyle style;
  final bool hasArrow;

  const ConnectorLineData({
    required this.start,
    required this.end,
    this.label = '',
    this.style = ConnectorLineStyle.curved,
    this.hasArrow = true,
  });
}

class CanvasConnectorLineWidget extends StatelessWidget {
  final ConnectorLineData line;

  const CanvasConnectorLineWidget({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final midX = (line.start.dx + line.end.dx) / 2;
    final midY = (line.start.dy + line.end.dy) / 2;

    return Stack(
      children: [
        CustomPaint(
          size: Size.infinite,
          painter: _ConnectorPainter(
            line: line,
            color: theme.colorScheme.primary,
          ),
        ),
        if (line.label.isNotEmpty)
          Positioned(
            left: midX - 40,
            top: midY - 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                line.label,
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  final ConnectorLineData line;
  final Color color;

  _ConnectorPainter({required this.line, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(line.start.dx, line.start.dy);

    if (line.style == ConnectorLineStyle.straight) {
      path.lineTo(line.end.dx, line.end.dy);
    } else if (line.style == ConnectorLineStyle.orthogonal) {
      final midX = (line.start.dx + line.end.dx) / 2;
      path.lineTo(midX, line.start.dy);
      path.lineTo(midX, line.end.dy);
      path.lineTo(line.end.dx, line.end.dy);
    } else {
      final controlX = (line.start.dx + line.end.dx) / 2;
      path.cubicTo(
        controlX,
        line.start.dy,
        controlX,
        line.end.dy,
        line.end.dx,
        line.end.dy,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) => true;
}
