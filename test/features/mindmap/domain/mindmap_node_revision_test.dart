import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_revision.dart';

void main() {
  test('strict JSON round trip validates snapshot node ID', () {
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.note,
      title: 'Note',
      day: DateTime(2026, 7, 28),
      now: DateTime(2026, 7, 28),
    );
    final revision = MindmapNodeRevision(
      id: 'node-1:1',
      nodeId: node.id,
      sequence: 1,
      kind: MindmapNodeRevisionKind.created,
      recordedAt: DateTime.utc(2026, 7, 28),
      snapshot: node,
    );

    final decoded = MindmapNodeRevision.fromJson(revision.toJson());

    expect(decoded.id, revision.id);
    expect(decoded.snapshot, node);
    expect(
      () => MindmapNodeRevision.fromJson({
        ...revision.toJson(),
        'nodeId': 'other',
      }),
      throwsFormatException,
    );
    expect(
      () => MindmapNodeRevision.fromJson({...revision.toJson(), 'sequence': 0}),
      throwsFormatException,
    );
  });
}
