/// Cloud sync orchestration over auth, remote backup storage, and local data.
library;

import 'dart:async';

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_repository.dart';
import '../domain/mindmap_backup_document.dart';
import '../domain/mindmap_sync_planner.dart';
import '../domain/sync_account.dart';
import '../domain/sync_state_store.dart';
import 'mindmap_backup_service.dart';

final class SyncAuthRequiredException implements Exception {
  const SyncAuthRequiredException();

  @override
  String toString() => 'SyncAuthRequiredException: sign-in is required.';
}

final class CloudSyncPreview {
  const CloudSyncPreview({
    required this.plan,
    required this.remoteWasMissing,
    this.remoteDocument,
  });

  final MindmapSyncPlan plan;
  final bool remoteWasMissing;
  final MindmapBackupDocument? remoteDocument;
}

final class CloudSyncReport {
  const CloudSyncReport({
    required this.importReport,
    required this.remoteWasMissing,
    this.pushedDocument,
  });

  final MindmapBackupImportReport importReport;
  final bool remoteWasMissing;
  final MindmapBackupDocument? pushedDocument;

  bool get blockedByConflicts => importReport.blockedByConflicts;
}

final class CloudSyncService {
  CloudSyncService({
    required MindmapRepository repository,
    required SyncAuthGateway authGateway,
    required SyncRemoteBackupStore remoteStore,
    required FutureOr<SyncDeviceIdentity> sourceDevice,
    SyncStateStore? syncStateStore,
    DateTime Function()? now,
    MindmapSyncPlanner planner = const MindmapSyncPlanner(),
    MindmapBackupService? backupService,
  }) : _authGateway = authGateway,
       _remoteStore = remoteStore,
       _syncStateStore = syncStateStore,
       _now = now ?? DateTime.now,
       _backupService =
           backupService ??
           MindmapBackupService(
             repository: repository,
             sourceDevice: sourceDevice,
             now: now,
             planner: planner,
           );

  final SyncAuthGateway _authGateway;
  final SyncRemoteBackupStore _remoteStore;
  final SyncStateStore? _syncStateStore;
  final DateTime Function() _now;
  final MindmapBackupService _backupService;

  Future<MindmapBackupDocument> pushBackup() async {
    final user = await _requireUser();
    final document = await _backupService.createCloudBackup();
    await _remoteStore.uploadBackup(user, document);
    await _saveBaseline(user, document);
    return document;
  }

  Future<CloudSyncPreview> previewPull({
    SyncConflictStrategy conflictStrategy = SyncConflictStrategy.manual,
    Map<String, SyncResolution> conflictResolutions = const {},
  }) async {
    final user = await _requireUser();
    final document = await _remoteStore.fetchLatestBackup(user);
    if (document == null) {
      return CloudSyncPreview(
        plan: _emptyImportReport().plan,
        remoteWasMissing: true,
      );
    }

    final plan = await _backupService.previewImport(
      document,
      baselineNodes: await _storedBaselineNodes(user),
      planner: MindmapSyncPlanner(
        strategy: conflictStrategy,
        conflictResolutions: conflictResolutions,
      ),
    );
    return CloudSyncPreview(
      plan: plan,
      remoteWasMissing: false,
      remoteDocument: document,
    );
  }

  Future<MindmapBackupImportReport> pullBackup({
    Iterable<MindmapNode>? baselineNodes,
    SyncConflictStrategy conflictStrategy = SyncConflictStrategy.manual,
    Map<String, SyncResolution> conflictResolutions = const {},
    MindmapBackupDocument? expectedRemoteDocument,
  }) async {
    final user = await _requireUser();
    final document = await _remoteStore.fetchLatestBackup(user);
    if (expectedRemoteDocument != null &&
        !_sameBackupRevision(document, expectedRemoteDocument)) {
      throw StateError(
        'Remote backup changed. Preview again before continuing.',
      );
    }
    if (document == null) {
      return const MindmapBackupImportReport(
        plan: MindmapSyncPlan(
          nodesToSave: [],
          nodeIdsToDelete: [],
          conflicts: [],
          resolvedConflicts: [],
        ),
        savedNodeIds: [],
        deletedNodeIds: [],
      );
    }

    final baseline = baselineNodes ?? await _storedBaselineNodes(user);
    final report = await _backupService.importBackup(
      document,
      baselineNodes: baseline,
      planner: MindmapSyncPlanner(
        strategy: conflictStrategy,
        conflictResolutions: conflictResolutions,
      ),
    );
    if (!report.blockedByConflicts) {
      await _saveBaseline(user, document);
    }

    return report;
  }

  Future<CloudSyncReport> syncNow({
    SyncConflictStrategy conflictStrategy = SyncConflictStrategy.manual,
    Map<String, SyncResolution> conflictResolutions = const {},
    MindmapBackupDocument? expectedRemoteDocument,
    bool? expectedRemoteWasMissing,
  }) async {
    final user = await _requireUser();
    final remoteDocument = await _remoteStore.fetchLatestBackup(user);
    if (expectedRemoteWasMissing != null &&
        expectedRemoteWasMissing != (remoteDocument == null)) {
      throw StateError(
        'Remote backup changed. Preview again before continuing.',
      );
    }
    if (expectedRemoteDocument != null &&
        !_sameBackupRevision(remoteDocument, expectedRemoteDocument)) {
      throw StateError(
        'Remote backup changed. Preview again before continuing.',
      );
    }
    if (remoteDocument == null) {
      final document = await _backupService.createCloudBackup();
      await _remoteStore.uploadBackup(user, document);
      await _saveBaseline(user, document);
      return CloudSyncReport(
        importReport: _emptyImportReport(),
        remoteWasMissing: true,
        pushedDocument: document,
      );
    }

    final report = await _backupService.importBackup(
      remoteDocument,
      baselineNodes: await _storedBaselineNodes(user),
      planner: MindmapSyncPlanner(
        strategy: conflictStrategy,
        conflictResolutions: conflictResolutions,
      ),
    );
    if (report.blockedByConflicts) {
      return CloudSyncReport(importReport: report, remoteWasMissing: false);
    }

    final mergedDocument = await _backupService.createCloudBackup();
    await _remoteStore.uploadBackup(user, mergedDocument);
    await _saveBaseline(user, mergedDocument);
    return CloudSyncReport(
      importReport: report,
      remoteWasMissing: false,
      pushedDocument: mergedDocument,
    );
  }

  Future<CloudSyncReport> resolveConflictsWithLatest({
    MindmapBackupDocument? expectedRemoteDocument,
  }) {
    return syncNow(
      conflictStrategy: SyncConflictStrategy.latestUpdatedAt,
      expectedRemoteDocument: expectedRemoteDocument,
    );
  }

  Future<SyncUser> _requireUser() async {
    final state = await _authGateway.currentState();
    final user = state.user;
    if (!state.isSignedIn || user == null) {
      throw const SyncAuthRequiredException();
    }
    return user;
  }

  Future<List<MindmapNode>> _storedBaselineNodes(SyncUser user) async {
    final snapshot = await _syncStateStore?.readSnapshot(user);
    return snapshot?.baseline.nodes ?? const <MindmapNode>[];
  }

  Future<void> _saveBaseline(
    SyncUser user,
    MindmapBackupDocument document,
  ) async {
    final syncStateStore = _syncStateStore;
    if (syncStateStore == null) return;

    await syncStateStore.saveSnapshot(
      user,
      SyncSnapshot(userId: user.id, syncedAt: _now(), baseline: document),
    );
  }
}

bool _sameBackupRevision(
  MindmapBackupDocument? current,
  MindmapBackupDocument expected,
) {
  if (current == null) return false;
  return current.type == expected.type &&
      current.schemaVersion == expected.schemaVersion &&
      current.exportedAt == expected.exportedAt &&
      current.sourceDevice == expected.sourceDevice &&
      _sameNodes(current.nodes, expected.nodes) &&
      _sameAttachmentRevisions(current.attachments, expected.attachments);
}

bool _sameNodes(List<MindmapNode> left, List<MindmapNode> right) {
  if (left.length != right.length) return false;
  final rightById = {for (final node in right) node.id: node};
  return left.every((node) => rightById[node.id] == node);
}

bool _sameAttachmentRevisions(
  List<MindmapBackupAttachment> left,
  List<MindmapBackupAttachment> right,
) {
  if (left.length != right.length) return false;
  final rightById = {
    for (final entry in right) entry.attachment.id: entry.attachment,
  };
  return left.every((entry) {
    final expected = rightById[entry.attachment.id];
    return expected != null &&
        expected.checksum == entry.attachment.checksum &&
        expected.byteLength == entry.attachment.byteLength;
  });
}

MindmapBackupImportReport _emptyImportReport() {
  return const MindmapBackupImportReport(
    plan: MindmapSyncPlan(
      nodesToSave: [],
      nodeIdsToDelete: [],
      conflicts: [],
      resolvedConflicts: [],
    ),
    savedNodeIds: [],
    deletedNodeIds: [],
  );
}
