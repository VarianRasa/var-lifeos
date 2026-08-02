/// UI-facing controller for sync account and backup actions.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/date_utils.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../data/http_sync_remote_backup_store.dart';
import '../domain/mindmap_backup_document.dart';
import '../domain/mindmap_sync_planner.dart';
import '../domain/sync_account.dart';
import '../domain/sync_activity.dart';
import '../domain/sync_device_identity_store.dart';
import '../domain/sync_health.dart';
import '../domain/sync_restore_point.dart';
import 'attachment_sync_executor.dart';
import 'cloud_sync_service.dart';
import 'mindmap_backup_service.dart';
import 'portable_backup_codec.dart';
import 'sync_providers.dart';

enum PendingSyncOperation { sync, push, pull }

final class PendingSyncIntent {
  const PendingSyncIntent({
    required this.operation,
    required this.accountEmail,
  });

  final PendingSyncOperation operation;
  final String accountEmail;

  Map<String, Object?> toJson() => {
    'operation': operation.name,
    'accountEmail': accountEmail,
  };

  static PendingSyncIntent? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final operationName = value['operation'];
    final accountEmail = value['accountEmail'];
    if (operationName is! String || accountEmail is! String) return null;
    for (final operation in PendingSyncOperation.values) {
      if (operation.name == operationName) {
        return PendingSyncIntent(
          operation: operation,
          accountEmail: accountEmail.trim().toLowerCase(),
        );
      }
    }
    return null;
  }
}

DateTime? latestSuccessfulCloudSyncAt(Iterable<SyncActivityEntry> activity) {
  final successful = activity.where(
    (entry) =>
        entry.status == SyncActivityStatus.success &&
        switch (entry.action) {
          SyncActivityAction.push ||
          SyncActivityAction.pull ||
          SyncActivityAction.syncNow ||
          SyncActivityAction.resolveRemote ||
          SyncActivityAction.resolveLocal ||
          SyncActivityAction.resolveNewest => true,
          SyncActivityAction.signIn ||
          SyncActivityAction.signOut ||
          SyncActivityAction.exportPortable ||
          SyncActivityAction.importPortable ||
          SyncActivityAction.restorePoint => false,
        },
  );
  if (successful.isEmpty) return null;
  return successful
      .map((entry) => entry.occurredAt)
      .reduce((latest, value) => value.isAfter(latest) ? value : latest);
}

bool autoBackupIsDue({
  required DateTime now,
  required DateTime? lastSyncedAt,
  required Duration interval,
}) {
  if (lastSyncedAt == null) return true;
  return !lastSyncedAt.add(interval).isAfter(now);
}

enum SyncOperationKind { portableImport, pull, useRemote, useNewest, syncNow }

final class SyncOperationPreview {
  const SyncOperationPreview({
    required this.operation,
    required this.impact,
    required this.conflicts,
    required this.warnings,
    required this.remoteWasMissing,
    this.remoteDocument,
  });

  factory SyncOperationPreview.fromPlan({
    required SyncOperationKind operation,
    required MindmapSyncPlan plan,
    required Iterable<MindmapNode> currentNodes,
    Iterable<String> warnings = const [],
    bool remoteWasMissing = false,
    MindmapBackupDocument? remoteDocument,
  }) {
    final targetById = <String, MindmapNode>{
      for (final node in currentNodes) node.id: node,
      for (final node in plan.nodesToSave) node.id: node,
    };
    for (final nodeId in plan.nodeIdsToDelete) {
      targetById.remove(nodeId);
    }
    return SyncOperationPreview(
      operation: operation,
      impact: SyncRestorePointImpact.compare(
        currentNodes: currentNodes,
        targetNodes: targetById.values,
      ),
      conflicts: List.unmodifiable([
        ...plan.conflicts,
        ...plan.resolvedConflicts,
      ]),
      warnings: List.unmodifiable(warnings),
      remoteWasMissing: remoteWasMissing,
      remoteDocument: remoteDocument,
    );
  }

  final SyncOperationKind operation;
  final SyncRestorePointImpact impact;
  final List<SyncConflict> conflicts;
  final List<String> warnings;
  final bool remoteWasMissing;
  final MindmapBackupDocument? remoteDocument;

  bool get requiresConfirmation =>
      impact.isDestructive || conflicts.isNotEmpty || warnings.isNotEmpty;
}

final class SyncConflictSummary {
  const SyncConflictSummary({
    required this.nodeId,
    required this.kindLabel,
    required this.baselineTitle,
    required this.localTitle,
    required this.remoteTitle,
    required this.baselineDetail,
    required this.localDetail,
    required this.remoteDetail,
    this.selectedResolution = SyncResolution.unresolved,
  });

  final String nodeId;
  final String kindLabel;
  final String baselineTitle;
  final String localTitle;
  final String remoteTitle;
  final String baselineDetail;
  final String localDetail;
  final String remoteDetail;
  final SyncResolution selectedResolution;

  bool get hasSelectedResolution =>
      selectedResolution != SyncResolution.unresolved;

  String get selectedResolutionLabel {
    return switch (selectedResolution) {
      SyncResolution.unresolved => '',
      SyncResolution.useLocal => 'Local',
      SyncResolution.useRemote => 'Remote',
      SyncResolution.useDelete => 'Delete',
    };
  }

  SyncConflictSummary copyWith({SyncResolution? selectedResolution}) {
    return SyncConflictSummary(
      nodeId: nodeId,
      kindLabel: kindLabel,
      baselineTitle: baselineTitle,
      localTitle: localTitle,
      remoteTitle: remoteTitle,
      baselineDetail: baselineDetail,
      localDetail: localDetail,
      remoteDetail: remoteDetail,
      selectedResolution: selectedResolution ?? this.selectedResolution,
    );
  }
}

final class SyncControllerState {
  const SyncControllerState({
    this.authState = const SyncAuthState.signedOut(),
    this.isBusy = false,
    this.lastMessage = '',
    this.lastSavedCount = 0,
    this.lastDeletedCount = 0,
    this.lastConflictCount = 0,
    this.lastPortablePackage = '',
    this.pendingConflicts = const [],
    this.activityLog = const [],
    this.restorePoints = const [],
    this.deviceIdentity,
    this.lastSyncedAt,
    this.autoBackupEnabled = false,
    this.autoBackupFrequency = 'daily',
    this.pendingOperation = '',
    this.pendingAccountEmail = '',
    this.attachmentCompletedCount = 0,
    this.attachmentPendingCount = 0,
    this.attachmentConflictCount = 0,
    this.attachmentWarnings = const [],
  });

  final SyncAuthState authState;
  final bool isBusy;
  final String lastMessage;
  final int lastSavedCount;
  final int lastDeletedCount;
  final int lastConflictCount;
  final String lastPortablePackage;
  final List<SyncConflictSummary> pendingConflicts;
  final List<SyncActivityEntry> activityLog;
  final List<SyncRestorePoint> restorePoints;
  final SyncDeviceIdentity? deviceIdentity;
  final DateTime? lastSyncedAt;
  final bool autoBackupEnabled;
  final String autoBackupFrequency;
  final String pendingOperation;
  final String pendingAccountEmail;
  final int attachmentCompletedCount;
  final int attachmentPendingCount;
  final int attachmentConflictCount;
  final List<String> attachmentWarnings;

  bool get hasPendingOperation => pendingOperation.isNotEmpty;

  bool get isSignedIn => authState.isSignedIn;

  String get email => authState.user?.email ?? '';

  SyncHealthSnapshot get syncHealth => SyncHealthSnapshot.evaluate(
    authState: authState,
    pendingConflictCount: lastConflictCount,
    activityLog: activityLog,
    lastSyncedAt: lastSyncedAt,
  );

  SyncControllerState copyWith({
    SyncAuthState? authState,
    bool? isBusy,
    String? lastMessage,
    int? lastSavedCount,
    int? lastDeletedCount,
    int? lastConflictCount,
    String? lastPortablePackage,
    List<SyncConflictSummary>? pendingConflicts,
    List<SyncActivityEntry>? activityLog,
    List<SyncRestorePoint>? restorePoints,
    SyncDeviceIdentity? deviceIdentity,
    DateTime? lastSyncedAt,
    bool? autoBackupEnabled,
    String? autoBackupFrequency,
    String? pendingOperation,
    String? pendingAccountEmail,
    int? attachmentCompletedCount,
    int? attachmentPendingCount,
    int? attachmentConflictCount,
    List<String>? attachmentWarnings,
  }) {
    return SyncControllerState(
      authState: authState ?? this.authState,
      isBusy: isBusy ?? this.isBusy,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSavedCount: lastSavedCount ?? this.lastSavedCount,
      lastDeletedCount: lastDeletedCount ?? this.lastDeletedCount,
      lastConflictCount: lastConflictCount ?? this.lastConflictCount,
      lastPortablePackage: lastPortablePackage ?? this.lastPortablePackage,
      pendingConflicts: pendingConflicts ?? this.pendingConflicts,
      activityLog: activityLog ?? this.activityLog,
      restorePoints: restorePoints ?? this.restorePoints,
      deviceIdentity: deviceIdentity ?? this.deviceIdentity,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      autoBackupFrequency: autoBackupFrequency ?? this.autoBackupFrequency,
      pendingOperation: pendingOperation ?? this.pendingOperation,
      pendingAccountEmail: pendingAccountEmail ?? this.pendingAccountEmail,
      attachmentCompletedCount:
          attachmentCompletedCount ?? this.attachmentCompletedCount,
      attachmentPendingCount:
          attachmentPendingCount ?? this.attachmentPendingCount,
      attachmentConflictCount:
          attachmentConflictCount ?? this.attachmentConflictCount,
      attachmentWarnings: attachmentWarnings ?? this.attachmentWarnings,
    );
  }
}

final syncControllerProvider =
    StateNotifierProvider<SyncController, SyncControllerState>((ref) {
      return SyncController(
        authGateway: ref.watch(syncAuthGatewayProvider),
        cloudSyncService: ref.watch(cloudSyncServiceProvider),
        backupService: ref.watch(mindmapBackupServiceProvider),
        activityStore: ref.watch(syncActivityStoreProvider),
        restorePointStore: ref.watch(syncRestorePointStoreProvider),
        deviceIdentityStore: ref.watch(syncDeviceIdentityStoreProvider),
        now: ref.watch(syncNowProvider),
        attachmentSyncRunner: ref.watch(attachmentSyncRunnerProvider),
        ref: ref,
      );
    });

const int _restorePointLimit = 5;

final class SyncController extends StateNotifier<SyncControllerState> {
  SyncController({
    required SyncAuthGateway authGateway,
    required CloudSyncService cloudSyncService,
    required MindmapBackupService backupService,
    required SyncActivityStore activityStore,
    required SyncRestorePointStore restorePointStore,
    required SyncDeviceIdentityStore deviceIdentityStore,
    required DateTime Function() now,
    required Future<AttachmentSyncExecutionReport> Function()
    attachmentSyncRunner,
    required Ref ref,
  }) : _authGateway = authGateway,
       _cloudSyncService = cloudSyncService,
       _backupService = backupService,
       _activityStore = activityStore,
       _restorePointStore = restorePointStore,
       _deviceIdentityStore = deviceIdentityStore,
       _now = now,
       _attachmentSyncRunner = attachmentSyncRunner,
       _ref = ref,
       super(const SyncControllerState());

  final SyncAuthGateway _authGateway;
  final CloudSyncService _cloudSyncService;
  final MindmapBackupService _backupService;
  final SyncActivityStore _activityStore;
  final SyncRestorePointStore _restorePointStore;
  final SyncDeviceIdentityStore _deviceIdentityStore;
  final DateTime Function() _now;
  final Future<AttachmentSyncExecutionReport> Function() _attachmentSyncRunner;
  final Ref _ref;
  final Map<String, SyncResolution> _pendingConflictResolutions = {};
  int _activitySequence = 0;
  int _restorePointSequence = 0;

  bool get isSignedIn => state.isSignedIn;

  String get lastMessage => state.lastMessage;

  Timer? _autoBackupTimer;

  SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  void startAutoBackup({Duration interval = const Duration(hours: 24)}) {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer.periodic(interval, (timer) {
      if (state.isSignedIn && !state.isBusy) {
        syncNow();
      }
    });
  }

  void stopAutoBackup() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    try {
      await _prefs.setBool('auto_backup_enabled', enabled);
    } catch (_) {}
    state = state.copyWith(autoBackupEnabled: enabled);
    if (enabled) {
      String freq = 'daily';
      try {
        freq = await _prefs.getString('auto_backup_frequency') ?? 'daily';
      } catch (_) {}
      startAutoBackup(interval: _intervalForFrequency(freq));
    } else {
      stopAutoBackup();
    }
  }

  Future<void> setAutoBackupFrequency(String frequency) async {
    try {
      await _prefs.setString('auto_backup_frequency', frequency);
    } catch (_) {}
    state = state.copyWith(autoBackupFrequency: frequency);
    bool enabled = false;
    try {
      enabled = await _prefs.getBool('auto_backup_enabled') ?? false;
    } catch (_) {}
    if (enabled) {
      startAutoBackup(interval: _intervalForFrequency(frequency));
    }
  }

  Duration _intervalForFrequency(String freq) {
    return switch (freq) {
      'daily' => const Duration(hours: 24),
      'weekly' => const Duration(days: 7),
      'monthly' => const Duration(days: 30),
      _ => const Duration(hours: 24),
    };
  }

  Timer? _offlineRetryTimer;
  static const _pendingOfflineSyncKey = 'sync_pending_offline_retry';
  static const _pendingSyncIntentKey = 'sync_pending_operation';
  PendingSyncIntent? _pendingSyncIntent;
  bool _cloudOperationInProgress = false;

  bool _isNetworkError(Object error) {
    final str = error.toString().toLowerCase();
    return str.contains('socketexception') ||
        str.contains('httpclientexception') ||
        str.contains('connection failed') ||
        str.contains('failed host lookup') ||
        str.contains('network_error') ||
        str.contains('network error') ||
        str.contains('clientexception');
  }

  void _scheduleOfflineRetry() {
    _offlineRetryTimer?.cancel();
    _offlineRetryTimer = Timer(const Duration(seconds: 30), () {
      if (_pendingSyncIntent != null) {
        unawaited(_retryPendingSyncIntent());
      }
    });
  }

  Future<void> _setPendingSyncIntent(PendingSyncIntent? intent) async {
    _pendingSyncIntent = intent;
    state = state.copyWith(
      pendingOperation: intent?.operation.name ?? '',
      pendingAccountEmail: intent?.accountEmail ?? '',
    );
    try {
      await _prefs.remove(_pendingOfflineSyncKey);
      if (intent == null) {
        await _prefs.remove(_pendingSyncIntentKey);
      } else {
        await _prefs.setString(
          _pendingSyncIntentKey,
          jsonEncode(intent.toJson()),
        );
      }
    } on Object {
      // In-memory retry still works when preferences are unavailable.
    }
  }

  Future<void> _queueOfflineOperation(PendingSyncOperation operation) async {
    final authState = await _authGateway.currentState();
    final accountEmail = authState.user?.email.toLowerCase() ?? state.email;
    await _setPendingSyncIntent(
      PendingSyncIntent(operation: operation, accountEmail: accountEmail),
    );
    _scheduleOfflineRetry();
  }

  Future<bool> _handleOfflineOperationFailure(
    Object error, {
    required PendingSyncOperation operation,
    required String queuedMessage,
  }) async {
    final isOffline = _isNetworkError(error);
    if (isOffline) {
      await _queueOfflineOperation(operation);
      state = state.copyWith(lastMessage: queuedMessage);
    } else {
      await _setPendingSyncIntent(null);
      _offlineRetryTimer?.cancel();
    }
    return isOffline;
  }

  Future<void> _retryPendingSyncIntent() async {
    final intent = _pendingSyncIntent;
    if (intent == null || !state.isSignedIn) return;
    if (intent.accountEmail != state.email.toLowerCase()) {
      await _setPendingSyncIntent(null);
      return;
    }
    switch (intent.operation) {
      case PendingSyncOperation.sync:
        await syncNow();
      case PendingSyncOperation.push:
        await pushBackup();
      case PendingSyncOperation.pull:
        await pullBackup();
    }
  }

  Future<void> retryPendingOperation() async {
    await _retryPendingSyncIntent();
  }

  Future<void> cancelPendingOperation() async {
    await _setPendingSyncIntent(null);
    _offlineRetryTimer?.cancel();
    state = state.copyWith(lastMessage: 'Queued sync cancelled');
  }

  @override
  void dispose() {
    _autoBackupTimer?.cancel();
    _offlineRetryTimer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final authState = await _authGateway.currentState();
      final deviceIdentity = await _deviceIdentityStore.readOrCreateIdentity();
      final storedActivity = await _activityStore.recent();
      final accountEmail = authState.user?.email.toLowerCase() ?? '';
      final storedRestorePoints = await _restorePointStore.recent(
        accountEmail: accountEmail,
      );
      final activityLog = storedActivity
          .where((entry) => entry.accountEmail.toLowerCase() == accountEmail)
          .toList();
      final restorePoints = storedRestorePoints;

      bool autoBackupEnabled = false;
      String autoBackupFrequency = 'daily';
      PendingSyncIntent? pendingIntent;
      bool legacyPendingSync = false;
      try {
        autoBackupEnabled =
            await _prefs.getBool('auto_backup_enabled') ?? false;
        autoBackupFrequency =
            await _prefs.getString('auto_backup_frequency') ?? 'daily';
        final rawIntent = await _prefs.getString(_pendingSyncIntentKey);
        if (rawIntent != null) {
          pendingIntent = PendingSyncIntent.fromJson(jsonDecode(rawIntent));
        }
        legacyPendingSync =
            await _prefs.getBool(_pendingOfflineSyncKey) ?? false;
      } on Object {
        // SharedPreferencesAsync may throw if not mocked in tests.
      }
      if (pendingIntent == null && legacyPendingSync && authState.isSignedIn) {
        pendingIntent = PendingSyncIntent(
          operation: PendingSyncOperation.sync,
          accountEmail: authState.user!.email,
        );
      }
      if (pendingIntent != null &&
          pendingIntent.accountEmail != authState.user?.email.toLowerCase()) {
        pendingIntent = null;
        await _setPendingSyncIntent(null);
      } else {
        _pendingSyncIntent = pendingIntent;
      }
      final lastSyncedAt = latestSuccessfulCloudSyncAt(activityLog);
      state = state.copyWith(
        authState: authState,
        activityLog: activityLog,
        restorePoints: restorePoints,
        deviceIdentity: deviceIdentity,
        lastSyncedAt: lastSyncedAt,
        autoBackupEnabled: autoBackupEnabled,
        autoBackupFrequency: autoBackupFrequency,
        pendingOperation: pendingIntent?.operation.name ?? '',
        pendingAccountEmail: pendingIntent?.accountEmail ?? '',
      );

      final autoBackupInterval = _intervalForFrequency(autoBackupFrequency);
      if (autoBackupEnabled) {
        startAutoBackup(interval: autoBackupInterval);
      }
      if (authState.isSignedIn && pendingIntent != null) {
        await _retryPendingSyncIntent();
      } else if (authState.isSignedIn &&
          autoBackupEnabled &&
          autoBackupIsDue(
            now: _now(),
            lastSyncedAt: lastSyncedAt,
            interval: autoBackupInterval,
          )) {
        await syncNow();
      }
    } on Object catch (error) {
      _reportFailure(error);
    }
  }

  Future<void> signIn({
    required String email,
    String password = '',
    String displayName = '',
  }) async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final authState = await _authGateway.signIn(
        email: email,
        password: password,
        displayName: displayName,
      );
      _pendingConflictResolutions.clear();
      state = state.copyWith(
        authState: authState,
        isBusy: false,
        lastMessage: 'Signed in',
        lastConflictCount: 0,
        pendingConflicts: const [],
      );
    } on Object catch (error) {
      _reportFailure(error);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final authState = await _authGateway.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      _pendingConflictResolutions.clear();
      state = state.copyWith(
        authState: authState,
        isBusy: false,
        lastMessage: 'Account created',
        lastConflictCount: 0,
        pendingConflicts: const [],
      );
    } on Object catch (error) {
      _reportFailure(error);
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      await _authGateway.sendPasswordResetEmail(email: email);
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Password reset email sent',
      );
    } on Object catch (error) {
      _reportFailure(error);
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      await _authGateway.signOut();
      await _setPendingSyncIntent(null);
      _offlineRetryTimer?.cancel();
      _pendingConflictResolutions.clear();
      state = const SyncControllerState(lastMessage: 'Signed out');
    } on Object catch (error) {
      _reportFailure(error);
    }
  }

  Future<void> renameDevice(String label) async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final deviceIdentity = await _deviceIdentityStore.updateLabel(label);
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Device renamed',
        deviceIdentity: deviceIdentity,
      );
    } on Object catch (error) {
      _reportFailure(error);
    }
  }

  bool _beginCloudOperation() {
    if (_cloudOperationInProgress) return false;
    _cloudOperationInProgress = true;
    return true;
  }

  void _endCloudOperation() {
    _cloudOperationInProgress = false;
  }

  Future<void> pushBackup() async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final document = await _cloudSyncService.pushBackup();
      final attachmentReport = await _runAttachmentSync();
      await _setPendingSyncIntent(null);
      _offlineRetryTimer?.cancel();
      _pendingConflictResolutions.clear();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Backup pushed',
        lastSavedCount: document.nodes.length,
        lastDeletedCount: 0,
        lastConflictCount: 0,
        pendingConflicts: const [],
        lastSyncedAt: document.exportedAt,
        attachmentCompletedCount: attachmentReport.completed,
        attachmentPendingCount: attachmentReport.pending,
        attachmentConflictCount: attachmentReport.conflicts,
        attachmentWarnings: attachmentReport.warnings,
      );
      await _recordActivity(
        action: SyncActivityAction.push,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
      );
      await _recordRestorePoint(label: 'Cloud push', document: document);
    } on Object catch (error) {
      _reportFailure(error);
      final isOffline = await _handleOfflineOperationFailure(
        error,
        operation: PendingSyncOperation.push,
        queuedMessage: 'Push queued (Offline)',
      );
      await _recordActivity(
        action: SyncActivityAction.push,
        status: isOffline
            ? SyncActivityStatus.blocked
            : SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } finally {
      _endCloudOperation();
    }
  }

  Future<void> pullBackup({
    MindmapBackupDocument? expectedRemoteDocument,
  }) async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.pullBackup(
        expectedRemoteDocument: expectedRemoteDocument,
      );
      invalidateMindmapStateFromRef(_ref);

      if (report.blockedByConflicts) {
        _pendingConflictResolutions.clear();
        await _setPendingSyncIntent(null);
        state = state.copyWith(
          isBusy: false,
          lastMessage: 'Sync blocked by conflicts',
          lastSavedCount: 0,
          lastDeletedCount: 0,
          lastConflictCount: report.plan.conflicts.length,
          pendingConflicts: _summariesFor(report.plan.conflicts),
        );
        await _recordActivity(
          action: SyncActivityAction.pull,
          status: SyncActivityStatus.blocked,
          message: state.lastMessage,
          conflictCount: state.lastConflictCount,
        );
        return;
      }

      await _setPendingSyncIntent(null);
      _offlineRetryTimer?.cancel();
      final attachmentReport = await _runAttachmentSync();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Backup pulled',
        lastSavedCount: report.savedNodeIds.length,
        lastDeletedCount: report.deletedNodeIds.length,
        lastConflictCount: 0,
        pendingConflicts: const [],
        attachmentCompletedCount: attachmentReport.completed,
        attachmentPendingCount: attachmentReport.pending,
        attachmentConflictCount: attachmentReport.conflicts,
        attachmentWarnings: attachmentReport.warnings,
      );
      await _recordActivity(
        action: SyncActivityAction.pull,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
        deletedCount: state.lastDeletedCount,
      );
    } on Object catch (error) {
      _reportFailure(error);
      final isOffline = await _handleOfflineOperationFailure(
        error,
        operation: PendingSyncOperation.pull,
        queuedMessage: 'Pull queued (Offline)',
      );
      await _recordActivity(
        action: SyncActivityAction.pull,
        status: isOffline
            ? SyncActivityStatus.blocked
            : SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } finally {
      _endCloudOperation();
    }
  }

  Future<void> syncNow({
    MindmapBackupDocument? expectedRemoteDocument,
    bool? expectedRemoteWasMissing,
  }) async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.syncNow(
        expectedRemoteDocument: expectedRemoteDocument,
        expectedRemoteWasMissing: expectedRemoteWasMissing,
      );
      invalidateMindmapStateFromRef(_ref);

      if (report.blockedByConflicts) {
        _pendingConflictResolutions.clear();
        await _setPendingSyncIntent(null);
        state = state.copyWith(
          isBusy: false,
          lastMessage: 'Sync blocked by conflicts',
          lastSavedCount: 0,
          lastDeletedCount: 0,
          lastConflictCount: report.importReport.plan.conflicts.length,
          pendingConflicts: _summariesFor(report.importReport.plan.conflicts),
        );
        await _recordActivity(
          action: SyncActivityAction.syncNow,
          status: SyncActivityStatus.blocked,
          message: state.lastMessage,
          conflictCount: state.lastConflictCount,
        );
        return;
      }

      final pushedDocument = report.pushedDocument;
      final attachmentReport = await _runAttachmentSync();
      _pendingConflictResolutions.clear();
      await _setPendingSyncIntent(null);
      _offlineRetryTimer?.cancel();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Sync complete',
        lastSavedCount: report.remoteWasMissing
            ? pushedDocument?.nodes.length ?? 0
            : report.importReport.savedNodeIds.length,
        lastDeletedCount: report.importReport.deletedNodeIds.length,
        lastConflictCount: 0,
        pendingConflicts: const [],
        lastSyncedAt: pushedDocument?.exportedAt,
        attachmentCompletedCount: attachmentReport.completed,
        attachmentPendingCount: attachmentReport.pending,
        attachmentConflictCount: attachmentReport.conflicts,
        attachmentWarnings: attachmentReport.warnings,
      );
      await _recordActivity(
        action: SyncActivityAction.syncNow,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
        deletedCount: state.lastDeletedCount,
      );
      if (pushedDocument != null) {
        await _recordRestorePoint(label: 'Sync now', document: pushedDocument);
      }
    } on Object catch (error) {
      _reportFailure(error);
      final isOffline = await _handleOfflineOperationFailure(
        error,
        operation: PendingSyncOperation.sync,
        queuedMessage: 'Sync queued (Offline)',
      );
      await _recordActivity(
        action: SyncActivityAction.syncNow,
        status: isOffline
            ? SyncActivityStatus.blocked
            : SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } finally {
      _endCloudOperation();
    }
  }

  Future<AttachmentSyncExecutionReport> _runAttachmentSync() async {
    try {
      return await _attachmentSyncRunner();
    } on Object {
      return const AttachmentSyncExecutionReport(
        warnings: ['Attachment sync failed; metadata sync remains complete.'],
      );
    }
  }

  Future<void> resolveConflictsWithRemote({
    MindmapBackupDocument? expectedRemoteDocument,
  }) async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.pullBackup(
        conflictStrategy: SyncConflictStrategy.keepRemote,
        expectedRemoteDocument: expectedRemoteDocument,
      );
      invalidateMindmapStateFromRef(_ref);
      _pendingConflictResolutions.clear();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Remote version applied',
        lastSavedCount: report.savedNodeIds.length,
        lastDeletedCount: report.deletedNodeIds.length,
        lastConflictCount: 0,
        pendingConflicts: const [],
      );
      await _recordActivity(
        action: SyncActivityAction.resolveRemote,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
        deletedCount: state.lastDeletedCount,
      );
    } on Object catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: SyncActivityAction.resolveRemote,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } finally {
      _endCloudOperation();
    }
  }

  Future<void> resolveConflictWithRemote(String nodeId) {
    return _selectOrResolveConflict(
      nodeId: nodeId,
      resolution: SyncResolution.useRemote,
      successMessage: 'Remote version applied',
      action: SyncActivityAction.resolveRemote,
      restoreLabel: 'Remote conflict resolution',
    );
  }

  Future<void> resolveConflictsWithLocal() async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final document = await _cloudSyncService.pushBackup();
      await _setPendingSyncIntent(null);
      _offlineRetryTimer?.cancel();
      _pendingConflictResolutions.clear();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Local version kept',
        lastSavedCount: document.nodes.length,
        lastDeletedCount: 0,
        lastConflictCount: 0,
        pendingConflicts: const [],
        lastSyncedAt: document.exportedAt,
      );
      await _recordActivity(
        action: SyncActivityAction.resolveLocal,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
      );
      await _recordRestorePoint(
        label: 'Local conflict resolution',
        document: document,
      );
    } on Object catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: SyncActivityAction.resolveLocal,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } finally {
      _endCloudOperation();
    }
  }

  Future<void> resolveConflictWithLocal(String nodeId) {
    return _selectOrResolveConflict(
      nodeId: nodeId,
      resolution: SyncResolution.useLocal,
      successMessage: 'Local version kept',
      action: SyncActivityAction.resolveLocal,
      restoreLabel: 'Local conflict resolution',
    );
  }

  Future<void> resolveConflictsWithNewest({
    MindmapBackupDocument? expectedRemoteDocument,
  }) async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.resolveConflictsWithLatest(
        expectedRemoteDocument: expectedRemoteDocument,
      );
      invalidateMindmapStateFromRef(_ref);

      if (report.blockedByConflicts) {
        _pendingConflictResolutions.clear();
        await _setPendingSyncIntent(null);
        state = state.copyWith(
          isBusy: false,
          lastMessage: 'Sync blocked by conflicts',
          lastSavedCount: 0,
          lastDeletedCount: 0,
          lastConflictCount: report.importReport.plan.conflicts.length,
          pendingConflicts: _summariesFor(report.importReport.plan.conflicts),
        );
        await _recordActivity(
          action: SyncActivityAction.resolveNewest,
          status: SyncActivityStatus.blocked,
          message: state.lastMessage,
          conflictCount: state.lastConflictCount,
        );
        return;
      }

      _pendingConflictResolutions.clear();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Newest versions kept',
        lastSavedCount: report.importReport.savedNodeIds.length,
        lastDeletedCount: report.importReport.deletedNodeIds.length,
        lastConflictCount: 0,
        pendingConflicts: const [],
        lastSyncedAt: report.pushedDocument?.exportedAt,
      );
      await _recordActivity(
        action: SyncActivityAction.resolveNewest,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
        deletedCount: state.lastDeletedCount,
      );
      final pushedDocument = report.pushedDocument;
      if (pushedDocument != null) {
        await _recordRestorePoint(
          label: 'Newest conflict resolution',
          document: pushedDocument,
        );
      }
    } on Object catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: SyncActivityAction.resolveNewest,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } finally {
      _endCloudOperation();
    }
  }

  Future<void> _selectOrResolveConflict({
    required String nodeId,
    required SyncResolution resolution,
    required String successMessage,
    required SyncActivityAction action,
    required String restoreLabel,
  }) async {
    final pendingNodeIds = state.pendingConflicts
        .map((conflict) => conflict.nodeId)
        .toSet();

    if (pendingNodeIds.length > 1 && pendingNodeIds.contains(nodeId)) {
      _pendingConflictResolutions[nodeId] = resolution;
      _pendingConflictResolutions.removeWhere(
        (id, _) => !pendingNodeIds.contains(id),
      );

      final allSelected = pendingNodeIds.every(
        _pendingConflictResolutions.containsKey,
      );
      if (!allSelected) {
        state = state.copyWith(
          lastMessage: 'Resolution selected',
          lastSavedCount: 0,
          lastDeletedCount: 0,
          pendingConflicts: _summariesWithSelections(
            state.pendingConflicts,
            _pendingConflictResolutions,
          ),
        );
        return;
      }

      final selectedResolutions = Map<String, SyncResolution>.unmodifiable(
        _pendingConflictResolutions,
      );
      return _resolveConflictResolutions(
        conflictResolutions: selectedResolutions,
        successMessage: 'Selected versions applied',
        action: SyncActivityAction.syncNow,
        restoreLabel: 'Selected conflict resolution',
      );
    }

    return _resolveConflictResolutions(
      conflictResolutions: {nodeId: resolution},
      successMessage: successMessage,
      action: action,
      restoreLabel: restoreLabel,
    );
  }

  Future<void> _resolveConflictResolutions({
    required Map<String, SyncResolution> conflictResolutions,
    required String successMessage,
    required SyncActivityAction action,
    required String restoreLabel,
  }) async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.syncNow(
        conflictResolutions: conflictResolutions,
      );
      invalidateMindmapStateFromRef(_ref);

      if (report.blockedByConflicts) {
        final conflicts = report.importReport.plan.conflicts;
        _pendingConflictResolutions
          ..clear()
          ..addAll(conflictResolutions)
          ..removeWhere(
            (id, _) => conflicts.every((conflict) => conflict.nodeId != id),
          );
        state = state.copyWith(
          isBusy: false,
          lastMessage: 'Sync blocked by conflicts',
          lastSavedCount: 0,
          lastDeletedCount: 0,
          lastConflictCount: report.importReport.plan.conflicts.length,
          pendingConflicts: _summariesFor(
            conflicts,
            selectedResolutions: _pendingConflictResolutions,
          ),
        );
        await _recordActivity(
          action: action,
          status: SyncActivityStatus.blocked,
          message: state.lastMessage,
          conflictCount: state.lastConflictCount,
        );
        return;
      }

      final pushedDocument = report.pushedDocument;
      final onlyResolution = conflictResolutions.length == 1
          ? conflictResolutions.values.single
          : null;
      final savedCount = onlyResolution == SyncResolution.useLocal
          ? pushedDocument?.nodes.length ?? 0
          : report.importReport.savedNodeIds.length;
      _pendingConflictResolutions.clear();
      state = state.copyWith(
        isBusy: false,
        lastMessage: successMessage,
        lastSavedCount: savedCount,
        lastDeletedCount: report.importReport.deletedNodeIds.length,
        lastConflictCount: 0,
        pendingConflicts: const [],
        lastSyncedAt: pushedDocument?.exportedAt,
      );
      await _recordActivity(
        action: action,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
        deletedCount: state.lastDeletedCount,
      );
      if (pushedDocument != null) {
        await _recordRestorePoint(
          label: restoreLabel,
          document: pushedDocument,
        );
      }
    } on Object catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: action,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } finally {
      _endCloudOperation();
    }
  }

  Future<SyncOperationPreview> previewPortableImport({
    required String package,
    required String passphrase,
  }) async {
    final currentDocument = await _backupService.createCloudBackup();
    final preview = await _backupService.previewPortableImport(
      package,
      passphrase: passphrase,
    );
    return SyncOperationPreview.fromPlan(
      operation: SyncOperationKind.portableImport,
      plan: preview.plan,
      currentNodes: currentDocument.nodes,
      warnings: preview.document.warnings.map((warning) => warning.message),
    );
  }

  Future<SyncOperationPreview> previewPull({
    SyncConflictStrategy strategy = SyncConflictStrategy.manual,
  }) {
    return _previewCloudOperation(
      operation: switch (strategy) {
        SyncConflictStrategy.keepRemote => SyncOperationKind.useRemote,
        SyncConflictStrategy.latestUpdatedAt => SyncOperationKind.useNewest,
        SyncConflictStrategy.manual ||
        SyncConflictStrategy.keepLocal => SyncOperationKind.pull,
      },
      strategy: strategy,
    );
  }

  Future<SyncOperationPreview> previewRemote() {
    return previewPull(strategy: SyncConflictStrategy.keepRemote);
  }

  Future<SyncOperationPreview> previewNewest() {
    return previewPull(strategy: SyncConflictStrategy.latestUpdatedAt);
  }

  Future<SyncOperationPreview> previewSyncNow() async {
    final preview = await _previewCloudOperation(
      operation: SyncOperationKind.syncNow,
      strategy: SyncConflictStrategy.manual,
    );
    if (!preview.remoteWasMissing) return preview;
    final localDocument = await _backupService.createCloudBackup();
    return SyncOperationPreview.fromPlan(
      operation: SyncOperationKind.syncNow,
      plan: MindmapSyncPlan(
        nodesToSave: localDocument.nodes,
        nodeIdsToDelete: const [],
        conflicts: const [],
        resolvedConflicts: const [],
      ),
      currentNodes: const [],
      warnings: localDocument.warnings.map((warning) => warning.message),
      remoteWasMissing: true,
    );
  }

  Future<SyncOperationPreview> _previewCloudOperation({
    required SyncOperationKind operation,
    required SyncConflictStrategy strategy,
  }) async {
    final currentDocument = await _backupService.createCloudBackup();
    final preview = await _cloudSyncService.previewPull(
      conflictStrategy: strategy,
    );
    return SyncOperationPreview.fromPlan(
      operation: operation,
      plan: preview.plan,
      currentNodes: currentDocument.nodes,
      warnings:
          preview.remoteDocument?.warnings.map((warning) => warning.message) ??
          const [],
      remoteWasMissing: preview.remoteWasMissing,
      remoteDocument: preview.remoteDocument,
    );
  }

  Future<void> exportPortableBackup({required String passphrase}) async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final export = await _backupService.createPortableBackup(
        passphrase: passphrase,
      );
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Encrypted backup ready',
        lastSavedCount: export.document.nodes.length,
        lastDeletedCount: 0,
        lastConflictCount: 0,
        lastPortablePackage: export.package,
        pendingConflicts: const [],
        lastSyncedAt: export.document.exportedAt,
      );
      await _recordActivity(
        action: SyncActivityAction.exportPortable,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
      );
      await _recordRestorePoint(
        label: 'Portable export',
        document: export.document,
      );
    } on PortableBackupException catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: SyncActivityAction.exportPortable,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } on Object catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: SyncActivityAction.exportPortable,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    }
  }

  Future<void> createRestorePoint({required String label}) async {
    final document = await _backupService.createBackup();
    await _recordRestorePoint(label: label, document: document);
  }

  Future<void> importPortableBackup({
    required String package,
    required String passphrase,
    bool previewConfirmed = false,
  }) async {
    if (!previewConfirmed) {
      throw ArgumentError('Portable import preview confirmation is required.');
    }
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final currentDocument = await _backupService.createBackup();
      await _recordRestorePoint(
        label: 'Before portable import',
        document: currentDocument,
      );
      final report = await _backupService.importPortableBackup(
        package,
        passphrase: passphrase,
        baselineNodes: currentDocument.nodes,
        planner: const MindmapSyncPlanner(
          strategy: SyncConflictStrategy.keepRemote,
        ),
      );
      invalidateMindmapStateFromRef(_ref);

      if (report.blockedByConflicts) {
        _pendingConflictResolutions.clear();
        state = state.copyWith(
          isBusy: false,
          lastMessage: 'Portable import blocked by conflicts',
          lastSavedCount: 0,
          lastDeletedCount: 0,
          lastConflictCount: report.plan.conflicts.length,
          pendingConflicts: _summariesFor(report.plan.conflicts),
        );
        await _recordActivity(
          action: SyncActivityAction.importPortable,
          status: SyncActivityStatus.blocked,
          message: state.lastMessage,
          conflictCount: state.lastConflictCount,
        );
        return;
      }

      _pendingConflictResolutions.clear();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Portable backup imported',
        lastSavedCount: report.savedNodeIds.length,
        lastDeletedCount: report.deletedNodeIds.length,
        lastConflictCount: 0,
        lastPortablePackage: package,
        pendingConflicts: const [],
        attachmentWarnings: report.warnings
            .map((warning) => warning.message)
            .toList(),
      );
      await _recordActivity(
        action: SyncActivityAction.importPortable,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
        deletedCount: state.lastDeletedCount,
      );
    } on PortableBackupException catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: SyncActivityAction.importPortable,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } on Object catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: SyncActivityAction.importPortable,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    }
  }

  Future<void> restorePoint(String restorePointId) async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final restorePoint = await _ownedRestorePoint(restorePointId);
      final currentDocument = await _backupService.createBackup();
      await _recordRestorePoint(
        label: 'Before restore',
        document: currentDocument,
      );
      final report = await _backupService.restoreBackup(restorePoint.document);
      invalidateMindmapStateFromRef(_ref);
      _pendingConflictResolutions.clear();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Restore point applied',
        lastSavedCount: report.savedNodeIds.length,
        lastDeletedCount: report.deletedNodeIds.length,
        lastConflictCount: 0,
        pendingConflicts: const [],
        lastSyncedAt: restorePoint.document.exportedAt,
      );
      await _recordActivity(
        action: SyncActivityAction.restorePoint,
        status: SyncActivityStatus.success,
        message: state.lastMessage,
        savedCount: state.lastSavedCount,
        deletedCount: state.lastDeletedCount,
      );
    } on Object catch (error) {
      _reportFailure(error);
      await _recordActivity(
        action: SyncActivityAction.restorePoint,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    } finally {
      _endCloudOperation();
    }
  }

  Future<SyncRestorePointImpact> previewRestorePoint(
    String restorePointId,
  ) async {
    final restorePoint = await _ownedRestorePoint(restorePointId);
    final currentDocument = await _backupService.createBackup();
    return restorePoint.previewAgainst(currentDocument.nodes);
  }

  Future<void> deleteRestorePoint(String restorePointId) async {
    if (!_beginCloudOperation()) return;
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      await _ownedRestorePoint(restorePointId);
      await _restorePointStore.delete(restorePointId);
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Restore point deleted',
        restorePoints: await _restorePointStore.recent(
          accountEmail: state.email.toLowerCase(),
        ),
      );
    } on Object catch (error) {
      _reportFailure(error);
    } finally {
      _endCloudOperation();
    }
  }

  Future<SyncRestorePoint> _ownedRestorePoint(String restorePointId) async {
    final restorePoint = await _restorePointStore.read(restorePointId);
    if (restorePoint == null ||
        restorePoint.accountEmail.toLowerCase() != state.email.toLowerCase()) {
      throw ArgumentError('Restore point was not found.');
    }
    return restorePoint;
  }

  void _reportFailure(Object error) {
    _pendingConflictResolutions.clear();
    state = state.copyWith(
      isBusy: false,
      lastMessage: _failureMessage(error),
      lastSavedCount: 0,
      lastDeletedCount: 0,
      lastConflictCount: 0,
      pendingConflicts: const [],
    );
  }

  Future<void> _recordActivity({
    required SyncActivityAction action,
    required SyncActivityStatus status,
    required String message,
    int savedCount = 0,
    int deletedCount = 0,
    int conflictCount = 0,
  }) async {
    final occurredAt = _now();
    final entry = SyncActivityEntry(
      id: '${occurredAt.toIso8601String()}-${_activitySequence++}',
      action: action,
      status: status,
      message: message,
      occurredAt: occurredAt,
      savedCount: savedCount,
      deletedCount: deletedCount,
      conflictCount: conflictCount,
      accountEmail: state.email,
    );
    await _activityStore.add(entry);
    final accountEmail = state.email.toLowerCase();
    state = state.copyWith(
      activityLog: (await _activityStore.recent())
          .where((item) => item.accountEmail.toLowerCase() == accountEmail)
          .toList(),
    );
  }

  Future<void> _recordRestorePoint({
    required String label,
    required MindmapBackupDocument document,
  }) async {
    final createdAt = _now();
    final point = SyncRestorePoint(
      id: '${createdAt.toIso8601String()}-${_restorePointSequence++}',
      label: label,
      createdAt: createdAt,
      document: document,
      accountEmail: state.email.toLowerCase(),
    );
    await _restorePointStore.add(point);
    final accountEmail = state.email.toLowerCase();
    await _restorePointStore.prune(
      keepLatest: _restorePointLimit,
      accountEmail: accountEmail,
    );
    state = state.copyWith(
      restorePoints: await _restorePointStore.recent(
        accountEmail: accountEmail,
      ),
    );
  }
}

List<SyncConflictSummary> _summariesFor(
  Iterable<SyncConflict> conflicts, {
  Map<String, SyncResolution> selectedResolutions = const {},
}) {
  return List.unmodifiable(
    conflicts.map(
      (conflict) => _summaryFor(
        conflict,
        selectedResolution:
            selectedResolutions[conflict.nodeId] ?? SyncResolution.unresolved,
      ),
    ),
  );
}

List<SyncConflictSummary> _summariesWithSelections(
  Iterable<SyncConflictSummary> conflicts,
  Map<String, SyncResolution> selectedResolutions,
) {
  return List.unmodifiable(
    conflicts.map(
      (conflict) => conflict.copyWith(
        selectedResolution:
            selectedResolutions[conflict.nodeId] ?? SyncResolution.unresolved,
      ),
    ),
  );
}

SyncConflictSummary _summaryFor(
  SyncConflict conflict, {
  SyncResolution selectedResolution = SyncResolution.unresolved,
}) {
  return SyncConflictSummary(
    nodeId: conflict.nodeId,
    kindLabel: _conflictKindLabel(conflict.kind),
    baselineTitle: conflict.baselineNode?.title ?? '',
    localTitle: conflict.localNode?.title ?? '',
    remoteTitle: conflict.remoteNode?.title ?? '',
    baselineDetail: _conflictNodeDetail(conflict.baselineNode),
    localDetail: _conflictNodeDetail(conflict.localNode),
    remoteDetail: _conflictNodeDetail(conflict.remoteNode),
    selectedResolution: selectedResolution,
  );
}

String _conflictNodeDetail(MindmapNode? node) {
  if (node == null) return '';

  final parts = [
    node.type.label,
    dayKey(node.day),
    node.status.label,
    if (node.priority != NodePriority.none) node.priority.label,
    'Updated ${_minuteKey(node.updatedAt)}',
  ];
  return parts.join(' / ');
}

String _minuteKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day $hour:$minute';
}

String _conflictKindLabel(SyncConflictKind kind) {
  return switch (kind) {
    SyncConflictKind.editEdit => 'Both edited',
    SyncConflictKind.deleteEdit => 'Delete/edit',
    SyncConflictKind.createCreate => 'Both created',
  };
}

String _failureMessage(Object error) {
  if (error is SyncRemoteStoreException) {
    return error.message;
  }
  if (error is SyncAuthException) {
    return error.message;
  }
  if (error is PortableBackupException) {
    return error.message;
  }
  if (error is SyncAuthRequiredException) {
    return 'Sign in is required.';
  }
  if (error is ArgumentError) {
    return error.message?.toString() ?? 'Sync request is invalid.';
  }
  return 'Sync failed. Please try again.';
}
