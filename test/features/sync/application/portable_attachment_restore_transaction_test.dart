import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/local_node_attachment_repository_web.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/sync/application/mindmap_backup_service.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';

void main() {
  test('blocking conflict performs zero attachment mutation', () async {
    final sourceAttachments = MemoryNodeAttachmentRepository(
      maxTotalBytes: 1024,
    );
    final media = await sourceAttachments.importBytes(
      bytes: const [1],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    final remote = _mediaNode('same', media.id);
    final local = remote.copyWith(
      title: 'Local edit',
      updatedAt: _now.add(const Duration(hours: 1)),
    );
    final document = await _service(
      InMemoryMindmapRepository(seedNodes: [remote]),
      sourceAttachments,
    ).createBackup();
    final targetAttachments = MemoryNodeAttachmentRepository(
      maxTotalBytes: 1024,
    );

    final report = await _service(
      InMemoryMindmapRepository(seedNodes: [local]),
      targetAttachments,
    ).importBackup(document);

    expect(report.blockedByConflicts, isTrue);
    expect(await targetAttachments.buildManifest(), isEmpty);
  });

  test('save failure mid-way restores nodes and attachments', () async {
    final original = _note('existing', 'Original');
    final delegate = InMemoryMindmapRepository(seedNodes: [original]);
    final repository = _FailingMindmapRepository(delegate, failSaveAt: 2);
    final sourceAttachments = MemoryNodeAttachmentRepository(
      maxTotalBytes: 1024,
    );
    final media = await sourceAttachments.importBytes(
      bytes: const [1],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    final document = await _service(
      InMemoryMindmapRepository(
        seedNodes: [
          original.copyWith(title: 'Changed'),
          _mediaNode('new-image', media.id),
        ],
      ),
      sourceAttachments,
    ).createBackup();
    final targetAttachments = MemoryNodeAttachmentRepository(
      maxTotalBytes: 1024,
    );

    await expectLater(
      MindmapBackupService(
        repository: repository,
        sourceDevice: _device,
        attachmentRepository: targetAttachments,
      ).restoreBackup(document),
      throwsA(isA<PortableBackupException>()),
    );

    expect((await delegate.getNode('existing'))?.title, 'Original');
    expect(await delegate.getNode('new-image'), isNull);
    expect(await targetAttachments.buildManifest(), isEmpty);
  });

  test('delete failure restores deleted nodes and attachments', () async {
    final first = _note('a', 'A');
    final second = _note('b', 'B');
    final delegate = InMemoryMindmapRepository(seedNodes: [first, second]);
    final repository = _FailingMindmapRepository(delegate, failDeleteAt: 2);
    final sourceAttachments = MemoryNodeAttachmentRepository(
      maxTotalBytes: 1024,
    );
    final media = await sourceAttachments.importBytes(
      bytes: const [1],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    final document = MindmapBackupDocument.create(
      sourceDevice: _device,
      exportedAt: _now,
      nodes: const [],
      attachments: [await _backupAttachment(sourceAttachments, media)],
    );
    final targetAttachments = MemoryNodeAttachmentRepository(
      maxTotalBytes: 1024,
    );

    await expectLater(
      MindmapBackupService(
        repository: repository,
        sourceDevice: _device,
        attachmentRepository: targetAttachments,
      ).restoreBackup(document),
      throwsA(isA<PortableBackupException>()),
    );

    expect(await delegate.getNode('a'), isNotNull);
    expect(await delegate.getNode('b'), isNotNull);
    expect(await targetAttachments.buildManifest(), isEmpty);
  });

  test('corrupt second attachment preflight commits none', () async {
    final source = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
    final first = await source.importBytes(
      bytes: const [1],
      fileName: 'first.png',
      mimeType: 'image/png',
    );
    final second = await source.importBytes(
      bytes: const [2],
      fileName: 'second.png',
      mimeType: 'image/png',
    );
    final document = MindmapBackupDocument.create(
      sourceDevice: _device,
      exportedAt: _now,
      nodes: const [],
      attachments: [
        await _backupAttachment(source, first),
        MindmapBackupAttachment(
          version: 1,
          attachment: second,
          payload: base64Encode(const [9]),
        ),
      ],
    );
    final target = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);

    await expectLater(
      _service(InMemoryMindmapRepository(), target).importBackup(document),
      throwsA(isA<PortableBackupException>()),
    );

    expect(await target.buildManifest(), isEmpty);
  });

  test('rollback delete failure reports primary and cleanup errors', () async {
    final source = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
    final media = await source.importBytes(
      bytes: const [1],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    final document = await _service(
      InMemoryMindmapRepository(seedNodes: [_mediaNode('image', media.id)]),
      source,
    ).createBackup();
    final targetDelegate = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
    final targetAttachments = _FailingDeleteAttachmentRepository(
      targetDelegate,
    );
    final repository = _FailingMindmapRepository(
      InMemoryMindmapRepository(),
      failSaveAt: 1,
    );

    final error =
        await MindmapBackupService(
              repository: repository,
              sourceDevice: _device,
              attachmentRepository: targetAttachments,
            )
            .importBackup(document)
            .then<PortableBackupException?>(
              (_) => null,
              onError: (Object error) => error as PortableBackupException,
            );

    expect(error, isNotNull);
    expect(error!.primaryError, isNotNull);
    expect(error.cleanupErrors, isNotEmpty);
    expect(error.message, contains('rollback was incomplete'));
  });

  test(
    'identical collision is skipped and unrelated collision fails',
    () async {
      final source = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
      final attachment = await source.importBytes(
        bytes: const [1],
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final target = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
      await target.restoreBytes(attachment: attachment, bytes: const [1]);
      final identical = await target.preflightRestore([
        NodeAttachmentRestoreItem(attachment: attachment, bytes: const [1]),
      ]);
      expect(identical.itemsToImport, isEmpty);
      expect(identical.identicalAttachmentIds, contains(attachment.id));

      final collision = NodeAttachment(
        id: attachment.id,
        fileName: 'other.png',
        mimeType: attachment.mimeType,
        byteLength: attachment.byteLength,
        checksum: attachment.checksum,
        createdAt: attachment.createdAt,
      );
      await expectLater(
        target.preflightRestore([
          NodeAttachmentRestoreItem(attachment: collision, bytes: const [1]),
        ]),
        throwsFormatException,
      );
      expect(await target.readBytes(attachment.id), [1]);
    },
  );

  test('parallel restores are serialized by service mutex', () async {
    final repository = _TrackingMindmapRepository();
    final service = MindmapBackupService(
      repository: repository,
      sourceDevice: _device,
    );
    final first = MindmapBackupDocument.create(
      sourceDevice: _device,
      exportedAt: _now,
      nodes: [_note('first', 'First')],
    );
    final second = MindmapBackupDocument.create(
      sourceDevice: _device,
      exportedAt: _now,
      nodes: [_note('second', 'Second')],
    );

    await Future.wait([
      service.importBackup(first),
      service.importBackup(second),
    ]);

    expect(repository.maxConcurrentMutations, 1);
    expect(await repository.getNode('first'), isNotNull);
    expect(await repository.getNode('second'), isNotNull);
  });

  test(
    'concurrent node change is not overwritten and attachment is retained',
    () async {
      final source = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
      final media = await source.importBytes(
        bytes: const [1],
        fileName: 'photo.png',
        mimeType: 'image/png',
      );
      final document = await _service(
        InMemoryMindmapRepository(
          seedNodes: [_mediaNode('a', media.id), _mediaNode('b', media.id)],
        ),
        source,
      ).createBackup();
      final delegate = InMemoryMindmapRepository();
      final repository = _ConcurrentMutationRepository(delegate);
      final targetAttachments = MemoryNodeAttachmentRepository(
        maxTotalBytes: 1024,
      );

      final error =
          await MindmapBackupService(
                repository: repository,
                sourceDevice: _device,
                attachmentRepository: targetAttachments,
              )
              .importBackup(document)
              .then<PortableBackupException?>(
                (_) => null,
                onError: (Object error) => error as PortableBackupException,
              );

      expect(error, isNotNull);
      expect(error!.cleanupErrors, isNotEmpty);
      expect((await delegate.getNode('a'))?.title, 'External change');
      expect((await delegate.getNode('a'))?.data['attachmentId'], media.id);
      expect(await targetAttachments.readBytes(media.id), [1]);
    },
  );

  test('direct import rejects crafted payload before any mutation', () async {
    final existing = _note('existing', 'Keep');
    final repository = InMemoryMindmapRepository(seedNodes: [existing]);
    final attachments = MemoryNodeAttachmentRepository(maxTotalBytes: 1024);
    final crafted = MindmapBackupDocument.create(
      sourceDevice: _device,
      exportedAt: _now,
      nodes: [_note('replacement', 'Replacement')],
      attachments: [
        MindmapBackupAttachment(
          version: nodeAttachmentManifestVersion,
          attachment: NodeAttachment(
            id: '00000000-0000-4000-8000-000000000099',
            fileName: 'photo.png',
            mimeType: 'image/png',
            byteLength: 3,
            checksum: 'invalid',
            createdAt: _now,
          ),
          payload: '!!!!',
        ),
      ],
    );

    await expectLater(
      MindmapBackupService(
        repository: repository,
        sourceDevice: _device,
        attachmentRepository: attachments,
      ).importBackup(crafted),
      throwsA(isA<PortableBackupException>()),
    );

    expect((await repository.getNode('existing'))?.title, 'Keep');
    expect(await repository.getNode('replacement'), isNull);
    expect(await attachments.buildManifest(), isEmpty);
  });
}

const _device = SyncDeviceIdentity(id: 'device-a', label: 'Laptop');
final _now = DateTime.utc(2026, 7, 14, 8);

MindmapBackupService _service(
  MindmapRepository nodes,
  MemoryNodeAttachmentRepository attachments,
) => MindmapBackupService(
  repository: nodes,
  sourceDevice: _device,
  attachmentRepository: attachments,
);

MindmapNode _mediaNode(String id, String attachmentId) => MindmapNode.create(
  id: id,
  type: NodeType.image,
  title: id,
  day: _now,
  now: _now,
).copyWith(data: {'attachmentId': attachmentId});

MindmapNode _note(String id, String title) => MindmapNode.create(
  id: id,
  type: NodeType.note,
  title: title,
  day: _now,
  now: _now,
);

Future<MindmapBackupAttachment> _backupAttachment(
  NodeAttachmentRepository repository,
  NodeAttachment attachment,
) async => MindmapBackupAttachment(
  version: nodeAttachmentManifestVersion,
  attachment: attachment,
  payload: base64Encode((await repository.readBytes(attachment.id))!),
);

final class _FailingMindmapRepository implements MindmapRepository {
  _FailingMindmapRepository(
    this.delegate, {
    this.failSaveAt,
    this.failDeleteAt,
  });

  final InMemoryMindmapRepository delegate;
  final int? failSaveAt;
  final int? failDeleteAt;
  int _saveCount = 0;
  int _deleteCount = 0;

  @override
  Future<void> deleteNode(String id) async {
    _deleteCount += 1;
    if (_deleteCount == failDeleteAt) throw StateError('delete failed');
    await delegate.deleteNode(id);
  }

  @override
  Future<MindmapNode?> getNode(String id) => delegate.getNode(id);
  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      delegate.listNodes(day: day);
  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    _saveCount += 1;
    if (_saveCount == failSaveAt) throw StateError('save failed');
    return delegate.saveNode(node);
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      delegate.searchNodes(query);
}

final class _FailingDeleteAttachmentRepository
    implements NodeAttachmentRepository, NodeAttachmentRestoreRepository {
  _FailingDeleteAttachmentRepository(this.delegate);
  final MemoryNodeAttachmentRepository delegate;

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() =>
      delegate.buildManifest();
  @override
  Future<void> delete(String attachmentId) =>
      Future<void>.error(StateError('cleanup failed'));
  @override
  Future<List<int>?> exportBytes(String attachmentId) =>
      delegate.exportBytes(attachmentId);
  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) => delegate.importBytes(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
  @override
  Future<NodeAttachmentRestorePlan> preflightRestore(
    List<NodeAttachmentRestoreItem> items,
  ) => delegate.preflightRestore(items);
  @override
  Future<List<int>?> readBytes(String attachmentId) =>
      delegate.readBytes(attachmentId);
  @override
  Future<NodeAttachment?> resolve(String attachmentId) =>
      delegate.resolve(attachmentId);
  @override
  Future<NodeAttachment> restoreBytes({
    required NodeAttachment attachment,
    required List<int> bytes,
  }) => delegate.restoreBytes(attachment: attachment, bytes: bytes);
}

final class _TrackingMindmapRepository implements MindmapRepository {
  final InMemoryMindmapRepository _delegate = InMemoryMindmapRepository();
  int _activeMutations = 0;
  int maxConcurrentMutations = 0;

  @override
  Future<void> deleteNode(String id) => _track(() => _delegate.deleteNode(id));
  @override
  Future<MindmapNode?> getNode(String id) => _delegate.getNode(id);
  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _delegate.listNodes(day: day);
  @override
  Future<MindmapNode> saveNode(MindmapNode node) =>
      _track(() => _delegate.saveNode(node));
  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _delegate.searchNodes(query);

  Future<T> _track<T>(Future<T> Function() operation) async {
    _activeMutations += 1;
    if (_activeMutations > maxConcurrentMutations) {
      maxConcurrentMutations = _activeMutations;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return await operation();
    } finally {
      _activeMutations -= 1;
    }
  }
}

final class _ConcurrentMutationRepository implements MindmapRepository {
  _ConcurrentMutationRepository(this.delegate);
  final InMemoryMindmapRepository delegate;
  int _saveCount = 0;

  @override
  Future<void> deleteNode(String id) => delegate.deleteNode(id);
  @override
  Future<MindmapNode?> getNode(String id) => delegate.getNode(id);
  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      delegate.listNodes(day: day);
  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    _saveCount += 1;
    if (_saveCount == 2) {
      final first = await delegate.getNode('a');
      if (first != null) {
        await delegate.saveNode(first.copyWith(title: 'External change'));
      }
      throw StateError('second save failed');
    }
    return delegate.saveNode(node);
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      delegate.searchNodes(query);
}
