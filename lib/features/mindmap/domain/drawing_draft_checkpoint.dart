import 'dart:convert';

import 'mindmap_node.dart';
import 'node_type_payloads.dart';

enum DrawingDraftStatus { recoverable, stale, orphan }

final class DrawingDraftCheckpoint {
  DrawingDraftCheckpoint({
    required this.nodeId,
    required this.baseUpdatedAt,
    required this.generation,
    required this.data,
    required this.updatedAt,
  }) {
    if (nodeId.trim().isEmpty) throw ArgumentError.value(nodeId, 'nodeId');
    if (generation < 1) throw RangeError.value(generation, 'generation');
    final encoded = utf8.encode(jsonEncode(data));
    if (encoded.length > maxDrawingSerializedPayloadBytes) {
      throw const FormatException('Canvas payload exceeds size limit.');
    }
  }

  factory DrawingDraftCheckpoint.fromJson(Map<String, Object?> json) {
    final nodeId = json['nodeId'];
    final baseUpdatedAt = json['baseUpdatedAt'];
    final generation = json['generation'];
    final data = json['data'];
    final updatedAt = json['updatedAt'];
    if (nodeId is! String ||
        baseUpdatedAt is! String ||
        generation is! int ||
        data is! Map ||
        updatedAt is! String) {
      throw const FormatException('Invalid drawing draft checkpoint.');
    }
    return DrawingDraftCheckpoint(
      nodeId: nodeId,
      baseUpdatedAt: DateTime.parse(baseUpdatedAt),
      generation: generation,
      data: Map<String, Object?>.from(data),
      updatedAt: DateTime.parse(updatedAt),
    );
  }

  final String nodeId;
  final DateTime baseUpdatedAt;
  final int generation;
  final Map<String, Object?> data;
  final DateTime updatedAt;

  DrawingDraftStatus statusFor(MindmapNode? node) {
    if (node == null) return DrawingDraftStatus.orphan;
    return node.updatedAt == baseUpdatedAt
        ? DrawingDraftStatus.recoverable
        : DrawingDraftStatus.stale;
  }

  List<String> validateFor(MindmapNode node) => CanvasPayload.fromNode(
    node.copyWith(data: data),
  ).validate(title: node.title);

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeId': nodeId,
    'baseUpdatedAt': baseUpdatedAt.toIso8601String(),
    'generation': generation,
    'data': data,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
