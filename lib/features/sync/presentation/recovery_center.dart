import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mindmap/application/mindmap_mutation_controller.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/drawing_draft_checkpoint.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_type_payloads.dart';
import '../application/sync_controller.dart';
import '../domain/sync_activity.dart';
import '../domain/sync_restore_point.dart';

class RecoveryCenterPage extends StatelessWidget {
  const RecoveryCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: RecoveryCenter());
  }
}

class RecoveryCenter extends ConsumerStatefulWidget {
  const RecoveryCenter({super.key});

  @override
  ConsumerState<RecoveryCenter> createState() => _RecoveryCenterState();
}

class _RecoveryCenterState extends ConsumerState<RecoveryCenter> {
  final _passphraseController = TextEditingController();
  final _packageController = TextEditingController();
  final _deviceNameController = TextEditingController();
  String _lastDeviceLabel = '';
  String _restoreSource = SyncRestorePointTimeline.allSourcesLabel;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (mounted) unawaited(ref.read(syncControllerProvider.notifier).load());
    });
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _packageController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(syncControllerProvider);
    final nodes = ref.watch(allMindmapNodesProvider);
    final drafts = ref.watch(drawingDraftCheckpointsProvider);
    _syncDeviceName(state.deviceIdentity?.label ?? '');

    return SafeArea(
      child: nodes.when(
        loading: () => Semantics(
          liveRegion: true,
          label: 'Recovery data loading',
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => Semantics(
          liveRegion: true,
          child: const Center(child: Text('Recovery data unavailable')),
        ),
        data: (localNodes) => LayoutBuilder(
          builder: (context, constraints) {
            final left = <Widget>[
              _Section(
                title: 'Health & account',
                child: _healthAndAccount(state, localNodes.length),
              ),
              _Section(
                title: 'Recover data',
                child: _recoverData(state, localNodes),
              ),
              _Section(
                title: 'Drawing drafts',
                child: drafts.when(
                  loading: () => Semantics(
                    liveRegion: true,
                    label: 'Drawing drafts loading',
                    child: const LinearProgressIndicator(),
                  ),
                  error: (_, _) => Semantics(
                    liveRegion: true,
                    child: const Text('Drawing drafts unavailable'),
                  ),
                  data: (checkpoints) =>
                      _drawingDrafts(checkpoints, localNodes),
                ),
              ),
            ];
            final right = <Widget>[
              _Section(
                title: 'Sync & attachments',
                child: _syncAndAttachments(
                  state,
                  localNodes,
                  'Firebase sync backend',
                ),
              ),
              _Section(title: 'Activity', child: _activity(state)),
            ];
            return ListView(
              key: const ValueKey('recovery-center'),
              padding: const EdgeInsets.all(16),
              children: [
                Text('Recovery Center', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Preview changes before data or cloud state is replaced.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                if (constraints.maxWidth < 1024)
                  _SectionColumn(
                    key: const ValueKey('recovery-single-column'),
                    children: [...left, ...right],
                  )
                else
                  Row(
                    key: const ValueKey('recovery-two-column'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _SectionColumn(children: left)),
                      const SizedBox(width: 16),
                      Expanded(child: _SectionColumn(children: right)),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _healthAndAccount(SyncControllerState state, int nodeCount) {
    final health = state.syncHealth;
    final lastSync = state.lastSyncedAt;
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.monitor_heart_outlined),
          title: Text('Sync health: ${health.label}'),
          subtitle: Text(
            '${health.detail}\n$nodeCount local nodes · '
            '${lastSync == null ? 'Never synced' : 'Last sync ${_time(lastSync)}'}',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(state.isSignedIn ? state.email : 'Signed out'),
          subtitle: Text(
            state.deviceIdentity == null
                ? 'Device identity loading'
                : '${state.deviceIdentity!.label} · ${state.deviceIdentity!.id}',
          ),
          trailing: FilledButton.tonal(
            key: const ValueKey('sync-sign-in-button'),
            onPressed: state.isBusy ? null : () => _openAuth(state),
            child: Text(state.isSignedIn ? 'Sign out' : 'Sign in'),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: constraints.maxWidth > 288
                    ? constraints.maxWidth - 56
                    : constraints.maxWidth,
                child: TextField(
                  key: const ValueKey('sync-device-name-field'),
                  controller: _deviceNameController,
                  enabled: !state.isBusy,
                  decoration: const InputDecoration(
                    labelText: 'Device name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton.filledTonal(
                key: const ValueKey('sync-device-save-button'),
                tooltip: 'Save device name',
                onPressed: state.isBusy
                    ? null
                    : () => ref
                          .read(syncControllerProvider.notifier)
                          .renameDevice(_deviceNameController.text),
                icon: const Icon(Icons.save_outlined),
              ),
            ],
          ),
        ),
        SwitchListTile(
          key: const ValueKey('auto-backup-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Automatic backup'),
          value: state.autoBackupEnabled,
          onChanged: state.isBusy
              ? null
              : ref.read(syncControllerProvider.notifier).setAutoBackupEnabled,
        ),
        DropdownButtonFormField<String>(
          key: const ValueKey('auto-backup-frequency'),
          isExpanded: true,
          initialValue: state.autoBackupFrequency,
          decoration: const InputDecoration(
            labelText: 'Backup frequency',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: state.isBusy
              ? null
              : (value) {
                  if (value != null) {
                    unawaited(
                      ref
                          .read(syncControllerProvider.notifier)
                          .setAutoBackupFrequency(value),
                    );
                  }
                },
        ),
        if (state.hasPendingOperation)
          ListTile(
            key: const ValueKey('sync-pending-operation-card'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_send_outlined),
            title: Text('${state.pendingOperation.toUpperCase()} queued'),
            subtitle: Text(state.pendingAccountEmail),
            trailing: Wrap(
              children: [
                TextButton(
                  key: const ValueKey('sync-retry-pending-button'),
                  onPressed: state.isBusy
                      ? null
                      : ref
                            .read(syncControllerProvider.notifier)
                            .retryPendingOperation,
                  child: const Text('Retry'),
                ),
                TextButton(
                  key: const ValueKey('sync-cancel-pending-button'),
                  onPressed: state.isBusy
                      ? null
                      : ref
                            .read(syncControllerProvider.notifier)
                            .cancelPendingOperation,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _recoverData(SyncControllerState state, List<MindmapNode> localNodes) {
    return Column(
      children: [
        TextField(
          key: const ValueKey('portable-passphrase-field'),
          controller: _passphraseController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Backup passphrase',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('portable-package-field'),
          controller: _packageController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Encrypted package',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('portable-export-button'),
              onPressed: state.isBusy ? null : _exportPortable,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Export'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('portable-import-button'),
              onPressed: state.isBusy ? null : _previewPortableImport,
              icon: const Icon(Icons.restore_page_outlined),
              label: const Text('Preview import'),
            ),
          ],
        ),
        if (state.restorePoints.isNotEmpty) ...[
          const Divider(height: 24),
          _restorePoints(state, localNodes),
        ],
      ],
    );
  }

  Widget _drawingDrafts(
    List<DrawingDraftCheckpoint> checkpoints,
    List<MindmapNode> nodes,
  ) {
    if (checkpoints.isEmpty) return const Text('No drawing drafts.');
    final byId = <String, MindmapNode>{for (final node in nodes) node.id: node};
    return Column(
      children: [
        for (final checkpoint in checkpoints)
          Builder(
            builder: (context) {
              final node = byId[checkpoint.nodeId];
              final status = checkpoint.statusFor(node);
              final errors = node == null
                  ? const <String>[]
                  : checkpoint.validateFor(node);
              return ListTile(
                key: ValueKey('drawing-draft-${checkpoint.nodeId}'),
                contentPadding: EdgeInsets.zero,
                title: Text(node?.title ?? checkpoint.nodeId),
                subtitle: Text(
                  '${status.name} · generation ${checkpoint.generation}'
                  '${errors.isEmpty ? '' : '\n${errors.first}'}',
                ),
                trailing: Wrap(
                  children: [
                    TextButton(
                      key: ValueKey(
                        'drawing-draft-recover-${checkpoint.nodeId}',
                      ),
                      onPressed:
                          status != DrawingDraftStatus.orphan && errors.isEmpty
                          ? () => _recoverDrawingDraft(checkpoint, node!)
                          : null,
                      child: const Text('Recover'),
                    ),
                    TextButton(
                      key: ValueKey(
                        'drawing-draft-discard-${checkpoint.nodeId}',
                      ),
                      onPressed: () => ref
                          .read(drawingDraftStoreProvider)
                          .deleteIfGeneration(
                            checkpoint.nodeId,
                            checkpoint.generation,
                          ),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _recoverDrawingDraft(
    DrawingDraftCheckpoint checkpoint,
    MindmapNode node,
  ) async {
    final store = ref.read(drawingDraftStoreProvider);
    final currentCheckpoint = await store.get(checkpoint.nodeId);
    final current = await ref.read(mindmapRepositoryProvider).getNode(node.id);
    if (current == null ||
        currentCheckpoint?.generation != checkpoint.generation) {
      ref.invalidate(drawingDraftCheckpointsProvider);
      return;
    }
    final errors = checkpoint.validateFor(current);
    if (errors.isNotEmpty) return;
    final payload = CanvasPayload.fromNode(
      current.copyWith(data: checkpoint.data),
    );
    await ref
        .read(mindmapMutationControllerProvider)
        .saveNode(
          current.copyWith(
            data: payload.toData(current.data),
            updatedAt: DateTime.now(),
          ),
        );
    await store.deleteIfGeneration(checkpoint.nodeId, checkpoint.generation);
  }

  Widget _syncAndAttachments(
    SyncControllerState state,
    List<MindmapNode> localNodes,
    String backend,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(backend),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('sync-now-button'),
              onPressed: state.isBusy || !state.isSignedIn
                  ? null
                  : () => _previewCloud(
                      preview: ref
                          .read(syncControllerProvider.notifier)
                          .previewSyncNow,
                      execute: (preview) => ref
                          .read(syncControllerProvider.notifier)
                          .syncNow(
                            expectedRemoteDocument: preview.remoteDocument,
                            expectedRemoteWasMissing: preview.remoteWasMissing,
                          ),
                      actionLabel: 'Sync now',
                    ),
              icon: const Icon(Icons.sync_outlined),
              label: const Text('Sync now'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('sync-pull-button'),
              onPressed: state.isBusy || !state.isSignedIn
                  ? null
                  : () => _previewCloud(
                      preview: ref
                          .read(syncControllerProvider.notifier)
                          .previewPull,
                      execute: (preview) => ref
                          .read(syncControllerProvider.notifier)
                          .pullBackup(
                            expectedRemoteDocument: preview.remoteDocument,
                          ),
                      actionLabel: 'Pull',
                    ),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Pull'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('sync-push-button'),
              onPressed: state.isBusy || !state.isSignedIn
                  ? null
                  : () => _confirmOverwrite(
                      title: 'Overwrite cloud backup?',
                      detail:
                          '${localNodes.length} local nodes will replace cloud metadata. '
                          '${state.attachmentPendingCount} attachments are pending.',
                      actionLabel: 'Push',
                      action: ref
                          .read(syncControllerProvider.notifier)
                          .pushBackup,
                    ),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Push'),
            ),
          ],
        ),
        if (state.lastConflictCount > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                key: const ValueKey('sync-use-remote-button'),
                onPressed: state.isBusy
                    ? null
                    : () => _previewCloud(
                        preview: ref
                            .read(syncControllerProvider.notifier)
                            .previewRemote,
                        execute: (preview) => ref
                            .read(syncControllerProvider.notifier)
                            .resolveConflictsWithRemote(
                              expectedRemoteDocument: preview.remoteDocument,
                            ),
                        actionLabel: 'Use remote',
                      ),
                child: const Text('Use remote'),
              ),
              FilledButton.tonal(
                key: const ValueKey('sync-use-newest-button'),
                onPressed: state.isBusy
                    ? null
                    : () => _previewCloud(
                        preview: ref
                            .read(syncControllerProvider.notifier)
                            .previewNewest,
                        execute: (preview) => ref
                            .read(syncControllerProvider.notifier)
                            .resolveConflictsWithNewest(
                              expectedRemoteDocument: preview.remoteDocument,
                            ),
                        actionLabel: 'Use newest',
                      ),
                child: const Text('Use newest'),
              ),
              OutlinedButton(
                key: const ValueKey('sync-keep-local-button'),
                onPressed: state.isBusy
                    ? null
                    : () => _confirmOverwrite(
                        title: 'Replace cloud with local data?',
                        detail:
                            '${localNodes.length} local nodes and local attachment state will be pushed.',
                        actionLabel: 'Keep local',
                        action: ref
                            .read(syncControllerProvider.notifier)
                            .resolveConflictsWithLocal,
                      ),
                child: const Text('Keep local'),
              ),
            ],
          ),
        ],
        const Divider(height: 24),
        Text(
          'Attachments: ${state.attachmentCompletedCount} complete · '
          '${state.attachmentPendingCount} pending · '
          '${state.attachmentConflictCount} conflicts',
        ),
        for (final warning in state.attachmentWarnings)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(warning),
          ),
        if (state.lastMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const ValueKey('sync-last-message'),
            liveRegion: true,
            child: Text(state.lastMessage),
          ),
        ],
        if (state.pendingConflicts.isNotEmpty) ...[
          const Divider(height: 24),
          Text('Conflicts', style: Theme.of(context).textTheme.titleSmall),
          for (final conflict in state.pendingConflicts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${conflict.kindLabel}: ${conflict.nodeId}'),
              subtitle: Text(
                'Local: ${conflict.localTitle.isEmpty ? '-' : conflict.localTitle}\n'
                'Remote: ${conflict.remoteTitle.isEmpty ? '-' : conflict.remoteTitle}',
              ),
              trailing: Wrap(
                children: [
                  TextButton(
                    key: ValueKey('sync-conflict-use-local-${conflict.nodeId}'),
                    onPressed: state.isBusy
                        ? null
                        : () => _confirmOverwrite(
                            title: 'Keep local conflict version?',
                            detail: conflict.localTitle,
                            actionLabel: 'Use local',
                            action: () => ref
                                .read(syncControllerProvider.notifier)
                                .resolveConflictWithLocal(conflict.nodeId),
                          ),
                    child: const Text('Local'),
                  ),
                  TextButton(
                    key: ValueKey(
                      'sync-conflict-use-remote-${conflict.nodeId}',
                    ),
                    onPressed: state.isBusy
                        ? null
                        : () => _confirmRemoteConflict(conflict),
                    child: const Text('Remote'),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _activity(SyncControllerState state) {
    if (state.activityLog.isEmpty) {
      return const Text('No recovery activity yet.');
    }
    return Column(
      children: [
        for (final entry in state.activityLog.take(10))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_activityIcon(entry.status)),
            title: Text('${entry.actionLabel} · ${entry.statusLabel}'),
            subtitle: Text(
              'Result: ${entry.message}\n'
              'Saved ${entry.savedCount} / Deleted ${entry.deletedCount} / '
              'Conflicts ${entry.conflictCount}',
            ),
            trailing: Text(_time(entry.occurredAt)),
          ),
      ],
    );
  }

  Widget _restorePoints(
    SyncControllerState state,
    List<MindmapNode> currentNodes,
  ) {
    final timeline = SyncRestorePointTimeline.create(
      points: state.restorePoints,
      selectedSource: _restoreSource,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Restore points', style: Theme.of(context).textTheme.titleSmall),
        if (timeline.sourceLabels.length > 1)
          Wrap(
            spacing: 8,
            children: [
              for (final source in timeline.sourceLabels)
                ChoiceChip(
                  key: ValueKey('restore-source-filter-$source'),
                  label: Text(source),
                  selected: timeline.selectedSource == source,
                  onSelected: (selected) {
                    if (selected) setState(() => _restoreSource = source);
                  },
                ),
            ],
          ),
        for (
          var index = 0;
          index < timeline.filteredPoints.take(5).length;
          index++
        )
          Builder(
            builder: (context) {
              final point = timeline.filteredPoints[index];
              final impact = point.previewAgainst(currentNodes);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_toggle_off_outlined),
                title: Text(point.label),
                subtitle: Text(
                  '${point.nodeCount} nodes · ${point.deviceLabel}\n'
                  'Impact: ${impact.summaryLabel} · ${impact.riskLabel}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      key: ValueKey('restore-point-$index-button'),
                      tooltip: 'Preview restore point',
                      onPressed: state.isBusy
                          ? null
                          : () => _previewRestorePoint(point),
                      icon: const Icon(Icons.restore_page_outlined),
                    ),
                    IconButton(
                      key: ValueKey('restore-point-$index-delete-button'),
                      tooltip: 'Delete restore point',
                      onPressed: state.isBusy
                          ? null
                          : () => _confirmDeleteRestorePoint(point),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _exportPortable() async {
    final controller = ref.read(syncControllerProvider.notifier);
    await controller.exportPortableBackup(
      passphrase: _passphraseController.text,
    );
    if (!mounted) return;
    final package = ref.read(syncControllerProvider).lastPortablePackage;
    if (package.isNotEmpty) {
      _packageController.text = package;
    }
  }

  Future<void> _previewPortableImport() async {
    try {
      final controller = ref.read(syncControllerProvider.notifier);
      final preview = await controller.previewPortableImport(
        package: _packageController.text,
        passphrase: _passphraseController.text,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _OperationPreviewDialog(
          title: 'Portable import preview',
          actionLabel: 'Import',
          preview: preview,
        ),
      );
      if (confirmed ?? false) {
        await controller.importPortableBackup(
          package: _packageController.text,
          passphrase: _passphraseController.text,
          previewConfirmed: true,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Preview failed: $error')));
    }
  }

  Future<void> _previewCloud({
    required Future<SyncOperationPreview> Function() preview,
    required Future<void> Function(SyncOperationPreview result) execute,
    required String actionLabel,
  }) async {
    try {
      final result = await preview();
      if (!mounted) return;
      if (!result.requiresConfirmation) {
        await execute(result);
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _OperationPreviewDialog(
          title: '$actionLabel preview',
          actionLabel: actionLabel,
          preview: result,
        ),
      );
      if (confirmed ?? false) await execute(result);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Preview failed: $error')));
    }
  }

  Future<void> _confirmRemoteConflict(SyncConflictSummary conflict) async {
    final remoteDeletesLocal = conflict.remoteTitle.isEmpty;
    var destructiveConfirmed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Use remote version?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                remoteDeletesLocal
                    ? 'Remote deleted this node. Applying remote will delete the local edited node.'
                    : 'Local changes will be replaced by ${conflict.remoteTitle}.',
              ),
              if (remoteDeletesLocal)
                CheckboxListTile(
                  key: const ValueKey(
                    'remote-conflict-destructive-confirmation-checkbox',
                  ),
                  contentPadding: EdgeInsets.zero,
                  value: destructiveConfirmed,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I understand the local node will be deleted',
                  ),
                  onChanged: (value) => setDialogState(
                    () => destructiveConfirmed = value ?? false,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('remote-conflict-confirm-button'),
              style: _dangerButtonStyle(context),
              onPressed: !remoteDeletesLocal || destructiveConfirmed
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Use remote'),
            ),
          ],
        ),
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(syncControllerProvider.notifier)
          .resolveConflictWithRemote(conflict.nodeId);
    }
  }

  Future<void> _confirmOverwrite({
    required String title,
    required String detail,
    required String actionLabel,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('overwrite-confirm-button'),
            style: _dangerButtonStyle(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await action();
  }

  Future<void> _previewRestorePoint(SyncRestorePoint point) async {
    final controller = ref.read(syncControllerProvider.notifier);
    final impact = await controller.previewRestorePoint(point.id);
    if (!mounted) return;
    final preview = SyncOperationPreview(
      operation: SyncOperationKind.portableImport,
      impact: impact,
      conflicts: const [],
      warnings: const [],
      remoteWasMissing: false,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _OperationPreviewDialog(
        title: 'Restore preview',
        actionLabel: 'Restore',
        preview: preview,
      ),
    );
    if (confirmed ?? false) await controller.restorePoint(point.id);
  }

  Future<void> _confirmDeleteRestorePoint(SyncRestorePoint point) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete restore point?'),
        content: Text(point.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('delete-restore-point-confirm-button'),
            style: _dangerButtonStyle(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(syncControllerProvider.notifier)
          .deleteRestorePoint(point.id);
    }
  }

  Future<void> _openAuth(SyncControllerState state) async {
    final controller = ref.read(syncControllerProvider.notifier);
    if (state.isSignedIn) {
      await controller.signOut();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _SyncAuthDialog(controller: controller),
    );
  }

  void _syncDeviceName(String label) {
    if (label.isEmpty || label == _lastDeviceLabel) return;
    _lastDeviceLabel = label;
    _deviceNameController.text = label;
  }
}

class _SectionColumn extends StatelessWidget {
  const _SectionColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _OperationPreviewDialog extends StatefulWidget {
  const _OperationPreviewDialog({
    required this.title,
    required this.actionLabel,
    required this.preview,
  });

  final String title;
  final String actionLabel;
  final SyncOperationPreview preview;

  @override
  State<_OperationPreviewDialog> createState() =>
      _OperationPreviewDialogState();
}

class _OperationPreviewDialogState extends State<_OperationPreviewDialog> {
  bool _destructiveConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final impact = widget.preview.impact;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(impact.summaryLabel),
            const SizedBox(height: 8),
            Text('${widget.preview.conflicts.length} conflicts'),
            if (widget.preview.remoteWasMissing)
              const Text(
                'No remote backup exists; local data will be uploaded.',
              ),
            for (final warning in widget.preview.warnings)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(warning),
              ),
            _ImpactList(title: 'Will add', titles: impact.addedTitles),
            _ImpactList(title: 'Will update', titles: impact.updatedTitles),
            _ImpactList(title: 'Will delete', titles: impact.deletedTitles),
            if (impact.isDestructive) ...[
              const ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('Warning: this action may delete local nodes.'),
              ),
              CheckboxListTile(
                key: const ValueKey(
                  'restore-destructive-confirmation-checkbox',
                ),
                contentPadding: EdgeInsets.zero,
                value: _destructiveConfirmed,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I understand local nodes may be deleted'),
                onChanged: (value) =>
                    setState(() => _destructiveConfirmed = value ?? false),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey(
            widget.actionLabel == 'Restore'
                ? 'restore-point-confirm-button'
                : 'operation-preview-confirm-button',
          ),
          style: impact.isDestructive ? _dangerButtonStyle(context) : null,
          onPressed: !impact.isDestructive || _destructiveConfirmed
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _ImpactList extends StatelessWidget {
  const _ImpactList({required this.title, required this.titles});

  final String title;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          for (final title in titles.take(5)) Text(title),
          if (titles.length > 5) Text('+${titles.length - 5} more'),
        ],
      ),
    );
  }
}

class _SyncAuthDialog extends StatefulWidget {
  const _SyncAuthDialog({required this.controller});

  final SyncController controller;

  @override
  State<_SyncAuthDialog> createState() => _SyncAuthDialogState();
}

class _SyncAuthDialogState extends State<_SyncAuthDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _busy = false;
  String _message = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cloud sync sign in'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('sync-auth-email-field'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              key: const ValueKey('sync-auth-password-field'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            TextField(
              key: const ValueKey('sync-auth-display-name-field'),
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
              ),
            ),
            if (_message.isNotEmpty)
              Text(_message, key: const ValueKey('sync-auth-message')),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('sync-auth-reset-button'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.controller.sendPasswordResetEmail(
                    email: _emailController.text,
                  ),
                ),
          child: const Text('Reset password'),
        ),
        OutlinedButton(
          key: const ValueKey('sync-auth-register-button'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.controller.register(
                    email: _emailController.text,
                    password: _passwordController.text,
                    displayName: _displayNameController.text,
                  ),
                  close: true,
                ),
          child: const Text('Register'),
        ),
        FilledButton(
          key: const ValueKey('sync-auth-sign-in-submit-button'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.controller.signIn(
                    email: _emailController.text,
                    password: _passwordController.text,
                    displayName: _displayNameController.text,
                  ),
                  close: true,
                ),
          child: const Text('Sign in'),
        ),
      ],
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool close = false,
  }) async {
    setState(() {
      _busy = true;
      _message = '';
    });
    await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = widget.controller.lastMessage;
    });
    if (close && widget.controller.isSignedIn) {
      Navigator.of(context).pop();
    }
  }
}

ButtonStyle _dangerButtonStyle(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: colorScheme.error,
    foregroundColor: colorScheme.onError,
  );
}

IconData _activityIcon(SyncActivityStatus status) => switch (status) {
  SyncActivityStatus.success => Icons.check_circle_outline,
  SyncActivityStatus.blocked => Icons.report_problem_outlined,
  SyncActivityStatus.failed => Icons.error_outline,
};

String _time(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day $hour:$minute';
}
