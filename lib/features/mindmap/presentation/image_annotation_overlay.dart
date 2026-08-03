import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';

class ImageAnnotationOverlay extends StatelessWidget {
  final ImageAnnotationData annotationData;
  final bool isAnnotating;
  final void Function(ImageAnnotationPin pin)? onPinTap;
  final void Function(Offset localOffset)? onTapToAddPin;

  const ImageAnnotationOverlay({
    super.key,
    required this.annotationData,
    this.isAnnotating = false,
    this.onPinTap,
    this.onTapToAddPin,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          children: [
            CustomPaint(
              size: Size(width, height),
              painter: _AnnotationPainter(annotationData: annotationData),
            ),
            for (var i = 0; i < annotationData.pins.length; i++) ...[
              Positioned(
                left: annotationData.pins[i].xRatio * width - 12,
                top: annotationData.pins[i].yRatio * height - 12,
                child: GestureDetector(
                  onTap: () => onPinTap?.call(annotationData.pins[i]),
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.amber,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final ImageAnnotationData annotationData;

  _AnnotationPainter({required this.annotationData});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in annotationData.strokes) {
      if (stroke.points.length < 2) continue;

      final paint = Paint()
        ..color = Color(stroke.colorValue)
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(
        stroke.points.first.xRatio * size.width,
        stroke.points.first.yRatio * size.height,
      );

      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(
          stroke.points[i].xRatio * size.width,
          stroke.points[i].yRatio * size.height,
        );
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
