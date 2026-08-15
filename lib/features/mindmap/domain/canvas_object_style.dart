enum CanvasShapeKind {
  rectangle,
  roundedRectangle,
  ellipse,
  triangle,
  diamond,
  parallelogram,
  trapezoid,
  pentagon,
  hexagon,
  star,
  arrow,
  callout,
  cloud,
}

enum CanvasConnectorStyle { straight, curved, elbow }

enum CanvasLinePattern { solid, dashed, dotted }

enum CanvasArrowhead { none, open, filled, diamond, circle }

enum CanvasPenStyle { pen, highlighter }

enum CanvasTextHorizontalAlign { left, center, right }

enum CanvasTextVerticalAlign { top, center, bottom }

final class CanvasTextStyle {
  const CanvasTextStyle({
    this.fontSize = 24,
    this.isBold = false,
    this.isItalic = false,
    this.horizontalAlign = CanvasTextHorizontalAlign.left,
    this.verticalAlign = CanvasTextVerticalAlign.top,
    this.textColor = '#FFFFFF',
    this.padding = 12,
  });

  factory CanvasTextStyle.fromPayload(Map<String, Object?> payload) =>
      CanvasTextStyle(
        fontSize: _number(payload['fontSize'], 24, 8, 96),
        isBold: payload['fontWeight'] == 'bold' || payload['isBold'] == true,
        isItalic:
            payload['fontStyle'] == 'italic' || payload['isItalic'] == true,
        horizontalAlign: _enumValue(
          CanvasTextHorizontalAlign.values,
          payload['textAlign'],
          CanvasTextHorizontalAlign.left,
        ),
        verticalAlign: _enumValue(
          CanvasTextVerticalAlign.values,
          payload['verticalAlign'],
          CanvasTextVerticalAlign.top,
        ),
        textColor: _color(payload['textColor'], '#FFFFFF'),
        padding: _number(payload['textPadding'], 12, 0, 48),
      );

  final double fontSize;
  final bool isBold;
  final bool isItalic;
  final CanvasTextHorizontalAlign horizontalAlign;
  final CanvasTextVerticalAlign verticalAlign;
  final String textColor;
  final double padding;

  CanvasTextStyle copyWith({
    double? fontSize,
    bool? isBold,
    bool? isItalic,
    CanvasTextHorizontalAlign? horizontalAlign,
    CanvasTextVerticalAlign? verticalAlign,
    String? textColor,
    double? padding,
  }) => CanvasTextStyle(
    fontSize: fontSize ?? this.fontSize,
    isBold: isBold ?? this.isBold,
    isItalic: isItalic ?? this.isItalic,
    horizontalAlign: horizontalAlign ?? this.horizontalAlign,
    verticalAlign: verticalAlign ?? this.verticalAlign,
    textColor: textColor ?? this.textColor,
    padding: padding ?? this.padding,
  );

  Map<String, Object?> toPayload() => <String, Object?>{
    'fontSize': fontSize,
    'fontWeight': isBold ? 'bold' : 'normal',
    'fontStyle': isItalic ? 'italic' : 'normal',
    'textAlign': horizontalAlign.name,
    'verticalAlign': verticalAlign.name,
    'textColor': textColor,
    'textPadding': padding,
  };
}

final class CanvasShapeStyle {
  const CanvasShapeStyle({
    this.kind = CanvasShapeKind.roundedRectangle,
    this.fillColor = '#4F7CFF',
    this.borderColor = '#FFFFFF',
    this.borderWidth = 1,
    this.opacity = 1,
  });

  factory CanvasShapeStyle.fromPayload(Map<String, Object?> payload) =>
      CanvasShapeStyle(
        kind: _enumValue(
          CanvasShapeKind.values,
          payload['shape'],
          CanvasShapeKind.roundedRectangle,
        ),
        fillColor: _color(payload['fillColor'], '#4F7CFF'),
        borderColor: _color(payload['borderColor'], '#FFFFFF'),
        borderWidth: _number(payload['borderWidth'], 1, 0, 12),
        opacity: _number(payload['opacity'], 1, 0.1, 1),
      );

  final CanvasShapeKind kind;
  final String fillColor;
  final String borderColor;
  final double borderWidth;
  final double opacity;

  Map<String, Object?> toPayload() => <String, Object?>{
    'shape': kind.name,
    'fillColor': fillColor,
    'borderColor': borderColor,
    'borderWidth': borderWidth,
    'opacity': opacity,
  };
}

final class CanvasConnectorAppearance {
  const CanvasConnectorAppearance({
    this.style = CanvasConnectorStyle.elbow,
    this.pattern = CanvasLinePattern.solid,
    this.startArrow = CanvasArrowhead.none,
    this.endArrow = CanvasArrowhead.open,
    this.strokeColor = '#4F7CFF',
    this.strokeWidth = 3,
    this.opacity = 1,
    this.label = '',
  });

  factory CanvasConnectorAppearance.fromPayload(Map<String, Object?> payload) =>
      CanvasConnectorAppearance(
        style: _enumValue(
          CanvasConnectorStyle.values,
          payload['connectorStyle'],
          CanvasConnectorStyle.elbow,
        ),
        pattern: _enumValue(
          CanvasLinePattern.values,
          payload['linePattern'],
          CanvasLinePattern.solid,
        ),
        startArrow: _enumValue(
          CanvasArrowhead.values,
          payload['startArrow'],
          CanvasArrowhead.none,
        ),
        endArrow: payload['endArrow'] == null && payload['arrowEnd'] == false
            ? CanvasArrowhead.none
            : _enumValue(
                CanvasArrowhead.values,
                payload['endArrow'],
                CanvasArrowhead.open,
              ),
        strokeColor: _color(
          payload['strokeColor'] ?? payload['fillColor'],
          '#4F7CFF',
        ),
        strokeWidth: _number(payload['strokeWidth'], 3, 1, 24),
        opacity: _number(payload['opacity'], 1, 0.1, 1),
        label: (payload['label'] as String? ?? '').trim(),
      );

  final CanvasConnectorStyle style;
  final CanvasLinePattern pattern;
  final CanvasArrowhead startArrow;
  final CanvasArrowhead endArrow;
  final String strokeColor;
  final double strokeWidth;
  final double opacity;
  final String label;

  CanvasConnectorAppearance copyWith({
    CanvasConnectorStyle? style,
    CanvasLinePattern? pattern,
    CanvasArrowhead? startArrow,
    CanvasArrowhead? endArrow,
    String? strokeColor,
    double? strokeWidth,
    double? opacity,
    String? label,
  }) => CanvasConnectorAppearance(
    style: style ?? this.style,
    pattern: pattern ?? this.pattern,
    startArrow: startArrow ?? this.startArrow,
    endArrow: endArrow ?? this.endArrow,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    opacity: opacity ?? this.opacity,
    label: label ?? this.label,
  );

  Map<String, Object?> toPayload() => <String, Object?>{
    'connectorStyle': style.name,
    'linePattern': pattern.name,
    'startArrow': startArrow.name,
    'endArrow': endArrow.name,
    'strokeColor': strokeColor,
    'strokeWidth': strokeWidth,
    'opacity': opacity,
    if (label.isNotEmpty) 'label': label,
  };
}

final class CanvasPenAppearance {
  const CanvasPenAppearance({
    this.style = CanvasPenStyle.pen,
    this.strokeColor = '#4F7CFF',
    this.strokeWidth = 3,
    this.opacity = 1,
    this.smoothing = 0.5,
  });

  factory CanvasPenAppearance.fromPayload(Map<String, Object?> payload) =>
      CanvasPenAppearance(
        style: _enumValue(
          CanvasPenStyle.values,
          payload['penStyle'],
          CanvasPenStyle.pen,
        ),
        strokeColor: _color(
          payload['strokeColor'] ?? payload['fillColor'],
          _legacyNamedColor(payload['color']) ?? '#4F7CFF',
        ),
        strokeWidth: _number(payload['strokeWidth'], 3, 1, 48),
        opacity: _number(payload['opacity'], 1, 0.05, 1),
        smoothing: _number(payload['smoothing'], 0.5, 0, 1),
      );

  final CanvasPenStyle style;
  final String strokeColor;
  final double strokeWidth;
  final double opacity;
  final double smoothing;

  CanvasPenAppearance copyWith({
    CanvasPenStyle? style,
    String? strokeColor,
    double? strokeWidth,
    double? opacity,
    double? smoothing,
  }) => CanvasPenAppearance(
    style: style ?? this.style,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    opacity: opacity ?? this.opacity,
    smoothing: smoothing ?? this.smoothing,
  );

  Map<String, Object?> toPayload() => <String, Object?>{
    'penStyle': style.name,
    'strokeColor': strokeColor,
    'strokeWidth': strokeWidth,
    'opacity': opacity,
    'smoothing': smoothing,
  };
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

double _number(Object? raw, double fallback, double minimum, double maximum) {
  if (raw is! num || !raw.isFinite) return fallback;
  return raw.toDouble().clamp(minimum, maximum);
}

String _color(Object? raw, String fallback) {
  if (raw is! String) return fallback;
  final value = raw.trim().toUpperCase();
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(value) ? value : fallback;
}

String? _legacyNamedColor(Object? raw) => switch (raw) {
  'blue' => '#4F7CFF',
  'green' => '#4CAF50',
  'rose' => '#F05B78',
  'amber' => '#FFC247',
  _ => null,
};
