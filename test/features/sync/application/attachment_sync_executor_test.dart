import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/sync/application/attachment_sync_executor.dart';
import 'package:var_app/features/sync/data/in_memory_attachment_sync_progress_store.dart';
import 'package:var_app/features/sync/domain/attachment_sync.dart';
import 'package:var_app/features/sync/domain/attachment_sync_progress.dart';
import 'package:var_app/features/sync/domain/remote_attachment_store.dart';

const String attachmentId = '123e4567-e89b-42d3-a456-426614174000';

void main() {
  test('uploads referenced verified local attachment', () async {
    final bytes = [1, 2, 3];
    final local = await _AttachmentRepository.withAttachment(bytes: bytes);
    final remote = _RemoteStore();
    final executor = _executor(local: local, remote: remote);

    final report = await executor.run();

    expect(report.completed, 1);
    expect(remote.uploaded[attachmentId], bytes);
  });

  test('stale unreferenced upload is skipped on resume', () async {
    final local = await _AttachmentRepository.withAttachment(bytes: [1]);
    final progress = InMemoryAttachmentSyncProgressStore();
    await progress.write(_pending(AttachmentSyncDirection.upload));
    final executor = _executor(
      local: local,
      remote: _RemoteStore(),
      progress: progress,
      referenced: false,
    );

    final report = await executor.run();

    expect(report.skipped, 1);
    expect(
      (await progress.readAll()).single.state,
      AttachmentSyncProgressState.skipped,
    );
  });

  test('pending progress resumes after executor recreation', () async {
    final local = await _AttachmentRepository.withAttachment(bytes: [1]);
    final progress = InMemoryAttachmentSyncProgressStore();
    await progress.write(_pending(AttachmentSyncDirection.upload));
    final remote = _RemoteStore();

    final report = await _executor(
      local: local,
      remote: remote,
      progress: progress,
    ).run();

    expect(report.completed, 1);
    expect(remote.uploadCalls, 1);
    expect(
      (await progress.readAll()).single.state,
      AttachmentSyncProgressState.completed,
    );
  });

  test(
    'backend switch creates independent progress and ignores old pending',
    () async {
      final local = await _AttachmentRepository.withAttachment(bytes: [1]);
      final progress = InMemoryAttachmentSyncProgressStore();
      await progress.write(
        _pending(
          AttachmentSyncDirection.upload,
          storeKind: AttachmentRemoteStoreKind.http,
          state: AttachmentSyncProgressState.waitingRetry,
        ),
      );
      await progress.write(
        _pending(
          AttachmentSyncDirection.download,
          storeKind: AttachmentRemoteStoreKind.http,
          state: AttachmentSyncProgressState.waitingAuth,
        ),
      );
      final remote = _RemoteStore();

      final report = await _executor(
        local: local,
        remote: remote,
        progress: progress,
        storeKind: AttachmentRemoteStoreKind.firebase,
      ).run();

      expect(remote.uploadCalls, 1);
      expect(report.completed, 1);
      expect(report.pending, 0);
      final entries = await progress.readAll();
      expect(
        entries.where(
          (entry) =>
              entry.remoteStoreKind == AttachmentRemoteStoreKind.http &&
              entry.isResumable,
        ),
        hasLength(2),
      );
      expect(
        entries
            .singleWhere(
              (entry) =>
                  entry.remoteStoreKind == AttachmentRemoteStoreKind.firebase,
            )
            .state,
        AttachmentSyncProgressState.completed,
      );
    },
  );

  test('downloads verified bytes and preserves stable id', () async {
    final bytes = [4, 5, 6];
    final metadata = await _metadata(bytes);
    final remote = _RemoteStore(remote: {attachmentId: (metadata, bytes)});
    final local = _AttachmentRepository();

    final report = await _executor(local: local, remote: remote).run();

    expect(report.completed, 1);
    expect((await local.resolve(attachmentId))?.id, attachmentId);
    expect(await local.readBytes(attachmentId), bytes);
  });

  test('identical local collision is idempotent', () async {
    final bytes = [7, 8];
    final local = await _AttachmentRepository.withAttachment(bytes: bytes);
    final metadata = await _metadata(bytes);
    final remote = _RemoteStore(remote: {attachmentId: (metadata, bytes)});

    final first = await _executor(local: local, remote: remote).run();
    final second = await _executor(local: local, remote: remote).run();

    expect(first.completed, 0);
    expect(second.completed, 0);
    expect(remote.uploadCalls, 0);
    expect(remote.downloadCalls, 0);
  });

  test('different local and remote content reports conflict', () async {
    final local = await _AttachmentRepository.withAttachment(bytes: [1]);
    final metadata = await _metadata([2]);
    final remote = _RemoteStore(
      remote: {
        attachmentId: (metadata, [2]),
      },
    );

    final report = await _executor(local: local, remote: remote).run();

    expect(report.conflicts, 1);
    expect(remote.uploadCalls, 0);
    expect(remote.downloadCalls, 0);
  });

  test('retryable failure uses deterministic bounded retry', () async {
    final local = await _AttachmentRepository.withAttachment(bytes: [1]);
    final remote = _RemoteStore(uploadFailures: 2);
    final waits = <Duration>[];
    final executor = _executor(
      local: local,
      remote: remote,
      delay: (duration) async => waits.add(duration),
    );

    final report = await executor.run();

    expect(report.completed, 1);
    expect(waits, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    expect(remote.uploadCalls, 3);
  });

  test('unauthorized waits for auth change without retrying', () async {
    final local = await _AttachmentRepository.withAttachment(bytes: [1]);
    final remote = _RemoteStore(unauthorized: true);
    final progress = InMemoryAttachmentSyncProgressStore();

    final report = await _executor(
      local: local,
      remote: remote,
      progress: progress,
    ).run();

    expect(report.hasWarnings, isTrue);
    expect(remote.uploadCalls, 1);
    expect(
      (await progress.readAll()).single.state,
      AttachmentSyncProgressState.waitingAuth,
    );
  });

  test('corrupt download is terminal and does not import', () async {
    final metadata = await _metadata([1, 2]);
    final remote = _RemoteStore(
      remote: {
        attachmentId: (metadata, [9, 9]),
      },
      corruptDownload: true,
    );
    final local = _AttachmentRepository();

    final report = await _executor(local: local, remote: remote).run();

    expect(report.hasWarnings, isTrue);
    expect(await local.resolve(attachmentId), isNull);
  });

  test(
    'unsupported backend leaves metadata sync semantics untouched',
    () async {
      final report = await _executor(
        local: _AttachmentRepository(),
        remote: _RemoteStore(capability: AttachmentSyncCapability.unsupported),
      ).run();

      expect(report.completed, 0);
      expect(report.hasWarnings, isTrue);
    },
  );

  test('parallel duplicate calls share one active run', () async {
    final gate = Completer<void>();
    final local = await _AttachmentRepository.withAttachment(bytes: [1]);
    final remote = _RemoteStore(uploadGate: gate.future);
    final executor = _executor(local: local, remote: remote);

    final first = executor.run();
    final second = executor.run();
    gate.complete();
    await Future.wait([first, second]);

    expect(remote.uploadCalls, 1);
  });

  test('rejects invalid execution limits', () async {
    final local = _AttachmentRepository();
    final remote = _RemoteStore();

    expect(
      () => _executor(local: local, remote: remote, maxParallel: 0),
      throwsArgumentError,
    );
    expect(
      () => _executor(local: local, remote: remote, maxAttempts: 0),
      throwsArgumentError,
    );
  });
}

AttachmentSyncExecutor _executor({
  required _AttachmentRepository local,
  required _RemoteStore remote,
  InMemoryAttachmentSyncProgressStore? progress,
  bool referenced = true,
  AttachmentSyncDelay? delay,
  AttachmentRemoteStoreKind storeKind = AttachmentRemoteStoreKind.http,
  int maxAttempts = 4,
  int maxParallel = 2,
}) => AttachmentSyncExecutor(
  mindmapRepository: InMemoryMindmapRepository(
    seedNodes: [if (referenced) _node()],
  ),
  attachmentRepository: local,
  remoteStore: remote,
  progressStore: progress ?? InMemoryAttachmentSyncProgressStore(),
  remoteStoreKind: storeKind,
  now: () => DateTime.utc(2026, 7, 15),
  delay: delay ?? (_) async {},
  maxAttempts: maxAttempts,
  maxParallel: maxParallel,
);

MindmapNode _node() => MindmapNode.create(
  id: 'image-node',
  type: NodeType.image,
  title: 'Image',
  day: DateTime(2026, 7, 15),
  now: DateTime(2026, 7, 15),
).copyWith(data: const {'attachmentId': attachmentId});

AttachmentSyncProgress _pending(
  AttachmentSyncDirection direction, {
  AttachmentRemoteStoreKind storeKind = AttachmentRemoteStoreKind.http,
  AttachmentSyncProgressState state = AttachmentSyncProgressState.pending,
}) => AttachmentSyncProgress(
  attachmentId: attachmentId,
  direction: direction,
  remoteStoreKind: storeKind,
  attempt: 0,
  state: state,
);

Future<NodeAttachment> _metadata(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return NodeAttachment(
    id: attachmentId,
    fileName: 'image.png',
    mimeType: 'image/png',
    byteLength: bytes.length,
    checksum: hash.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join(),
    createdAt: DateTime.utc(2026, 7, 15),
  );
}

final class _AttachmentRepository
    implements NodeAttachmentRepository, NodeAttachmentRestoreRepository {
  _AttachmentRepository();

  static Future<_AttachmentRepository> withAttachment({
    required List<int> bytes,
  }) async {
    final repository = _AttachmentRepository();
    final attachment = await _metadata(bytes);
    repository._attachments[attachment.id] = attachment;
    repository._bytes[attachment.id] = List.of(bytes);
    return repository;
  }

  final Map<String, NodeAttachment> _attachments = {};
  final Map<String, List<int>> _bytes = {};

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async => [
    for (final attachment in _attachments.values)
      NodeAttachmentManifestEntry(version: 1, attachment: attachment),
  ];

  @override
  Future<void> delete(String attachmentId) async {
    _attachments.remove(attachmentId);
    _bytes.remove(attachmentId);
  }

  @override
  Future<List<int>?> exportBytes(String attachmentId) =>
      readBytes(attachmentId);

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) => throw UnimplementedError();

  @override
  Future<NodeAttachmentRestorePlan> preflightRestore(
    List<NodeAttachmentRestoreItem> items,
  ) async {
    final imports = <NodeAttachmentRestoreItem>[];
    final identical = <String>{};
    for (final item in items) {
      final current = _attachments[item.attachment.id];
      if (current == null) {
        imports.add(item);
      } else if (current.checksum == item.attachment.checksum) {
        identical.add(item.attachment.id);
      } else {
        throw const FormatException('Attachment ID collision.');
      }
    }
    return NodeAttachmentRestorePlan(
      itemsToImport: imports,
      identicalAttachmentIds: identical,
    );
  }

  @override
  Future<List<int>?> readBytes(String attachmentId) async =>
      _bytes[attachmentId];

  @override
  Future<NodeAttachment?> resolve(String attachmentId) async =>
      _attachments[attachmentId];

  @override
  Future<NodeAttachment> restoreBytes({
    required NodeAttachment attachment,
    required List<int> bytes,
  }) async {
    _attachments[attachment.id] = attachment;
    _bytes[attachment.id] = List.of(bytes);
    return attachment;
  }
}

final class _RemoteStore implements RemoteAttachmentStore {
  _RemoteStore({
    this.capability = AttachmentSyncCapability.supported,
    Map<String, (NodeAttachment, List<int>)>? remote,
    this.uploadFailures = 0,
    this.unauthorized = false,
    this.corruptDownload = false,
    this.uploadGate,
  }) : remote = remote ?? {};

  @override
  final AttachmentSyncCapability capability;
  final Map<String, (NodeAttachment, List<int>)> remote;
  final Map<String, List<int>> uploaded = {};
  int uploadFailures;
  final bool unauthorized;
  final bool corruptDownload;
  final Future<void>? uploadGate;
  int uploadCalls = 0;
  int downloadCalls = 0;

  @override
  Future<void> delete({
    required String attachmentId,
    required String tombstoneVersion,
  }) => throw UnimplementedError();

  @override
  Future<RemoteAttachmentDownload> download(String attachmentId) async {
    downloadCalls++;
    final entry = remote[attachmentId]!;
    if (corruptDownload) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.integrity,
        'Corrupt download.',
      );
    }
    return RemoteAttachmentDownload.verified(
      metadata: RemoteAttachmentMetadata.fromNodeAttachment(entry.$1),
      bytes: entry.$2,
    );
  }

  @override
  Future<RemoteAttachmentMetadata?> head(String attachmentId) async {
    final entry = remote[attachmentId];
    return entry == null
        ? null
        : RemoteAttachmentMetadata.fromNodeAttachment(entry.$1);
  }

  @override
  Future<void> upload({
    required NodeAttachment metadata,
    required Stream<List<int>> bytes,
  }) async {
    uploadCalls++;
    await uploadGate;
    if (unauthorized) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.unauthorized,
        'Authentication required.',
      );
    }
    if (uploadFailures > 0) {
      uploadFailures--;
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.transport,
        'Offline.',
      );
    }
    uploaded[metadata.id] = await bytes.expand((chunk) => chunk).toList();
    remote[metadata.id] = (metadata, uploaded[metadata.id]!);
  }
}
