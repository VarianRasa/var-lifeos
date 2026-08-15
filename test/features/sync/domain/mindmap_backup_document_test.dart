import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';

void main() {
  test('creates a versioned backup document with sorted node payloads', () {
    final later = _node(
      id: 'node-b',
      title: 'Later',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 18, 10),
    );
    final earlier = _node(
      id: 'node-a',
      title: 'Earlier',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 9),
    );

    final document = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(
        id: 'device-a',
        label: 'Work laptop',
      ),
      exportedAt: DateTime(2026, 6, 18, 12),
      nodes: [later, earlier],
    );

    expect(document.schemaVersion, 2);
    expect(document.type, 'var.mindmap.backup');
    expect(document.nodes.map((node) => node.id), ['node-a', 'node-b']);

    final json = document.toJson();
    expect(json['schemaVersion'], 2);
    expect(json['type'], 'var.mindmap.backup');
    expect(json['sourceDevice'], {'id': 'device-a', 'label': 'Work laptop'});
    expect((json['nodes'] as List).length, 2);
  });

  test('round trips backup JSON into domain nodes', () {
    final node = _node(
      id: 'note-1',
      title: 'Portable note',
      project: 'Launch App',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 9),
    );
    final document = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(
        id: 'device-a',
        label: 'Work laptop',
      ),
      exportedAt: DateTime(2026, 6, 18, 12),
      nodes: [node],
    );

    final restored = MindmapBackupDocument.fromJson(document.toJson());

    expect(restored.sourceDevice.id, 'device-a');
    expect(restored.exportedAt, DateTime(2026, 6, 18, 12));
    expect(restored.nodes, [node]);
  });

  test('rejects malformed and duplicate node entries', () {
    final node = _node(
      id: 'duplicate',
      title: 'Duplicate',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 9),
    ).toJson();
    final base = <String, Object?>{
      'type': 'var.mindmap.backup',
      'schemaVersion': 1,
      'exportedAt': DateTime(2026, 6, 18, 12).toIso8601String(),
      'sourceDevice': {'id': 'device-a', 'label': 'Work laptop'},
    };

    expect(
      () => MindmapBackupDocument.fromJson({
        ...base,
        'nodes': [node, node],
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MindmapBackupDocument.fromJson({
        ...base,
        'nodes': [null],
      }),
      throwsA(isA<FormatException>()),
    );
  });
  test('rejects invalid typed drawing payloads', () {
    final canvas = MindmapNode.create(
      id: 'canvas',
      type: NodeType.canvas,
      title: 'Canvas',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 9),
      data: <String, Object?>{
        'canvas': <String, Object?>{
          'elements': <Object?>[
            <String, Object?>{
              'id': 'stroke',
              'type': 'stroke',
              'color': 'blue',
              'points': List<Object?>.filled(
                maxDrawingPointsPerItem + 1,
                <String, Object?>{'x': 0.5, 'y': 0.5},
              ),
            },
          ],
        },
      },
    );
    final json = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      exportedAt: DateTime(2026, 6, 18, 12),
      nodes: const <MindmapNode>[],
    ).toJson();

    expect(
      () => MindmapBackupDocument.fromJson(<String, Object?>{
        ...json,
        'nodes': <Object?>[canvas.toJson()],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unsupported backup schemas', () {
    expect(
      () => MindmapBackupDocument.fromJson({
        'type': 'var.mindmap.backup',
        'schemaVersion': 99,
        'exportedAt': DateTime(2026, 6, 18, 12).toIso8601String(),
        'sourceDevice': {'id': 'device-a', 'label': 'Work laptop'},
        'nodes': const [],
      }),
      throwsA(isA<FormatException>()),
    );
  });
}

MindmapNode _node({
  required String id,
  required String title,
  required DateTime day,
  required DateTime now,
  String project = '',
}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    project: project,
    day: day,
    now: now,
  );
}
