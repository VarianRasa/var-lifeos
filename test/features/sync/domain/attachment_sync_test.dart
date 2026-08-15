import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/sync/domain/attachment_sync.dart';

void main() {
  test('plans canonical upload metadata without bytes or local path', () {
    final plan = const AttachmentSyncPlanner().plan(
      nodes: [_node(_assetA)],
      localManifest: [_entry(_assetA, _checksumA)],
    );
    final item = plan.workItems.single;
    expect(item.direction, AttachmentSyncDirection.upload);
    expect(item.metadata.remoteObjectKey, 'attachments/$_assetA');
    expect(item.metadata.checksum, _checksumA);
    expect(item.toJson().toString(), isNot(contains('localPath')));
    expect(item.toJson().toString(), isNot(contains('bytes')));
  });

  test('normalizes uppercase SHA-256 and plans canonical download', () {
    final plan = const AttachmentSyncPlanner().plan(
      nodes: [_node(_assetA)],
      localManifest: const [],
      remoteManifest: [_remote(_assetA, _checksumA.toUpperCase())],
    );
    expect(plan.workItems.single.direction, AttachmentSyncDirection.download);
    expect(plan.workItems.single.metadata.checksum, _checksumA);
  });

  test('rejects traversal, schemes, query, fragment, and key mismatch', () {
    final invalidKeys = [
      '../$_assetA',
      r'attachments\asset',
      'https://example.test/$_assetA',
      'attachments/$_assetA?download=1',
      'attachments/$_assetA#fragment',
      'attachments/$_assetB',
      '/attachments/$_assetA',
    ];
    for (final key in invalidKeys) {
      final plan = const AttachmentSyncPlanner().plan(
        nodes: [_node(_assetA)],
        localManifest: const [],
        remoteManifest: [_remote(_assetA, _checksumA, key: key)],
      );
      expect(plan.workItems, isEmpty, reason: key);
      expect(plan.warnings, isNotEmpty, reason: key);
    }
  });

  test('rejects malformed local and remote checksums with warnings', () {
    final plan = const AttachmentSyncPlanner().plan(
      nodes: [_node(_assetA), _node(_assetB)],
      localManifest: [_entry(_assetA, 'bad')],
      remoteManifest: [_remote(_assetB, '1234')],
    );
    expect(plan.workItems, isEmpty);
    expect(plan.warnings, hasLength(2));
  });

  test('checksum mismatch creates conflict and no transfer work', () {
    final plan = const AttachmentSyncPlanner().plan(
      nodes: [_node(_assetA)],
      localManifest: [_entry(_assetA, _checksumA)],
      remoteManifest: [_remote(_assetA, _checksumB)],
    );
    expect(plan.workItems, isEmpty);
    expect(
      plan.conflicts.single.kind,
      AttachmentSyncConflictKind.checksumMismatch,
    );
    expect(plan.conflicts.single.attachmentId, _assetA);
  });

  test('same checksum with size mismatch creates metadata conflict', () {
    final remote = _remote(_assetA, _checksumA)..['byteLength'] = 99;
    final plan = const AttachmentSyncPlanner().plan(
      nodes: [_node(_assetA)],
      localManifest: [_entry(_assetA, _checksumA)],
      remoteManifest: [remote],
    );
    expect(plan.workItems, isEmpty);
    expect(
      plan.conflicts.single.kind,
      AttachmentSyncConflictKind.metadataMismatch,
    );
    expect(plan.warnings, isNotEmpty);
  });

  test('same checksum with MIME mismatch creates metadata conflict', () {
    final remote = _remote(_assetA, _checksumA)..['mimeType'] = 'video/mp4';
    final plan = const AttachmentSyncPlanner().plan(
      nodes: [_node(_assetA)],
      localManifest: [_entry(_assetA, _checksumA)],
      remoteManifest: [remote],
    );
    expect(plan.workItems, isEmpty);
    expect(
      plan.conflicts.single.kind,
      AttachmentSyncConflictKind.metadataMismatch,
    );
    expect(plan.warnings, isNotEmpty);
  });

  test('MIME comparison normalizes case and surrounding space', () {
    final remote = _remote(_assetA, _checksumA)..['mimeType'] = ' IMAGE/PNG ';
    final plan = const AttachmentSyncPlanner().plan(
      nodes: [_node(_assetA)],
      localManifest: [_entry(_assetA, _checksumA)],
      remoteManifest: [remote],
    );
    expect(plan.workItems, isEmpty);
    expect(plan.conflicts, isEmpty);
  });

  test(
    'identical duplicates dedupe while conflicting duplicates block work',
    () {
      final identical = const AttachmentSyncPlanner().plan(
        nodes: [_node(_assetA)],
        localManifest: const [],
        remoteManifest: [
          _remote(_assetA, _checksumA),
          _remote(_assetA, _checksumA),
        ],
      );
      expect(identical.workItems, hasLength(1));
      expect(identical.conflicts, isEmpty);

      final conflicting = const AttachmentSyncPlanner().plan(
        nodes: [_node(_assetA)],
        localManifest: const [],
        remoteManifest: [
          _remote(_assetA, _checksumA),
          _remote(_assetA, _checksumB),
        ],
      );
      expect(conflicting.workItems, isEmpty);
      expect(
        conflicting.conflicts.single.kind,
        AttachmentSyncConflictKind.duplicateMetadata,
      );
    },
  );

  test('work and conflict output is stable sorted', () {
    final plan = const AttachmentSyncPlanner().plan(
      nodes: [_node(_assetC), _node(_assetA), _node(_assetB)],
      localManifest: [_entry(_assetC, _checksumA), _entry(_assetA, _checksumA)],
      remoteManifest: [_remote(_assetB, _checksumA)],
    );
    expect(plan.workItems.map((item) => item.metadata.attachmentId), [
      _assetA,
      _assetB,
      _assetC,
    ]);
    expect(AttachmentSyncDirection.values, [
      AttachmentSyncDirection.upload,
      AttachmentSyncDirection.download,
    ]);
  });

  test('malformed metadata type is ignored safely', () {
    final plan = const AttachmentSyncPlanner().plan(
      nodes: const [],
      localManifest: const [],
      remoteManifest: const [
        {'attachmentId': 1, 'localPath': 'secret'},
      ],
    );
    expect(plan.workItems, isEmpty);
    expect(plan.warnings, hasLength(1));
  });
}

MindmapNode _node(String attachmentId) =>
    MindmapNode.create(
      id: 'node-$attachmentId',
      type: NodeType.image,
      title: 'Image',
      day: DateTime(2026, 7, 14),
      now: DateTime(2026, 7, 14),
    ).copyWith(
      data: {
        'image': {'attachmentId': attachmentId},
      },
    );

NodeAttachmentManifestEntry _entry(String id, String checksum) =>
    NodeAttachmentManifestEntry(
      version: nodeAttachmentManifestVersion,
      attachment: NodeAttachment(
        id: id,
        fileName: 'image.png',
        mimeType: 'image/png',
        byteLength: 42,
        checksum: checksum,
        createdAt: DateTime(2026, 7, 14),
      ),
    );

Map<String, Object?> _remote(String id, String checksum, {String? key}) => {
  'attachmentId': id,
  'checksum': checksum,
  'byteLength': 42,
  'mimeType': 'image/png',
  'remoteObjectKey': key ?? 'attachments/$id',
};

const _assetA = '123e4567-e89b-42d3-a456-426614174000';
const _assetB = '123e4567-e89b-42d3-a456-426614174001';
const _assetC = '123e4567-e89b-42d3-a456-426614174002';
const _checksumA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _checksumB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
