import 'package:flutter/material.dart';

enum ImageCropShape { rectangle, rounded, circle }

class ImageCropMaskWidget extends StatelessWidget {
  final String imageUrl;
  final ImageCropShape shape;
  final double width;
  final double height;

  const ImageCropMaskWidget({
    super.key,
    required this.imageUrl,
    this.shape = ImageCropShape.rounded,
    this.width = 240,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    BoxShape boxShape = BoxShape.rectangle;
    BorderRadius? borderRadius;

    if (shape == ImageCropShape.circle) {
      boxShape = BoxShape.circle;
    } else if (shape == ImageCropShape.rounded) {
      borderRadius = BorderRadius.circular(16);
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(shape: boxShape, borderRadius: borderRadius),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: Colors.grey.shade800,
          child: const Icon(Icons.image, color: Colors.white54),
        ),
      ),
    );
  }
}
