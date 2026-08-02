import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/local_node_attachment_repository_web.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/mindmap_backup_service.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/mindmap_sync_planner.dart';

void main() {
  test('exports repository nodes as a backup document', () async {
    final node = _node(
      id: 'note-1',
      title: 'Portable note',
      now: DateTime(2026, 6, 18, 9),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final service = MindmapBackupService(
      repository: repository,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );

    final document = await service.createBackup();

    expect(document.exportedAt, DateTime(2026, 6, 18, 12));
    expect(document.sourceDevice.id, 'device-a');
    expect(document.nodes, [node]);
  });

  test('cloud backup omits attachment payloads', () async {
    final attachments = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
    final attachment = await attachments.importBytes(
      bytes: const [1, 2, 3],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    final node = _node(
      id: 'image-1',
      title: 'Image',
      now: DateTime(2026, 6, 18, 9),
    ).copyWith(data: {'attachmentId': attachment.id});
    final service = MindmapBackupService(
      repository: InMemoryMindmapRepository(seedNodes: [node]),
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      attachmentRepository: attachments,
    );

    final cloud = await service.createCloudBackup();
    final portable = await service.createBackup();

    expect(cloud.nodes, [node]);
    expect(cloud.attachments, isEmpty);
    expect(cloud.warnings, isEmpty);
    expect(portable.attachments.single.attachment.id, attachment.id);
    expect(portable.attachments.single.decodePayload(), [1, 2, 3]);
  });

  test('cloud backup warns when attachment metadata is missing', () async {
    const missingId = '00000000-0000-4000-8000-000000000099';
    final node = _node(
      id: 'image-1',
      title: 'Image',
      now: DateTime(2026, 6, 18, 9),
    ).copyWith(data: {'attachmentId': missingId});
    final service = MindmapBackupService(
      repository: InMemoryMindmapRepository(seedNodes: [node]),
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      attachmentRepository: MemoryNodeAttachmentRepository(maxTotalBytes: 1024),
    );

    final cloud = await service.createCloudBackup();

    expect(cloud.attachments, isEmpty);
    expect(cloud.warnings.single.attachmentId, missingId);
  });

  test('imports a backup by applying remote saves and deletes', () async {
    final base = _node(
      id: 'shared',
      title: 'Shared',
      now: DateTime(2026, 6, 18, 9),
    );
    final stale = _node(
      id: 'stale',
      title: 'Remote deleted',
      now: DateTime(2026, 6, 18, 9),
    );
    final remote = base.copyWith(
      title: 'Shared from tablet',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [base, stale]);
    final service = MindmapBackupService(
      repository: repository,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final document = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Tablet'),
      exportedAt: DateTime(2026, 6, 18, 12),
      nodes: [remote],
    );

    final report = await service.importBackup(
      document,
      baselineNodes: [base, stale],
    );

    expect(report.blockedByConflicts, isFalse);
    expect(report.savedNodeIds, ['shared']);
    expect(report.deletedNodeIds, ['stale']);
    expect((await repository.getNode('shared'))?.title, 'Shared from tablet');
    expect(await repository.getNode('stale'), isNull);
  });

  test('previews import conflicts without mutating the repository', () async {
    final baseline = _node(
      id: 'note-1',
      title: 'Original',
      now: DateTime(2026, 6, 18, 9),
    );
    final local = baseline.copyWith(
      title: 'Local edit',
      updatedAt: DateTime(2026, 6, 18, 10),
    );
    final remote = baseline.copyWith(
      title: 'Remote edit',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [local]);
    final service = MindmapBackupService(
      repository: repository,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final document = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Tablet'),
      exportedAt: DateTime(2026, 6, 18, 12),
      nodes: [remote],
    );

    final plan = await service.previewImport(
      document,
      baselineNodes: [baseline],
    );

    expect(plan.conflicts.single.kind, SyncConflictKind.editEdit);
    expect((await repository.getNode('note-1'))?.title, 'Local edit');
  });

  test('previews encrypted portable import without mutation', () async {
    final local = _node(
      id: 'local-only',
      title: 'Local only',
      now: DateTime(2026, 6, 19, 9),
    );
    final remote = _node(
      id: 'remote-only',
      title: 'Remote only',
      now: DateTime(2026, 6, 19, 10),
    );
    final localRepository = InMemoryMindmapRepository(seedNodes: [local]);
    final remoteRepository = InMemoryMindmapRepository(seedNodes: [remote]);
    final codec = PortableMindmapBackupCodec(
      iterations: PortableMindmapBackupCodec.minKdfIterations,
      randomBytes: _deterministicRandomBytes(),
    );
    final localService = MindmapBackupService(
      repository: localRepository,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      portableCodec: codec,
    );
    final remoteService = MindmapBackupService(
      repository: remoteRepository,
      sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Tablet'),
      portableCodec: codec,
    );
    final package = await remoteService.createPortableBackup(
      passphrase: 'shared-secret',
    );

    final preview = await localService.previewPortableImport(
      package.package,
      passphrase: 'shared-secret',
    );

    expect(preview.document.nodes.single.id, 'remote-only');
    expect(preview.plan.nodesToSave.single.id, 'remote-only');
    expect(preview.plan.nodeIdsToDelete, ['local-only']);
    expect((await localRepository.listNodes()).single.id, 'local-only');
  });

  test('exports and imports encrypted portable backup packages', () async {
    final sourceRepository = InMemoryMindmapRepository(
      seedNodes: [
        _node(
          id: 'portable-note',
          title: 'Confidential planning note',
          now: DateTime(2026, 6, 19, 9),
        ),
      ],
    );
    final targetRepository = InMemoryMindmapRepository();
    final codec = PortableMindmapBackupCodec(
      iterations: PortableMindmapBackupCodec.minKdfIterations,
      randomBytes: _deterministicRandomBytes(),
    );
    final sourceService = MindmapBackupService(
      repository: sourceRepository,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 19, 12),
      portableCodec: codec,
    );
    final targetService = MindmapBackupService(
      repository: targetRepository,
      sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Tablet'),
      portableCodec: codec,
    );

    final export = await sourceService.createPortableBackup(
      passphrase: 'shared-secret',
    );
    final report = await targetService.importPortableBackup(
      export.package,
      passphrase: 'shared-secret',
    );

    expect(export.package, isNot(contains('Confidential planning note')));
    expect(export.document.nodes.single.id, 'portable-note');
    expect(report.savedNodeIds, ['portable-note']);
    expect(
      (await targetRepository.getNode('portable-note'))?.title,
      'Confidential planning note',
    );
  });
}

MindmapNode _node({
  required String id,
  required String title,
  required DateTime now,
}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    day: DateTime(2026, 6, 18),
    now: now,
  );
}

List<int> Function(int) _deterministicRandomBytes() {
  var call = 0;
  return (length) {
    call += 1;
    return List<int>.generate(length, (index) => (call * 41 + index) % 256);
  };
}
