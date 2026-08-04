import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/canvas_file_drop_handler.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';

void main() {
  const handler = CanvasFileDropHandler();
  final dummyBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0]);

  test('CanvasFileDropHandler classifies PNG bytes as image node', () async {
    final node = await handler.processDroppedFile(
      fileName: 'photo.png',
      bytes: dummyBytes,
      position: const CanvasPosition(100, 200),
      dayKey: '2026-08-04',
    );

    expect(node.type, NodeType.image);
    expect(node.position.dx, 100);
    expect(node.position.dy, 200);
  });

  test('CanvasFileDropHandler classifies audio file correctly', () async {
    final node = await handler.processDroppedFile(
      fileName: 'audio.mp3',
      bytes: dummyBytes,
      position: const CanvasPosition(0, 0),
      dayKey: '2026-08-04',
    );

    expect(node.type, NodeType.audio);
  });

  test('CanvasFileDropHandler classifies video file correctly', () async {
    final node = await handler.processDroppedFile(
      fileName: 'clip.mp4',
      bytes: dummyBytes,
      position: const CanvasPosition(0, 0),
      dayKey: '2026-08-04',
    );

    expect(node.type, NodeType.video);
  });

  test('CanvasFileDropHandler classifies unknown extension as link node', () async {
    final node = await handler.processDroppedFile(
      fileName: 'document.pdf',
      bytes: dummyBytes,
      position: const CanvasPosition(0, 0),
      dayKey: '2026-08-04',
    );

    expect(node.type, NodeType.link);
    expect(node.data['isLocalFile'], true);
  });
}
