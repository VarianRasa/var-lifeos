import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/local_node_attachment_repository_web.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/sync/application/mindmap_backup_service.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';

void main() {
  // Pipeline boundary: attachment payloads live beside nodes in the versioned
  // backup document. PortableMindmapBackupCodec encrypts that entire document
  // with the existing AES-GCM/PBKDF2 envelope.
  test('round-trips image and video metadata plus verified bytes', () async {
    final sourceAttachments = MemoryNodeAttachmentRepository(
      maxTotalBytes: 1024 * 1024,
    );
    final image = await sourceAttachments.importBytes(
      bytes: const [137, 80, 78, 71],
      fileName: 'cover.png',
      mimeType: 'image/png',
    );
    final video = await sourceAttachments.importBytes(
      bytes: const [0, 0, 0, 24],
      fileName: 'clip.mp4',
      mimeType: 'video/mp4',
    );
    final sourceNodes = InMemoryMindmapRepository(
      seedNodes: [
        _mediaNode('image', NodeType.image, image.id),
        _mediaNode('video', NodeType.video, video.id),
      ],
    );
    final targetNodes = InMemoryMindmapRepository();
    final targetAttachments = MemoryNodeAttachmentRepository(
      maxTotalBytes: 1024 * 1024,
    );
    final codec = _codec();
    final source = _service(sourceNodes, sourceAttachments, codec);
    final target = _service(targetNodes, targetAttachments, codec);

    final exported = await source.createPortableBackup(passphrase: 'secret');
    final report = await target.importPortableBackup(
      exported.package,
      passphrase: 'secret',
    );

    expect(exported.package, isNot(contains(base64Encode([137, 80, 78, 71]))));
    expect(report.warnings, isEmpty);
    expect(await targetAttachments.readBytes(image.id), [137, 80, 78, 71]);
    expect(await targetAttachments.readBytes(video.id), [0, 0, 0, 24]);
    expect(
      ImagePayload.fromNode((await targetNodes.getNode('image'))!).attachmentId,
      image.id,
    );
    expect(
      (await targetNodes.getNode('video'))?.data['attachmentId'],
      video.id,
    );
  });

  test('missing blob warns but preserves valid node data', () async {
    const missing = '00000000-0000-4000-8000-000000000099';
    final document = MindmapBackupDocument.create(
      sourceDevice: _device,
      exportedAt: _now,
      nodes: [_mediaNode('image', NodeType.image, missing)],
    );
    final nodes = InMemoryMindmapRepository();
    final attachments = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);

    final report = await _service(
      nodes,
      attachments,
      _codec(),
    ).importBackup(document);

    expect(report.savedNodeIds, ['image']);
    expect(report.warnings.single.attachmentId, missing);
    expect(
      ImagePayload.fromNode((await nodes.getNode('image'))!).attachmentId,
      missing,
    );
  });

  test(
    'corrupt attachment checksum fails before destructive restore',
    () async {
      final existing = _note('existing', 'Keep me');
      final nodes = InMemoryMindmapRepository(seedNodes: [existing]);
      final attachments = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
      final valid = await MemoryNodeAttachmentRepository(maxTotalBytes: 1024)
          .importBytes(
            bytes: const [1, 2, 3],
            fileName: 'photo.png',
            mimeType: 'image/png',
          );
      final corrupt = MindmapBackupAttachment(
        version: 1,
        attachment: valid,
        payload: base64Encode(const [9, 9, 9]),
      );
      final document = MindmapBackupDocument.create(
        sourceDevice: _device,
        exportedAt: _now,
        nodes: [_note('replacement', 'Replacement')],
        attachments: [corrupt],
      );

      await expectLater(
        _service(nodes, attachments, _codec()).importBackup(document),
        throwsA(isA<PortableBackupException>()),
      );

      expect((await nodes.getNode('existing'))?.title, 'Keep me');
      expect(await nodes.getNode('replacement'), isNull);
      expect(await attachments.buildManifest(), isEmpty);
    },
  );

  test('duplicate attachment id and traversal filename are rejected', () {
    final valid = {
      'version': 1,
      'attachment': {
        'id': '00000000-0000-4000-8000-000000000001',
        'fileName': 'safe.png',
        'mimeType': 'image/png',
        'byteLength': 1,
        'checksum': '00',
        'createdAt': _now.toIso8601String(),
      },
      'payload': base64Encode([0]),
    };
    final duplicate = MindmapBackupDocument.create(
      sourceDevice: _device,
      exportedAt: _now,
      nodes: const [],
    ).toJson()..['attachments'] = [valid, valid];
    expect(
      () => MindmapBackupDocument.fromJson(duplicate),
      throwsFormatException,
    );

    final traversal = Map<String, Object?>.from(valid);
    traversal['attachment'] = Map<String, Object?>.from(
      valid['attachment']! as Map<String, Object?>,
    )..['fileName'] = '../escape.png';
    final document = MindmapBackupDocument.fromJson(
      MindmapBackupDocument.create(
        sourceDevice: _device,
        exportedAt: _now,
        nodes: const [],
      ).toJson()..['attachments'] = [traversal],
    );
    final target = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
    expect(
      () => _service(
        InMemoryMindmapRepository(),
        target,
        _codec(),
      ).importBackup(document),
      throwsA(isA<PortableBackupException>()),
    );
  });

  test(
    'legacy schema version one without attachments still restores',
    () async {
      final legacy =
          MindmapBackupDocument.create(
              sourceDevice: _device,
              exportedAt: _now,
              nodes: [_note('legacy', 'Legacy note')],
            ).toJson()
            ..['schemaVersion'] = 1
            ..remove('attachments');
      final document = MindmapBackupDocument.fromJson(legacy);
      final nodes = InMemoryMindmapRepository();

      final report = await _service(
        nodes,
        MemoryNodeAttachmentRepository(maxTotalBytes: 1024),
        _codec(),
      ).importBackup(document);

      expect(report.savedNodeIds, ['legacy']);
      expect((await nodes.getNode('legacy'))?.title, 'Legacy note');
    },
  );
}

const _device = SyncDeviceIdentity(id: 'device-a', label: 'Laptop');
final _now = DateTime.utc(2026, 7, 14, 8);

MindmapBackupService _service(
  InMemoryMindmapRepository nodes,
  MemoryNodeAttachmentRepository attachments,
  PortableMindmapBackupCodec codec,
) {
  return MindmapBackupService(
    repository: nodes,
    sourceDevice: _device,
    now: () => _now,
    portableCodec: codec,
    attachmentRepository: attachments,
  );
}

PortableMindmapBackupCodec _codec() => PortableMindmapBackupCodec(
  iterations: PortableMindmapBackupCodec.minKdfIterations,
  randomBytes: (length) => List<int>.generate(length, (index) => index + 1),
);

MindmapNode _mediaNode(String id, NodeType type, String attachmentId) {
  return MindmapNode.create(
    id: id,
    type: type,
    title: id,
    day: _now,
    now: _now,
  ).copyWith(
    data: type == NodeType.image
        ? ImagePayload(attachmentId: attachmentId).toData()
        : {'attachmentId': attachmentId},
  );
}

MindmapNode _note(String id, String title) => MindmapNode.create(
  id: id,
  type: NodeType.note,
  title: title,
  day: _now,
  now: _now,
);
