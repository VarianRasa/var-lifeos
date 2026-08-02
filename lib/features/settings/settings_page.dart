import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';
import '../../core/theme/node_visuals.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/date_utils.dart';
import '../mindmap/application/database_lock_provider.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/canvas_board.dart';
import '../mindmap/domain/canvas_board_template.dart';
import '../mindmap/domain/custom_node_template_codec.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/node_template.dart';
import '../mindmap/domain/recurring_routine.dart';
import '../search/application/search_providers.dart';
import '../sync/application/sync_controller.dart';
import 'application/reminder_auto_scheduler.dart';
import 'application/reminder_notification_navigation.dart';
import 'data/persisted_reminder_notification_adapter.dart';
import 'domain/reminder_notification_adapter.dart';
import 'domain/reminder_planner.dart';
import 'keyboard_shortcuts_dialog.dart';

ShapeDecoration _settingsPanelDecoration(
  BuildContext context, {
  bool prominent = false,
}) {
  final theme = Theme.of(context);
  final tokens = AppDesignTokens.of(context);
  return ShapeDecoration(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        prominent ? tokens.radiusPage : tokens.radiusContainer,
      ),
      side: BorderSide(color: theme.dividerColor),
    ),
  );
}

class _CloudExtractionCard extends StatelessWidget {
  const _CloudExtractionCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        key: const ValueKey('settings-cloud-extraction'),
        value: enabled,
        onChanged: onChanged,
        secondary: const Icon(Icons.cloud_outlined),
        title: const Text('Cloud OCR and transcription'),
        subtitle: const Text(
          'Allow eligible attachments to use cloud extraction. Local-only content never uploads.',
        ),
      ),
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  void _showPaletteDialog(BuildContext context, WidgetRef ref) {
    final active = ref.read(themeVariantProvider);
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Select Palette'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: AppThemeVariant.valuesForSettings.map((v) {
                final colors = AppThemeVariantColors.of(v);
                return ListTile(
                  title: Text(v.displayName),
                  leading: Icon(
                    v == active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: v == active ? theme.colorScheme.primary : null,
                  ),
                  trailing: Container(
                    width: 36,
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: LinearGradient(
                        colors: [
                          colors.nodeColors[NodeType.task] ??
                              Colors.transparent,
                          colors.nodeColors[NodeType.kanban] ??
                              Colors.transparent,
                          colors.nodeColors[NodeType.plan] ??
                              Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  onTap: () {
                    ref.read(themeVariantProvider.notifier).setThemeVariant(v);
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final variant = ref.watch(themeVariantProvider);
    final effectiveMode = variant.effectiveThemeMode(mode);
    final fontSize = ref.watch(themeFontSizeProvider);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SettingsOverviewCard(),
          const SizedBox(height: 16),
          const _FeatureGuideCard(),
          const SizedBox(height: 24),
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
                    selected: {effectiveMode},
                    onSelectionChanged: variant.forcesDarkMode
                        ? null
                        : (s) => ref
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.format_size_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Text size', style: theme.textTheme.bodyLarge),
                  ),
                  SegmentedButton<AppFontSize>(
                    segments: [
                      for (final size in AppFontSize.values)
                        ButtonSegment(value: size, label: Text(size.label)),
                    ],
                    selected: {fontSize},
                    onSelectionChanged: (selection) => ref
                        .read(themeFontSizeProvider.notifier)
                        .setFontSize(selection.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Palette'),
              subtitle: Text(
                'Active: ${variant.displayName}. '
                '${variant.forcesDarkMode ? 'Dark only. ' : ''}'
                'Marker colors are adapted to the active theme.',
              ),
              onTap: () => _showPaletteDialog(context, ref),
              trailing: Container(
                width: 44,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                      theme.colorScheme.tertiary,
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Search privacy', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _CloudExtractionCard(
            enabled: ref.watch(cloudExtractionEnabledProvider).value ?? false,
            onChanged: (value) async {
              await ref
                  .read(searchPrivacyPreferencesProvider)
                  .setCloudExtractionEnabled(value);
              ref.invalidate(cloudExtractionEnabledProvider);
            },
          ),
          const SizedBox(height: 24),
          Text('Sync & backup', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              key: const ValueKey('settings-recovery-center-entry'),
              leading: const Icon(Icons.health_and_safety_outlined),
              title: const Text('Recovery Center'),
              subtitle: const Text(
                'Preview sync, restore points, and encrypted backups safely.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/recovery'),
            ),
          ),
          const SizedBox(height: 24),
          Text('Templates & saved views', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const _TemplateManagerCard(),
          const SizedBox(height: 12),
          const _BoardTemplatesManagerCard(),
          const SizedBox(height: 12),
          const _SavedViewsManagerCard(),
          const SizedBox(height: 12),
          const _GraphFiltersManagerCard(),
          const SizedBox(height: 24),
          Text('Reminders', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const _ReminderPreviewCard(),
          const SizedBox(height: 24),
          Text('Security', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const _DatabaseLockCard(),
          const SizedBox(height: 24),
          const _DataManagementCard(),
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
                    keys: ['1–6'],
                    desc: 'Agenda quick filters',
                  ),
                  const Divider(height: 12),
                  const _ShortcutRow(
                    keys: ['Esc'],
                    desc: 'Close panels / clear focus',
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
}

Future<void> _showMarkdownImportDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import Markdown'),
      content: TextField(
        controller: controller,
        maxLines: 10,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: const InputDecoration(
          hintText: '## Note title\nBody with [[links]]',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (result != true || controller.text.trim().isEmpty) return;

  final repository = ref.read(mindmapRepositoryProvider);
  final nodes = _markdownToMindmapNodes(controller.text, DateTime.now());
  for (final node in nodes) {
    await repository.saveNode(node);
  }
  invalidateMindmapState(ref);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported ${nodes.length} Markdown notes')),
    );
  }
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
      await ref
          .read(syncControllerProvider.notifier)
          .createRestorePoint(label: 'Before clear all data');
      final repository = ref.read(mindmapRepositoryProvider);
      final nodes = await repository.listNodes();
      for (final node in nodes) {
        await repository.deleteNode(node.id);
      }
      invalidateMindmapState(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All local data cleared successfully.')),
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

class _SettingsOverviewCard extends StatelessWidget {
  const _SettingsOverviewCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: _settingsPanelDecoration(context, prominent: true),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.tune_outlined,
              size: 34,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Control center', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Theme, sync, backup, data tools, and shortcuts in one place.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateEditorDialog extends StatefulWidget {
  const _TemplateEditorDialog({required this.template});

  final NodeTemplate template;

  @override
  State<_TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<_TemplateEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _projectController;
  late final TextEditingController _areaController;
  late final TextEditingController _tagsController;
  late NodeType _type;
  late NodeStatus _status;
  late NodePriority _priority;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _labelController = TextEditingController(text: template.label);
    _titleController = TextEditingController(text: template.title);
    _bodyController = TextEditingController(text: template.body);
    _projectController = TextEditingController(text: template.project);
    _areaController = TextEditingController(text: template.area);
    _tagsController = TextEditingController(text: template.tags.join(', '));
    _type = template.type;
    _status = template.status;
    _priority = template.priority;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _projectController.dispose();
    _areaController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelController.text.trim();
    final title = _titleController.text.trim();
    if (label.isEmpty || title.isEmpty) return;
    final template = widget.template;
    Navigator.of(context).pop(
      NodeTemplate(
        id: template.id,
        label: label,
        type: _type,
        title: title,
        body: _bodyController.text.trim(),
        status: _status,
        priority: _priority,
        project: _projectController.text.trim(),
        area: _areaController.text.trim(),
        tags: _tagsController.text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false),
        progress: template.progress,
        checklist: template.checklist,
        data: template.data,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit template'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _labelController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Template name'),
              ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Node title'),
              ),
              TextField(
                controller: _bodyController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Body'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<NodeType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final type in NodeType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              DropdownButtonFormField<NodeStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final status in NodeStatus.values)
                    DropdownMenuItem(value: status, child: Text(status.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              DropdownButtonFormField<NodePriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: [
                  for (final priority in NodePriority.values)
                    DropdownMenuItem(
                      value: priority,
                      child: Text(priority.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              TextField(
                controller: _projectController,
                decoration: const InputDecoration(labelText: 'Project'),
              ),
              TextField(
                controller: _areaController,
                decoration: const InputDecoration(labelText: 'Area'),
              ),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  helperText: 'Comma separated',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _BoardTemplatesManagerCard extends ConsumerStatefulWidget {
  const _BoardTemplatesManagerCard();

  @override
  ConsumerState<_BoardTemplatesManagerCard> createState() =>
      _BoardTemplatesManagerCardState();
}

class _BoardTemplatesManagerCardState
    extends ConsumerState<_BoardTemplatesManagerCard> {
  bool _expanded = false;
  String _query = '';

  void _refresh(String workspaceName) {
    ref.invalidate(availableBoardTemplatesProvider(workspaceName));
    ref.invalidate(activeProjectCanvasBoardsProvider);
  }

  void _showError(String action, Object error) {
    if (!mounted) return;
    final message = error is StateError ? error.message : error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to $action board template: $message')),
    );
  }

  Future<String?> _nameDialog({
    required String title,
    required String action,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('board-template-name-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Template name'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: Text(action),
          ),
        ],
      ),
    );
    return value;
  }

  Future<void> _add(List<CanvasBoard> boards) async {
    final source = await showDialog<CanvasBoard>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose source board'),
        children: [
          for (final group
              in boards
                  .groupListsBy((board) => board.workspaceName!)
                  .entries) ...[
            Semantics(header: true, child: ListTile(title: Text(group.key))),
            for (final board in group.value)
              SimpleDialogOption(
                key: ValueKey('board-template-source-${board.id}'),
                onPressed: () => Navigator.of(context).pop(board),
                child: Text(board.title),
              ),
          ],
        ],
      ),
    );
    if (source == null || !mounted) return;
    final name = await _nameDialog(
      title: 'Save linked template',
      action: 'Save',
      initial: source.title,
    );
    if (name == null || !mounted) return;
    try {
      await ref
          .read(boardTemplateServiceProvider)
          .saveSourceAsTemplate(
            sourceBoardId: source.id,
            workspaceName: source.workspaceName!,
            name: name,
            now: DateTime.now(),
          );
      if (!mounted) return;
      _refresh(source.workspaceName!);
    } on Object catch (error) {
      _showError('save', error);
    }
  }

  Future<void> _rename(CanvasBoardTemplate template, String workspace) async {
    final name = await _nameDialog(
      title: 'Rename board template',
      action: 'Rename',
      initial: template.name,
    );
    if (name == null || !mounted) return;
    try {
      await ref
          .read(boardTemplateServiceProvider)
          .renameTemplate(
            templateId: template.id,
            expectedUpdatedAt: template.updatedAt,
            name: name,
            now: DateTime.now(),
          );
      if (!mounted) return;
      _refresh(workspace);
    } on Object catch (error) {
      _showError('rename', error);
    }
  }

  Future<void> _delete(CanvasBoardTemplate template, String workspace) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete board template?'),
        content: Text('Delete “${template.name}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('board-template-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(boardTemplateServiceProvider).deleteTemplate(template.id);
      if (!mounted) return;
      _refresh(workspace);
    } on Object catch (error) {
      _showError('delete', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boards =
        ref.watch(activeProjectCanvasBoardsProvider).valueOrNull ?? const [];
    final workspaces =
        boards.map((board) => board.workspaceName!).toSet().toList()..sort();
    final templates = <({CanvasBoardTemplate template, String workspace})>[
      for (final workspace in workspaces)
        for (final template
            in ref
                    .watch(availableBoardTemplatesProvider(workspace))
                    .valueOrNull ??
                const [])
          (template: template, workspace: workspace),
    ];
    final query = _query.trim().toLowerCase();
    final filtered = templates
        .where((item) => item.template.name.toLowerCase().contains(query))
        .toList(growable: false);
    final panelShape = _settingsPanelDecoration(context).shape;
    return Material(
      color: theme.colorScheme.surface,
      shape: panelShape,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Board templates',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-board-template-add'),
                  onPressed: boards.isEmpty
                      ? null
                      : () => unawaited(_add(boards)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-board-templates-toggle'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  label: Text(_expanded ? 'Hide' : 'Show'),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('settings-board-template-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search board templates',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              for (final template in builtInCanvasBoardTemplates)
                if (template.name.toLowerCase().contains(query))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.lock_outline),
                    title: Text(template.name),
                    subtitle: const Text('Built-in · Read-only'),
                  ),
              for (final item in filtered)
                ListTile(
                  dense: true,
                  title: Text(item.template.name),
                  subtitle: Text('${item.workspace} · Linked source'),
                  trailing: PopupMenuButton<String>(
                    key: ValueKey(
                      'settings-board-template-menu-${item.template.id}',
                    ),
                    tooltip: 'Board template actions',
                    onSelected: (action) {
                      if (action == 'rename') {
                        unawaited(_rename(item.template, item.workspace));
                      } else if (action == 'delete') {
                        unawaited(_delete(item.template, item.workspace));
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TemplateManagerCard extends ConsumerStatefulWidget {
  const _TemplateManagerCard();

  @override
  ConsumerState<_TemplateManagerCard> createState() =>
      _TemplateManagerCardState();
}

class _TemplateManagerCardState extends ConsumerState<_TemplateManagerCard> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  List<NodeTemplate> _customTemplates = const [];
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final raw = await _preferences.getString(customNodeTemplatesPreferenceKey);
    Object? decoded;
    try {
      decoded = raw == null ? null : jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    if (!mounted) return;
    setState(() => _customTemplates = nodeTemplatesFromJsonList(decoded));
  }

  Future<void> _saveTemplates(List<NodeTemplate> templates) async {
    await _preferences.setString(
      customNodeTemplatesPreferenceKey,
      jsonEncode([
        for (final template in templates) nodeTemplateToJson(template),
      ]),
    );
    if (mounted) setState(() => _customTemplates = templates);
  }

  Future<void> _addFromExistingNode(List<MindmapNode> nodes) async {
    final node = await showDialog<MindmapNode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Save node as template'),
        children: [
          for (final node in nodes.where((node) => !node.isArchived).take(12))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(node),
              child: Text(node.title),
            ),
        ],
      ),
    );
    if (node == null) return;
    final template = NodeTemplate(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      label: node.title,
      type: node.type,
      title: node.title,
      body: node.body,
      status: node.status,
      priority: node.priority,
      project: node.project,
      area: node.area,
      tags: node.tags,
      progress: node.progress,
      checklist: [for (final item in node.checklist) item.title],
      data: node.data,
    );
    await _saveTemplates([..._customTemplates, template]);
  }

  Future<void> _editTemplate(NodeTemplate template) async {
    final edited = await showDialog<NodeTemplate>(
      context: context,
      builder: (context) => _TemplateEditorDialog(template: template),
    );
    if (edited == null) return;
    await _saveTemplates([
      for (final item in _customTemplates)
        if (item.id == template.id) edited else item,
    ]);
  }

  Future<void> _duplicateTemplate(NodeTemplate template) async {
    final copy = NodeTemplate(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      label: '${template.label} copy',
      type: template.type,
      title: template.title,
      body: template.body,
      status: template.status,
      priority: template.priority,
      project: template.project,
      area: template.area,
      tags: template.tags,
      progress: template.progress,
      checklist: template.checklist,
      data: template.data,
    );
    await _saveTemplates([..._customTemplates, copy]);
  }

  Future<void> _moveTemplate(String id, int delta) async {
    final index = _customTemplates.indexWhere((template) => template.id == id);
    if (index < 0) return;
    final nextIndex = (index + delta).clamp(0, _customTemplates.length - 1);
    if (nextIndex == index) return;
    final templates = [..._customTemplates];
    final template = templates.removeAt(index);
    templates.insert(nextIndex, template);
    await _saveTemplates(templates);
  }

  Future<void> _deleteTemplate(String id) async {
    await _saveTemplates([
      for (final template in _customTemplates)
        if (template.id != id) template,
    ]);
  }

  Future<void> _exportTemplates() async {
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode([
          for (final template in _customTemplates) nodeTemplateToJson(template),
        ]),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${_customTemplates.length} templates')),
    );
  }

  Future<void> _importTemplates() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import templates'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Templates JSON',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.isEmpty) return;
    try {
      final imported = nodeTemplatesFromJsonList(jsonDecode(raw));
      final merged = <String, NodeTemplate>{
        for (final template in _customTemplates) template.id: template,
        for (final template in imported) template.id: template,
      };
      await _saveTemplates(merged.values.toList(growable: false));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid template JSON')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = ref.watch(allMindmapNodesProvider).valueOrNull ?? const [];
    return DecoratedBox(
      decoration: _settingsPanelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Template manager',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: nodes.isEmpty
                      ? null
                      : () => _addFromExistingNode(nodes),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Template import/export',
                  onSelected: (value) {
                    if (value == 'export') unawaited(_exportTemplates());
                    if (value == 'import') unawaited(_importTemplates());
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'export', child: Text('Export JSON')),
                    PopupMenuItem(value: 'import', child: Text('Import JSON')),
                  ],
                ),
                Text(
                  '${defaultNodeTemplates.length + _customTemplates.length}',
                  style: theme.textTheme.labelSmall,
                ),
                TextButton.icon(
                  key: const ValueKey('settings-template-manager-toggle'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  label: Text(_expanded ? 'Hide' : 'Show'),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final template in defaultNodeTemplates)
                    Chip(
                      avatar: Icon(NodeVisuals.icon(template.type), size: 16),
                      label: Text(template.label),
                    ),
                  for (final template in _customTemplates)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InputChip(
                          avatar: Icon(
                            NodeVisuals.icon(template.type),
                            size: 16,
                          ),
                          label: Text(template.label),
                          onPressed: () => unawaited(_editTemplate(template)),
                          onDeleted: () => _deleteTemplate(template.id),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Template actions',
                          onSelected: (value) {
                            if (value == 'duplicate') {
                              unawaited(_duplicateTemplate(template));
                            }
                            if (value == 'up') {
                              unawaited(_moveTemplate(template.id, -1));
                            }
                            if (value == 'down') {
                              unawaited(_moveTemplate(template.id, 1));
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicate'),
                            ),
                            PopupMenuItem(value: 'up', child: Text('Move up')),
                            PopupMenuItem(
                              value: 'down',
                              child: Text('Move down'),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Custom templates are stored locally and appear in Command quick create.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const _savedViewDayOptions = [
  _SavedViewOption('canvas', 'Canvas', Icons.hub_outlined),
  _SavedViewOption('timeline', 'Timeline', Icons.calendar_view_day_outlined),
  _SavedViewOption('board', 'Board', Icons.view_kanban_outlined),
  _SavedViewOption('table', 'Table', Icons.table_rows_outlined),
];

const _savedViewTableOptions = [
  _SavedViewOption('all', 'All', Icons.table_rows_outlined),
  _SavedViewOption('open', 'Open', Icons.radio_button_unchecked),
  _SavedViewOption('done', 'Done', Icons.check_circle_outline),
  _SavedViewOption('tasks', 'Tasks', Icons.check_box_outlined),
  _SavedViewOption('priority', 'Priority', Icons.priority_high_rounded),
  _SavedViewOption('due', 'Due', Icons.event_available_outlined),
  _SavedViewOption('pinned', 'Pinned', Icons.push_pin_outlined),
  _SavedViewOption('archived', 'Archived', Icons.archive_outlined),
  _SavedViewOption('linked', 'Linked', Icons.hub_outlined),
];

const _savedViewSortOptions = [
  _SavedViewOption('updatedDesc', 'Updated', Icons.update_outlined),
  _SavedViewOption('titleAsc', 'Title', Icons.sort_by_alpha_outlined),
  _SavedViewOption('priorityDesc', 'Priority', Icons.priority_high_rounded),
  _SavedViewOption('dueAsc', 'Due', Icons.event_available_outlined),
];

final class _SavedViewOption {
  const _SavedViewOption(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

class _SavedViewOptionChips extends StatelessWidget {
  const _SavedViewOptionChips({
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    required this.keyPrefix,
  });

  final List<_SavedViewOption> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final option in options)
          ChoiceChip(
            key: ValueKey('$keyPrefix-${option.value}'),
            avatar: Icon(option.icon, size: 16),
            label: Text(option.label),
            selected: selectedValue == option.value,
            onSelected: (selected) {
              if (selected) onSelected(option.value);
            },
          ),
      ],
    );
  }
}

class _SavedViewsManagerCard extends StatefulWidget {
  const _SavedViewsManagerCard();

  @override
  State<_SavedViewsManagerCard> createState() => _SavedViewsManagerCardState();
}

class _SavedViewsManagerCardState extends State<_SavedViewsManagerCard> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  String _dayView = 'canvas';
  String _tableView = 'all';
  String _tableSort = 'updatedDesc';
  List<_SavedViewDefinition> _customViews = const [];
  bool _loaded = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dayView = await _preferences.getString('day_view_mode');
    final tableView = await _preferences.getString('day_table_quick_view');
    final tableSort = await _preferences.getString('day_table_sort_mode');
    final customViews = await _preferences.getString('custom_saved_views');
    if (!mounted) return;
    setState(() {
      _dayView = _savedViewOptionValue(
        _savedViewDayOptions,
        dayView ?? _dayView,
        'canvas',
      );
      _tableView = _savedViewOptionValue(
        _savedViewTableOptions,
        tableView ?? _tableView,
        'all',
      );
      _tableSort = _savedViewOptionValue(
        _savedViewSortOptions,
        tableSort ?? _tableSort,
        'updatedDesc',
      );
      _customViews = _decodeSavedViews(customViews);
      _loaded = true;
    });
  }

  String get _currentDefaultSummary =>
      '${_savedViewOptionLabel(_savedViewDayOptions, _dayView)} / '
      '${_savedViewOptionLabel(_savedViewTableOptions, _tableView)} / '
      'Sort: ${_savedViewOptionLabel(_savedViewSortOptions, _tableSort)}';

  bool _isSelectedSavedView(_SavedViewDefinition view) {
    return _dayView == view.dayView &&
        _tableView == view.tableView &&
        (view.tableSort == null || _tableSort == view.tableSort);
  }

  Future<void> _setDayView(String value) async {
    final next = _savedViewOptionValue(_savedViewDayOptions, value, 'canvas');
    setState(() => _dayView = next);
    await _preferences.setString('day_view_mode', next);
  }

  Future<void> _setTableView(String value) async {
    final next = _savedViewOptionValue(_savedViewTableOptions, value, 'all');
    setState(() => _tableView = next);
    await _preferences.setString('day_table_quick_view', next);
  }

  Future<void> _setTableSort(String value) async {
    final next = _savedViewOptionValue(
      _savedViewSortOptions,
      value,
      'updatedDesc',
    );
    setState(() => _tableSort = next);
    await _preferences.setString('day_table_sort_mode', next);
  }

  Future<void> _setSavedView(
    String dayView,
    String tableView, [
    String? tableSort,
  ]) async {
    final nextDayView = _savedViewOptionValue(
      _savedViewDayOptions,
      dayView,
      'canvas',
    );
    final nextTableView = _savedViewOptionValue(
      _savedViewTableOptions,
      tableView,
      'all',
    );
    final nextTableSort = tableSort == null
        ? _tableSort
        : _savedViewOptionValue(
            _savedViewSortOptions,
            tableSort,
            'updatedDesc',
          );
    await _preferences.setString('day_view_mode', nextDayView);
    await _preferences.setString('day_table_quick_view', nextTableView);
    await _preferences.setString('day_table_sort_mode', nextTableSort);
    if (!mounted) return;
    setState(() {
      _dayView = nextDayView;
      _tableView = nextTableView;
      _tableSort = nextTableSort;
    });
  }

  Future<void> _saveCustomViews(List<_SavedViewDefinition> views) async {
    await _preferences.setString(
      'custom_saved_views',
      jsonEncode([for (final view in views) view.toJson()]),
    );
    if (mounted) setState(() => _customViews = views);
  }

  Future<void> _addCustomView() async {
    final view = await showDialog<_SavedViewDefinition>(
      context: context,
      builder: (context) => _SavedViewDialog(
        title: 'Save current view',
        actionLabel: 'Save',
        initial: _SavedViewDefinition(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          label: _currentDefaultSummary,
          dayView: _dayView,
          tableView: _tableView,
          tableSort: _tableSort,
        ),
      ),
    );
    if (view == null) return;
    await _saveCustomViews([..._customViews, view]);
  }

  Future<void> _editCustomView(_SavedViewDefinition view) async {
    final updated = await showDialog<_SavedViewDefinition>(
      context: context,
      builder: (context) => _SavedViewDialog(
        title: 'Edit saved view',
        actionLabel: 'Save',
        initial: view,
      ),
    );
    if (updated == null) return;
    await _saveCustomViews([
      for (final item in _customViews)
        if (item.id == view.id) updated else item,
    ]);
  }

  Future<void> _duplicateCustomView(_SavedViewDefinition view) async {
    await _saveCustomViews([
      ..._customViews,
      _SavedViewDefinition(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: '${view.label} copy',
        dayView: view.dayView,
        tableView: view.tableView,
        tableSort: view.tableSort,
      ),
    ]);
  }

  Future<void> _deleteCustomView(String id) async {
    await _saveCustomViews([
      for (final view in _customViews)
        if (view.id != id) view,
    ]);
  }

  Future<void> _exportCustomViews() async {
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode([for (final view in _customViews) view.toJson()]),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${_customViews.length} saved views')),
    );
  }

  Future<void> _importCustomViews() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import saved views'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Saved views JSON',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final imported = decoded is List<Object?>
          ? decoded.map(_SavedViewDefinition.fromJson).nonNulls
          : const Iterable<_SavedViewDefinition>.empty();
      final merged = <String, _SavedViewDefinition>{
        for (final view in _customViews) view.id: view,
        for (final view in imported) view.id: view,
      };
      await _saveCustomViews(merged.values.toList(growable: false));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid saved views JSON')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const views = [
      _SavedViewDefinition(
        id: 'canvas-inbox',
        label: 'Canvas inbox',
        dayView: 'canvas',
        tableView: 'all',
      ),
      _SavedViewDefinition(
        id: 'priority-table',
        label: 'Priority table',
        dayView: 'table',
        tableView: 'priority',
        tableSort: 'priorityDesc',
      ),
      _SavedViewDefinition(
        id: 'due-table',
        label: 'Due table',
        dayView: 'table',
        tableView: 'due',
        tableSort: 'dueAsc',
      ),
      _SavedViewDefinition(
        id: 'kanban-board',
        label: 'Kanban board',
        dayView: 'board',
        tableView: 'open',
      ),
    ];
    return DecoratedBox(
      decoration: _settingsPanelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.view_quilt_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Saved views', style: theme.textTheme.bodyLarge),
                ),
                if (!_loaded)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  TextButton.icon(
                    onPressed: _addCustomView,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Save'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Saved view import/export',
                    onSelected: (value) {
                      if (value == 'export') unawaited(_exportCustomViews());
                      if (value == 'import') unawaited(_importCustomViews());
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'export',
                        child: Text('Export JSON'),
                      ),
                      PopupMenuItem(
                        value: 'import',
                        child: Text('Import JSON'),
                      ),
                    ],
                  ),
                ],
                TextButton.icon(
                  key: const ValueKey('settings-saved-views-toggle'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  label: Text(_expanded ? 'Hide' : 'Show'),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Text('Default day view', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              _SavedViewOptionChips(
                options: _savedViewDayOptions,
                selectedValue: _dayView,
                keyPrefix: 'settings-day-view',
                onSelected: (value) => unawaited(_setDayView(value)),
              ),
              const SizedBox(height: 12),
              Text('Table quick view', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              _SavedViewOptionChips(
                options: _savedViewTableOptions,
                selectedValue: _tableView,
                keyPrefix: 'settings-table-quick-view',
                onSelected: (value) => unawaited(_setTableView(value)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('settings-table-sort-mode'),
                initialValue: _tableSort,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Table sort',
                ),
                items: [
                  for (final option in _savedViewSortOptions)
                    DropdownMenuItem(
                      value: option.value,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(option.icon, size: 16),
                          const SizedBox(width: 8),
                          Text(option.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) unawaited(_setTableSort(value));
                },
              ),
              const SizedBox(height: 12),
              Text('Presets', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final view in views)
                    FilterChip(
                      key: ValueKey('settings-saved-view-preset-${view.id}'),
                      label: Text(view.label),
                      selected: _isSelectedSavedView(view),
                      tooltip: _savedViewSummary(view),
                      onSelected: (_) => _setSavedView(
                        view.dayView,
                        view.tableView,
                        view.tableSort,
                      ),
                    ),
                ],
              ),
              if (_customViews.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Custom views', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final view in _customViews)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InputChip(
                            key: ValueKey('settings-custom-view-${view.id}'),
                            label: Text(view.label),
                            selected: _isSelectedSavedView(view),
                            tooltip: _savedViewSummary(view),
                            onPressed: () => _setSavedView(
                              view.dayView,
                              view.tableView,
                              view.tableSort,
                            ),
                            onDeleted: () => _deleteCustomView(view.id),
                          ),
                          PopupMenuButton<String>(
                            key: ValueKey(
                              'settings-custom-view-menu-${view.id}',
                            ),
                            tooltip: 'Saved view actions',
                            onSelected: (value) {
                              if (value == 'edit') {
                                unawaited(_editCustomView(view));
                              }
                              if (value == 'duplicate') {
                                unawaited(_duplicateCustomView(view));
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'duplicate',
                                child: Text('Duplicate'),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Current default: $_currentDefaultSummary',
                key: const ValueKey('settings-saved-view-current-default'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _SavedViewDefinition {
  const _SavedViewDefinition({
    required this.id,
    required this.label,
    required this.dayView,
    required this.tableView,
    this.tableSort,
  });

  final String id;
  final String label;
  final String dayView;
  final String tableView;
  final String? tableSort;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'dayView': dayView,
    'tableView': tableView,
    if (tableSort != null) 'tableSort': tableSort,
  };

  static _SavedViewDefinition? fromJson(Object? value) {
    if (value case final Map<String, Object?> map) {
      final id = map['id']?.toString() ?? '';
      final label = map['label']?.toString() ?? '';
      final dayView = map['dayView']?.toString() ?? '';
      final tableView = map['tableView']?.toString() ?? '';
      final tableSort = map['tableSort']?.toString();
      if (id.isEmpty || label.isEmpty || dayView.isEmpty || tableView.isEmpty) {
        return null;
      }
      return _SavedViewDefinition(
        id: id,
        label: label,
        dayView: dayView,
        tableView: tableView,
        tableSort: tableSort,
      );
    }
    return null;
  }
}

List<_SavedViewDefinition> _decodeSavedViews(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const [];
    return decoded
        .map(_SavedViewDefinition.fromJson)
        .nonNulls
        .toList(growable: false);
  } on FormatException {
    return const [];
  }
}

String _savedViewOptionValue(
  List<_SavedViewOption> options,
  String value,
  String fallback,
) {
  return options.any((option) => option.value == value) ? value : fallback;
}

String _savedViewOptionLabel(List<_SavedViewOption> options, String value) {
  return options.firstWhereOrNull((option) => option.value == value)?.label ??
      value;
}

String _savedViewSummary(_SavedViewDefinition view) {
  final sort = view.tableSort == null
      ? null
      : _savedViewOptionLabel(_savedViewSortOptions, view.tableSort!);
  return [
    _savedViewOptionLabel(_savedViewDayOptions, view.dayView),
    _savedViewOptionLabel(_savedViewTableOptions, view.tableView),
    if (sort != null) 'Sort: $sort',
  ].join(' / ');
}

class _SavedViewDialog extends StatefulWidget {
  const _SavedViewDialog({
    required this.title,
    required this.actionLabel,
    required this.initial,
  });

  final String title;
  final String actionLabel;
  final _SavedViewDefinition initial;

  @override
  State<_SavedViewDialog> createState() => _SavedViewDialogState();
}

class _SavedViewDialogState extends State<_SavedViewDialog> {
  late final TextEditingController _labelController;
  late String _dayView;
  late String _tableView;
  late String _tableSort;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initial.label);
    _dayView = _savedViewOptionValue(
      _savedViewDayOptions,
      widget.initial.dayView,
      'canvas',
    );
    _tableView = _savedViewOptionValue(
      _savedViewTableOptions,
      widget.initial.tableView,
      'all',
    );
    _tableSort = _savedViewOptionValue(
      _savedViewSortOptions,
      widget.initial.tableSort ?? 'updatedDesc',
      'updatedDesc',
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelController.text.trim();
    if (label.isEmpty) return;
    Navigator.of(context).pop(
      _SavedViewDefinition(
        id: widget.initial.id,
        label: label,
        dayView: _dayView,
        tableView: _tableView,
        tableSort: _tableSort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('saved-view-label-field'),
                controller: _labelController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'View name'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              const Text('Day view'),
              const SizedBox(height: 6),
              _SavedViewOptionChips(
                options: _savedViewDayOptions,
                selectedValue: _dayView,
                keyPrefix: 'saved-view-dialog-day-view',
                onSelected: (value) => setState(() => _dayView = value),
              ),
              const SizedBox(height: 12),
              const Text('Table quick view'),
              const SizedBox(height: 6),
              _SavedViewOptionChips(
                options: _savedViewTableOptions,
                selectedValue: _tableView,
                keyPrefix: 'saved-view-dialog-table-view',
                onSelected: (value) => setState(() => _tableView = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('saved-view-dialog-table-sort'),
                initialValue: _tableSort,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Table sort',
                ),
                items: [
                  for (final option in _savedViewSortOptions)
                    DropdownMenuItem(
                      value: option.value,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _tableSort = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

final class _SettingsGraphFilter {
  const _SettingsGraphFilter({
    required this.id,
    required this.label,
    required this.raw,
  });

  final String id;
  final String label;
  final Map<String, Object?> raw;

  Map<String, Object?> toJson() => raw;

  static _SettingsGraphFilter? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final raw = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key != null) entry.key.toString(): entry.value,
    };
    final id = raw['id']?.toString() ?? '';
    final label = raw['label']?.toString() ?? '';
    if (id.isEmpty || label.isEmpty) return null;
    return _SettingsGraphFilter(id: id, label: label, raw: raw);
  }
}

class _GraphFiltersManagerCard extends StatefulWidget {
  const _GraphFiltersManagerCard();

  @override
  State<_GraphFiltersManagerCard> createState() =>
      _GraphFiltersManagerCardState();
}

class _GraphFiltersManagerCardState extends State<_GraphFiltersManagerCard> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  List<_SettingsGraphFilter> _filters = const [];
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFilters());
  }

  Future<void> _loadFilters() async {
    final raw = await _preferences.getString('graph_saved_filters');
    Object? decoded;
    try {
      decoded = raw == null ? null : jsonDecode(raw);
    } on FormatException {
      decoded = null;
    }
    final filters = decoded is List<Object?>
        ? decoded.map(_SettingsGraphFilter.fromJson).nonNulls.toList()
        : <_SettingsGraphFilter>[];
    if (mounted) setState(() => _filters = filters);
  }

  Future<void> _saveFilters(List<_SettingsGraphFilter> filters) async {
    await _preferences.setString(
      'graph_saved_filters',
      jsonEncode([for (final filter in filters) filter.toJson()]),
    );
    if (mounted) setState(() => _filters = filters);
  }

  Future<void> _renameFilter(_SettingsGraphFilter filter) async {
    final controller = TextEditingController(text: filter.label);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename graph filter'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Filter name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;
    await _saveFilters([
      for (final item in _filters)
        item.id == filter.id
            ? _SettingsGraphFilter(
                id: item.id,
                label: label,
                raw: {...item.raw, 'label': label},
              )
            : item,
    ]);
  }

  Future<void> _duplicateFilter(_SettingsGraphFilter filter) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await _saveFilters([
      ..._filters,
      _SettingsGraphFilter(
        id: id,
        label: '${filter.label} copy',
        raw: {...filter.raw, 'id': id, 'label': '${filter.label} copy'},
      ),
    ]);
  }

  Future<void> _deleteFilter(String id) async {
    await _saveFilters([
      for (final filter in _filters)
        if (filter.id != id) filter,
    ]);
  }

  Future<void> _exportFilters() async {
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode([for (final filter in _filters) filter.toJson()]),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${_filters.length} graph filters')),
    );
  }

  Future<void> _importFilters() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import graph filters'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Graph filters JSON',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final imported = decoded is List<Object?>
          ? decoded.map(_SettingsGraphFilter.fromJson).nonNulls
          : const Iterable<_SettingsGraphFilter>.empty();
      final merged = <String, _SettingsGraphFilter>{
        for (final filter in _filters) filter.id: filter,
        for (final filter in imported) filter.id: filter,
      };
      await _saveFilters(merged.values.toList(growable: false));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid graph filters JSON')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: _settingsPanelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Graph filters',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                Text('${_filters.length}', style: theme.textTheme.labelSmall),
                TextButton.icon(
                  key: const ValueKey('settings-graph-filters-toggle'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  label: Text(_expanded ? 'Hide' : 'Show'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Graph filter import/export',
                  onSelected: (value) {
                    if (value == 'export') unawaited(_exportFilters());
                    if (value == 'import') unawaited(_importFilters());
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'export', child: Text('Export JSON')),
                    PopupMenuItem(value: 'import', child: Text('Import JSON')),
                  ],
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              if (_filters.isEmpty)
                Text(
                  'No saved graph filters yet.',
                  style: theme.textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in _filters)
                      InputChip(
                        label: Text(filter.label),
                        avatar: const Icon(Icons.filter_alt_outlined, size: 16),
                        onDeleted: () => unawaited(_deleteFilter(filter.id)),
                        onPressed: () => unawaited(_renameFilter(filter)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        tooltip: 'Tap rename, close delete',
                      ),
                    for (final filter in _filters)
                      ActionChip(
                        avatar: const Icon(Icons.copy_all_outlined, size: 16),
                        label: Text('${filter.label} copy'),
                        onPressed: () => unawaited(_duplicateFilter(filter)),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReminderPreviewCard extends ConsumerStatefulWidget {
  const _ReminderPreviewCard();

  @override
  ConsumerState<_ReminderPreviewCard> createState() =>
      _ReminderPreviewCardState();
}

class _ReminderPreviewCardState extends ConsumerState<_ReminderPreviewCard> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  int _lookaheadDays = 7;
  bool _dueRemindersEnabled = true;
  bool _routineRemindersEnabled = true;
  int _reminderHour = 9;
  int _reminderMinute = 0;
  int _snoozeMinutes = 30;
  String? _reminderSyncMessage;
  int? _importedReminderPayloadCount;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final lookahead = await _preferences.getInt('reminder_lookahead_days');
    final dueEnabled = await _preferences.getBool('due_reminders_enabled');
    final routineEnabled = await _preferences.getBool(
      'routine_reminders_enabled',
    );
    final reminderHour = await _preferences.getInt('reminder_default_hour');
    final reminderMinute = await _preferences.getInt('reminder_default_minute');
    final snoozeMinutes = await _preferences.getInt('reminder_snooze_minutes');
    if (!mounted) return;
    setState(() {
      _lookaheadDays = lookahead ?? _lookaheadDays;
      _dueRemindersEnabled = dueEnabled ?? _dueRemindersEnabled;
      _routineRemindersEnabled = routineEnabled ?? _routineRemindersEnabled;
      _reminderHour = (reminderHour ?? _reminderHour).clamp(0, 23);
      _reminderMinute = (reminderMinute ?? _reminderMinute).clamp(0, 59);
      _snoozeMinutes = (snoozeMinutes ?? _snoozeMinutes).clamp(5, 240);
    });
  }

  ReminderSchedulePolicy get _schedulePolicy => ReminderSchedulePolicy(
    hour: _reminderHour,
    minute: _reminderMinute,
    snoozeMinutes: _snoozeMinutes,
  );

  Future<void> _setLookahead(double value) async {
    final days = value.round();
    setState(() => _lookaheadDays = days);
    await _preferences.setInt('reminder_lookahead_days', days);
  }

  Future<void> _setDueEnabled(bool value) async {
    setState(() => _dueRemindersEnabled = value);
    await _preferences.setBool('due_reminders_enabled', value);
  }

  Future<void> _setRoutineEnabled(bool value) async {
    setState(() => _routineRemindersEnabled = value);
    await _preferences.setBool('routine_reminders_enabled', value);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked == null) return;
    setState(() {
      _reminderHour = picked.hour;
      _reminderMinute = picked.minute;
    });
    await _preferences.setInt('reminder_default_hour', picked.hour);
    await _preferences.setInt('reminder_default_minute', picked.minute);
  }

  Future<void> _setSnoozeMinutes(int value) async {
    setState(() => _snoozeMinutes = value);
    await _preferences.setInt('reminder_snooze_minutes', value);
  }

  Future<void> _syncReminderSchedule(ReminderPlan plan) async {
    final notifications = buildScheduledReminderNotifications(
      plan,
      policy: _schedulePolicy,
    );
    await PersistedReminderNotificationAdapter().sync(
      plan,
      policy: _schedulePolicy,
    );
    try {
      final nativeAdapter = ref.read(nativeReminderNotificationAdapterProvider);
      if (!nativeAdapter.isSupported) {
        throw UnsupportedError(
          'Native scheduled notifications are unavailable on this platform.',
        );
      }
      await nativeAdapter.sync(plan, policy: _schedulePolicy);
      await ref.read(reminderAutoSchedulerProvider).setEnabled(true);
      if (!mounted) return;
      setState(() {
        _reminderSyncMessage =
            'Scheduled ${notifications.length} OS notifications at ${_formatReminderTime(context)}.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _reminderSyncMessage =
            'Saved ${notifications.length} reminder payloads, but OS scheduling failed: $error';
      });
    }
  }

  Future<void> _importReminderPayloadsPreview() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview reminder payloads'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Reminder payload JSON',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Preview'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final notifications = scheduledReminderNotificationsFromJson(decoded);
      if (!mounted) return;
      setState(() => _importedReminderPayloadCount = notifications.length);
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid reminder payload JSON')),
      );
    }
  }

  Future<void> _copyReminderPayloads(ReminderPlan plan) async {
    final notifications = buildScheduledReminderNotifications(
      plan,
      policy: _schedulePolicy,
    );
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode([
          for (final notification in notifications) notification.toJson(),
        ]),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${notifications.length} reminders JSON')),
    );
  }

  String _formatReminderTime(BuildContext context) {
    return TimeOfDay(
      hour: _reminderHour,
      minute: _reminderMinute,
    ).format(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = ref.watch(allMindmapNodesProvider);
    return DecoratedBox(
      decoration: _settingsPanelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: nodes.when(
          data: (value) {
            final today = DateTime.now().dateOnly;
            final plan = buildReminderPlan(
              nodes: value,
              routines: defaultRecurringRoutines,
              options: ReminderPlannerOptions(
                today: today,
                lookaheadDays: _lookaheadDays,
                dueRemindersEnabled: _dueRemindersEnabled,
                routineRemindersEnabled: _routineRemindersEnabled,
              ),
            );
            final grouped = plan.groupedByDay.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Upcoming due reminders',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    Text(
                      '${plan.items.length}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due reminders'),
                  value: _dueRemindersEnabled,
                  onChanged: _setDueEnabled,
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Routine reminders'),
                  value: _routineRemindersEnabled,
                  onChanged: _setRoutineEnabled,
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time_outlined, size: 18),
                  title: const Text('Default reminder time'),
                  subtitle: Text(_formatReminderTime(context)),
                  trailing: OutlinedButton(
                    onPressed: () => unawaited(_pickReminderTime()),
                    child: const Text('Change'),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in const [10, 15, 30, 60, 120])
                      ChoiceChip(
                        label: Text('Snooze ${minutes}m'),
                        selected: _snoozeMinutes == minutes,
                        onSelected: (_) =>
                            unawaited(_setSnoozeMinutes(minutes)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Lookahead: $_lookaheadDays days'),
                Slider(
                  min: 1,
                  max: 30,
                  divisions: 29,
                  value: _lookaheadDays.toDouble().clamp(1, 30),
                  label: '$_lookaheadDays days',
                  onChanged: _setLookahead,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_syncReminderSchedule(plan)),
                      icon: const Icon(Icons.notifications_outlined, size: 16),
                      label: const Text('Sync reminder schedule'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_copyReminderPayloads(plan)),
                      icon: const Icon(Icons.copy_all_outlined, size: 16),
                      label: const Text('Copy payloads'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(_importReminderPayloadsPreview()),
                      icon: const Icon(Icons.upload_file_outlined, size: 16),
                      label: const Text('Preview payloads'),
                    ),
                  ],
                ),
                if (_reminderSyncMessage != null)
                  Text(
                    _reminderSyncMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (_importedReminderPayloadCount != null)
                  Text(
                    'Imported payload preview: $_importedReminderPayloadCount reminders.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 8),
                if (plan.items.isEmpty)
                  Text(
                    'No reminders in the next $_lookaheadDays days.',
                    style: theme.textTheme.bodySmall,
                  )
                else ...[
                  if (plan.overdue.isNotEmpty)
                    Text(
                      '${plan.overdue.length} overdue included today',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  for (final group in grouped.take(4)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        dayKey(group.key),
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    for (final item in group.value.take(4))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.kind == ReminderPlanItemKind.routine
                              ? Icons.repeat_outlined
                              : item.isOverdue
                              ? Icons.warning_amber_outlined
                              : Icons.schedule_outlined,
                          size: 18,
                        ),
                        title: Text(item.title),
                        subtitle: Text(
                          item.kind == ReminderPlanItemKind.routine
                              ? 'Routine'
                              : item.isOverdue
                              ? 'Overdue from ${dayKey(item.node!.dueDate!)}'
                              : 'Due',
                        ),
                      ),
                  ],
                ],
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('Unable to load reminders'),
        ),
      ),
    );
  }
}

List<MindmapNode> _markdownToMindmapNodes(String markdown, DateTime now) {
  final sections = markdown.split(RegExp(r'(?=^##\s+)', multiLine: true));
  final drafts = <({String title, String body, List<String> links})>[];
  for (final section in sections) {
    final trimmed = section.trim();
    if (trimmed.isEmpty) continue;
    final lines = trimmed.split('\n');
    final rawTitle = lines.first.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    if (rawTitle.isEmpty || rawTitle == 'Var export') continue;
    final body = lines.skip(1).join('\n').trim();
    final links = RegExp(r'\[\[([^\]]+)\]\]')
        .allMatches(body)
        .map((match) => match.group(1)!.trim())
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList();
    drafts.add((title: rawTitle, body: body, links: links));
  }

  final titles = <String>{for (final draft in drafts) draft.title};
  for (final link in drafts.expand((draft) => draft.links)) {
    if (!titles.add(link)) continue;
    drafts.add((
      title: link,
      body: 'Auto-created from Markdown link.',
      links: const [],
    ));
  }

  final idsByTitle = <String, String>{
    for (var i = 0; i < drafts.length; i++)
      drafts[i].title: 'md-${now.microsecondsSinceEpoch}-$i',
  };

  return [
    for (final draft in drafts)
      MindmapNode.create(
        id: idsByTitle[draft.title]!,
        type: NodeType.note,
        title: draft.title,
        body: draft.body,
        day: now.dateOnly,
        tags: const ['markdown-import'],
        relatedNodeIds: [
          for (final link in draft.links)
            if (idsByTitle[link] != null) idsByTitle[link]!,
        ],
        data: {
          if (draft.links.isNotEmpty) 'markdownLinks': draft.links,
          if (draft.links.isNotEmpty)
            'relations': [
              for (final link in draft.links)
                if (idsByTitle[link] != null)
                  {'targetId': idsByTitle[link]!, 'label': 'mentions'},
            ],
        },
        now: now,
      ),
  ];
}

String _mindmapNodesToMarkdown(List<MindmapNode> nodes) {
  final sorted = [...nodes]
    ..sort((a, b) {
      final day = a.day.compareTo(b.day);
      if (day != 0) return day;
      return a.title.compareTo(b.title);
    });
  final buffer = StringBuffer('# Var export\n\n');
  for (final node in sorted) {
    if (node.isArchived) continue;
    buffer.writeln('## ${node.title}');
    buffer.writeln();
    buffer.writeln('- Type: ${node.type.label}');
    buffer.writeln('- Day: ${dayKey(node.day)}');
    if (node.status != NodeStatus.open) {
      buffer.writeln('- Status: ${node.status.label}');
    }
    if (node.priority != NodePriority.none) {
      buffer.writeln('- Priority: ${node.priority.label}');
    }
    if (node.tags.isNotEmpty) {
      buffer.writeln('- Tags: ${node.tags.map((tag) => '#$tag').join(' ')}');
    }
    if (node.relatedNodeIds.isNotEmpty) {
      final linkedTitles = [
        for (final id in node.relatedNodeIds)
          nodes.where((candidate) => candidate.id == id).firstOrNull?.title,
      ].whereType<String>();
      buffer.writeln(
        '- Links: ${linkedTitles.map((title) => '[[$title]]').join(', ')}',
      );
    }
    if (node.body.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(node.body.trim());
    }
    buffer.writeln();
  }
  return buffer.toString();
}

class _FeatureGuideCard extends StatefulWidget {
  const _FeatureGuideCard();

  @override
  State<_FeatureGuideCard> createState() => _FeatureGuideCardState();
}

class _FeatureGuideCardState extends State<_FeatureGuideCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: _settingsPanelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Quick start guide',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    _expanded ? 'Hide guide' : 'Show guide',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              const _GuideStep(
                icon: Icons.calendar_today_outlined,
                title: 'Calendar first',
                body: 'Pick a day, then plan work on canvas, table, or board.',
              ),
              const _GuideStep(
                icon: Icons.account_tree_outlined,
                title: 'Connect ideas',
                body:
                    'Use [[links]], relation labels, backlinks, and graph view.',
              ),
              const _GuideStep(
                icon: Icons.auto_awesome_outlined,
                title: 'Automate routines',
                body:
                    'Use Smart actions, routine presets, snooze, skip, and apply.',
              ),
              const _GuideStep(
                icon: Icons.insights_outlined,
                title: 'Review weekly',
                body:
                    'Insights shows wins, overdue work, goals, and next actions.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataManagementCard extends ConsumerStatefulWidget {
  const _DataManagementCard();

  @override
  ConsumerState<_DataManagementCard> createState() =>
      _DataManagementCardState();
}

class _DataManagementCardState extends ConsumerState<_DataManagementCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Data management', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: _settingsPanelDecoration(context),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    TextButton.icon(
                      key: const ValueKey('data-management-toggle'),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                      ),
                      label: Text(
                        _expanded ? 'Hide options' : 'Data management options',
                      ),
                    ),
                  ],
                ),
              ),
              if (_expanded) ...[
                const Divider(height: 1),
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
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Export Markdown'),
                  subtitle: const Text(
                    'Copy Obsidian-compatible Markdown with [[backlinks]]',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () async {
                    final repository = ref.read(mindmapRepositoryProvider);
                    final nodes = await repository.listNodes();
                    final markdown = _mindmapNodesToMarkdown(nodes);
                    await Clipboard.setData(ClipboardData(text: markdown));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Markdown export copied to clipboard'),
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.note_add_outlined),
                  title: const Text('Import Markdown'),
                  subtitle: const Text('Paste Obsidian-style Markdown notes'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => _showMarkdownImportDialog(context, ref),
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
            ],
          ),
        ),
      ],
    );
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

class _DatabaseLockCard extends ConsumerWidget {
  const _DatabaseLockCard();

  void _showPinDialog(BuildContext context, WidgetRef ref, bool isSet) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isSet ? 'Change/Disable PIN' : 'Set PIN Lock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSet
                    ? 'Enter new PIN (or leave empty to disable):'
                    : 'Enter a 4-6 digit numeric PIN to encrypt your local database:',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'PIN'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final pin = controller.text;
                if (pin.isEmpty) {
                  if (isSet) {
                    ref.read(databaseLockProvider.notifier).removePin();
                  }
                } else {
                  ref.read(databaseLockProvider.notifier).setPin(pin);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(databaseLockProvider);
    return DecoratedBox(
      decoration: _settingsPanelDecoration(context),
      child: ListTile(
        leading: const Icon(Icons.security_outlined),
        title: const Text('Database PIN Lock'),
        subtitle: Text(
          lock.hasPin
              ? 'PIN Lock is active. Local database is encrypted.'
              : 'PIN Lock is inactive.',
        ),
        trailing: Icon(
          lock.hasPin ? Icons.lock_rounded : Icons.lock_open_rounded,
        ),
        onTap: () => _showPinDialog(context, ref, lock.hasPin),
      ),
    );
  }
}
