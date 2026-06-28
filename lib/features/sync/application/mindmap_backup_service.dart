/// Application service for export/import backup sync flows.
library;

import 'dart:async';

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_repository.dart';
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

final class MindmapBackupImportReport {
  const MindmapBackupImportReport({
    required this.plan,
    required this.savedNodeIds,
    required this.deletedNodeIds,
  });

  final MindmapSyncPlan plan;
  final List<String> savedNodeIds;
  final List<String> deletedNodeIds;

  bool get blockedByConflicts => plan.hasBlockingConflicts;
}

final class MindmapBackupService {
  MindmapBackupService({
    required MindmapRepository repository,
    required FutureOr<SyncDeviceIdentity> sourceDevice,
    DateTime Function()? now,
    MindmapSyncPlanner planner = const MindmapSyncPlanner(),
    PortableMindmapBackupCodec? portableCodec,
  }) : _repository = repository,
       _sourceDevice = sourceDevice,
       _now = now ?? DateTime.now,
       _planner = planner,
       _portableCodec = portableCodec ?? PortableMindmapBackupCodec();

  final MindmapRepository _repository;
  final FutureOr<SyncDeviceIdentity> _sourceDevice;
  final DateTime Function() _now;
  final MindmapSyncPlanner _planner;
  final PortableMindmapBackupCodec _portableCodec;

  Future<MindmapBackupDocument> createBackup() async {
    final nodes = await _repository.listNodes();
    final sourceDevice = await Future<SyncDeviceIdentity>.value(_sourceDevice);
    return MindmapBackupDocument.create(
      sourceDevice: sourceDevice,
      exportedAt: _now(),
      nodes: nodes,
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

  Future<MindmapBackupImportReport> importBackup(
    MindmapBackupDocument document, {
    Iterable<MindmapNode> baselineNodes = const [],
    MindmapSyncPlanner? planner,
  }) async {
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
      );
    }

    final savedNodeIds = <String>[];
    for (final node in plan.nodesToSave) {
      await _repository.saveNode(node);
      savedNodeIds.add(node.id);
    }

    final deletedNodeIds = <String>[];
    for (final nodeId in plan.nodeIdsToDelete) {
      await _repository.deleteNode(nodeId);
      deletedNodeIds.add(nodeId);
    }

    return MindmapBackupImportReport(
      plan: plan,
      savedNodeIds: List.unmodifiable(savedNodeIds),
      deletedNodeIds: List.unmodifiable(deletedNodeIds),
    );
  }

  Future<MindmapBackupImportReport> restoreBackup(
    MindmapBackupDocument document,
  ) async {
    final localNodes = await _repository.listNodes();
    return importBackup(
      document,
      baselineNodes: localNodes,
      planner: const MindmapSyncPlanner(
        strategy: SyncConflictStrategy.keepRemote,
      ),
    );
  }

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
}
