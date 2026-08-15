/// Executes resumable attachment sync without changing metadata sync success.
library;

import 'dart:async';

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_repository.dart';
import '../../mindmap/domain/node_attachment.dart';
import '../domain/attachment_sync.dart';
import '../domain/attachment_sync_progress.dart';
import '../domain/remote_attachment_store.dart';

typedef AttachmentSyncDelay = Future<void> Function(Duration duration);

final class AttachmentSyncExecutionReport {
  const AttachmentSyncExecutionReport({
    this.completed = 0,
    this.skipped = 0,
    this.conflicts = 0,
    this.pending = 0,
    this.warnings = const [],
  });

  final int completed;
  final int skipped;
  final int conflicts;
  final int pending;
  final List<String> warnings;

  bool get hasWarnings => warnings.isNotEmpty || conflicts > 0 || pending > 0;
}

final class AttachmentSyncExecutor {
  AttachmentSyncExecutor({
    required MindmapRepository mindmapRepository,
    required NodeAttachmentRepository attachmentRepository,
    required RemoteAttachmentStore remoteStore,
    required AttachmentSyncProgressStore progressStore,
    required AttachmentRemoteStoreKind remoteStoreKind,
    DateTime Function()? now,
    AttachmentSyncDelay? delay,
    int maxAttempts = 4,
    int maxParallel = 2,
  }) : _mindmapRepository = mindmapRepository,
       _attachmentRepository = attachmentRepository,
       _remoteStore = remoteStore,
       _progressStore = progressStore,
       _remoteStoreKind = remoteStoreKind,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       maxAttempts = _positiveLimit(maxAttempts, 'maxAttempts'),
       maxParallel = _positiveLimit(maxParallel, 'maxParallel');

  final MindmapRepository _mindmapRepository;
  final NodeAttachmentRepository _attachmentRepository;
  final RemoteAttachmentStore _remoteStore;
  final AttachmentSyncProgressStore _progressStore;
  final AttachmentRemoteStoreKind _remoteStoreKind;
  final DateTime Function() _now;
  final AttachmentSyncDelay _delay;
  final int maxAttempts;
  final int maxParallel;
  Future<AttachmentSyncExecutionReport>? _activeRun;

  Future<AttachmentSyncExecutionReport> run() {
    return _activeRun ??= _run().whenComplete(() => _activeRun = null);
  }

  Future<AttachmentSyncExecutionReport> _run() async {
    if (_remoteStore.capability != AttachmentSyncCapability.supported) {
      return const AttachmentSyncExecutionReport(
        warnings: ['Attachment sync is unsupported by the active backend.'],
      );
    }
    final nodes = await _mindmapRepository.listNodes();
    final manifest = await _attachmentRepository.buildManifest();
    final referencedIds = _referencedAttachmentIds(nodes);
    final remoteManifest = <Map<String, Object?>>[];
    final warnings = <String>[];
    for (final id in referencedIds) {
      try {
        final metadata = await _remoteStore.head(id);
        if (metadata != null) {
          remoteManifest.add({
            ...metadata.toJson(),
            'remoteObjectKey': 'attachments/$id',
          });
        }
      } on RemoteAttachmentException catch (error) {
        warnings.add(error.message);
      }
    }
    final plan = const AttachmentSyncPlanner().plan(
      nodes: nodes,
      localManifest: manifest,
      remoteManifest: remoteManifest,
    );
    final existingByKey = {
      for (final entry in await _progressStore.readAll()) entry.key: entry,
    };
    for (final item in plan.workItems) {
      final key = AttachmentSyncProgress(
        attachmentId: item.metadata.attachmentId,
        direction: item.direction,
        remoteStoreKind: _remoteStoreKind,
        attempt: 0,
        state: AttachmentSyncProgressState.pending,
      ).key;
      if (existingByKey[key]?.isResumable ?? false) continue;
      await _progressStore.write(
        AttachmentSyncProgress(
          attachmentId: item.metadata.attachmentId,
          direction: item.direction,
          remoteStoreKind: _remoteStoreKind,
          attempt: 0,
          state: AttachmentSyncProgressState.pending,
        ),
      );
    }
    final existing = await _progressStore.readAll();
    final queue = existing.where((entry) {
      if (entry.remoteStoreKind != _remoteStoreKind || !entry.isResumable) {
        return false;
      }
      final nextRetryAt = entry.nextRetryAt;
      return nextRetryAt == null || !nextRetryAt.isAfter(_now().toUtc());
    }).toList();
    var completed = 0;
    var skipped = 0;
    var conflicts = plan.conflicts.length;
    warnings.addAll(plan.warnings);
    for (var offset = 0; offset < queue.length; offset += maxParallel) {
      final batch = queue.skip(offset).take(maxParallel);
      final results = await Future.wait(batch.map(_execute));
      for (final result in results) {
        switch (result) {
          case AttachmentSyncProgressState.completed:
            completed++;
          case AttachmentSyncProgressState.skipped:
            skipped++;
          case AttachmentSyncProgressState.conflict:
            conflicts++;
          case AttachmentSyncProgressState.failed ||
              AttachmentSyncProgressState.waitingAuth ||
              AttachmentSyncProgressState.waitingRetry:
            warnings.add('Attachment sync needs attention.');
          case AttachmentSyncProgressState.pending ||
              AttachmentSyncProgressState.running:
            break;
        }
      }
    }
    final pending = (await _progressStore.readAll())
        .where(
          (entry) =>
              entry.remoteStoreKind == _remoteStoreKind && entry.isResumable,
        )
        .length;
    return AttachmentSyncExecutionReport(
      completed: completed,
      skipped: skipped,
      conflicts: conflicts,
      pending: pending,
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<AttachmentSyncProgressState> _execute(
    AttachmentSyncProgress progress,
  ) async {
    var current = progress.copyWith(
      state: AttachmentSyncProgressState.running,
      clearNextRetryAt: true,
      lastError: '',
    );
    await _progressStore.write(current);
    try {
      final state = switch (current.direction) {
        AttachmentSyncDirection.upload => await _upload(current.attachmentId),
        AttachmentSyncDirection.download => await _download(
          current.attachmentId,
        ),
      };
      current = current.copyWith(state: state, clearNextRetryAt: true);
      await _progressStore.write(current);
      return state;
    } on RemoteAttachmentException catch (error) {
      return _handleFailure(current, error.kind, error.message);
    } on FormatException catch (error) {
      return _handleFailure(
        current,
        RemoteAttachmentFailureKind.integrity,
        error.message,
      );
    } on Object {
      return _handleFailure(
        current,
        RemoteAttachmentFailureKind.transport,
        'Attachment transfer failed.',
      );
    }
  }

  Future<AttachmentSyncProgressState> _upload(String attachmentId) async {
    final nodes = await _mindmapRepository.listNodes();
    if (!_referencedAttachmentIds(nodes).contains(attachmentId)) {
      return AttachmentSyncProgressState.skipped;
    }
    final attachment = await _attachmentRepository.resolve(attachmentId);
    final bytes = await _attachmentRepository.readBytes(attachmentId);
    if (attachment == null || bytes == null) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.integrity,
        'Local attachment is missing or corrupt.',
      );
    }
    final current = RemoteAttachmentMetadata.fromNodeAttachment(attachment);
    final remote = await _remoteStore.head(attachmentId);
    if (remote != null) {
      return remote.hasSameContent(current)
          ? AttachmentSyncProgressState.completed
          : AttachmentSyncProgressState.conflict;
    }
    await _remoteStore.upload(metadata: attachment, bytes: Stream.value(bytes));
    return AttachmentSyncProgressState.completed;
  }

  Future<AttachmentSyncProgressState> _download(String attachmentId) async {
    final nodes = await _mindmapRepository.listNodes();
    if (!_referencedAttachmentIds(nodes).contains(attachmentId)) {
      return AttachmentSyncProgressState.skipped;
    }
    final download = await _remoteStore.download(attachmentId);
    final local = await _attachmentRepository.resolve(attachmentId);
    if (local != null) {
      final localMetadata = RemoteAttachmentMetadata.fromNodeAttachment(local);
      return localMetadata.hasSameContent(download.metadata)
          ? AttachmentSyncProgressState.completed
          : AttachmentSyncProgressState.conflict;
    }
    if (_attachmentRepository is! NodeAttachmentRestoreRepository) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.unavailable,
        'Local attachment restore is unavailable.',
      );
    }
    final restoreRepository =
        _attachmentRepository as NodeAttachmentRestoreRepository;
    final attachment = NodeAttachment(
      id: download.metadata.attachmentId,
      fileName: download.metadata.fileName,
      mimeType: download.metadata.mimeType,
      byteLength: download.metadata.byteLength,
      checksum: download.metadata.checksum,
      createdAt: _now().toUtc(),
    );
    final item = NodeAttachmentRestoreItem(
      attachment: attachment,
      bytes: download.bytes,
    );
    final preflight = await restoreRepository.preflightRestore([item]);
    if (preflight.identicalAttachmentIds.contains(attachmentId)) {
      return AttachmentSyncProgressState.completed;
    }
    await restoreRepository.restoreBytes(
      attachment: attachment,
      bytes: download.bytes,
    );
    return AttachmentSyncProgressState.completed;
  }

  Future<AttachmentSyncProgressState> _handleFailure(
    AttachmentSyncProgress progress,
    RemoteAttachmentFailureKind kind,
    String message,
  ) async {
    if (kind == RemoteAttachmentFailureKind.unauthorized) {
      await _progressStore.write(
        progress.copyWith(
          attempt: progress.attempt + 1,
          state: AttachmentSyncProgressState.waitingAuth,
          lastError: message,
        ),
      );
      return AttachmentSyncProgressState.waitingAuth;
    }
    if (kind == RemoteAttachmentFailureKind.integrity ||
        kind == RemoteAttachmentFailureKind.conflict ||
        kind == RemoteAttachmentFailureKind.notFound ||
        kind == RemoteAttachmentFailureKind.invalidMetadata ||
        kind == RemoteAttachmentFailureKind.sizeLimit) {
      final state = kind == RemoteAttachmentFailureKind.conflict
          ? AttachmentSyncProgressState.conflict
          : AttachmentSyncProgressState.failed;
      await _progressStore.write(
        progress.copyWith(
          attempt: progress.attempt + 1,
          state: state,
          lastError: message,
        ),
      );
      return state;
    }
    final attempt = progress.attempt + 1;
    if (attempt >= maxAttempts) {
      await _progressStore.write(
        progress.copyWith(
          attempt: attempt,
          state: AttachmentSyncProgressState.failed,
          lastError: message,
        ),
      );
      return AttachmentSyncProgressState.failed;
    }
    final backoff = Duration(seconds: 1 << (attempt - 1).clamp(0, 5));
    final retryAt = _now().toUtc().add(backoff);
    await _progressStore.write(
      progress.copyWith(
        attempt: attempt,
        nextRetryAt: retryAt,
        state: AttachmentSyncProgressState.waitingRetry,
        lastError: message,
      ),
    );
    await _delay(backoff);
    final retry = progress.copyWith(
      attempt: attempt,
      state: AttachmentSyncProgressState.pending,
      clearNextRetryAt: true,
      lastError: message,
    );
    await _progressStore.write(retry);
    return _execute(retry);
  }
}

Set<String> _referencedAttachmentIds(Iterable<MindmapNode> nodes) {
  final ids = <String>{};
  for (final node in nodes) {
    void collect(Object? value, [String? key]) {
      if (value is Map) {
        for (final entry in value.entries) {
          collect(
            entry.value,
            entry.key is String ? entry.key as String : null,
          );
        }
      } else if (value is Iterable) {
        for (final item in value) {
          collect(item);
        }
      } else if (value is String &&
          (key == 'attachmentId' || key == 'thumbnailAttachmentId')) {
        ids.add(value);
      }
    }

    collect(node.data);
  }
  return ids;
}

int _positiveLimit(int value, String name) {
  if (value < 1) throw ArgumentError.value(value, name, 'Must be at least 1.');
  return value;
}
