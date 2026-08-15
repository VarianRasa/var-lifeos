import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';

void main() {
  test('new media and travel node types keep stable names and labels', () {
    expect(NodeType.itinerary.name, 'itinerary');
    expect(NodeType.itinerary.label, 'Itinerary');
    expect(NodeType.image.name, 'image');
    expect(NodeType.image.label, 'Image');
    expect(NodeType.video.name, 'video');
    expect(NodeType.video.label, 'Video');
  });

  test(
    'new node types append without shifting existing serialized indexes',
    () {
      expect(NodeType.empty.index, 26);
      expect(NodeType.values.sublist(27), [
        NodeType.itinerary,
        NodeType.image,
        NodeType.video,
        NodeType.frame,
        NodeType.swatch,
      ]);
    },
  );
}
