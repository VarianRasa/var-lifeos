import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_controller.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../sync/application/sync_controller.dart';
import '../sync/domain/sync_activity.dart';
import '../sync/domain/sync_health.dart';
import '../sync/domain/sync_restore_point.dart';
import 'keyboard_shortcuts_dialog.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Appearance', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.dark_mode_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Theme', style: theme.textTheme.bodyLarge),
                  ),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Auto'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Accent Color', style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 10),
                  Consumer(
                    builder: (context, ref, child) {
                      final activeColor = ref.watch(themeAccentColorProvider);
                      final colors = [
                        const Color(0xFF6C8EEF), // Default Indigo
                        const Color(0xFF8B5CF6), // Violet
                        const Color(0xFF10B981), // Emerald
                        const Color(0xFFF59E0B), // Amber
                        const Color(0xFFEF4444), // Crimson
                        const Color(0xFF14B8A6), // Teal
                        const Color(0xFFF43F5E), // Rose
                        const Color(0xFF7A869A), // Slate Gray
                      ];
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: colors.map((color) {
                          final isSelected =
                              activeColor.toARGB32() == color.toARGB32();
                          return GestureDetector(
                            onTap: () {
                              ref
                                  .read(themeAccentColorProvider.notifier)
                                  .setAccentColor(color);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? (theme.brightness == Brightness.dark
                                            ? Colors.white
                                            : Colors.black)
                                      : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: isSelected
                                  ? Icon(
                                      Icons.check,
                                      color:
                                          ThemeData.estimateBrightnessForColor(
                                                color,
                                              ) ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Colors.black,
                                      size: 18,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Sync & backup', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const _SyncBackupCard(),
          const SizedBox(height: 24),
          Text('Data management', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Export Data'),
                  subtitle: const Text(
                    'Export all mindmap nodes to JSON and copy to clipboard',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () async {
                    try {
                      final repository = ref.read(mindmapRepositoryProvider);
                      final nodes = await repository.listNodes();
                      final rawJson = jsonEncode(
                        nodes.map((n) => n.toJson()).toList(),
                      );
                      await Clipboard.setData(ClipboardData(text: rawJson));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'All data exported & copied to clipboard!',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to export data: $e')),
                        );
                      }
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Import Data'),
                  subtitle: const Text(
                    'Import mindmap nodes from exported JSON string',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _showImportDialog(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Clear All Data',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: const Text(
                    'Completely delete all mindmap nodes and reset application state',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _showClearDataDialog(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Keyboard shortcuts', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const _ShortcutRow(
                    keys: ['Ctrl', 'K'],
                    desc: 'Open command palette',
                  ),
                  const Divider(height: 12),
                  const _ShortcutRow(
                    keys: ['Ctrl', 'N'],
                    desc: 'Create new node',
                  ),
                  const Divider(height: 12),
                  const _ShortcutRow(
                    keys: ['Ctrl', 'T'],
                    desc: 'Jump to today',
                  ),
                  const Divider(height: 12),
                  const _ShortcutRow(
                    keys: ['Arrow Keys'],
                    desc: 'Navigate calendar',
                  ),
                  const Divider(height: 12),
                  const _ShortcutRow(
                    keys: ['Esc'],
                    desc: 'Close dialogs & panels',
                  ),
                  const Divider(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => showKeyboardShortcutsDialog(context),
                      icon: const Icon(Icons.keyboard, size: 18),
                      label: const Text('View all shortcuts'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('About', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text(AppInfo.name),
                  subtitle: Text(AppInfo.tagline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the exported JSON string below to import nodes. Existing nodes with matching IDs will be overwritten.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '[{"id": "node_1", ...}]',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      try {
        final List<dynamic> decoded =
            jsonDecode(controller.text.trim()) as List<dynamic>;
        final repository = ref.read(mindmapRepositoryProvider);
        int count = 0;
        for (final rawNode in decoded) {
          if (rawNode is Map) {
            final node = MindmapNode.fromJson(rawNode.cast<String, dynamic>());
            await repository.saveNode(node);
            count++;
          }
        }
        invalidateMindmapState(ref);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully imported $count nodes!')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to import data: $e')));
        }
      }
    }
  }

  Future<void> _showClearDataDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text(
          'This action is irreversible. All of your mindmaps, nodes, tasks, goals, and habits will be deleted from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final repository = ref.read(mindmapRepositoryProvider);
        final nodes = await repository.listNodes();
        for (final node in nodes) {
          await repository.deleteNode(node.id);
        }
        invalidateMindmapState(ref);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All local data cleared successfully.'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to clear data: $e')));
        }
      }
    }
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.desc});

  final List<String> keys;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(desc, style: theme.textTheme.bodyMedium),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < keys.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(width: 4),
                  Text('+', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 4),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Text(
                    keys[i],
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncBackupCard extends ConsumerStatefulWidget {
  const _SyncBackupCard();

  @override
  ConsumerState<_SyncBackupCard> createState() => _SyncBackupCardState();
}

class _SyncBackupCardState extends ConsumerState<_SyncBackupCard> {
  final _passphraseController = TextEditingController();
  final _packageController = TextEditingController();
  final _deviceNameController = TextEditingController();
  String _lastDeviceLabel = '';
  String _restoreSourceFilter = SyncRestorePointTimeline.allSourcesLabel;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (!mounted) return;
      ref.read(syncControllerProvider.notifier).load();
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
    final nodes = ref.watch(allMindmapNodesProvider);
    final syncState = ref.watch(syncControllerProvider);
    final theme = Theme.of(context);
    _syncDeviceNameField(syncState.deviceIdentity?.label ?? '');

    return Card(
      child: nodes.when(
        data: (value) => Column(
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Local-first'),
              subtitle: Text(
                syncState.isSignedIn ? syncState.email : 'Signed out',
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: _SyncMetric(
                      icon: Icons.storage_outlined,
                      label: _countLabel(value.length),
                    ),
                  ),
                  Expanded(
                    child: _SyncMetric(
                      icon: Icons.check_circle_outline,
                      label: syncState.lastConflictCount == 0
                          ? 'No conflicts'
                          : '${syncState.lastConflictCount} conflicts',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: _SyncHealthPanel(
                state: syncState,
                deviceNameController: _deviceNameController,
                onSaveDeviceName: _saveDeviceName,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('sync-sign-in-button'),
                    icon: Icon(
                      syncState.isSignedIn
                          ? Icons.logout_outlined
                          : Icons.login_outlined,
                    ),
                    label: Text(syncState.isSignedIn ? 'Sign out' : 'Sign in'),
                    onPressed: syncState.isBusy
                        ? null
                        : () => _toggleSignIn(syncState),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('sync-now-button'),
                    icon: const Icon(Icons.sync_outlined),
                    label: const Text('Sync now'),
                    onPressed: syncState.isBusy || !syncState.isSignedIn
                        ? null
                        : () => ref
                              .read(syncControllerProvider.notifier)
                              .syncNow(),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('sync-push-button'),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Push'),
                    onPressed: syncState.isBusy || !syncState.isSignedIn
                        ? null
                        : () => ref
                              .read(syncControllerProvider.notifier)
                              .pushBackup(),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('sync-pull-button'),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Pull'),
                    onPressed: syncState.isBusy || !syncState.isSignedIn
                        ? null
                        : () => ref
                              .read(syncControllerProvider.notifier)
                              .pullBackup(),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('portable-export-button'),
                    icon: const Icon(Icons.enhanced_encryption_outlined),
                    label: const Text('Export'),
                    onPressed: syncState.isBusy ? null : _exportPortableBackup,
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('portable-import-button'),
                    icon: const Icon(Icons.restore_page_outlined),
                    label: const Text('Import'),
                    onPressed: syncState.isBusy ? null : _importPortableBackup,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('portable-passphrase-field'),
                    controller: _passphraseController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_outline),
                      labelText: 'Backup passphrase',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('portable-package-field'),
                    controller: _packageController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.data_object_outlined),
                      labelText: 'Encrypted package',
                    ),
                  ),
                ],
              ),
            ),
            if (syncState.lastMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    syncState.lastMessage,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ),
            if (syncState.pendingConflicts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _ConflictQueue(
                  conflicts: syncState.pendingConflicts,
                  isBusy: syncState.isBusy,
                  onUseLocal: (nodeId) => ref
                      .read(syncControllerProvider.notifier)
                      .resolveConflictWithLocal(nodeId),
                  onUseRemote: (nodeId) => ref
                      .read(syncControllerProvider.notifier)
                      .resolveConflictWithRemote(nodeId),
                ),
              ),
            if (syncState.lastConflictCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('sync-use-remote-button'),
                      icon: const Icon(Icons.cloud_done_outlined),
                      label: const Text('Use remote'),
                      onPressed: syncState.isBusy
                          ? null
                          : () => ref
                                .read(syncControllerProvider.notifier)
                                .resolveConflictsWithRemote(),
                    ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('sync-use-newest-button'),
                      icon: const Icon(Icons.auto_awesome_motion_outlined),
                      label: const Text('Use newest'),
                      onPressed: syncState.isBusy
                          ? null
                          : () => ref
                                .read(syncControllerProvider.notifier)
                                .resolveConflictsWithNewest(),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('sync-keep-local-button'),
                      icon: const Icon(Icons.devices_outlined),
                      label: const Text('Keep local'),
                      onPressed: syncState.isBusy
                          ? null
                          : () => ref
                                .read(syncControllerProvider.notifier)
                                .resolveConflictsWithLocal(),
                    ),
                  ],
                ),
              ),
            if (syncState.lastSavedCount > 0 || syncState.lastDeletedCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _syncDeltaLabel(
                      syncState.lastSavedCount,
                      syncState.lastDeletedCount,
                    ),
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ),
            if (syncState.restorePoints.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _RestorePoints(
                  points: syncState.restorePoints,
                  currentNodes: value,
                  selectedSource: _restoreSourceFilter,
                  onSourceChanged: _selectRestoreSource,
                  onRestore: _previewRestorePoint,
                  onDelete: (id) => ref
                      .read(syncControllerProvider.notifier)
                      .deleteRestorePoint(id),
                ),
              ),
            if (syncState.activityLog.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _ActivityLog(entries: syncState.activityLog),
              ),
          ],
        ),
        loading: () => const ListTile(
          leading: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Local-first'),
          subtitle: Text('Loading'),
        ),
        error: (_, _) => ListTile(
          leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
          title: const Text('Local-first'),
          subtitle: const Text('Unavailable'),
        ),
      ),
    );
  }

  Future<void> _exportPortableBackup() async {
    await ref
        .read(syncControllerProvider.notifier)
        .exportPortableBackup(passphrase: _passphraseController.text);
    if (!mounted) return;

    final package = ref.read(syncControllerProvider).lastPortablePackage;
    if (package.isNotEmpty) {
      _packageController.text = package;
    }
  }

  Future<void> _importPortableBackup() async {
    await ref
        .read(syncControllerProvider.notifier)
        .importPortableBackup(
          package: _packageController.text,
          passphrase: _passphraseController.text,
        );
  }

  Future<void> _toggleSignIn(SyncControllerState syncState) async {
    final controller = ref.read(syncControllerProvider.notifier);
    if (syncState.isSignedIn) {
      await controller.signOut();
      return;
    }

    await controller.signIn(email: 'local@var.app', displayName: 'Local user');
  }

  Future<void> _saveDeviceName() async {
    await ref
        .read(syncControllerProvider.notifier)
        .renameDevice(_deviceNameController.text);
  }

  Future<void> _previewRestorePoint(SyncRestorePoint point) async {
    final controller = ref.read(syncControllerProvider.notifier);
    final impact = await controller.previewRestorePoint(point.id);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _RestorePointPreviewDialog(point: point, impact: impact);
      },
    );
    if (confirmed ?? false) {
      await controller.restorePoint(point.id);
    }
  }

  void _selectRestoreSource(String source) {
    setState(() {
      _restoreSourceFilter = source;
    });
  }

  void _syncDeviceNameField(String label) {
    if (label.isEmpty || label == _lastDeviceLabel) return;

    _lastDeviceLabel = label;
    if (_deviceNameController.text != label) {
      _deviceNameController.text = label;
    }
  }
}

class _SyncHealthPanel extends StatelessWidget {
  const _SyncHealthPanel({
    required this.state,
    required this.deviceNameController,
    required this.onSaveDeviceName,
  });

  final SyncControllerState state;
  final TextEditingController deviceNameController;
  final VoidCallback onSaveDeviceName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = state.syncHealth;
    final identity = state.deviceIdentity;
    final color = _healthColor(theme, health.level);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.monitor_heart_outlined, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Sync health', style: theme.textTheme.labelLarge),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                health.label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(health.detail, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.devices_outlined,
              size: 18,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                identity?.label ?? 'This device',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ),
            if (identity != null)
              Flexible(
                child: Text(
                  identity.id,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('sync-device-name-field'),
                controller: deviceNameController,
                enabled: !state.isBusy,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.drive_file_rename_outline),
                  labelText: 'Device name',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('sync-device-save-button'),
              tooltip: 'Save device name',
              icon: const Icon(Icons.save_outlined),
              onPressed: state.isBusy ? null : onSaveDeviceName,
            ),
          ],
        ),
      ],
    );
  }
}

class _ActivityLog extends StatelessWidget {
  const _ActivityLog({required this.entries});

  final List<SyncActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.history_outlined,
              size: 18,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text('Recent activity', style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in entries.take(3)) ...[
          _ActivityLogRow(entry: entry),
          if (entry != entries.take(3).last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RestorePoints extends StatelessWidget {
  const _RestorePoints({
    required this.points,
    required this.currentNodes,
    required this.selectedSource,
    required this.onSourceChanged,
    required this.onRestore,
    required this.onDelete,
  });

  final List<SyncRestorePoint> points;
  final List<MindmapNode> currentNodes;
  final String selectedSource;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<SyncRestorePoint> onRestore;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeline = SyncRestorePointTimeline.create(
      points: points,
      selectedSource: selectedSource,
    );
    final visible = timeline.filteredPoints.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.restore_outlined,
              size: 18,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text('Restore points', style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 8),
        if (timeline.sourceLabels.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final source in timeline.sourceLabels) ...[
                  ChoiceChip(
                    key: ValueKey('restore-source-filter-$source'),
                    label: Text(source),
                    selected: timeline.selectedSource == source,
                    onSelected: (selected) {
                      if (selected) onSourceChanged(source);
                    },
                  ),
                  if (source != timeline.sourceLabels.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (timeline.hiddenCount > 0) ...[
          Text(
            '${timeline.hiddenCount} hidden by source',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
        ],
        for (var index = 0; index < visible.length; index++) ...[
          _RestorePointRow(
            point: visible[index],
            index: index,
            currentNodes: currentNodes,
            onRestore: onRestore,
            onDelete: onDelete,
          ),
          if (index != visible.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RestorePointRow extends StatelessWidget {
  const _RestorePointRow({
    required this.point,
    required this.index,
    required this.currentNodes,
    required this.onRestore,
    required this.onDelete,
  });

  final SyncRestorePoint point;
  final int index;
  final List<MindmapNode> currentNodes;
  final ValueChanged<SyncRestorePoint> onRestore;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final impact = point.previewAgainst(currentNodes);

    return Row(
      children: [
        Icon(
          Icons.history_toggle_off_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                point.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 2),
              Text(
                '${_countLabel(point.nodeCount)} / ${point.deviceLabel}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(
                'Impact: ${impact.summaryLabel}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: _RestoreRiskChip(impact: impact),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          key: ValueKey('restore-point-$index-button'),
          tooltip: 'Restore point',
          icon: const Icon(Icons.restore_page_outlined),
          onPressed: () => onRestore(point),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: ValueKey('restore-point-$index-delete-button'),
          tooltip: 'Delete restore point',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => onDelete(point.id),
        ),
      ],
    );
  }
}

class _RestoreRiskChip extends StatelessWidget {
  const _RestoreRiskChip({required this.impact});

  final SyncRestorePointImpact impact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = impact.isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          impact.riskLabel,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _RestorePointPreviewDialog extends StatefulWidget {
  const _RestorePointPreviewDialog({required this.point, required this.impact});

  final SyncRestorePoint point;
  final SyncRestorePointImpact impact;

  @override
  State<_RestorePointPreviewDialog> createState() =>
      _RestorePointPreviewDialogState();
}

class _RestorePointPreviewDialogState
    extends State<_RestorePointPreviewDialog> {
  bool _destructiveConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requiresDestructiveConfirmation = widget.impact.isDestructive;

    return AlertDialog(
      title: const Text('Restore preview'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.point.label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              '${_countLabel(widget.point.nodeCount)} / '
              '${widget.point.deviceLabel}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RestoreImpactChip(
                  icon: Icons.add_circle_outline,
                  label: _impactPart(widget.impact.addedCount, 'add', 'adds'),
                ),
                _RestoreImpactChip(
                  icon: Icons.edit_outlined,
                  label: _impactPart(
                    widget.impact.updatedCount,
                    'update',
                    'updates',
                  ),
                ),
                _RestoreImpactChip(
                  icon: Icons.delete_outline,
                  label: _impactPart(
                    widget.impact.deletedCount,
                    'delete',
                    'deletes',
                  ),
                ),
              ],
            ),
            _RestoreImpactSection(
              title: 'Will add',
              titles: widget.impact.addedTitles,
            ),
            _RestoreImpactSection(
              title: 'Will update',
              titles: widget.impact.updatedTitles,
            ),
            _RestoreImpactSection(
              title: 'Will delete',
              titles: widget.impact.deletedTitles,
            ),
            if (requiresDestructiveConfirmation) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const ValueKey(
                  'restore-destructive-confirmation-checkbox',
                ),
                value: _destructiveConfirmed,
                onChanged: (value) {
                  setState(() {
                    _destructiveConfirmed = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('I understand local nodes may be deleted'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('restore-point-cancel-button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('restore-point-confirm-button'),
          icon: const Icon(Icons.restore_page_outlined),
          label: const Text('Restore'),
          onPressed: !requiresDestructiveConfirmation || _destructiveConfirmed
              ? () => Navigator.of(context).pop(true)
              : null,
        ),
      ],
    );
  }
}

class _RestoreImpactSection extends StatelessWidget {
  const _RestoreImpactSection({required this.title, required this.titles});

  final String title;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final visible = titles.take(4).toList();
    final hiddenCount = titles.length - visible.length;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          for (final item in visible) ...[
            Text(
              item,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (item != visible.last) const SizedBox(height: 2),
          ],
          if (hiddenCount > 0) ...[
            const SizedBox(height: 2),
            Text('+$hiddenCount more', style: theme.textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

class _RestoreImpactChip extends StatelessWidget {
  const _RestoreImpactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _ActivityLogRow extends StatelessWidget {
  const _ActivityLogRow({required this.entry});

  final SyncActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_activityIcon(entry), size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.actionLabel,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(entry.statusLabel, style: theme.textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Result: ${entry.message}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(_activityCounts(entry), style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConflictQueue extends StatelessWidget {
  const _ConflictQueue({
    required this.conflicts,
    required this.isBusy,
    required this.onUseLocal,
    required this.onUseRemote,
  });

  final List<SyncConflictSummary> conflicts;
  final bool isBusy;
  final ValueChanged<String> onUseLocal;
  final ValueChanged<String> onUseRemote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.rule_folder_outlined,
              size: 18,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text('Conflict queue', style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 8),
        for (final conflict in conflicts) ...[
          _ConflictSummaryRow(
            conflict: conflict,
            isBusy: isBusy,
            onUseLocal: onUseLocal,
            onUseRemote: onUseRemote,
          ),
          if (conflict != conflicts.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ConflictSummaryRow extends StatelessWidget {
  const _ConflictSummaryRow({
    required this.conflict,
    required this.isBusy,
    required this.onUseLocal,
    required this.onUseRemote,
  });

  final SyncConflictSummary conflict;
  final bool isBusy;
  final ValueChanged<String> onUseLocal;
  final ValueChanged<String> onUseRemote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outlineVariant.withValues(alpha: 0.7);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    conflict.kindLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conflict.nodeId,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                if (conflict.hasSelectedResolution) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Selected: ${conflict.selectedResolutionLabel}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _ConflictVersion(
                  label: 'Base',
                  title: conflict.baselineTitle,
                  detail: conflict.baselineDetail,
                ),
                _ConflictVersion(
                  label: 'Local',
                  title: conflict.localTitle,
                  detail: conflict.localDetail,
                ),
                _ConflictVersion(
                  label: 'Remote',
                  title: conflict.remoteTitle,
                  detail: conflict.remoteDetail,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('sync-conflict-use-local-${conflict.nodeId}'),
                  icon: const Icon(Icons.devices_outlined, size: 16),
                  label: const Text('Use local'),
                  onPressed: isBusy ? null : () => onUseLocal(conflict.nodeId),
                ),
                FilledButton.tonalIcon(
                  key: ValueKey('sync-conflict-use-remote-${conflict.nodeId}'),
                  icon: const Icon(Icons.cloud_done_outlined, size: 16),
                  label: const Text('Use remote'),
                  onPressed: isBusy ? null : () => onUseRemote(conflict.nodeId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictVersion extends StatelessWidget {
  const _ConflictVersion({
    required this.label,
    required this.title,
    required this.detail,
  });

  final String label;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            title.isEmpty ? '-' : title,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SyncMetric extends StatelessWidget {
  const _SyncMetric({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? theme.colorScheme.secondary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

String _countLabel(int count) => count == 1 ? '1 node' : '$count nodes';

String _syncDeltaLabel(int saved, int deleted) {
  final parts = <String>[
    if (saved > 0) saved == 1 ? '1 saved' : '$saved saved',
    if (deleted > 0) deleted == 1 ? '1 deleted' : '$deleted deleted',
  ];
  return parts.join(' / ');
}

String _impactPart(int count, String singular, String plural) {
  return count == 1 ? '1 $singular' : '$count $plural';
}

IconData _activityIcon(SyncActivityEntry entry) {
  return switch (entry.status) {
    SyncActivityStatus.success => Icons.check_circle_outline,
    SyncActivityStatus.blocked => Icons.report_problem_outlined,
    SyncActivityStatus.failed => Icons.error_outline,
  };
}

Color _healthColor(ThemeData theme, SyncHealthLevel level) {
  return switch (level) {
    SyncHealthLevel.signedOut => theme.colorScheme.outline,
    SyncHealthLevel.healthy => theme.colorScheme.primary,
    SyncHealthLevel.needsAttention => theme.colorScheme.tertiary,
    SyncHealthLevel.degraded => theme.colorScheme.error,
  };
}

String _activityCounts(SyncActivityEntry entry) {
  return [
    'Saved ${entry.savedCount}',
    'Deleted ${entry.deletedCount}',
    'Conflicts ${entry.conflictCount}',
  ].join(' / ');
}
