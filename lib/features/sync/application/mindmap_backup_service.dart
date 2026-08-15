/// Application service for export/import backup sync flows.
library;

import 'dart:async';
import 'dart:convert';

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_repository.dart';
import '../../mindmap/domain/node_attachment.dart';
import '../domain/mindmap_backup_document.dart';
import '../domain/mindmap_sync_planner.dart';
import 'portable_backup_codec.dart';

final class MindmapPortableBackupExport {
  const MindmapPortableBackupExport({
    required this.document,
    required this.package,
  });

  final MindmapBackupDocument document;
  final String package;
}

final class MindmapPortableBackupImportPreview {
  const MindmapPortableBackupImportPreview({
    required this.document,
    required this.plan,
  });

  final MindmapBackupDocument document;
  final MindmapSyncPlan plan;
}

final class MindmapBackupImportReport {
  const MindmapBackupImportReport({
    required this.plan,
    required this.savedNodeIds,
    required this.deletedNodeIds,
    this.warnings = const [],
  });

  final MindmapSyncPlan plan;
  final List<String> savedNodeIds;
  final List<String> deletedNodeIds;
  final List<MindmapBackupWarning> warnings;

  bool get blockedByConflicts => plan.hasBlockingConflicts;
}

final class MindmapBackupService {
  MindmapBackupService({
    required MindmapRepository repository,
    required FutureOr<SyncDeviceIdentity> sourceDevice,
    DateTime Function()? now,
    MindmapSyncPlanner planner = const MindmapSyncPlanner(),
    PortableMindmapBackupCodec? portableCodec,
    FutureOr<NodeAttachmentRepository?> attachmentRepository,
    Future<NodeAttachmentRepository?> Function()? attachmentRepositoryLoader,
  }) : _repository = repository,
       _sourceDevice = sourceDevice,
       _now = now ?? DateTime.now,
       _planner = planner,
       _portableCodec = portableCodec ?? PortableMindmapBackupCodec(),
       _attachmentRepository = attachmentRepository,
       _attachmentRepositoryLoader = attachmentRepositoryLoader;

  final MindmapRepository _repository;
  final FutureOr<SyncDeviceIdentity> _sourceDevice;
  final DateTime Function() _now;
  final MindmapSyncPlanner _planner;
  final PortableMindmapBackupCodec _portableCodec;
  final FutureOr<NodeAttachmentRepository?> _attachmentRepository;
  final Future<NodeAttachmentRepository?> Function()?
  _attachmentRepositoryLoader;
  Future<void> _restoreTail = Future<void>.value();

  Future<MindmapBackupDocument> createBackup() async {
    final nodes = await _repository.listNodes();
    final attachments = <MindmapBackupAttachment>[];
    final warnings = <MindmapBackupWarning>[];
    final referencedAttachmentIds = _referencedAttachmentIds(nodes);
    if (referencedAttachmentIds.isNotEmpty) {
      final attachmentRepository = await _resolveAttachmentRepository();
      final manifest = attachmentRepository == null
          ? const <NodeAttachmentManifestEntry>[]
          : await attachmentRepository.buildManifest();
      final entriesById = {
        for (final entry in manifest) entry.attachment.id: entry,
      };
      for (final attachmentId in referencedAttachmentIds) {
        final entry = entriesById[attachmentId];
        if (entry == null || attachmentRepository == null) {
          warnings.add(_missingAttachmentWarning(attachmentId));
          continue;
        }
        final bytes = await attachmentRepository.readBytes(entry.attachment.id);
        if (bytes == null) {
          warnings.add(_missingAttachmentWarning(entry.attachment.id));
          continue;
        }
        attachments.add(
          MindmapBackupAttachment(
            version: entry.version,
            attachment: entry.attachment,
            payload: base64Encode(bytes),
          ),
        );
      }
    }
    return _createDocument(
      nodes: nodes,
      attachments: attachments,
      warnings: warnings,
    );
  }

  Future<MindmapBackupDocument> createCloudBackup() async {
    final nodes = await _repository.listNodes();
    final referencedAttachmentIds = _referencedAttachmentIds(nodes);
    final attachmentRepository = referencedAttachmentIds.isEmpty
        ? null
        : await _resolveAttachmentRepository();
    final manifest = attachmentRepository == null
        ? const <NodeAttachmentManifestEntry>[]
        : await attachmentRepository.buildManifest();
    final availableIds = {for (final entry in manifest) entry.attachment.id};
    return _createDocument(
      nodes: nodes,
      warnings: referencedAttachmentIds
          .where((attachmentId) => !availableIds.contains(attachmentId))
          .map(_missingAttachmentWarning),
    );
  }

  Future<MindmapBackupDocument> _createDocument({
    required Iterable<MindmapNode> nodes,
    Iterable<MindmapBackupAttachment> attachments = const [],
    Iterable<MindmapBackupWarning> warnings = const [],
  }) async {
    final sourceDevice = await Future<SyncDeviceIdentity>.value(_sourceDevice);
    return MindmapBackupDocument.create(
      sourceDevice: sourceDevice,
      exportedAt: _now(),
      nodes: nodes,
      attachments: attachments,
      warnings: warnings,
    );
  }

  Future<MindmapPortableBackupExport> createPortableBackup({
    required String passphrase,
  }) async {
    final document = await createBackup();
    final package = await _portableCodec.encode(
      document,
      passphrase: passphrase,
    );
    return MindmapPortableBackupExport(document: document, package: package);
  }

  Future<MindmapSyncPlan> previewImport(
    MindmapBackupDocument document, {
    Iterable<MindmapNode> baselineNodes = const [],
    MindmapSyncPlanner? planner,
  }) async {
    final localNodes = await _repository.listNodes();
    return (planner ?? _planner).plan(
      localNodes: localNodes,
      remoteNodes: document.nodes,
      baselineNodes: baselineNodes,
    );
  }

  Future<MindmapPortableBackupImportPreview> previewPortableImport(
    String package, {
    required String passphrase,
    Iterable<MindmapNode>? baselineNodes,
    MindmapSyncPlanner? planner,
  }) async {
    final document = await _portableCodec.decode(
      package,
      passphrase: passphrase,
    );
    document.validateForImport();
    final localNodes = await _repository.listNodes();
    return MindmapPortableBackupImportPreview(
      document: document,
      plan:
          (planner ??
                  (baselineNodes == null
                      ? const MindmapSyncPlanner(
                          strategy: SyncConflictStrategy.keepRemote,
                        )
                      : _planner))
              .plan(
                localNodes: localNodes,
                remoteNodes: document.nodes,
                baselineNodes: baselineNodes ?? localNodes,
              ),
    );
  }

  Future<MindmapBackupImportReport> importBackup(
    MindmapBackupDocument document, {
    Iterable<MindmapNode> baselineNodes = const [],
    MindmapSyncPlanner? planner,
  }) => _serializeRestore(
    () => _importBackupUnlocked(
      document,
      baselineNodes: baselineNodes,
      planner: planner,
    ),
  );

  Future<MindmapBackupImportReport> _importBackupUnlocked(
    MindmapBackupDocument document, {
    required Iterable<MindmapNode> baselineNodes,
    MindmapSyncPlanner? planner,
  }) async {
    try {
      document.validateForImport();
    } on FormatException catch (error) {
      throw PortableBackupException(
        'Backup document is invalid.',
        primaryError: error,
      );
    }
    final restoredAttachmentIds = document.attachments
        .map((entry) => entry.attachment.id)
        .toSet();
    final warnings = _referencedAttachmentIds(document.nodes)
        .where((id) => !restoredAttachmentIds.contains(id))
        .map(_missingAttachmentWarning)
        .toList(growable: false);
    final attachmentRepository = document.attachments.isEmpty
        ? null
        : await _resolveAttachmentRepository();
    final NodeAttachmentRestoreRepository? restoreRepository =
        attachmentRepository is NodeAttachmentRestoreRepository
        ? attachmentRepository as NodeAttachmentRestoreRepository
        : null;
    if (document.attachments.isNotEmpty && restoreRepository == null) {
      throw const PortableBackupException('Attachment storage is unavailable.');
    }

    final List<NodeAttachmentRestoreItem> restoreItems;
    try {
      restoreItems = document.attachments
          .map(
            (entry) => NodeAttachmentRestoreItem(
              attachment: entry.attachment,
              bytes: entry.decodePayload(),
            ),
          )
          .toList(growable: false);
    } on FormatException catch (error) {
      throw PortableBackupException(
        'Backup attachment payload is invalid.',
        primaryError: error,
      );
    }
    final attachmentPlan = restoreRepository == null
        ? const NodeAttachmentRestorePlan(
            itemsToImport: [],
            identicalAttachmentIds: {},
          )
        : await _preflightAttachments(restoreRepository, restoreItems);
    final plan = await previewImport(
      document,
      baselineNodes: baselineNodes,
      planner: planner,
    );
    if (plan.hasBlockingConflicts) {
      return MindmapBackupImportReport(
        plan: plan,
        savedNodeIds: const [],
        deletedNodeIds: const [],
        warnings: warnings,
      );
    }

    final affectedNodeIds = {
      ...plan.nodesToSave.map((node) => node.id),
      ...plan.nodeIdsToDelete,
    }.toList()..sort();
    final nodeSnapshots = <String, MindmapNode?>{};
    for (final nodeId in affectedNodeIds) {
      nodeSnapshots[nodeId] = await _repository.getNode(nodeId);
    }
    final importedAttachmentIds = <String>[];
    final writtenNodes = <String, MindmapNode?>{};
    try {
      if (restoreRepository != null) {
        for (final item in attachmentPlan.itemsToImport) {
          await restoreRepository.restoreBytes(
            attachment: item.attachment,
            bytes: item.bytes,
          );
          importedAttachmentIds.add(item.attachment.id);
        }
      }
      final savedNodeIds = <String>[];
      for (final node in plan.nodesToSave) {
        final current = await _repository.getNode(node.id);
        if (current != nodeSnapshots[node.id]) {
          throw StateError('Node ${node.id} changed during restore.');
        }
        await _repository.saveNode(node);
        writtenNodes[node.id] = node;
        savedNodeIds.add(node.id);
      }
      final deletedNodeIds = <String>[];
      for (final nodeId in plan.nodeIdsToDelete) {
        final current = await _repository.getNode(nodeId);
        if (current != nodeSnapshots[nodeId]) {
          throw StateError('Node $nodeId changed during restore.');
        }
        await _repository.deleteNode(nodeId);
        writtenNodes[nodeId] = null;
        deletedNodeIds.add(nodeId);
      }
      return MindmapBackupImportReport(
        plan: plan,
        savedNodeIds: List.unmodifiable(savedNodeIds),
        deletedNodeIds: List.unmodifiable(deletedNodeIds),
        warnings: List.unmodifiable(warnings),
      );
    } catch (primaryError) {
      final cleanupErrors = <Object>[];
      for (final nodeId in affectedNodeIds) {
        if (!writtenNodes.containsKey(nodeId)) continue;
        try {
          final current = await _repository.getNode(nodeId);
          if (current != writtenNodes[nodeId]) {
            throw StateError(
              'Rollback conflict: node $nodeId changed after restore write.',
            );
          }
          final snapshot = nodeSnapshots[nodeId];
          if (snapshot == null) {
            await _repository.deleteNode(nodeId);
          } else {
            await _repository.saveNode(snapshot);
          }
        } on Object catch (error) {
          cleanupErrors.add(error);
        }
      }
      var canDeleteAttachments = cleanupErrors.isEmpty;
      if (canDeleteAttachments && importedAttachmentIds.isNotEmpty) {
        try {
          final remainingReferences = _referencedAttachmentIds(
            await _repository.listNodes(),
          ).intersection(importedAttachmentIds.toSet());
          if (remainingReferences.isNotEmpty) {
            canDeleteAttachments = false;
            cleanupErrors.add(
              StateError(
                'Rollback retained attachments still referenced by nodes: '
                '${remainingReferences.join(', ')}.',
              ),
            );
          }
        } on Object catch (error) {
          canDeleteAttachments = false;
          cleanupErrors.add(error);
        }
      }
      if (attachmentRepository != null && canDeleteAttachments) {
        for (final attachmentId in importedAttachmentIds.reversed) {
          try {
            await attachmentRepository.delete(attachmentId);
          } on Object catch (error) {
            cleanupErrors.add(error);
          }
        }
      }
      throw PortableBackupException(
        cleanupErrors.isEmpty
            ? 'Backup restore failed. Changes were rolled back.'
            : 'Backup restore failed and rollback was incomplete.',
        primaryError: primaryError,
        cleanupErrors: List.unmodifiable(cleanupErrors),
      );
    }
  }

  Future<MindmapBackupImportReport> restoreBackup(
    MindmapBackupDocument document,
  ) => _serializeRestore(() async {
    final localNodes = await _repository.listNodes();
    return _importBackupUnlocked(
      document,
      baselineNodes: localNodes,
      planner: const MindmapSyncPlanner(
        strategy: SyncConflictStrategy.keepRemote,
      ),
    );
  });

  Future<MindmapBackupImportReport> importPortableBackup(
    String package, {
    required String passphrase,
    Iterable<MindmapNode> baselineNodes = const [],
    MindmapSyncPlanner? planner,
  }) async {
    final document = await _portableCodec.decode(
      package,
      passphrase: passphrase,
    );
    return importBackup(
      document,
      baselineNodes: baselineNodes,
      planner: planner,
    );
  }

  Future<NodeAttachmentRepository?> _resolveAttachmentRepository() {
    final loader = _attachmentRepositoryLoader;
    return loader != null
        ? loader()
        : Future<NodeAttachmentRepository?>.value(_attachmentRepository);
  }

  Future<T> _serializeRestore<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _restoreTail = _restoreTail.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

Future<NodeAttachmentRestorePlan> _preflightAttachments(
  NodeAttachmentRestoreRepository repository,
  List<NodeAttachmentRestoreItem> items,
) async {
  try {
    return await repository.preflightRestore(items);
  } on Object catch (error) {
    throw PortableBackupException(
      'Backup attachment validation failed.',
      primaryError: error,
    );
  }
}

MindmapBackupWarning _missingAttachmentWarning(String attachmentId) {
  return MindmapBackupWarning(
    code: MindmapBackupWarningCode.missingAttachmentPayload,
    attachmentId: attachmentId,
    message: 'Attachment payload $attachmentId is missing.',
  );
}

Set<String> _referencedAttachmentIds(Iterable<MindmapNode> nodes) {
  final result = <String>{};
  void visit(Object? value, [String? key]) {
    if ((key == 'attachmentId' || key == 'thumbnailAttachmentId') &&
        value is String &&
        value.trim().isNotEmpty) {
      result.add(value.trim());
      return;
    }
    if (value is Map<Object?, Object?>) {
      for (final entry in value.entries) {
        visit(entry.value, entry.key is String ? entry.key as String : null);
      }
    } else if (value is Iterable<Object?>) {
      for (final item in value) {
        visit(item);
      }
    }
  }

  for (final node in nodes) {
    visit(node.data);
  }
  return result;
}
