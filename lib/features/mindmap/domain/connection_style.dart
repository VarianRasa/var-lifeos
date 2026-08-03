enum ConnectionLineType { bezier, straight, orthogonal }

enum ConnectionLinePattern { solid, dashed, dotted }

enum ConnectionArrowhead { target, both, none }

class ConnectionStyle {
  final ConnectionLineType lineType;
  final ConnectionLinePattern linePattern;
  final ConnectionArrowhead arrowhead;
  final String? colorHex;
  final double strokeWidth;
  final String? label;

  const ConnectionStyle({
    this.lineType = ConnectionLineType.bezier,
    this.linePattern = ConnectionLinePattern.solid,
    this.arrowhead = ConnectionArrowhead.target,
    this.colorHex,
    this.strokeWidth = 2.0,
    this.label,
  });

  Map<String, dynamic> toJson() => {
        'lineType': lineType.name,
        'linePattern': linePattern.name,
        'arrowhead': arrowhead.name,
        'colorHex': colorHex,
        'strokeWidth': strokeWidth,
        'label': label,
      };

  factory ConnectionStyle.fromJson(Map<String, dynamic> json) {
    return ConnectionStyle(
      lineType: ConnectionLineType.values.firstWhere(
        (e) => e.name == json['lineType'],
        orElse: () => ConnectionLineType.bezier,
      ),
      linePattern: ConnectionLinePattern.values.firstWhere(
        (e) => e.name == json['linePattern'],
        orElse: () => ConnectionLinePattern.solid,
      ),
      arrowhead: ConnectionArrowhead.values.firstWhere(
        (e) => e.name == json['arrowhead'],
        orElse: () => ConnectionArrowhead.target,
      ),
      colorHex: json['colorHex'] as String?,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      label: json['label'] as String?,
    );
  }

  ConnectionStyle copyWith({
    ConnectionLineType? lineType,
    ConnectionLinePattern? linePattern,
    ConnectionArrowhead? arrowhead,
    String? colorHex,
    double? strokeWidth,
    String? label,
  }) {
    return ConnectionStyle(
      lineType: lineType ?? this.lineType,
      linePattern: linePattern ?? this.linePattern,
      arrowhead: arrowhead ?? this.arrowhead,
      colorHex: colorHex ?? this.colorHex,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionStyle &&
          runtimeType == other.runtimeType &&
          lineType == other.lineType &&
          linePattern == other.linePattern &&
          arrowhead == other.arrowhead &&
          colorHex == other.colorHex &&
          strokeWidth == other.strokeWidth &&
          label == other.label;

  @override
  int get hashCode =>
      lineType.hashCode ^
      linePattern.hashCode ^
      arrowhead.hashCode ^
      colorHex.hashCode ^
      strokeWidth.hashCode ^
      label.hashCode;
}
