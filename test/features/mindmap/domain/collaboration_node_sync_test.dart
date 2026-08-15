import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/collaboration_node_sync.dart';

void main() {
  test('strict envelope accepts live node and rejects identity mismatch', () {
    final envelope = CollaborationNodeEnvelope.fromJson({
      'schemaVersion': 1,
      'remoteNodeId': 'node-1',
      'dayKey': '2026-07-28',
      'revision': 1,
      'deleted': false,
      'payload': {'id': 'node-1', 'day': '2026-07-28'},
      'createdByUid': 'owner',
      'updatedByUid': 'owner',
    });
    expect(envelope.revision, 1);
    expect(
      () => CollaborationNodeEnvelope.fromJson({
        ...envelope.toJson(),
        'payload': {'id': 'forged', 'day': '2026-07-28'},
      }),
      throwsFormatException,
    );
    expect(
      () => CollaborationNodeEnvelope.fromJson({
        ...envelope.toJson(),
        'extra': true,
      }),
      throwsFormatException,
    );
  });

  test('tombstone requires null payload', () {
    expect(
      CollaborationNodeEnvelope.fromJson({
        'schemaVersion': 1,
        'remoteNodeId': 'node-1',
        'dayKey': '2026-07-28',
        'revision': 2,
        'deleted': true,
        'payload': null,
        'createdByUid': 'owner',
        'updatedByUid': 'editor',
      }).deleted,
      isTrue,
    );
  });
}
