import 'package:flutter/material.dart';

class CollaboratorCursorWidget extends StatelessWidget {
  const CollaboratorCursorWidget({
    super.key,
    required this.name,
    required this.color,
    required this.position,
  });

  final String name;
  final Color color;
  final Offset position;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF0A1317);
    return TweenAnimationBuilder<Offset>(
      tween: Tween<Offset>(begin: position, end: position),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      builder: (context, animPos, child) {
        return Positioned(left: animPos.dx, top: animPos.dy, child: child!);
      },
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Cursor Arrow
            CustomPaint(
              size: const Size(18, 20),
              painter: _CursorArrowPainter(color, colorScheme.outline),
            ),
            // User name banner
            Positioned(
              left: 10,
              top: 15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.26),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CursorArrowPainter extends CustomPainter {
  _CursorArrowPainter(this.color, this.borderColor);
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height * 0.6)
      ..lineTo(size.width * 0.45, size.height * 0.6)
      ..lineTo(size.width * 0.25, size.height)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CursorArrowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.borderColor != borderColor;
  }
}
