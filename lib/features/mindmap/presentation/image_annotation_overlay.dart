import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/application/image_annotation_controller.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';

class ImageAnnotationOverlay extends StatelessWidget {
  final ImageAnnotationData annotationData;
  final bool isAnnotating;
  final void Function(ImageAnnotationPin pin)? onPinTap;
  final void Function(Offset localOffset)? onTapToAddPin;
  final ImageAnnotationController? controller;
  final int strokeColorValue;
  final double strokeWidth;

  const ImageAnnotationOverlay({
    super.key,
    required this.annotationData,
    this.isAnnotating = false,
    this.onPinTap,
    this.onTapToAddPin,
    this.controller,
    this.strokeColorValue = 0xFFFF0000,
    this.strokeWidth = 3.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: isAnnotating && onTapToAddPin != null
              ? (details) => onTapToAddPin!(details.localPosition)
              : null,
          onPanStart: isAnnotating && controller != null
              ? (details) {
                  if (width <= 0 || height <= 0) return;
                  controller!.startStroke(
                    colorValue: strokeColorValue,
                    strokeWidth: strokeWidth,
                    xRatio: details.localPosition.dx / width,
                    yRatio: details.localPosition.dy / height,
                  );
                }
              : null,
          onPanUpdate: isAnnotating && controller != null
              ? (details) {
                  if (width <= 0 || height <= 0) return;
                  controller!.addPointToCurrentStroke(
                    xRatio: details.localPosition.dx / width,
                    yRatio: details.localPosition.dy / height,
                  );
                }
              : null,
          onPanEnd: isAnnotating && controller != null
              ? (_) => controller!.endStroke()
              : null,
          child: Stack(
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
                    behavior: HitTestBehavior.opaque,
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
          ),
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
      if (stroke.points.isEmpty) continue;

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
