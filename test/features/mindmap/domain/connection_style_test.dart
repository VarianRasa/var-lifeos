import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/connection_style.dart';

void main() {
  test('ConnectionStyle json serialization & copyWith', () {
    const style = ConnectionStyle(
      lineType: ConnectionLineType.orthogonal,
      linePattern: ConnectionLinePattern.dashed,
      arrowhead: ConnectionArrowhead.both,
      colorHex: '#6366F1',
      strokeWidth: 3.0,
      label: 'Depends on',
    );

    final json = style.toJson();
    expect(json['lineType'], 'orthogonal');
    expect(json['linePattern'], 'dashed');
    expect(json['arrowhead'], 'both');
    expect(json['colorHex'], '#6366F1');
    expect(json['strokeWidth'], 3.0);
    expect(json['label'], 'Depends on');

    final parsed = ConnectionStyle.fromJson(json);
    expect(parsed, equals(style));

    final copy = style.copyWith(linePattern: ConnectionLinePattern.solid);
    expect(copy.linePattern, ConnectionLinePattern.solid);
    expect(copy.lineType, ConnectionLineType.orthogonal);
  });
}
