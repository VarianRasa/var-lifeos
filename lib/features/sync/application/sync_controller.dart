/// UI-facing controller for sync account and backup actions.
library;

import 'dart:async';
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
import 'cloud_sync_service.dart';
import 'mindmap_backup_service.dart';
import 'portable_backup_codec.dart';
import 'sync_providers.dart';

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
    required Ref ref,
  }) : _authGateway = authGateway,
       _cloudSyncService = cloudSyncService,
       _backupService = backupService,
       _activityStore = activityStore,
       _restorePointStore = restorePointStore,
       _deviceIdentityStore = deviceIdentityStore,
       _now = now,
       _ref = ref,
       super(const SyncControllerState());

  final SyncAuthGateway _authGateway;
  final CloudSyncService _cloudSyncService;
  final MindmapBackupService _backupService;
  final SyncActivityStore _activityStore;
  final SyncRestorePointStore _restorePointStore;
  final SyncDeviceIdentityStore _deviceIdentityStore;
  final DateTime Function() _now;
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
  bool _hasPendingOfflineSync = false;

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
      if (_hasPendingOfflineSync) {
        syncNow();
      }
    });
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
      final activityLog = await _activityStore.recent();
      final restorePoints = await _restorePointStore.recent();

      bool autoBackupEnabled = false;
      String autoBackupFrequency = 'daily';
      try {
        autoBackupEnabled = await _prefs.getBool('auto_backup_enabled') ?? false;
        autoBackupFrequency = await _prefs.getString('auto_backup_frequency') ?? 'daily';
      } catch (_) {
        // SharedPreferencesAsync may throw if not mocked in tests
      }

      state = state.copyWith(
        authState: authState,
        activityLog: activityLog,
        restorePoints: restorePoints,
        deviceIdentity: deviceIdentity,
        autoBackupEnabled: autoBackupEnabled,
        autoBackupFrequency: autoBackupFrequency,
      );

      if (autoBackupEnabled) {
        startAutoBackup(interval: _intervalForFrequency(autoBackupFrequency));
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

  Future<void> pushBackup() async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final document = await _cloudSyncService.pushBackup();
      _pendingConflictResolutions.clear();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Backup pushed',
        lastSavedCount: document.nodes.length,
        lastDeletedCount: 0,
        lastConflictCount: 0,
        pendingConflicts: const [],
        lastSyncedAt: document.exportedAt,
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
      await _recordActivity(
        action: SyncActivityAction.push,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    }
  }

  Future<void> pullBackup() async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.pullBackup();
      invalidateMindmapStateFromRef(_ref);

      if (report.blockedByConflicts) {
        _pendingConflictResolutions.clear();
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

      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Backup pulled',
        lastSavedCount: report.savedNodeIds.length,
        lastDeletedCount: report.deletedNodeIds.length,
        lastConflictCount: 0,
        pendingConflicts: const [],
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
      await _recordActivity(
        action: SyncActivityAction.pull,
        status: SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    }
  }

  Future<void> syncNow() async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.syncNow();
      invalidateMindmapStateFromRef(_ref);

      if (report.blockedByConflicts) {
        _pendingConflictResolutions.clear();
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
      _pendingConflictResolutions.clear();
      _hasPendingOfflineSync = false;
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
      final isOffline = _isNetworkError(error);
      if (isOffline) {
        _hasPendingOfflineSync = true;
        state = state.copyWith(
          lastMessage: 'Sync queued (Offline)',
        );
        _scheduleOfflineRetry();
      } else {
        _hasPendingOfflineSync = false;
        _offlineRetryTimer?.cancel();
      }
      await _recordActivity(
        action: SyncActivityAction.syncNow,
        status: isOffline ? SyncActivityStatus.blocked : SyncActivityStatus.failed,
        message: state.lastMessage,
      );
    }
  }

  Future<void> resolveConflictsWithRemote() async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.pullBackup(
        conflictStrategy: SyncConflictStrategy.keepRemote,
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
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final document = await _cloudSyncService.pushBackup();
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

  Future<void> resolveConflictsWithNewest() async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _cloudSyncService.resolveConflictsWithLatest();
      invalidateMindmapStateFromRef(_ref);

      if (report.blockedByConflicts) {
        _pendingConflictResolutions.clear();
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
    }
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
  }) async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final report = await _backupService.importPortableBackup(
        package,
        passphrase: passphrase,
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
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      final restorePoint = await _restorePointStore.read(restorePointId);
      if (restorePoint == null) {
        throw ArgumentError('Restore point was not found.');
      }

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
    }
  }

  Future<SyncRestorePointImpact> previewRestorePoint(
    String restorePointId,
  ) async {
    final restorePoint = await _restorePointStore.read(restorePointId);
    if (restorePoint == null) {
      throw ArgumentError('Restore point was not found.');
    }

    final currentDocument = await _backupService.createBackup();
    return restorePoint.previewAgainst(currentDocument.nodes);
  }

  Future<void> deleteRestorePoint(String restorePointId) async {
    state = state.copyWith(isBusy: true, lastMessage: '');
    try {
      await _restorePointStore.delete(restorePointId);
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Restore point deleted',
        restorePoints: await _restorePointStore.recent(),
      );
    } on Object catch (error) {
      _reportFailure(error);
    }
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
    state = state.copyWith(activityLog: await _activityStore.recent());
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
    );
    await _restorePointStore.add(point);
    await _restorePointStore.prune(keepLatest: _restorePointLimit);
    state = state.copyWith(restorePoints: await _restorePointStore.recent());
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
