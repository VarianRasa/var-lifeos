class ImageAnnotationPoint {
  final double xRatio;
  final double yRatio;

  const ImageAnnotationPoint({required this.xRatio, required this.yRatio})
    : assert(xRatio >= 0 && xRatio <= 1),
      assert(yRatio >= 0 && yRatio <= 1);

  Map<String, dynamic> toJson() => {'xRatio': xRatio, 'yRatio': yRatio};

  factory ImageAnnotationPoint.fromJson(Map<String, dynamic> json) =>
      ImageAnnotationPoint(
        xRatio: (json['xRatio'] as num).toDouble(),
        yRatio: (json['yRatio'] as num).toDouble(),
      );
}

class ImageAnnotationPin {
  final String id;
  final double xRatio;
  final double yRatio;
  final String text;
  final String? createdAt;

  const ImageAnnotationPin({
    required this.id,
    required this.xRatio,
    required this.yRatio,
    required this.text,
    this.createdAt,
  }) : assert(xRatio >= 0 && xRatio <= 1),
       assert(yRatio >= 0 && yRatio <= 1);

  Map<String, dynamic> toJson() => {
    'id': id,
    'xRatio': xRatio,
    'yRatio': yRatio,
    'text': text,
    'createdAt': createdAt ?? DateTime.now().toIso8601String(),
  };

  factory ImageAnnotationPin.fromJson(Map<String, dynamic> json) =>
      ImageAnnotationPin(
        id: json['id'] as String,
        xRatio: (json['xRatio'] as num).toDouble(),
        yRatio: (json['yRatio'] as num).toDouble(),
        text: json['text'] as String,
        createdAt: json['createdAt'] as String?,
      );
}

class ImageAnnotationStroke {
  final int colorValue;
  final double strokeWidth;
  final List<ImageAnnotationPoint> points;

  const ImageAnnotationStroke({
    required this.colorValue,
    required this.strokeWidth,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
    'color': colorValue,
    'strokeWidth': strokeWidth,
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory ImageAnnotationStroke.fromJson(Map<String, dynamic> json) =>
      ImageAnnotationStroke(
        colorValue: json['color'] as int,
        strokeWidth: (json['strokeWidth'] as num).toDouble(),
        points: ((json['points'] as List?) ?? [])
            .map(
              (p) => ImageAnnotationPoint.fromJson(p as Map<String, dynamic>),
            )
            .toList(),
      );
}

class ImageAnnotationData {
  final List<ImageAnnotationPin> pins;
  final List<ImageAnnotationStroke> strokes;

  const ImageAnnotationData({this.pins = const [], this.strokes = const []});

  Map<String, dynamic> toJson() => {
    'pins': pins.map((p) => p.toJson()).toList(),
    'strokes': strokes.map((s) => s.toJson()).toList(),
  };

  factory ImageAnnotationData.fromJson(Map<String, dynamic> json) {
    return ImageAnnotationData(
      pins: ((json['pins'] as List?) ?? [])
          .map((p) => ImageAnnotationPin.fromJson(p as Map<String, dynamic>))
          .toList(),
      strokes: ((json['strokes'] as List?) ?? [])
          .map((s) => ImageAnnotationStroke.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
