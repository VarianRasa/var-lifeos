import 'mindmap_node.dart';

enum MindmapNodeRevisionKind { baseline, created, updated, deleted, restored }

final class MindmapNodeRevision {
  const MindmapNodeRevision({
    required this.id,
    required this.nodeId,
    required this.sequence,
    required this.kind,
    required this.recordedAt,
    required this.snapshot,
  });

  factory MindmapNodeRevision.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final nodeId = json['nodeId'];
    final sequence = json['sequence'];
    final kindName = json['kind'];
    final recordedAt = json['recordedAt'];
    final snapshotJson = json['snapshot'];
    if (id is! String ||
        id.isEmpty ||
        nodeId is! String ||
        nodeId.isEmpty ||
        sequence is! int ||
        sequence < 1 ||
        kindName is! String ||
        recordedAt is! String ||
        snapshotJson is! Map) {
      throw const FormatException('Invalid mindmap node revision JSON.');
    }
    final kinds = MindmapNodeRevisionKind.values.where(
      (value) => value.name == kindName,
    );
    if (kinds.length != 1) {
      throw const FormatException('Invalid mindmap node revision kind.');
    }
    final snapshot = MindmapNode.fromJson(snapshotJson.cast<String, Object?>());
    if (snapshot.id != nodeId) {
      throw const FormatException('Revision snapshot node ID does not match.');
    }
    return MindmapNodeRevision(
      id: id,
      nodeId: nodeId,
      sequence: sequence,
      kind: kinds.single,
      recordedAt: DateTime.parse(recordedAt),
      snapshot: snapshot,
    );
  }

  final String id;
  final String nodeId;
  final int sequence;
  final MindmapNodeRevisionKind kind;
  final DateTime recordedAt;
  final MindmapNode snapshot;

  Map<String, Object?> toJson() => {
    'id': id,
    'nodeId': nodeId,
    'sequence': sequence,
    'kind': kind.name,
    'recordedAt': recordedAt.toIso8601String(),
    'snapshot': snapshot.toJson(),
  };
}
