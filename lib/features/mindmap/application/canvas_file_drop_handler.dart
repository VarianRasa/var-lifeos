import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../domain/canvas_position.dart';
import '../domain/mindmap_node.dart';
import '../domain/node_type_payloads.dart';

class CanvasFileDropHandler {
  const CanvasFileDropHandler();

  Future<MindmapNode> processDroppedFile({
    required String fileName,
    required Uint8List bytes,
    required CanvasPosition position,
    required String dayKey,
  }) async {
    final ext = p.extension(fileName).toLowerCase();
    final id = const Uuid().v4();
    final parsedDay = DateTime.parse(dayKey);

    NodeType type;
    Map<String, Object?> data = {};

    if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) {
      type = NodeType.image;
      data = ImagePayload(
        fileName: fileName,
        byteLength: bytes.length,
        url: '',
      ).toData();
    } else if (['.mp3', '.wav', '.aac', '.m4a', '.ogg'].contains(ext)) {
      type = NodeType.audio;
      data = AudioPayload(
        fileName: fileName,
        sizeBytes: bytes.length,
      ).toData({});
    } else if (['.mp4', '.mov', '.webm'].contains(ext)) {
      type = NodeType.video;
      data = VideoPayload(fileName: fileName).toData();
    } else {
      type = NodeType.link;
      data = {
        'title': fileName,
        'fileSize': bytes.length,
        'fileExtension': ext.replaceFirst('.', ''),
        'isLocalFile': true,
      };
    }

    return MindmapNode(
      id: id,
      day: parsedDay,
      type: type,
      title: fileName,
      position: position,
      data: data,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
