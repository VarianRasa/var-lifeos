/// Day detail page — opens the mindmap for a given date.
///
/// Renders the day's mindmap canvas, side panels, timeline, and node mutation
/// flows through the repository/provider boundary.
library;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/runtime_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';
import '../../core/theme/node_visuals.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/error_message.dart';
import '../command/domain/quick_create_command_parser.dart';
import '../mindmap/application/canvas_workshop_controller.dart';
import '../mindmap/application/collaboration_controller.dart';
import '../mindmap/application/collaboration_session.dart';
import '../mindmap/application/inline_node_workspace_controller.dart';
import '../mindmap/application/media_file_import_service.dart';
import '../mindmap/application/mindmap_mutation_controller.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/node_comment_controller.dart';
import '../mindmap/application/node_inline_edit_controller.dart';
import '../mindmap/application/recurring_routine_application.dart';
import '../mindmap/data/http_audio_transcription_repository.dart';
import '../mindmap/domain/audio_transcription.dart';
import '../mindmap/domain/canvas_board.dart';
import '../mindmap/domain/canvas_position.dart';
import '../mindmap/domain/canvas_workshop.dart';
import '../mindmap/domain/collaboration_room.dart';
import '../mindmap/domain/custom_node_template_codec.dart';
import '../mindmap/domain/drawing_draft_checkpoint.dart';
import '../mindmap/domain/goal_progress.dart';
import '../mindmap/domain/habit_completion.dart';
import '../mindmap/domain/inline_node_workspace_policy.dart';
import '../mindmap/domain/kanban_board.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/node_attachment.dart';
import '../mindmap/domain/node_presentation.dart';
import '../mindmap/domain/node_template.dart';
import '../mindmap/domain/node_type_payloads.dart';
import '../mindmap/domain/node_ui_state_codec.dart';
import '../mindmap/domain/plan_progress.dart';
import '../mindmap/domain/project_plan.dart';
import '../mindmap/domain/recurring_routine.dart';
import '../mindmap/domain/task_checklist_progress.dart';
import '../mindmap/domain/workspace_context.dart';
import '../mindmap/presentation/canvas_assistant_dialog.dart';
import '../mindmap/presentation/inline_node_workspace.dart';
import '../mindmap/presentation/life_explorer.dart';
import '../mindmap/presentation/mindmap_canvas.dart';
import '../mindmap/presentation/node_comments_panel.dart';
import '../mindmap/presentation/node_editors/audio_node_editor.dart';
import '../mindmap/presentation/node_editors/canvas_node_editor.dart';
import '../mindmap/presentation/node_editors/knowledge_node_editors.dart';
import '../mindmap/presentation/node_editors/media_travel_node_editors.dart';
import '../mindmap/presentation/node_revision_history_dialog.dart';
import '../mindmap/presentation/node_shell.dart';
import '../mindmap/presentation/node_type_inline_editor.dart';
import '../workspace/data/workspace_title_repository.dart';
import 'application/carry_over_planner.dart';
import 'application/daily_planning_engine.dart';
import 'application/daily_review_builder.dart';
import 'application/day_markdown_export.dart';
import 'application/day_mini_insights.dart';
import 'application/day_templates.dart';
import 'application/focus_session.dart';
import 'application/node_inbox.dart';
import 'application/workload_balancer.dart';
import 'widgets/daily_cockpit_panel.dart';
import 'widgets/daily_timeline_schedule.dart';
import 'widgets/day_canvas_tab_header.dart';

final class _CanvasMenuItem<T> {
  const _CanvasMenuItem({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}

const _canvasContextFolders = [
  _CanvasMenuItem(
    value: _CanvasContextFolder.create,
    icon: Icons.add_circle_outline,
    label: 'Create',
  ),
  _CanvasMenuItem(
    value: _CanvasContextFolder.selection,
    icon: Icons.select_all,
    label: 'Selection',
  ),
  _CanvasMenuItem(
    value: _CanvasContextFolder.view,
    icon: Icons.visibility_outlined,
    label: 'View',
  ),
  _CanvasMenuItem(
    value: _CanvasContextFolder.layout,
    icon: Icons.account_tree_outlined,
    label: 'Layout',
  ),
  _CanvasMenuItem(
    value: _CanvasContextFolder.organize,
    icon: Icons.folder_outlined,
    label: 'Organize',
  ),
  _CanvasMenuItem(
    value: _CanvasContextFolder.transfer,
    icon: Icons.import_export,
    label: 'Import/export',
  ),
  _CanvasMenuItem(
    value: _CanvasContextFolder.commands,
    icon: Icons.terminal,
    label: 'Commands',
  ),
];

List<_CanvasMenuItem<CanvasContextAction>> _canvasContextFolderActions(
  _CanvasContextFolder folder,
) {
  return switch (folder) {
    _CanvasContextFolder.create => const [
      _CanvasMenuItem(
        value: CanvasContextAction.createNode,
        icon: Icons.add_circle_outline,
        label: 'Create node',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.quickTask,
        icon: Icons.check_box_outlined,
        label: 'Quick task',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.quickNote,
        icon: Icons.note_add_outlined,
        label: 'Quick note',
      ),
    ],
    _CanvasContextFolder.selection => const [
      _CanvasMenuItem(
        value: CanvasContextAction.paste,
        icon: Icons.content_paste,
        label: 'Paste copied nodes',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.selectAll,
        icon: Icons.select_all,
        label: 'Select all',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.moveSelectionHere,
        icon: Icons.open_with,
        label: 'Move selection here',
      ),
    ],
    _CanvasContextFolder.view => const [
      _CanvasMenuItem(
        value: CanvasContextAction.fitAll,
        icon: Icons.fit_screen,
        label: 'Fit all nodes',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.resetZoom,
        icon: Icons.center_focus_strong,
        label: 'Reset zoom',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.toggleGrid,
        icon: Icons.grid_on,
        label: 'Toggle grid',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.toggleSnap,
        icon: Icons.grid_4x4,
        label: 'Toggle snap to grid',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.toggleMinimap,
        icon: Icons.map_outlined,
        label: 'Toggle minimap',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.toggleCompleted,
        icon: Icons.visibility_outlined,
        label: 'Completed tasks stay visible',
      ),
    ],
    _CanvasContextFolder.layout => const [
      _CanvasMenuItem(
        value: CanvasContextAction.tidyLayout,
        icon: Icons.grid_view,
        label: 'Tidy grid layout',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.radialLayout,
        icon: Icons.hub_outlined,
        label: 'Mindmap layout',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.typeLayout,
        icon: Icons.category_outlined,
        label: 'Group by type',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.timelineLayout,
        icon: Icons.timeline,
        label: 'Timeline layout',
      ),
    ],
    _CanvasContextFolder.organize => const [
      _CanvasMenuItem(
        value: CanvasContextAction.groupSelection,
        icon: Icons.folder_copy_outlined,
        label: 'Group selection',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.ungroupSelection,
        icon: Icons.folder_off_outlined,
        label: 'Ungroup selection',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.cycleBackground,
        icon: Icons.wallpaper_outlined,
        label: 'Change background',
      ),
    ],
    _CanvasContextFolder.transfer => const [
      _CanvasMenuItem(
        value: CanvasContextAction.importClipboard,
        icon: Icons.input,
        label: 'Import clipboard as node',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.exportJson,
        icon: Icons.data_object,
        label: 'Copy canvas JSON',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.exportPng,
        icon: Icons.image_outlined,
        label: 'Export canvas PNG',
      ),
      _CanvasMenuItem(
        value: CanvasContextAction.exportPdf,
        icon: Icons.picture_as_pdf_outlined,
        label: 'Export canvas PDF',
      ),
    ],
    _CanvasContextFolder.commands => const [
      _CanvasMenuItem(
        value: CanvasContextAction.commandPalette,
        icon: Icons.terminal,
        label: 'Open command palette',
      ),
    ],
  };
}

enum _CanvasContextFolder {
  create,
  selection,
  view,
  layout,
  organize,
  transfer,
  commands,
}

final class _CanvasContextCascadeMenu extends StatefulWidget {
  const _CanvasContextCascadeMenu({required this.origin});

  final Offset origin;

  @override
  State<_CanvasContextCascadeMenu> createState() =>
      _CanvasContextCascadeMenuState();
}

final class _CanvasContextCascadeMenuState
    extends State<_CanvasContextCascadeMenu> {
  _CanvasContextFolder? _activeFolder;

  @override
  Widget build(BuildContext context) {
    const mainWidth = 224.0;
    const submenuWidth = 244.0;
    const menuPadding = 8.0;
    final rowHeight = AppDesignTokens.of(context).minimumTarget;
    final size = MediaQuery.sizeOf(context);
    final left = widget.origin.dx.clamp(
      menuPadding,
      (size.width - mainWidth - menuPadding).clamp(menuPadding, size.width),
    );
    final mainMenuHeight = _canvasContextFolders.length * rowHeight + 8;
    final top = widget.origin.dy.clamp(
      menuPadding,
      (size.height - mainMenuHeight - menuPadding).clamp(
        menuPadding,
        size.height,
      ),
    );
    final submenuLeft = left + mainWidth + 4 + submenuWidth <= size.width
        ? left + mainWidth + 4
        : (left - submenuWidth - 4).clamp(menuPadding, size.width);
    final activeFolder = _activeFolder;
    final activeFolderIndex = activeFolder == null
        ? 0
        : _canvasContextFolders.indexWhere(
            (folder) => folder.value == activeFolder,
          );
    final submenuHeight = activeFolder == null
        ? 0.0
        : _canvasContextFolderActions(activeFolder).length * rowHeight + 8;
    final alignedSubmenuTop = top + activeFolderIndex * rowHeight;
    final submenuTop = alignedSubmenuTop.clamp(
      menuPadding,
      (size.height - submenuHeight - menuPadding).clamp(
        menuPadding,
        size.height,
      ),
    );

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: mainWidth,
          child: _menuPanel(
            context,
            children: [
              for (final folder in _canvasContextFolders) _folderRow(folder),
            ],
          ),
        ),
        if (_activeFolder case final folder?)
          Positioned(
            key: const ValueKey('canvas-context-submenu'),
            left: submenuLeft,
            top: submenuTop,
            width: submenuWidth,
            child: _menuPanel(
              context,
              children: [
                for (final action in _canvasContextFolderActions(folder))
                  _actionRow(action),
              ],
            ),
          ),
      ],
    );
  }

  Widget _menuPanel(BuildContext context, {required List<Widget> children}) {
    final theme = Theme.of(context);
    final popupTheme = theme.popupMenuTheme;
    final tokens = AppDesignTokens.of(context);
    return Material(
      color: popupTheme.color,
      surfaceTintColor: popupTheme.surfaceTintColor,
      elevation: popupTheme.elevation ?? 3,
      shadowColor: popupTheme.shadowColor,
      shape:
          popupTheme.shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusContainer),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _folderRow(_CanvasMenuItem<_CanvasContextFolder> folder) {
    final selected = folder.value == _activeFolder;
    return MouseRegion(
      onEnter: (_) => setState(() => _activeFolder = folder.value),
      child: InkWell(
        key: ValueKey('canvas-context-folder-${folder.value.name}'),
        onTap: () => setState(() => _activeFolder = folder.value),
        child: Container(
          constraints: BoxConstraints(
            minHeight: AppDesignTokens.of(context).minimumTarget,
          ),
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(folder.icon, size: 19),
              const SizedBox(width: 10),
              Expanded(child: Text(folder.label)),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionRow(_CanvasMenuItem<CanvasContextAction> action) {
    return InkWell(
      key: ValueKey('canvas-context-action-${action.value.name}'),
      onTap: () => Navigator.of(context).pop(action.value),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: AppDesignTokens.of(context).minimumTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(action.icon, size: 19),
              const SizedBox(width: 10),
              Expanded(child: Text(action.label)),
            ],
          ),
        ),
      ),
    );
  }
}

class DayPage extends ConsumerStatefulWidget {
  const DayPage({
    required this.date,
    this.highlightNodeId,
    this.initialBoardId,
    this.mediaFileExporter,
    super.key,
  });

  final DateTime date;
  final String? highlightNodeId;
  final String? initialBoardId;
  final MediaFileExporter? mediaFileExporter;

  @override
  ConsumerState<DayPage> createState() => _DayPageState();
}

class _NonTextEditingActivator extends ShortcutActivator {
  const _NonTextEditingActivator(this.delegate);

  final ShortcutActivator delegate;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => delegate.triggers;

  @override
  String debugDescribeKeys() => delegate.debugDescribeKeys();

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    final BuildContext? context = FocusManager.instance.primaryFocus?.context;
    final bool isEditingText =
        context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
    return !isEditingText && delegate.accepts(event, state);
  }
}

class _DayPageState extends ConsumerState<DayPage> with WidgetsBindingObserver {
  final _canvasKey = GlobalKey<MindmapCanvasState>();
  List<CanvasObject> _assistantPreviewObjects = const <CanvasObject>[];
  late final InlineNodeWorkspaceController _inlineWorkspaceController;
  String? _selectedNodeId;
  String? _activeBoardId;
  final TextEditingController _quickCaptureController = TextEditingController();
  bool _isMissionMode = false;
  DateTime? _focusStartedAt;
  String? _focusNodeId;
  String? _followingCollaboratorId;
  int? _focusTargetMinutes;
  bool _focusTargetNotified = false;
  Timer? _focusTicker;
  String? _workshopMaintenanceSignature;
  static const CanvasWorkshopController _workshop = CanvasWorkshopController();
  bool _isDayTabsCollapsed = true;
  final bool _isDayTabsHidden = false;
  final bool _isRibbonToolbarCollapsed = false;
  bool _isFloatingTopBarVisible = true;
  bool _isFloatingRibbonVisible = true;
  bool _isFloatingBoardTabsVisible = true;
  bool _isBlankBoardHidden = false;
  bool _isCanvasAddNodeMenuOpen = false;
  bool _isLifeExplorerExpanded = true;
  bool _allowBackPop = false;
  bool _isHandlingBackPop = false;
  int _highlightSelectionGeneration = 0;
  _DayViewMode _viewMode = _DayViewMode.canvas;
  _MindmapRibbonTab _ribbonTab = _MindmapRibbonTab.home;
  final Map<String, NodeSaveStatus> _inlineSaveStatuses = {};
  final Set<String> _inlineEditingNodeIds = {};
  final Map<String, Future<void>> _nodeMutationQueues = {};
  _DayContextFilter _contextFilter = _DayContextFilter.all;
  String? _workspaceContextKey;
  _TableQuickView _tableQuickView = _TableQuickView.all;
  _TableSortMode _tableSortMode = _TableSortMode.updatedDesc;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const String _viewModePreferenceKey = 'day_view_mode';
  static const String _ribbonTabPreferenceKey = 'mindmap_ribbon_tab';
  static const String _contextFilterPreferenceKey = 'day_context_filter';
  static const String _workspaceContextPreferenceKey = 'day_workspace_context';
  static const String _tableQuickViewPreferenceKey = 'day_table_quick_view';
  static const String _tableSortModePreferenceKey = 'day_table_sort_mode';
  static const String _lifeExplorerPreferenceKey = 'life_explorer_expanded';

  // Undo / Redo stacks for node mutations (max 50 entries).
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  static const int _maxUndo = 50;

  @override
  void initState() {
    super.initState();
    _activeBoardId = widget.initialBoardId;
    WidgetsBinding.instance.addObserver(this);
    _inlineWorkspaceController = ref.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    ref.listenManual<Map<String, InlineNodeDraftState>>(
      inlineNodeWorkspaceControllerProvider.select((state) => state.nodes),
      (previous, next) {
        if (!mounted || identical(previous, next)) return;
        for (final entry in next.entries) {
          final prior = previous?[entry.key];
          final current = entry.value;
          if (prior?.status == InlineNodeSaveStatus.saving &&
              current.status == InlineNodeSaveStatus.saved &&
              prior!.generation == current.generation &&
              prior.base.updatedAt != current.base.updatedAt) {
            _pushUndo(
              _UndoEntry(
                kind: _UndoKind.save,
                nodeId: entry.key,
                before: prior.base,
                after: current.base,
              ),
            );
          }
          _inlineSaveStatuses[entry.key] = switch (current.status) {
            InlineNodeSaveStatus.dirty => NodeSaveStatus.dirty,
            InlineNodeSaveStatus.saving => NodeSaveStatus.saving,
            InlineNodeSaveStatus.saved => NodeSaveStatus.saved,
            InlineNodeSaveStatus.error => NodeSaveStatus.error,
            InlineNodeSaveStatus.idle => NodeSaveStatus.idle,
          };
        }
        setState(() {});
      },
    );
    if (widget.highlightNodeId != null) {
      _scheduleHighlightedNodeSelection(widget.highlightNodeId);
    }
    _loadViewPreferences();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusTicker?.cancel();
    _quickCaptureController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightNodeId != oldWidget.highlightNodeId) {
      _scheduleHighlightedNodeSelection(widget.highlightNodeId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushInlineWorkspace());
    }
  }

  Future<void> _loadViewPreferences() async {
    final storedViewMode = await _preferences.getString(_viewModePreferenceKey);
    final storedRibbonTab = await _preferences.getString(
      _ribbonTabPreferenceKey,
    );
    final storedContextFilter = await _preferences.getString(
      _contextFilterPreferenceKey,
    );
    final storedWorkspaceContext = await _preferences.getString(
      _workspaceContextPreferenceKey,
    );
    final storedTableView = await _preferences.getString(
      _tableQuickViewPreferenceKey,
    );
    final storedTableSortMode = await _preferences.getString(
      _tableSortModePreferenceKey,
    );
    final storedLifeExplorerExpanded = await _preferences.getBool(
      _lifeExplorerPreferenceKey,
    );
    if (!mounted) return;

    setState(() {
      _viewMode = _dayViewModeFromName(storedViewMode) ?? _viewMode;
      _ribbonTab = _MindmapRibbonTab.values.firstWhere(
        (tab) => tab.name == storedRibbonTab,
        orElse: () => _ribbonTab,
      );
      _contextFilter =
          _dayContextFilterFromName(storedContextFilter) ?? _contextFilter;
      _workspaceContextKey = storedWorkspaceContext?.isEmpty == true
          ? null
          : storedWorkspaceContext;
      _tableQuickView =
          _tableQuickViewFromName(storedTableView) ?? _tableQuickView;
      _tableSortMode =
          _tableSortModeFromName(storedTableSortMode) ?? _tableSortMode;
      _isLifeExplorerExpanded =
          storedLifeExplorerExpanded ?? _isLifeExplorerExpanded;
    });
  }

  Future<void> _setRibbonTab(_MindmapRibbonTab tab) async {
    setState(() => _ribbonTab = tab);
    await _preferences.setString(_ribbonTabPreferenceKey, tab.name);
  }

  Future<void> _setSelectedNodePreset(
    MindmapNode node,
    NodeSizePreset preset,
  ) async {
    await _serializeNodeMutation(node.id, () async {
      if (_inlineEditingNodeIds.contains(node.id) &&
          !await _finishSelectedNodeEdit(node)) {
        return;
      }
      final latest = await ref.read(mindmapRepositoryProvider).getNode(node.id);
      if (latest == null) return;
      final current = NodeUiStateCodec.read(latest);
      final updated = latest
          .copyWithUiState(
            NodeUiState(
              sizePreset: preset,
              width: current.width,
              height: current.height,
              collapsedSections: current.collapsedSections,
              editorVersion: current.editorVersion,
            ),
          )
          .copyWith(updatedAt: DateTime.now());
      if (mounted) {
        setState(() => _inlineSaveStatuses[node.id] = NodeSaveStatus.saving);
      }
      await ref.read(mindmapMutationControllerProvider).saveNode(updated);
      if (mounted && _selectedNodeId == node.id) {
        setState(() => _inlineSaveStatuses[node.id] = NodeSaveStatus.saved);
      }
    });
  }

  Future<void> _deleteCanvasNodes(List<MindmapNode> nodes) async {
    if (nodes.isEmpty || !await _flushInlineWorkspace()) return;
    final repository = ref.read(mindmapRepositoryProvider);
    final deleted = <MindmapNode>[];
    for (final source in nodes) {
      final latest = await repository.getNode(source.id);
      if (latest == null) continue;
      _pushUndo(
        _UndoEntry(kind: _UndoKind.delete, nodeId: latest.id, before: latest),
      );
      await repository.deleteNode(latest.id);
      deleted.add(latest);
    }
    await _canvasKey.currentState?.runContextAction(
      CanvasContextAction.clearSelection,
    );
    for (final node in deleted) {
      await _deleteCanvasObjectReference(node);
    }
    for (final day in deleted.map((node) => node.day.dateOnly).toSet()) {
      invalidateMindmapState(ref, day: day);
    }
    if (mounted && deleted.isNotEmpty) {
      _showSnackBar('Deleted ${deleted.length} selected nodes');
    }
  }

  Future<void> _resizeCanvasNode(
    MindmapNode node,
    NodeResizeChange change,
  ) async {
    await _serializeNodeMutation(node.id, () async {
      final repository = ref.read(mindmapRepositoryProvider);
      final latest = await repository.getNode(node.id);
      if (latest == null) return;
      final currentUi = NodeUiStateCodec.read(latest);
      final position = CanvasPosition(
        latest.position.dx + change.positionDelta.dx,
        latest.position.dy + change.positionDelta.dy,
      );
      final updated = latest.copyWith(
        position: position,
        data: NodeUiStateCodec.write(
          latest,
          NodeUiState(
            sizePreset: change.preset,
            width: change.size.width,
            height: change.size.height,
            collapsedSections: currentUi.collapsedSections,
            editorVersion: currentUi.editorVersion,
          ),
        ),
        updatedAt: DateTime.now(),
      );
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.save,
          nodeId: latest.id,
          before: latest,
          after: updated,
        ),
      );
      await ref.read(mindmapMutationControllerProvider).saveNode(updated);
      await _persistCanvasNodeGeometry(updated);
    });
  }

  Future<void> _persistCanvasNodeGeometry(MindmapNode node) async {
    final day = node.day.dateOnly;
    final boardId = dailyCanvasBoardId(day);
    final boardRepository = ref.read(canvasBoardRepositoryProvider);
    final persisted = await boardRepository.getBoard(boardId);
    if (persisted == null) {
      final nodes = await ref
          .read(mindmapRepositoryProvider)
          .listNodes(day: day);
      await boardRepository.saveBoard(
        CanvasBoard.daily(day: day, nodes: nodes, now: DateTime.now()),
      );
    } else {
      final uiState = NodeUiStateCodec.read(node);
      final current = persisted.objectById('node:${node.id}');
      final updated =
          (current ??
                  CanvasObject(
                    id: 'node:${node.id}',
                    type: CanvasObjectType.nodeReference,
                    geometry: CanvasGeometry(
                      x: node.position.dx,
                      y: node.position.dy,
                      width: uiState.width,
                      height: uiState.height,
                    ),
                    mindmapNodeId: node.id,
                    createdAt: node.createdAt,
                    updatedAt: node.updatedAt,
                  ))
              .copyWith(
                geometry: CanvasGeometry(
                  x: node.position.dx,
                  y: node.position.dy,
                  width: uiState.width,
                  height: uiState.height,
                ),
                updatedAt: node.updatedAt,
              );
      await boardRepository.saveObjects(boardId, <CanvasObject>[updated]);
    }
    ref.invalidate(dailyCanvasBoardProvider(day));
  }

  Future<void> _deleteCanvasObjectReference(MindmapNode node) async {
    final day = node.day.dateOnly;
    await ref.read(canvasBoardRepositoryProvider).deleteObjects(
      dailyCanvasBoardId(day),
      <String>['node:${node.id}'],
    );
    ref.invalidate(dailyCanvasBoardProvider(day));
  }

  Future<void> _createNativeCanvasObject(
    DateTime day,
    CanvasObject object,
  ) async {
    final normalizedDay = day.dateOnly;
    final boardId = dailyCanvasBoardId(normalizedDay);
    final boardRepository = ref.read(canvasBoardRepositoryProvider);
    final persisted = await boardRepository.getBoard(boardId);
    late final CanvasObject savedObject;
    if (persisted == null) {
      final nodes = await ref
          .read(mindmapRepositoryProvider)
          .listNodes(day: normalizedDay);
      final board = CanvasBoard.daily(
        day: normalizedDay,
        nodes: nodes,
        now: DateTime.now(),
      );
      savedObject = object.copyWith(zIndex: board.objects.length);
      await boardRepository.saveBoard(
        board.copyWith(objects: <CanvasObject>[...board.objects, savedObject]),
      );
    } else {
      final nextZIndex =
          persisted.objects.fold<int>(
            -1,
            (current, candidate) =>
                candidate.zIndex > current ? candidate.zIndex : current,
          ) +
          1;
      savedObject = object.copyWith(zIndex: nextZIndex);
      await boardRepository.saveObjects(boardId, <CanvasObject>[savedObject]);
    }
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.canvasCreate,
        nodeId: savedObject.id,
        canvasAfter: savedObject,
      ),
    );
    ref.invalidate(dailyCanvasBoardProvider(normalizedDay));
  }

  Future<CanvasImageSource?> _importNativeCanvasImage() async {
    try {
      final repository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      final payload = await MediaFileImportService(
        repository: repository,
        picker: const FilePickerMediaFilePicker(),
      ).pickImage();
      if (payload == null) return null;
      return CanvasImageSource(
        attachmentId: payload.attachmentId,
        fileName: payload.fileName,
        mimeType: payload.mimeType,
        byteLength: payload.byteLength ?? 0,
      );
    } on FormatException catch (error) {
      if (mounted) _showSnackBar(error.message);
      return null;
    }
  }

  Future<List<int>?> _loadNativeCanvasAttachment(String attachmentId) async {
    final repository = await ref.read(nodeAttachmentRepositoryProvider.future);
    return repository.readBytes(attachmentId);
  }

  Future<void> _updateNativeCanvasObject(
    DateTime day,
    CanvasObject object,
  ) async {
    final normalizedDay = day.dateOnly;
    final repository = ref.read(canvasBoardRepositoryProvider);
    final boardId = dailyCanvasBoardId(normalizedDay);
    final before = (await repository.getBoard(boardId))?.objectById(object.id);
    await repository.saveObjects(boardId, <CanvasObject>[object]);
    if (before != null && before != object) {
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.canvasUpdate,
          nodeId: object.id,
          canvasBefore: before,
          canvasAfter: object,
        ),
      );
    }
    ref.invalidate(dailyCanvasBoardProvider(normalizedDay));
  }

  Future<void> _deleteNativeCanvasObject(
    DateTime day,
    CanvasObject object,
  ) async {
    final normalizedDay = day.dateOnly;
    await ref.read(canvasBoardRepositoryProvider).deleteObjects(
      dailyCanvasBoardId(normalizedDay),
      <String>[object.id],
    );
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.canvasDelete,
        nodeId: object.id,
        canvasBefore: object,
      ),
    );
    ref.invalidate(dailyCanvasBoardProvider(normalizedDay));
  }

  Future<void> _createNativeCanvasObjects(
    DateTime day,
    List<CanvasObject> objects,
  ) async {
    if (objects.isEmpty) return;
    final normalizedDay = day.dateOnly;
    final boardId = dailyCanvasBoardId(normalizedDay);
    final repository = ref.read(canvasBoardRepositoryProvider);
    final persisted = await repository.getBoard(boardId);
    final baseZIndex =
        persisted?.objects.fold<int>(
          -1,
          (current, object) =>
              object.zIndex > current ? object.zIndex : current,
        ) ??
        -1;
    final saved = <CanvasObject>[
      for (var index = 0; index < objects.length; index++)
        objects[index].copyWith(zIndex: baseZIndex + index + 1),
    ];
    if (persisted == null) {
      final nodes = await ref
          .read(mindmapRepositoryProvider)
          .listNodes(day: normalizedDay);
      final board = CanvasBoard.daily(
        day: normalizedDay,
        nodes: nodes,
        now: DateTime.now(),
      );
      await repository.saveBoard(
        board.copyWith(objects: <CanvasObject>[...board.objects, ...saved]),
      );
    } else {
      await repository.saveObjects(boardId, saved);
    }
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.canvasBatch,
        nodeId: saved.first.id,
        canvasAfterBatch: saved,
      ),
    );
    ref.invalidate(dailyCanvasBoardProvider(normalizedDay));
  }

  Future<void> _updateNativeCanvasObjects(
    DateTime day,
    List<CanvasObject> objects,
  ) async {
    if (objects.isEmpty) return;
    final normalizedDay = day.dateOnly;
    final repository = ref.read(canvasBoardRepositoryProvider);
    final boardId = dailyCanvasBoardId(normalizedDay);
    final board = await repository.getBoard(boardId);
    final before = objects
        .map((object) => board?.objectById(object.id))
        .nonNulls
        .toList();
    await repository.saveObjects(boardId, objects);
    if (before.isNotEmpty) {
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.canvasBatch,
          nodeId: objects.first.id,
          canvasBeforeBatch: before,
          canvasAfterBatch: objects,
        ),
      );
    }
    ref.invalidate(dailyCanvasBoardProvider(normalizedDay));
  }

  Future<void> _deleteNativeCanvasObjects(
    DateTime day,
    List<CanvasObject> objects,
  ) async {
    if (objects.isEmpty) return;
    final normalizedDay = day.dateOnly;
    await ref
        .read(canvasBoardRepositoryProvider)
        .deleteObjects(
          dailyCanvasBoardId(normalizedDay),
          objects.map((object) => object.id),
        );
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.canvasBatch,
        nodeId: objects.first.id,
        canvasBeforeBatch: objects,
      ),
    );
    ref.invalidate(dailyCanvasBoardProvider(normalizedDay));
  }

  Future<void> _openDailyCanvasAssistant(
    CanvasBoard board,
    List<MindmapNode> nodes,
    bool canApply,
  ) async {
    final selectedIds =
        _canvasKey.currentState?.selectedCanvasObjectIds ?? const <String>{};
    final result = await showDialog<CanvasAssistantDialogResult>(
      context: context,
      builder: (context) => CanvasAssistantDialog(
        board: board,
        nodes: nodes,
        selectedObjectIds: selectedIds,
        canApply: canApply,
        workshopAiEndpoint: ref.read(runtimeConfigProvider).workshopAiEndpoint,
        onPreviewChanged: (objects) {
          if (mounted) setState(() => _assistantPreviewObjects = objects);
        },
      ),
    );
    if (mounted) {
      setState(() => _assistantPreviewObjects = const <CanvasObject>[]);
    }
    if (result == null || !mounted) return;
    final repository = ref.read(canvasBoardRepositoryProvider);
    final current = await repository.getBoard(board.id) ?? board;
    if (!result.analysis.isCurrent(current)) {
      if (mounted) _showSnackBar('Board changed. Run assistant again.');
      return;
    }
    final now = DateTime.now();
    var applied = result.analysis.apply(result.proposalIds, now: now);
    final snapshot = result.aiSummarySnapshot;
    if (snapshot != null) {
      applied = applied.copyWith(
        workshopSession: applied.workshopSession.saveAiSummary(snapshot),
      );
    }
    final next = applied.recordActivity(
      type: CanvasActivityType.assistantApplied,
      summary:
          'Applied ${result.proposalIds.length} canvas assistant suggestion${result.proposalIds.length == 1 ? '' : 's'}',
      now: now,
      objectIds: result.analysis.analyzedObjectIds,
    );
    await repository.saveBoard(next);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.canvasBoard,
        nodeId: board.id,
        canvasBoardBefore: current,
        canvasBoardAfter: next,
      ),
    );
    ref.invalidate(dailyCanvasBoardProvider(widget.date.dateOnly));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Canvas assistant suggestions applied.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(_undo()),
        ),
      ),
    );
  }

  Future<void> _createDailySubBoard(DateTime day) async {
    final normalizedDay = day.dateOnly;
    final now = DateTime.now();
    final newBoardId = 'day-board-${now.millisecondsSinceEpoch}';
    final newBoard = CanvasBoard(
      id: newBoardId,
      title: 'Canvas Board',
      kind: CanvasBoardKind.daily,
      day: normalizedDay,
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(canvasBoardRepositoryProvider).saveBoard(newBoard);
    ref.invalidate(dailyCanvasBoardsProvider(normalizedDay));
    if (!mounted) return;
    setState(() {
      _activeBoardId = newBoardId;
    });
    _showSnackBar('New board created');
  }

  Future<void> _renameDailyBoard(CanvasBoard board) async {
    final controller = TextEditingController(text: board.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Board'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Board name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (title == null || title.isEmpty || title == board.title) return;

    await ref
        .read(canvasBoardRepositoryProvider)
        .saveBoard(board.copyWith(title: title, updatedAt: DateTime.now()));
    ref.invalidate(dailyCanvasBoardsProvider(board.day!.dateOnly));
    if (!mounted) return;
    _showSnackBar('Board renamed');
  }

  Future<void> _deleteDailyBoard(
    CanvasBoard board,
    List<CanvasBoard> dayBoards,
  ) async {
    if (board.isPrimaryDayBoard) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Board'),
        content: Text(
          'Delete "${board.title}"? All content on this board will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(canvasBoardRepositoryProvider).deleteBoard(board.id);
    ref.invalidate(dailyCanvasBoardsProvider(board.day!.dateOnly));
    if (!mounted) return;

    if (_activeBoardId == board.id) {
      for (final candidate in dayBoards) {
        if (candidate.isPrimaryDayBoard) {
          setState(() => _activeBoardId = candidate.id);
          break;
        }
      }
    }
    _showSnackBar('Board deleted');
  }

  List<CanvasWorkshopStage> _dailyWorkshopAgenda(String template) {
    const durations = <int>[60, 180, 60, 120, 120, 60];
    final agenda = _workshop.agendaTemplate(template);
    return <CanvasWorkshopStage>[
      for (final (index, stage) in agenda.indexed)
        CanvasWorkshopStage(
          id: stage.id,
          title: stage.title,
          type: stage.type,
          durationSeconds: durations[index],
          instructions: stage.instructions,
          maxVotesPerParticipant: 3,
        ),
    ];
  }

  Future<void> _saveWorkshopBoard(CanvasBoard before, CanvasBoard after) async {
    if (before == after) return;
    await ref.read(canvasBoardRepositoryProvider).saveBoard(after);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.canvasBoard,
        nodeId: before.id,
        canvasBoardBefore: before,
        canvasBoardAfter: after,
      ),
    );
    ref.invalidate(dailyCanvasBoardProvider(widget.date.dateOnly));
  }

  CanvasBoard _withDailyVotingSession(
    CanvasBoard board,
    CanvasVotingSession session,
    DateTime now,
  ) => board.copyWith(
    votingSession: session,
    objects: <CanvasObject>[
      for (final object in board.objects)
        object.voteCount == session.votesForObject(object.id)
            ? object
            : object.withVoteCount(
                session.votesForObject(object.id),
                updatedAt: now,
              ),
    ],
    updatedAt: now,
  );

  Future<void> _showDailyVotingResults(CanvasBoard board) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final ranked =
          board.objects
              .where((object) => object.type != CanvasObjectType.connector)
              .toList()
            ..sort(
              (left, right) => board.votingSession
                  .votesForObject(right.id)
                  .compareTo(board.votingSession.votesForObject(left.id)),
            );
      return AlertDialog(
        title: const Text('Voting results'),
        content: SizedBox(
          width: 420,
          child: ranked.isEmpty
              ? const Text('No canvas objects to rank.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: ranked.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final object = ranked[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(object.type.name),
                      trailing: Text(
                        '${board.votingSession.votesForObject(object.id)} votes',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );

  Future<void> _openDailyVotingDialog(CanvasBoard board) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!board.votingSession.isActive)
              ListTile(
                leading: const Icon(Icons.how_to_vote_outlined),
                title: const Text('Start voting'),
                onTap: () => Navigator.pop(sheetContext, 'start'),
              ),
            if (board.votingSession.isActive)
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('End voting'),
                onTap: () => Navigator.pop(sheetContext, 'end'),
              ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Show results'),
              onTap: () => Navigator.pop(sheetContext, 'results'),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset voting'),
              onTap: () => Navigator.pop(sheetContext, 'reset'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'results') {
      await _showDailyVotingResults(board);
      return;
    }
    final now = DateTime.now();
    final session = switch (action) {
      'start' => board.votingSession.start(maxVotes: 3, anonymous: false),
      'end' => board.votingSession.end(),
      'reset' => board.votingSession.reset(),
      _ => board.votingSession,
    };
    await _saveWorkshopBoard(
      board,
      _withDailyVotingSession(board, session, now),
    );
  }

  Future<void> _openDailyWorkshopMenu(CanvasBoard board) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!board.workshopSession.isActive) ...[
              for (final option in const <(String, String)>[
                ('brainstorm', 'Start brainstorm'),
                ('retrospective', 'Start retrospective'),
                ('decision', 'Start decision'),
              ])
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(option.$2),
                  onTap: () => Navigator.pop(sheetContext, option.$1),
                ),
            ] else ...[
              ListTile(
                leading: Icon(
                  board.workshopSession.status == CanvasWorkshopStatus.paused
                      ? Icons.play_arrow
                      : Icons.pause,
                ),
                title: Text(
                  board.workshopSession.status == CanvasWorkshopStatus.paused
                      ? 'Resume workshop'
                      : 'Pause workshop',
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  board.workshopSession.status == CanvasWorkshopStatus.paused
                      ? 'resume'
                      : 'pause',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.skip_next),
                title: const Text('Advance stage'),
                onTap: () => Navigator.pop(sheetContext, 'advance'),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Reveal contributions'),
                onTap: () => Navigator.pop(sheetContext, 'reveal'),
              ),
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('End workshop'),
                onTap: () => Navigator.pop(sheetContext, 'end'),
              ),
            ],
            if (board.workshopSession.summary != null)
              ListTile(
                leading: const Icon(Icons.summarize_outlined),
                title: const Text('Show summary'),
                onTap: () => Navigator.pop(sheetContext, 'summary'),
              ),
          ],
        ),
      ),
    );
    if (action != null) {
      await _handleDailyWorkshopAction(board, action);
    }
  }

  Future<void> _showDailyActivityHistory(CanvasBoard board) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Activity history — ${board.title}'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: board.activity.isEmpty
            ? const Center(child: Text('No activity logged yet.'))
            : ListView.separated(
                itemCount: board.activity.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = board.activity[index];
                  return ListTile(
                    leading: const Icon(Icons.history_outlined),
                    title: Text(item.summary),
                    subtitle: Text(
                      '${item.occurredAt.hour}:${item.occurredAt.minute.toString().padLeft(2, '0')}',
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _openDailyBoardTemplates(CanvasBoard board) async {
    final template = await showModalBottomSheet<CanvasProjectTemplate>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.architecture_outlined),
              title: const Text('Project planning'),
              onTap: () => Navigator.pop(
                sheetContext,
                CanvasProjectTemplate.projectPlan,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.view_kanban_outlined),
              title: const Text('Kanban workflow'),
              onTap: () =>
                  Navigator.pop(sheetContext, CanvasProjectTemplate.kanban),
            ),
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('Brainstorming'),
              onTap: () =>
                  Navigator.pop(sheetContext, CanvasProjectTemplate.brainstorm),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Moodboard'),
              onTap: () =>
                  Navigator.pop(sheetContext, CanvasProjectTemplate.moodboard),
            ),
          ],
        ),
      ),
    );
    if (template == null || !mounted) return;
    final now = DateTime.now();
    final updated = board.addProjectTemplate(template, now: now);
    await ref.read(canvasBoardRepositoryProvider).saveBoard(updated);
    ref.invalidate(dailyCanvasBoardsProvider(widget.date.dateOnly));
    _showSnackBar('Template applied');
  }

  Future<void> _exportDailyBoard(CanvasBoard board) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Board Actions — ${board.title}'),
        content: Text(
          'Objects count: ${board.objects.length}\nCreated: ${board.createdAt.toIso8601String().split('T').first}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'duplicate'),
            child: const Text('Duplicate Board'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'export'),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (result == 'duplicate' && mounted) {
      final now = DateTime.now();
      final duplicated = board.copyWith(
        title: '${board.title} (Copy)',
        updatedAt: now,
      );
      await ref.read(canvasBoardRepositoryProvider).saveBoard(duplicated);
      ref.invalidate(dailyCanvasBoardsProvider(widget.date.dateOnly));
      setState(() => _activeBoardId = duplicated.id);
      _showSnackBar('Board duplicated');
    }
  }

  Future<void> _startDailyWorkshop(CanvasBoard board, String template) =>
      _saveWorkshopBoard(
        board,
        _workshop.startAgenda(
          board: board,
          sessionId: const Uuid().v4(),
          hostUid: 'local',
          agenda: _dailyWorkshopAgenda(template),
          now: DateTime.now(),
        ),
      );

  Future<void> _handleDailyWorkshopAction(
    CanvasBoard board,
    String action,
  ) async {
    final now = DateTime.now();
    switch (action) {
      case 'brainstorm':
      case 'retrospective':
      case 'decision':
        await _startDailyWorkshop(board, action);
      case 'pause':
        await _saveWorkshopBoard(board, _workshop.pause(board, now));
      case 'resume':
        await _saveWorkshopBoard(board, _workshop.resume(board, now));
      case 'advance':
        await _saveWorkshopBoard(board, _workshop.advanceStage(board, now));
      case 'reveal':
        await _saveWorkshopBoard(board, _workshop.revealStage(board, now));
      case 'end':
        await _saveWorkshopBoard(board, _workshop.end(board, now));
      case 'summary':
        final summary = board.workshopSession.summary;
        if (summary != null) await _showDailyWorkshopSummary(summary);
    }
  }

  Future<void> _showDailyWorkshopSummary(
    CanvasWorkshopSummary summary,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Workshop summary'),
      content: Text(
        'Active time: ${summary.activeDurationSeconds ~/ 60}m ${summary.activeDurationSeconds % 60}s\n'
        'Participants: ${summary.participantCount}\n'
        'Objects added: ${summary.objectsAdded}\n'
        'Objects updated: ${summary.objectsUpdated}\n'
        'Objects deleted: ${summary.objectsDeleted}\n'
        'Winning votes: ${summary.votingWinnerVotes}\n'
        'Stages completed: ${summary.completedStageIds.length}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  String _dailyWorkshopTime(CanvasWorkshopSession session) {
    final seconds = session.activeStageRemainingSeconds(DateTime.now());
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _saveDailyCanvasViewport(
    CanvasBoard board,
    CanvasViewport viewport,
  ) async {
    final repository = ref.read(canvasBoardRepositoryProvider);
    final current = await repository.getBoard(board.id) ?? board;
    if (current.viewport == viewport) return;
    await repository.saveBoard(
      current.copyWith(viewport: viewport, updatedAt: DateTime.now()),
    );
    ref.invalidate(dailyCanvasBoardProvider(widget.date.dateOnly));
  }

  Future<void> _serializeNodeMutation(
    String nodeId,
    Future<void> Function() mutation,
  ) {
    final previous = _nodeMutationQueues[nodeId] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .catchError((Object _) {})
        .then((_) => mutation())
        .catchError((Object error) {
          if (mounted) {
            setState(() => _inlineSaveStatuses[nodeId] = NodeSaveStatus.error);
            _showSnackBar('Node update failed: $error');
          }
        })
        .whenComplete(() {
          if (identical(_nodeMutationQueues[nodeId], next)) {
            _nodeMutationQueues.remove(nodeId);
          }
        });
    _nodeMutationQueues[nodeId] = next;
    return next;
  }

  void _beginSelectedNodeEdit(MindmapNode node) {
    _canvasKey.currentState?.beginInlineEdit(node.id);
  }

  Future<bool> _finishSelectedNodeEdit(MindmapNode node) async {
    return await _canvasKey.currentState?.finishInlineEdit(node.id) ?? true;
  }

  Future<void> _clearSelectedNode(MindmapNode node) async {
    await _nodeMutationQueues[node.id];
    if (!mounted) return;
    if (_inlineEditingNodeIds.contains(node.id)) {
      final saved = await _finishSelectedNodeEdit(node);
      if (!saved || !mounted) return;
    }
    final cleared = await ref
        .read(inlineNodeWorkspaceControllerProvider.notifier)
        .requestExpansion(null);
    if (!cleared || !mounted) return;
    setState(() {
      _selectedNodeId = null;
      _inlineEditingNodeIds.remove(node.id);
      _inlineSaveStatuses.remove(node.id);
      if (_ribbonTab == _MindmapRibbonTab.node) {
        _ribbonTab = _MindmapRibbonTab.home;
      }
    });
  }

  Future<bool> _selectNode(MindmapNode node) async {
    final currentId = _selectedNodeId;
    if (currentId != null &&
        currentId != node.id &&
        _inlineEditingNodeIds.contains(currentId)) {
      final current = await ref
          .read(mindmapRepositoryProvider)
          .getNode(currentId);
      if (current != null && !await _finishSelectedNodeEdit(current)) {
        return false;
      }
    }
    if (!mounted) return false;
    final expanded = await ref
        .read(inlineNodeWorkspaceControllerProvider.notifier)
        .requestExpansion(node.id);
    if (!expanded ||
        !mounted ||
        ref.read(inlineNodeWorkspaceControllerProvider).expandedNodeId !=
            node.id) {
      return false;
    }
    setState(() {
      if (currentId != null && currentId != node.id) {
        _inlineEditingNodeIds.remove(currentId);
        _inlineSaveStatuses.remove(currentId);
      }
      _selectedNodeId = node.id;
      _ribbonTab = _MindmapRibbonTab.node;
    });
    return true;
  }

  void _scheduleHighlightedNodeSelection(String? nodeId) {
    final generation = ++_highlightSelectionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_applyHighlightedNodeSelection(nodeId, generation));
      }
    });
  }

  Future<void> _applyHighlightedNodeSelection(
    String? nodeId,
    int generation,
  ) async {
    if (nodeId == null) {
      await _clearSelection();
      return;
    }
    final node = await ref.read(mindmapRepositoryProvider).getNode(nodeId);
    if (!mounted || generation != _highlightSelectionGeneration) return;
    if (node == null || dayKey(node.day) != dayKey(widget.date)) {
      _inlineWorkspaceController.discardMissingNode(nodeId);
      _showSnackBar('Node no longer exists');
      return;
    }
    if (!await _selectNode(node) ||
        !mounted ||
        generation != _highlightSelectionGeneration) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _highlightSelectionGeneration) return;
    _canvasKey.currentState?.focusOnPosition(node.position);
  }

  Future<bool> _clearSelection() async {
    final nodeId = _selectedNodeId;
    if (nodeId == null) {
      return _inlineWorkspaceController.requestExpansion(null);
    }
    final node = await ref.read(mindmapRepositoryProvider).getNode(nodeId);
    if (node != null) {
      await _clearSelectedNode(node);
      return _selectedNodeId == null;
    }
    _inlineWorkspaceController.discardMissingNode(nodeId);
    if (!mounted) return false;
    setState(() {
      _selectedNodeId = null;
      _inlineEditingNodeIds.remove(nodeId);
      _inlineSaveStatuses.remove(nodeId);
    });
    return true;
  }

  Future<bool> _guardExpandedSelectionChange(
    String? currentNodeId,
    String? nextNodeId,
  ) async {
    if (currentNodeId == null || currentNodeId == nextNodeId) return true;
    await _nodeMutationQueues[currentNodeId];
    return ref
        .read(inlineNodeWorkspaceControllerProvider.notifier)
        .requestExpansion(nextNodeId);
  }

  Widget _buildExpandedNode(MindmapNode persistedNode) {
    return Consumer(
      builder: (context, ref, _) {
        final draftState = ref.watch(
          inlineNodeWorkspaceControllerProvider.select(
            (state) => state.nodes[persistedNode.id],
          ),
        );
        final node = draftState?.draft ?? persistedNode;
        final typedDraft = nodeTypeInlineDraftFor(node);
        final previewAttachmentId = switch (typedDraft) {
          final ImagePayload payload => payload.attachmentId,
          final VideoPayload payload => payload.attachmentId,
          final ResourcePayload payload =>
            payload.primaryAsset?.attachmentId ?? '',
          _ => '',
        };
        final previewBytesState = previewAttachmentId.isEmpty
            ? null
            : ref.watch(
                nodeAttachmentPreviewBytesProvider(previewAttachmentId),
              );
        final (
          previewBytes,
          previewLoading,
          previewError,
        ) = switch (previewBytesState) {
          AsyncData(:final value) => (
            value,
            false,
            value == null ? 'Media thumbnail is missing.' : null,
          ),
          AsyncError(:final error) => (null, false, error.toString()),
          AsyncLoading() => (null, true, null),
          null => (null, false, null),
          _ => (null, false, null),
        };
        final draftError = draftState?.error;
        final validationErrors =
            draftState?.status == InlineNodeSaveStatus.dirty &&
                draftError is String
            ? <String>[draftError]
            : const <String>[];
        return InlineNodeWorkspace(
          key: ValueKey<String>('inline-workspace-${node.id}'),
          node: node,
          editContext: NodeEditContext(
            node: node,
            typedDraft: typedDraft,
            cachedPayload: typedDraft,
            effectivePreset: NodeUiStateCodec.read(node).sizePreset,
            validationErrors: validationErrors,
            onTitleChanged: (_) {},
            onBodyChanged: (_) {},
            onDraftChanged: (_) {},
            onNodeDraftChanged: (_) {},
            attachmentBytes: previewBytes,
            attachmentLoading: previewLoading,
            attachmentError: previewError,
            onTaskChecklistAction: (_) async {},
            onTaskAttachmentAdd: _addTaskAttachment,
            onTaskAttachmentOpen: _openTaskAttachment,
            onTaskAttachmentRemove: _removeTaskAttachment,
            onResourceAssetAdd: _addResourceAsset,
            onResourceAssetOpen: _openResourceAsset,
            onKanbanAttachmentAdd: _addKanbanAttachment,
            onKanbanAttachmentOpen: _openKanbanAttachment,
            onKanbanAttachmentRemove: _removeKanbanAttachment,
            onPlanAttachmentAdd: _addPlanAttachment,
            onPlanAttachmentOpen: _openPlanAttachment,
            onPlanAttachmentRemove: _removePlanAttachment,
            onKanbanAction: (_) async {},
            onPlanAction: (_) async {},
            onGoalAction: (_) async {},
            onHabitAction: (_) async {},
            onTimerAction: (_) async {},
            onEmptyAction: (_) async {},
            onKnowledgeAction: (Object action) =>
                _handleInlineKnowledgeAction(node, action),
            onItineraryAction: (Object action) =>
                _handleInlineItineraryAction(node, action),
            onMediaAction: (Object action) =>
                _handleInlineMediaAction(node, action),
            onActionError: (Object error, StackTrace stackTrace) {
              _showSnackBar('Action failed: $error');
            },
          ),
          saveStatus: draftState?.status ?? InlineNodeSaveStatus.idle,
          onCollapse: () => unawaited(_clearSelectedNode(node)),
          onRetrySave: () => unawaited(
            ref
                .read(inlineNodeWorkspaceControllerProvider.notifier)
                .flush(node.id),
          ),
          onDraftChanged: (patch) => ref
              .read(inlineNodeWorkspaceControllerProvider.notifier)
              .updateDraft(node.id, patch),
        );
      },
    );
  }

  Future<TaskAttachmentReference?> _addTaskAttachment() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        withData: true,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      final bytes = file.bytes;
      if (file.size <= 0 || bytes == null || bytes.isEmpty) {
        throw const FormatException('Selected attachment is empty.');
      }
      if (file.size > maxNodeAttachmentBytes ||
          bytes.length > maxNodeAttachmentBytes) {
        throw const FormatException('Attachment exceeds 100 MB.');
      }
      if (bytes.length != file.size) {
        throw const FormatException('Attachment data is incomplete.');
      }
      final repository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      final attachment = await repository.importBytes(
        bytes: bytes,
        fileName: file.name,
        mimeType: _taskAttachmentMimeType(file.extension),
      );
      return TaskAttachmentReference(
        id: attachment.id,
        fileName: attachment.fileName,
        mimeType: attachment.mimeType,
        byteLength: attachment.byteLength,
      );
    } on Object catch (error) {
      if (mounted) _showSnackBar('Attachment failed: $error');
      return null;
    }
  }

  Future<ResourceAsset?> _addResourceAsset() async {
    final attachment = await _addTaskAttachment();
    if (attachment == null) return null;
    return ResourceAsset(
      id: 'asset-${const Uuid().v4()}',
      kind: 'file',
      label: attachment.fileName,
      attachmentId: attachment.id,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.byteLength,
      fileName: attachment.fileName,
      extension: _resourceExtensionFromFileName(attachment.fileName),
    );
  }

  Future<void> _openResourceAsset(ResourceAsset asset) async {
    if (asset.isUrl) {
      final uri = Uri.tryParse(asset.location.trim());
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException('Resource URL could not be opened.');
      }
      return;
    }
    if (!asset.isFile || asset.attachmentId.isEmpty) {
      throw const FormatException('Resource file is unavailable.');
    }
    await _openTaskAttachment(
      TaskAttachmentReference(
        id: asset.attachmentId,
        fileName: asset.fileName.isEmpty ? asset.displayName : asset.fileName,
        mimeType: asset.mimeType.isEmpty
            ? _taskAttachmentMimeType(asset.extension)
            : asset.mimeType,
        byteLength: asset.sizeBytes ?? 0,
      ),
    );
  }

  Future<KanbanAttachmentReference?> _addKanbanAttachment() async {
    final attachment = await _addTaskAttachment();
    return attachment == null
        ? null
        : KanbanAttachmentReference(
            id: attachment.id,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            byteLength: attachment.byteLength,
          );
  }

  Future<void> _openKanbanAttachment(KanbanAttachmentReference attachment) =>
      _openTaskAttachment(
        TaskAttachmentReference(
          id: attachment.id,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          byteLength: attachment.byteLength,
        ),
      );

  Future<void> _removeKanbanAttachment(KanbanAttachmentReference attachment) =>
      _removeTaskAttachment(
        TaskAttachmentReference(
          id: attachment.id,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          byteLength: attachment.byteLength,
        ),
      );
  Future<ProjectPlanAttachmentReference?> _addPlanAttachment() async {
    final attachment = await _addTaskAttachment();
    return attachment == null
        ? null
        : ProjectPlanAttachmentReference(
            id: attachment.id,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            byteLength: attachment.byteLength,
          );
  }

  Future<void> _openPlanAttachment(ProjectPlanAttachmentReference attachment) =>
      _openTaskAttachment(
        TaskAttachmentReference(
          id: attachment.id,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          byteLength: attachment.byteLength,
        ),
      );

  Future<void> _removePlanAttachment(
    ProjectPlanAttachmentReference attachment,
  ) => _removeTaskAttachment(
    TaskAttachmentReference(
      id: attachment.id,
      fileName: attachment.fileName,
      mimeType: attachment.mimeType,
      byteLength: attachment.byteLength,
    ),
  );
  Future<void> _openTaskAttachment(TaskAttachmentReference attachment) async {
    final repository = await ref.read(nodeAttachmentRepositoryProvider.future);
    final bytes = await repository.readBytes(attachment.id);
    if (bytes == null) {
      throw const FormatException('Attachment is unavailable.');
    }
    final data = Uint8List.fromList(bytes);
    if (attachment.mimeType.startsWith('image/')) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: InteractiveViewer(child: Image.memory(data)),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    if (_isTaskTextAttachment(attachment.fileName)) {
      final preview = utf8.decode(data, allowMalformed: true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(attachment.fileName),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(
                preview.length > 20000 ? preview.substring(0, 20000) : preview,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    final exporter = widget.mediaFileExporter;
    if (exporter == null) {
      throw UnsupportedError('File preview is unavailable.');
    }
    await exporter(data, attachment.fileName);
  }

  Future<void> _removeTaskAttachment(TaskAttachmentReference attachment) async {
    final repository = await ref.read(nodeAttachmentRepositoryProvider.future);
    await repository.delete(attachment.id);
  }

  static String _taskAttachmentMimeType(String? extension) =>
      switch (extension?.trim().toLowerCase()) {
        'gif' => 'image/gif',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        _ => 'application/octet-stream',
      };

  static bool _isTaskTextAttachment(String fileName) {
    final lower = fileName.toLowerCase();
    return const <String>[
      '.txt',
      '.md',
      '.csv',
      '.json',
      '.yaml',
      '.yml',
    ].any(lower.endsWith);
  }

  static String _resourceExtensionFromFileName(String fileName) {
    final name = fileName.trim().replaceAll('\\', '/').split('/').last;
    final separator = name.lastIndexOf('.');
    return separator <= 0 || separator == name.length - 1
        ? ''
        : name.substring(separator + 1).toLowerCase();
  }

  Future<bool> _selectAndFocusNode(MindmapNode node) async {
    final bool selected = await _selectNode(node);
    if (!selected) return false;
    _canvasKey.currentState?.focusOnPosition(node.position);
    return true;
  }

  Future<void> _handleInlineMediaAction(MindmapNode node, Object action) async {
    if (action is SaveEditedImageAction) {
      try {
        final repository = await ref.read(
          nodeAttachmentRepositoryProvider.future,
        );
        final attachment = await repository.importBytes(
          bytes: action.bytes,
          fileName: 'edited-image-${DateTime.now().millisecondsSinceEpoch}.png',
          mimeType: 'image/png',
        );
        action.result.complete(
          action.existing.copyWith(
            attachmentId: attachment.id,
            originalAttachmentId: action.existing.originalAttachmentId.isEmpty
                ? action.existing.attachmentId
                : action.existing.originalAttachmentId,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            byteLength: attachment.byteLength,
            clearUrl: true,
            rotationQuarterTurns: 0,
            flipHorizontal: false,
            flipVertical: false,
            brightness: 0,
            contrast: 0,
            saturation: 0,
            filter: ImageFilterPreset.none,
            annotations: const <ImageAnnotation>[],
          ),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is RestoreOriginalImageAction) {
      try {
        final repository = await ref.read(
          nodeAttachmentRepositoryProvider.future,
        );
        final attachment = await repository.resolve(
          action.existing.originalAttachmentId,
        );
        if (attachment == null) {
          throw StateError('Original image attachment is unavailable.');
        }
        action.result.complete(
          action.existing.copyWith(
            attachmentId: attachment.id,
            mimeType: attachment.mimeType,
            fileName: attachment.fileName,
            byteLength: attachment.byteLength,
            originalAttachmentId: '',
            clearUrl: true,
            rotationQuarterTurns: 0,
            flipHorizontal: false,
            flipVertical: false,
            brightness: 0,
            contrast: 0,
            saturation: 0,
            filter: ImageFilterPreset.none,
            annotations: const <ImageAnnotation>[],
          ),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is ReplaceImageAction || action is ReplaceVideoAction) {
      await _replaceMedia(node);
      return;
    }
    if (action is ExportImageAction || action is ExportVideoAction) {
      await _exportSelectedMedia(node);
      return;
    }
    if (action is OpenImageExternallyAction ||
        action is OpenVideoExternallyAction) {
      await _openMediaSource(node);
    }
  }

  Future<void> _handleInlineKnowledgeAction(
    MindmapNode node,
    Object action,
  ) async {
    if (action is PickAudioFileAction) {
      try {
        final service = await ref.read(mediaFileImportServiceProvider.future);
        action.result.complete(
          await service.pickAudio(existing: action.existing),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is ImportRecordedAudioAction) {
      try {
        final repository = await ref.read(
          nodeAttachmentRepositoryProvider.future,
        );
        final attachment = await repository.importBytes(
          bytes: action.bytes,
          fileName: 'recording-${DateTime.now().millisecondsSinceEpoch}.wav',
          mimeType: 'audio/wav',
        );
        action.result.complete(
          action.existing.copyWith(
            sourceType: AudioSourceType.attachment,
            attachmentId: attachment.id,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            sizeBytes: attachment.byteLength,
            remoteUrl: '',
          ),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is TranscribeAudioAction) {
      try {
        final endpoint = ref
            .read(runtimeConfigProvider)
            .audioTranscriptionEndpoint;
        if (endpoint == null) {
          throw const AudioTranscriptionException(
            'not-configured',
            'AI transcription endpoint is not configured.',
          );
        }
        if (action.payload.attachmentId.isEmpty) {
          throw const AudioTranscriptionException(
            'attachment-required',
            'Import or record audio before transcription.',
          );
        }
        final attachments = await ref.read(
          nodeAttachmentRepositoryProvider.future,
        );
        final bytes = await attachments.readBytes(action.payload.attachmentId);
        if (bytes == null) {
          throw const AudioTranscriptionException(
            'audio-missing',
            'Stored audio could not be read.',
          );
        }
        final result =
            await HttpAudioTranscriptionRepository(
              endpoint: endpoint,
            ).transcribe(
              bytes: bytes,
              fileName: action.payload.fileName,
              mimeType: action.payload.mimeType,
            );
        action.result.complete(
          action.payload.copyWith(
            transcriptText: result.text,
            transcriptSegments: result.segments,
            transcriptionStatus: 'complete',
            transcriptionError: '',
          ),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is LoadAudioAttachmentAction) {
      try {
        final repository = await ref.read(
          nodeAttachmentRepositoryProvider.future,
        );
        final bytes = await repository.readBytes(action.attachmentId);
        action.result.complete(
          bytes == null ? null : Uint8List.fromList(bytes),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is DeleteAudioVoiceNoteAction) {
      try {
        if (action.payload.attachmentId.isNotEmpty) {
          final repository = await ref.read(
            nodeAttachmentRepositoryProvider.future,
          );
          await repository.delete(action.payload.attachmentId);
        }
        action.result.complete(
          action.payload.copyWith(
            sourceType: AudioSourceType.none,
            attachmentId: '',
            fileName: '',
            mimeType: '',
            sizeBytes: 0,
            remoteUrl: '',
            durationMilliseconds: 0,
            transcriptSegments: const <AudioTranscriptSegment>[],
            transcriptionStatus: 'idle',
            transcriptionError: '',
          ),
        );
      } on Object catch (error, stackTrace) {
        action.result.complete(null);
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    if (action is OpenKnowledgeExternalAction) {
      final Uri? uri = Uri.tryParse(action.target);
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) _showSnackBar('Unable to open link');
      }
      return;
    }
    if (action is OpenSubCanvasAction) {
      final MindmapNode? latest = await ref
          .read(mindmapRepositoryProvider)
          .getNode(action.nodeId);
      if (latest == null || !mounted) return;
      final CanvasPayload initialPayload = CanvasPayload.fromNode(latest);
      CanvasPayload draft = initialPayload;
      final draftStore = ref.read(drawingDraftStoreProvider);
      final String recoveryKey = 'canvas_fullscreen_draft_${action.nodeId}';
      var checkpoint = await draftStore.get(action.nodeId);
      final String? legacy = await _preferences.getString(recoveryKey);
      if (checkpoint == null && legacy != null) {
        try {
          final Object? decoded = jsonDecode(legacy);
          if (decoded is Map &&
              decoded['baseUpdatedAt'] == latest.updatedAt.toIso8601String() &&
              decoded['data'] is Map) {
            final migrated = DrawingDraftCheckpoint(
              nodeId: action.nodeId,
              baseUpdatedAt: latest.updatedAt,
              generation: 1,
              data: Map<String, Object?>.from(decoded['data'] as Map),
              updatedAt: DateTime.now().toUtc(),
            );
            if (migrated.validateFor(latest).isEmpty) {
              await draftStore.putIfNewer(migrated);
              checkpoint = migrated;
            }
          }
        } on Object {
          checkpoint = null;
        }
        await _preferences.remove(recoveryKey);
      }
      var generation = checkpoint?.generation ?? 0;
      Future<void> checkpointWrites = Future<void>.value();
      if (checkpoint?.statusFor(latest) == DrawingDraftStatus.recoverable &&
          checkpoint!.validateFor(latest).isEmpty) {
        draft = CanvasPayload.fromNode(latest.copyWith(data: checkpoint.data));
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            latest.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close canvas',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: CanvasNodeEditor(
                          payload: draft,
                          onChanged: (CanvasPayload value) {
                            draft = value;
                            generation += 1;
                            final committedGeneration = generation;
                            checkpointWrites = checkpointWrites.then(
                              (_) => draftStore.putIfNewer(
                                DrawingDraftCheckpoint(
                                  nodeId: action.nodeId,
                                  baseUpdatedAt: latest.updatedAt,
                                  generation: committedGeneration,
                                  data: draft.toData(latest.data),
                                  updatedAt: DateTime.now().toUtc(),
                                ),
                              ),
                            );
                            unawaited(checkpointWrites);
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await checkpointWrites;
      final MindmapNode? current = await ref
          .read(mindmapRepositoryProvider)
          .getNode(action.nodeId);
      if (current == null) return;
      final CanvasPayload currentPayload = CanvasPayload.fromNode(current);
      final bool remoteCanvasChanged =
          jsonEncode(currentPayload.toData(const <String, Object?>{})) !=
          jsonEncode(initialPayload.toData(const <String, Object?>{}));
      if (remoteCanvasChanged && current.updatedAt.isAfter(latest.updatedAt)) {
        if (mounted) {
          _showSnackBar('Canvas changed elsewhere. Draft kept for recovery.');
        }
        return;
      }
      final MindmapNode updated = current.copyWith(
        data: draft.toData(current.data),
        updatedAt: DateTime.now(),
      );
      await ref.read(mindmapMutationControllerProvider).saveNode(updated);
      await draftStore.deleteIfGeneration(action.nodeId, generation);
    }
  }

  Future<void> _handleInlineItineraryAction(
    MindmapNode node,
    Object action,
  ) async {
    if (action is! ConvertItineraryAgendaAction) return;
    await _withLatestNodeAfterFlush(node.id, (MindmapNode latest) async {
      final DateTime now = DateTime.now();
      final MindmapNode created = MindmapNode.create(
        id: const Uuid().v4(),
        type: action.target == ItineraryConversionTarget.task
            ? NodeType.task
            : NodeType.event,
        title: action.item.title,
        day: latest.day,
        body: action.item.location,
        position: CanvasPosition(
          latest.position.dx + 260,
          latest.position.dy + 80,
        ),
        relatedNodeIds: <String>[latest.id],
        data: action.target == ItineraryConversionTarget.event
            ? EventCalendarPayload(
                startDate: dayKey(latest.day),
                endDate: dayKey(latest.day),
                startTime: _agendaClock(action.item.startMinutes),
                endTime: _agendaClock(action.item.startMinutes + 60),
              ).toData(const <String, Object?>{})
            : const <String, Object?>{},
        now: now,
      );
      await ref.read(mindmapRepositoryProvider).saveNode(created);
      invalidateMindmapState(ref, day: latest.day);
    });
  }

  String _agendaClock(int minutes) {
    final int hour = (minutes ~/ 60).clamp(0, 23);
    final int minute = (minutes % 60).clamp(0, 59);
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportSelectedMedia(MindmapNode node) async {
    if (!await _flushInlineWorkspace(node.id)) return;
    final result = await _canvasKey.currentState?.exportMedia(
      node.id,
      fileExporter: widget.mediaFileExporter,
    );
    if (!mounted || result == null) return;
    _showSnackBar(result.message);
  }

  Future<void> _replaceMedia(MindmapNode node) async {
    final nodeId = node.id;
    final source = _mediaSourceSnapshot(node);
    final oldAttachmentId = _mediaAttachmentId(node);
    final Future<Object?> dialog = node.type == NodeType.image
        ? _showImageUrlImportDialog(
            context,
            existing: ImagePayload.fromNode(node),
          )
        : _showVideoUrlImportDialog(
            context,
            existing: VideoPayload.fromNode(node),
          );
    final Object? payload = await dialog;
    final newAttachmentId = switch (payload) {
      final ImagePayload replacement => replacement.attachmentId,
      final VideoPayload replacement => replacement.attachmentId,
      _ => '',
    };
    final ownsNewAttachment =
        newAttachmentId.isNotEmpty && newAttachmentId != oldAttachmentId;
    var committed = false;
    try {
      if (payload == null || !mounted || _selectedNodeId != nodeId) return;
      await _serializeNodeMutation(nodeId, () async {
        await _inlineWorkspaceController.flushThenMutateLatest(nodeId, (
          latest,
        ) async {
          if (_selectedNodeId != nodeId ||
              latest.type != node.type ||
              _mediaSourceSnapshot(latest) != source) {
            return;
          }
          final data = switch (payload) {
            final ImagePayload replacement => _mergeImageReplacement(
              original: ImagePayload.fromNode(node),
              latest: ImagePayload.fromNode(latest),
              replacement: replacement,
            ).toData(latest.data),
            final VideoPayload replacement => _mergeVideoReplacement(
              original: VideoPayload.fromNode(node),
              latest: VideoPayload.fromNode(latest),
              replacement: replacement,
            ).toData(latest.data),
            _ => latest.data,
          };
          await ref
              .read(mindmapMutationControllerProvider)
              .saveNode(latest.copyWith(data: data, updatedAt: DateTime.now()));
          committed = true;
        });
      });
    } finally {
      if (ownsNewAttachment && !committed) {
        await _deleteAttachmentBestEffort(newAttachmentId);
      }
    }
    // ponytail: old attachment cleanup needs retention-backed repository
    // snapshots; add GC in integration flow instead of deleting from UI.
  }

  String _mediaAttachmentId(MindmapNode node) => switch (node.type) {
    NodeType.image => ImagePayload.fromNode(node).attachmentId,
    NodeType.video => VideoPayload.fromNode(node).attachmentId,
    _ => '',
  };

  ImagePayload _mergeImageReplacement({
    required ImagePayload original,
    required ImagePayload latest,
    required ImagePayload replacement,
  }) {
    return ImagePayload(
      attachmentId: replacement.attachmentId,
      url: replacement.url,
      mimeType: replacement.mimeType,
      fileName: replacement.fileName,
      caption: replacement.caption == original.caption
          ? latest.caption
          : replacement.caption,
      altText: replacement.altText == original.altText
          ? latest.altText
          : replacement.altText,
      fitMode: latest.fitMode,
      width: latest.width,
      height: latest.height,
      thumbnailWidth: latest.thumbnailWidth,
      thumbnailHeight: latest.thumbnailHeight,
      byteLength: replacement.attachmentId.isEmpty
          ? null
          : replacement.byteLength,
      originalAttachmentId: latest.originalAttachmentId,
      sourceUrl: latest.sourceUrl,
      tags: latest.tags,
      rotationQuarterTurns: latest.rotationQuarterTurns,
      flipHorizontal: latest.flipHorizontal,
      flipVertical: latest.flipVertical,
      brightness: latest.brightness,
      contrast: latest.contrast,
      saturation: latest.saturation,
      filter: latest.filter,
      annotations: latest.annotations,
    );
  }

  VideoPayload _mergeVideoReplacement({
    required VideoPayload original,
    required VideoPayload latest,
    required VideoPayload replacement,
  }) {
    return VideoPayload(
      attachmentId: replacement.attachmentId,
      url: replacement.url,
      mimeType: replacement.mimeType,
      fileName: replacement.fileName,
      durationSeconds: latest.durationSeconds,
      thumbnailAttachmentId: latest.thumbnailAttachmentId,
      thumbnailUrl: latest.thumbnailUrl,
      playbackPositionSeconds: latest.playbackPositionSeconds,
      muted: latest.muted,
      caption: replacement.caption == original.caption
          ? latest.caption
          : replacement.caption,
      altText: replacement.altText == original.altText
          ? latest.altText
          : replacement.altText,
      fitMode: latest.fitMode,
    );
  }

  Future<void> _deleteAttachmentBestEffort(String attachmentId) async {
    try {
      final repository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      await repository.delete(attachmentId);
    } on Object {
      // Best effort: attachment cleanup must not undo a committed node save.
    }
  }

  String _mediaSourceSnapshot(MindmapNode node) => switch (node.type) {
    NodeType.image =>
      '${ImagePayload.fromNode(node).attachmentId}|${ImagePayload.fromNode(node).url}',
    NodeType.video =>
      '${VideoPayload.fromNode(node).attachmentId}|${VideoPayload.fromNode(node).url}',
    _ => '',
  };

  bool _hasSafeMediaUrl(MindmapNode node) {
    final source = switch (node.type) {
      NodeType.image => ImagePayload.fromNode(node).url,
      NodeType.video => VideoPayload.fromNode(node).url,
      _ => '',
    };
    final uri = Uri.tryParse(source);
    return uri != null &&
        const {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
  }

  Future<void> _openMediaSource(MindmapNode node) async {
    final source = switch (node.type) {
      NodeType.image => ImagePayload.fromNode(node).url,
      NodeType.video => VideoPayload.fromNode(node).url,
      _ => '',
    };
    final uri = Uri.tryParse(source);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      _showSnackBar('No safe external URL available');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        _showSnackBar('Unable to open media source');
      }
    } on Object catch (error) {
      if (mounted) _showSnackBar('Unable to open media source: $error');
    }
  }

  Future<void> _setViewMode(_DayViewMode value) async {
    setState(() => _viewMode = value);
    await _preferences.setString(_viewModePreferenceKey, value.name);
  }

  Future<void> _setContextFilter(_DayContextFilter value) async {
    setState(() {
      _contextFilter = value;
      _workspaceContextKey = null;
    });
    await _preferences.setString(_contextFilterPreferenceKey, value.name);
    await _preferences.remove(_workspaceContextPreferenceKey);
  }

  Future<void> _setWorkspaceContextFilter(WorkspaceContext context) async {
    final key = _workspaceContextFilterKey(context);
    setState(() {
      _contextFilter = _DayContextFilter.all;
      _workspaceContextKey = key;
    });
    await _preferences.setString(
      _contextFilterPreferenceKey,
      _contextFilter.name,
    );
    await _preferences.setString(_workspaceContextPreferenceKey, key);
  }

  bool _matchesActiveContext(MindmapNode node) {
    final workspaceKey = _workspaceContextKey;
    if (workspaceKey == null) return _contextFilter.matches(node);
    final projectKey = _workspaceContextFilterKeyFor(
      WorkspaceContextType.project,
      node.project,
    );
    final areaKey = _workspaceContextFilterKeyFor(
      WorkspaceContextType.area,
      node.area,
    );
    return workspaceKey == projectKey || workspaceKey == areaKey;
  }

  Future<void> _setTableQuickView(_TableQuickView value) async {
    setState(() => _tableQuickView = value);
    await _preferences.setString(_tableQuickViewPreferenceKey, value.name);
  }

  Future<void> _setTableSortMode(_TableSortMode value) async {
    setState(() => _tableSortMode = value);
    await _preferences.setString(_tableSortModePreferenceKey, value.name);
  }

  List<_DailyPlanningSuggestion> _dailyPlanningSuggestions({
    required DateTime day,
    required List<MindmapNode> nodes,
    required List<MindmapNode> dayNodes,
    required int readyRoutineCount,
  }) {
    final models = buildDailyPlanningSuggestions(
      DailyPlanningContext(
        day: day,
        allNodes: nodes,
        dayNodes: dayNodes,
        readyRoutineCount: readyRoutineCount,
      ),
    );
    return [
      for (final model in models)
        _mapDailyPlanningSuggestion(model, day, nodes, dayNodes),
    ];
  }

  _DailyPlanningSuggestion _mapDailyPlanningSuggestion(
    DailyPlanningSuggestionModel model,
    DateTime day,
    List<MindmapNode> nodes,
    List<MindmapNode> dayNodes,
  ) {
    return switch (model.type) {
      DailyPlanningActionType.applyRoutines => _DailyPlanningSuggestion(
        icon: Icons.auto_awesome_motion_outlined,
        label: model.label,
        onPressed: () => unawaited(_applyReadyRoutines(day)),
      ),
      DailyPlanningActionType.carryOver => _DailyPlanningSuggestion(
        icon: Icons.event_repeat,
        label: model.label,
        onPressed: () => unawaited(
          _showCarryOverSheet(
            day,
            buildCarryOverCandidates(nodes: nodes, selectedDay: day),
          ),
        ),
      ),
      DailyPlanningActionType.reviewOverdue => _DailyPlanningSuggestion(
        icon: Icons.warning_amber_rounded,
        label: model.label,
        onPressed: () => unawaited(
          _carryOverOverdueTasks(day, _nodesByIds(nodes, model.payload)),
        ),
      ),
      DailyPlanningActionType.rescheduleLowPriority => _DailyPlanningSuggestion(
        icon: Icons.low_priority_rounded,
        label: model.label,
        onPressed: () => unawaited(
          _showCarryOverSheet(
            day,
            buildCarryOverCandidates(nodes: nodes, selectedDay: day)
                .where((candidate) => model.payload.contains(candidate.node.id))
                .toList(),
            title: model.label,
          ),
        ),
      ),
      DailyPlanningActionType.createGoalNextAction => _DailyPlanningSuggestion(
        icon: Icons.add_task_outlined,
        label: model.label,
        onPressed: () {
          final node = _nodeById(nodes, model.nodeId);
          if (node != null) unawaited(_createGoalNextAction(day, node));
        },
      ),
      DailyPlanningActionType.applyTemplate => _DailyPlanningSuggestion(
        icon: Icons.dashboard_customize_outlined,
        label: model.label,
        onPressed: () => unawaited(_showDayTemplateSheet(day, dayNodes)),
      ),
      DailyPlanningActionType.startDailyReview => _DailyPlanningSuggestion(
        icon: Icons.rate_review_outlined,
        label: model.label,
        onPressed: () => unawaited(_openOrCreateDailyReview(day, dayNodes)),
      ),
      DailyPlanningActionType.createTomorrowTopTasks =>
        _DailyPlanningSuggestion(
          icon: Icons.playlist_add_check_rounded,
          label: model.label,
          onPressed: () {
            final review = _nodeById(dayNodes, model.nodeId);
            if (review != null) {
              unawaited(_createTomorrowTopTasks(day, review, model.payload));
            }
          },
        ),
    };
  }

  MindmapNode? _nodeById(List<MindmapNode> nodes, String? id) {
    if (id == null) return null;
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<MindmapNode> _nodesByIds(List<MindmapNode> nodes, List<String> ids) {
    final idSet = ids.toSet();
    return nodes.where((node) => idSet.contains(node.id)).toList();
  }

  Future<void> _applyReadyRoutines(DateTime day) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final plan = await previewRecurringRoutines(
      repository: repository,
      day: day,
      now: now,
    );
    if (plan.readyCount == 0) {
      if (mounted) _showSnackBar('No routines ready');
      return;
    }

    final created = await applyRecurringRoutines(
      repository: repository,
      day: day,
      now: now,
    );
    invalidateMindmapState(ref, day: day);
    if (mounted) {
      final count = created.length;
      _showSnackBar(
        count == 1 ? '1 routine applied' : '$count routines applied',
      );
    }
  }

  Future<void> _carryOverOverdueTasks(
    DateTime day,
    List<MindmapNode> tasks,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    for (final task in tasks) {
      final updated = task.copyWith(dueDate: day, updatedAt: DateTime.now());
      await repository.saveNode(updated);
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.save,
          nodeId: task.id,
          before: task,
          after: updated,
        ),
      );
    }
    invalidateMindmapState(ref, day: day);
    if (mounted) _showSnackBar('Overdue tasks carried over');
  }

  Future<void> _showCarryOverSheet(
    DateTime day,
    List<CarryOverCandidate> candidates, {
    String title = 'Carry-over assistant',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_repeat),
                    title: Text(title),
                    subtitle: Text('${candidates.length} unfinished items'),
                  );
                }
                final candidate = candidates[index - 1];
                final node = candidate.node;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    NodeVisuals.icon(node.type),
                    color: NodeVisuals.color(context, node.type),
                  ),
                  title: Text(
                    node.title.isEmpty ? node.type.label : node.title,
                  ),
                  subtitle: Text(
                    '${candidate.reason.label} ·${dayKey(node.day)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Move to day',
                        icon: const Icon(Icons.drive_file_move_outline),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _applyCarryOverAction(
                            day,
                            node,
                            CarryOverAction.moveToDay,
                          );
                        },
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Duplicate to day',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _applyCarryOverAction(
                            day,
                            node,
                            CarryOverAction.duplicateToDay,
                          );
                        },
                      ),
                      PopupMenuButton<CarryOverAction>(
                        tooltip: 'More actions',
                        onSelected: (action) async {
                          Navigator.of(context).pop();
                          await _applyCarryOverAction(day, node, action);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: CarryOverAction.reschedule,
                            child: Text('Reschedule'),
                          ),
                          const PopupMenuItem(
                            value: CarryOverAction.markDone,
                            child: Text('Mark done'),
                          ),
                          const PopupMenuItem(
                            value: CarryOverAction.archive,
                            child: Text('Archive'),
                          ),
                          if (node.checklist.isNotEmpty)
                            const PopupMenuItem(
                              value: CarryOverAction.splitChecklist,
                              child: Text('Split checklist'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemCount: candidates.length + 1,
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyCarryOverAction(
    DateTime day,
    MindmapNode node,
    CarryOverAction action,
  ) async {
    await _withLatestNodeAfterFlush(node.id, (latest) async {
      if (!mounted) return;
      final repository = ref.read(mindmapRepositoryProvider);
      final now = DateTime.now();
      switch (action) {
        case CarryOverAction.moveToDay:
          final updated = latest.copyWith(
            day: day,
            dueDate: day,
            updatedAt: now,
          );
          await repository.saveNode(updated);
          _pushUndo(
            _UndoEntry(
              kind: _UndoKind.save,
              nodeId: latest.id,
              before: latest,
              after: updated,
            ),
          );
          invalidateMindmapState(ref, day: day, extraDay: latest.day);
          if (mounted) _showSnackBar('Moved to ${dayKey(day)}');
        case CarryOverAction.reschedule:
          final pickedDay = await showDatePicker(
            context: context,
            initialDate: day,
            firstDate: DateTime(day.year - 1),
            lastDate: DateTime(day.year + 3),
          );
          if (pickedDay == null) return;
          final updated = latest.copyWith(
            day: pickedDay,
            dueDate: pickedDay,
            updatedAt: now,
          );
          await repository.saveNode(updated);
          _pushUndo(
            _UndoEntry(
              kind: _UndoKind.save,
              nodeId: latest.id,
              before: latest,
              after: updated,
            ),
          );
          invalidateMindmapState(ref, day: day, extraDay: latest.day);
          invalidateMindmapState(ref, day: pickedDay);
          if (mounted) _showSnackBar('Rescheduled to ${dayKey(pickedDay)}');
        case CarryOverAction.duplicateToDay:
          final duplicate = latest.copyWith(
            id: const Uuid().v4(),
            day: day,
            dueDate: day,
            createdAt: now,
            updatedAt: now,
          );
          await repository.saveNode(duplicate);
          _pushUndo(
            _UndoEntry(
              kind: _UndoKind.create,
              nodeId: duplicate.id,
              after: duplicate,
            ),
          );
          invalidateMindmapState(ref, day: day);
          if (mounted) _showSnackBar('Duplicated to ${dayKey(day)}');
        case CarryOverAction.markDone:
          final updated = latest.copyWith(
            isDone: true,
            status: NodeStatus.done,
            progress: 1,
            updatedAt: now,
          );
          await repository.saveNode(updated);
          _pushUndo(
            _UndoEntry(
              kind: _UndoKind.save,
              nodeId: latest.id,
              before: latest,
              after: updated,
            ),
          );
          invalidateMindmapState(ref, day: day, extraDay: latest.day);
          if (mounted) _showSnackBar('Marked done');
        case CarryOverAction.archive:
          final updated = latest.copyWith(isArchived: true, updatedAt: now);
          await repository.saveNode(updated);
          _pushUndo(
            _UndoEntry(
              kind: _UndoKind.save,
              nodeId: latest.id,
              before: latest,
              after: updated,
            ),
          );
          invalidateMindmapState(ref, day: day, extraDay: latest.day);
          if (mounted) _showSnackBar('Archived');
        case CarryOverAction.splitChecklist:
          final openItems = latest.checklist
              .where((item) => !item.isDone)
              .toList();
          if (openItems.isEmpty) {
            if (mounted) _showSnackBar('No open checklist items');
            return;
          }
          final createdNodes = <MindmapNode>[];
          for (var i = 0; i < openItems.length; i += 1) {
            final item = openItems[i];
            final child = MindmapNode.create(
              id: const Uuid().v4(),
              type: NodeType.task,
              title: item.title,
              day: day,
              position: CanvasPosition(
                latest.position.dx + 260,
                latest.position.dy + (i * 90),
              ),
              priority: latest.priority,
              project: latest.project,
              area: latest.area,
              tags: latest.tags,
              dueDate: day,
              relatedNodeIds: [latest.id],
              data: {
                'relations': [
                  {'targetId': latest.id, 'label': 'split from'},
                ],
              },
              now: now,
            );
            await repository.saveNode(child);
            createdNodes.add(child);
            _pushUndo(
              _UndoEntry(
                kind: _UndoKind.create,
                nodeId: child.id,
                after: child,
              ),
            );
          }
          final updated = latest.copyWith(
            day: day,
            dueDate: day,
            relatedNodeIds: {
              ...latest.relatedNodeIds,
              for (final child in createdNodes) child.id,
            }.toList(),
            updatedAt: now,
          );
          await repository.saveNode(updated);
          _pushUndo(
            _UndoEntry(
              kind: _UndoKind.save,
              nodeId: latest.id,
              before: latest,
              after: updated,
            ),
          );
          invalidateMindmapState(ref, day: day, extraDay: latest.day);
          if (mounted) _showSnackBar('Checklist split into tasks');
      }
    });
  }

  Future<void> _createGoalNextAction(DateTime day, MindmapNode goal) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final node = MindmapNode(
      id: 'daily-goal-action-${now.microsecondsSinceEpoch}',
      type: NodeType.task,
      title: 'Next action: ${goal.title}',
      day: day,
      createdAt: now,
      updatedAt: now,
      body: 'Move goal forward: [[${goal.title}]]',
      position: CanvasPosition(goal.position.dx + 260, goal.position.dy + 80),
      priority: NodePriority.high,
      project: goal.project,
      area: goal.area,
      tags: const ['next-action'],
      relatedNodeIds: [goal.id],
      dueDate: day,
      data: {
        'relations': [
          {'targetId': goal.id, 'label': 'moves goal'},
        ],
      },
    );
    await repository.saveNode(node);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    invalidateMindmapState(ref, day: day, extraDay: goal.day);
    if (mounted) _showSnackBar('Next action created');
  }

  Future<void> _showDayTemplateSheet(
    DateTime day,
    List<MindmapNode> dayNodes,
  ) async {
    final rawTemplates = await SharedPreferencesAsync().getString(
      customNodeTemplatesPreferenceKey,
    );
    Object? decodedTemplates;
    try {
      decodedTemplates = rawTemplates == null ? null : jsonDecode(rawTemplates);
    } on FormatException {
      decodedTemplates = null;
    }
    final customTemplates = nodeTemplatesFromJsonList(decodedTemplates);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: dayTemplates.length + customTemplates.length + 1,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: const Text('Apply day template'),
                  subtitle: Text('One-click setup for ${dayKey(day)}'),
                );
              }
              final sortedTemplates = [
                ...dayTemplates.where(
                  (template) => template.id == 'personal-reset',
                ),
                ...dayTemplates.where(
                  (template) => template.id != 'personal-reset',
                ),
              ];
              if (index > sortedTemplates.length) {
                final template =
                    customTemplates[index - sortedTemplates.length - 1];
                return ListTile(
                  key: ValueKey('day-custom-template-${template.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(template.label),
                  subtitle: const Text('Custom template · 1 node'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _applyCustomNodeTemplate(day, template);
                  },
                );
              }
              final template = sortedTemplates[index - 1];
              final applied = hasAppliedDayTemplate(dayNodes, template.id);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !applied,
                leading: Icon(
                  applied ? Icons.check_circle_outline : Icons.auto_awesome,
                  color: applied
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
                ),
                title: Text(template.label),
                subtitle: Text(
                  applied
                      ? 'Already applied'
                      : '${template.description} ·${template.drafts.length} nodes',
                ),
                onTap: applied
                    ? null
                    : () async {
                        Navigator.of(context).pop();
                        await _applyDayTemplate(day, template);
                      },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _applyCustomNodeTemplate(
    DateTime day,
    NodeTemplate template,
  ) async {
    final now = DateTime.now();
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: template.type,
      title: template.title,
      day: day,
      body: template.body,
      status: template.status,
      priority: template.priority,
      project: template.project,
      area: template.area,
      tags: template.tags,
      progress: template.progress,
      checklist: [
        for (final (index, title) in template.checklist.indexed)
          TaskChecklistItem(
            id: '${now.microsecondsSinceEpoch}-$index',
            title: title,
          ),
      ],
      data: template.data,
      now: now,
    );
    await ref.read(mindmapRepositoryProvider).saveNode(node);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    invalidateMindmapState(ref, day: day);
  }

  Future<void> _applyDayTemplate(DateTime day, DayTemplate template) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final existingNodes =
        ref.read(nodesForDayProvider(day)).valueOrNull ?? const <MindmapNode>[];
    final nodes = buildDayTemplateNodes(
      template: template,
      day: day,
      now: DateTime.now(),
      idFactory: () => const Uuid().v4(),
      existingNodes: existingNodes,
    );
    if (nodes.isEmpty) {
      if (mounted) _showSnackBar('${template.label} already applied');
      return;
    }

    for (final node in nodes) {
      await repository.saveNode(node);
      _pushUndo(
        _UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node),
      );
    }
    invalidateMindmapState(ref, day: day);
    if (mounted) _showSnackBar('${template.label} applied');
  }

  Future<void> _createTomorrowTopTasks(
    DateTime day,
    MindmapNode review,
    List<String> titles,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final tomorrow = day.add(const Duration(days: 1)).dateOnly;
    final now = DateTime.now();
    final existingTomorrowNodes = await repository.listNodes(day: tomorrow);
    final existingTitles = existingTomorrowNodes
        .where((node) => node.tags.contains('tomorrow-top-3'))
        .map((node) => node.title.trim().toLowerCase())
        .toSet();
    var createdCount = 0;

    for (var i = 0; i < titles.length; i += 1) {
      final title = titles[i].trim();
      if (title.isEmpty || existingTitles.contains(title.toLowerCase())) {
        continue;
      }
      final node = MindmapNode.create(
        id: const Uuid().v4(),
        type: NodeType.task,
        title: title,
        day: tomorrow,
        position: CanvasPosition(120 + (i * 220), -120),
        priority: i == 0 ? NodePriority.high : NodePriority.medium,
        dueDate: tomorrow,
        tags: const ['daily-review', 'tomorrow-top-3'],
        relatedNodeIds: [review.id],
        data: {
          'relations': [
            {'targetId': review.id, 'label': 'from review'},
          ],
        },
        now: now.add(Duration(seconds: i)),
      );
      await repository.saveNode(node);
      existingTitles.add(title.toLowerCase());
      _pushUndo(
        _UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node),
      );
      createdCount += 1;
    }

    invalidateMindmapState(ref, day: day, extraDay: tomorrow);
    if (mounted) {
      if (createdCount == 0) {
        _showSnackBar('Tomorrow top 3 already created');
      } else {
        _showSnackBar(
          createdCount == 1
              ? 'Tomorrow task created'
              : '$createdCount tomorrow tasks created',
        );
      }
    }
  }

  Future<void> _openOrCreateDailyReview(
    DateTime day,
    List<MindmapNode> dayNodes,
  ) async {
    final existingReview = dayNodes.cast<MindmapNode?>().firstWhere(
      (node) =>
          node != null &&
          node.type == NodeType.journal &&
          (node.tags.contains('daily-review') ||
              node.title == dailyReviewTitle(day)),
      orElse: () => null,
    );
    if (existingReview != null) {
      if (await _selectNode(existingReview) && mounted) {
        _showSnackBar('Daily review opened');
      }
      return;
    }

    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final journalNodes = dayNodes
        .where((node) => node.type == NodeType.journal && !node.isArchived)
        .length;
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: NodeType.journal,
      title: dailyReviewTitle(day),
      day: day,
      body: buildDailyReviewBody(day, dayNodes),
      position: CanvasPosition(0, -220 - (journalNodes * 120)),
      tags: const ['daily-review'],
      data: const {
        'journal': {'prompt': 'Daily review', 'isDailyReview': true},
      },
      now: now,
    );
    await repository.saveNode(node);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    invalidateMindmapState(ref, day: day);
    if (await _selectNode(node) && mounted) {
      _showSnackBar('Daily review created');
    }
  }

  void _pushUndo(_UndoEntry entry) {
    setState(() {
      _undoStack.add(entry);
      if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
      _redoStack.clear();
    });
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;
    if (!await _flushInlineWorkspace()) return;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    setState(() {});
    try {
      final repository = ref.read(mindmapRepositoryProvider);
      switch (entry.kind) {
        case _UndoKind.save:
          // Revert to the node before the save.
          if (entry.before != null) {
            final restored = entry.before!.copyWith(updatedAt: DateTime.now());
            await repository.saveNode(restored);
            await _persistCanvasNodeGeometry(restored);
            _inlineWorkspaceController.rebaseNode(restored);
          }
        case _UndoKind.delete:
          // Re-create the deleted node.
          if (entry.before != null) {
            await repository.saveNode(entry.before!);
            await _persistCanvasNodeGeometry(entry.before!);
          }
        case _UndoKind.create:
          // Remove the created node.
          await repository.deleteNode(entry.nodeId);
          if (entry.after != null) {
            await _deleteCanvasObjectReference(entry.after!);
          }
        case _UndoKind.canvasUpdate:
        case _UndoKind.canvasDelete:
          if (entry.canvasBefore != null) {
            await ref.read(canvasBoardRepositoryProvider).saveObjects(
              dailyCanvasBoardId(widget.date.dateOnly),
              <CanvasObject>[entry.canvasBefore!],
            );
          }
        case _UndoKind.canvasCreate:
          await ref.read(canvasBoardRepositoryProvider).deleteObjects(
            dailyCanvasBoardId(widget.date.dateOnly),
            <String>[entry.nodeId],
          );
        case _UndoKind.canvasBatch:
          final repository = ref.read(canvasBoardRepositoryProvider);
          await repository.deleteObjects(
            dailyCanvasBoardId(widget.date.dateOnly),
            entry.canvasAfterBatch.map((object) => object.id),
          );
          await repository.saveObjects(
            dailyCanvasBoardId(widget.date.dateOnly),
            entry.canvasBeforeBatch,
          );
        case _UndoKind.canvasBoard:
          if (entry.canvasBoardBefore != null) {
            await ref
                .read(canvasBoardRepositoryProvider)
                .saveBoard(entry.canvasBoardBefore!);
          }
      }
      final day = widget.date.dateOnly;
      invalidateMindmapState(ref, day: day);
      ref.invalidate(dailyCanvasBoardProvider(day));
      if (context.mounted) _showUndoRedoSnackBar('Undo');
    } catch (e) {
      if (context.mounted) _showSnackBar('Undo failed: $e');
    }
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    if (!await _flushInlineWorkspace()) return;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    setState(() {});
    try {
      final repository = ref.read(mindmapRepositoryProvider);
      switch (entry.kind) {
        case _UndoKind.save:
          if (entry.after != null) {
            final restored = entry.after!.copyWith(updatedAt: DateTime.now());
            await repository.saveNode(restored);
            await _persistCanvasNodeGeometry(restored);
            _inlineWorkspaceController.rebaseNode(restored);
          }
        case _UndoKind.delete:
          await repository.deleteNode(entry.nodeId);
          if (entry.before != null) {
            await _deleteCanvasObjectReference(entry.before!);
          }
        case _UndoKind.create:
          if (entry.after != null) {
            await repository.saveNode(entry.after!);
            await _persistCanvasNodeGeometry(entry.after!);
          }
        case _UndoKind.canvasUpdate:
        case _UndoKind.canvasCreate:
          if (entry.canvasAfter != null) {
            await ref.read(canvasBoardRepositoryProvider).saveObjects(
              dailyCanvasBoardId(widget.date.dateOnly),
              <CanvasObject>[entry.canvasAfter!],
            );
          }
        case _UndoKind.canvasDelete:
          await ref.read(canvasBoardRepositoryProvider).deleteObjects(
            dailyCanvasBoardId(widget.date.dateOnly),
            <String>[entry.nodeId],
          );
        case _UndoKind.canvasBatch:
          final repository = ref.read(canvasBoardRepositoryProvider);
          await repository.deleteObjects(
            dailyCanvasBoardId(widget.date.dateOnly),
            entry.canvasBeforeBatch.map((object) => object.id),
          );
          await repository.saveObjects(
            dailyCanvasBoardId(widget.date.dateOnly),
            entry.canvasAfterBatch,
          );
        case _UndoKind.canvasBoard:
          if (entry.canvasBoardAfter != null) {
            await ref
                .read(canvasBoardRepositoryProvider)
                .saveBoard(entry.canvasBoardAfter!);
          }
      }
      final day = widget.date.dateOnly;
      invalidateMindmapState(ref, day: day);
      ref.invalidate(dailyCanvasBoardProvider(day));
      if (context.mounted) _showUndoRedoSnackBar('Redo');
    } catch (e) {
      if (context.mounted) _showSnackBar('Redo failed: $e');
    }
  }

  void _showSnackBar(String message) {
    _showCompactSnackBar(
      icon: Icons.check_circle_outline_rounded,
      message: message,
      duration: const Duration(milliseconds: 1600),
    );
  }

  Future<void> _copyDayMarkdown(DateTime day, List<MindmapNode> nodes) async {
    if (!await _flushInlineWorkspace()) return;
    final latestNodes = await ref
        .read(mindmapRepositoryProvider)
        .listNodes(day: day);
    final markdown = buildDayMarkdownExport(day: day, nodes: latestNodes);
    await Clipboard.setData(ClipboardData(text: markdown));
    if (mounted) _showSnackBar('Day markdown copied');
  }

  Future<void> _showActivityLog() async {
    if (!await _clearSelection() || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ActivityLogSheet(
        undoEntries: _undoStack.reversed.toList(),
        redoEntries: _redoStack.reversed.toList(),
        onUndo: _undoStack.isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_undo());
              },
        onRedo: _redoStack.isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_redo());
              },
      ),
    );
  }

  void _showUndoRedoSnackBar(String action) {
    final undoCount = _undoStack.length;
    final redoCount = _redoStack.length;
    final canUndo = undoCount > 0;
    final canRedo = redoCount > 0;
    final showRedo = action == 'Undo' && canRedo;
    final showUndo = action == 'Redo' && canUndo;

    _showCompactSnackBar(
      icon: Icons.history_rounded,
      message: '$action •$undoCount undo / $redoCount redo',
      duration: const Duration(milliseconds: 2200),
      actionLabel: showRedo
          ? 'Redo'
          : showUndo
          ? 'Undo'
          : null,
      onActionPressed: showRedo
          ? _redo
          : showUndo
          ? _undo
          : null,
    );
  }

  void _showCompactSnackBar({
    required IconData icon,
    required String message,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final snackWidth = screenWidth < 420 ? screenWidth - 32 : 388.0;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: snackWidth,
        duration: duration,
        dismissDirection: DismissDirection.horizontal,
        elevation: 14,
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusContainer,
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  onActionPressed();
                },
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size(
                    0,
                    AppDesignTokens.of(context).minimumTarget,
                  ),
                ),
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runCanvasAction(CanvasContextAction action) async {
    if ((action == CanvasContextAction.exportJson ||
            action == CanvasContextAction.exportPng) &&
        !await _flushInlineWorkspace()) {
      return;
    }
    if (action == CanvasContextAction.exportJson ||
        action == CanvasContextAction.exportPng) {
      await ref.read(nodesForDayProvider(widget.date.dateOnly).future);
      if (!mounted) return;
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    await _canvasKey.currentState?.runContextAction(action);
    if (mounted) setState(() {});
  }

  Future<void> _showMobileToolsSheet(
    MindmapNode? node,
    DateTime normalizedDate,
    WidgetRef ref,
    List<MindmapNode> canvasNodes,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DefaultTabController(
        length: 4,
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            children: [
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(icon: Icon(Icons.dashboard_outlined), text: 'Canvas'),
                  Tab(icon: Icon(Icons.tune), text: 'Node'),
                  Tab(icon: Icon(Icons.format_bold), text: 'Format'),
                  Tab(icon: Icon(Icons.link), text: 'Links'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _MobileToolList(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.add_box_outlined),
                          title: const Text('New node'),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _showCanvasProductivityNodeMenu(
                              ref,
                              normalizedDate,
                              canvasNodes,
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.fit_screen_outlined),
                          title: const Text('Reset canvas view'),
                          onTap: () {
                            _canvasKey.currentState?.focusOnPosition(
                              const CanvasPosition(0, 0),
                            );
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                        SwitchListTile(
                          value: _isLifeExplorerExpanded,
                          title: const Text('Life Explorer'),
                          secondary: const Icon(Icons.view_sidebar_outlined),
                          onChanged: (value) {
                            setState(() => _isLifeExplorerExpanded = value);
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                      ],
                    ),
                    _MobileEditorLauncher(
                      icon: Icons.tune,
                      title: 'Node properties',
                      description: 'Type, status, priority, date, and fields.',
                      enabled: node != null,
                      onOpen: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_selectAndFocusNode(node!));
                      },
                    ),
                    _MobileEditorLauncher(
                      icon: Icons.format_bold,
                      title: 'Fullscreen content editor',
                      description: 'Body, Markdown, checklist, and formatting.',
                      enabled: node != null,
                      onOpen: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_selectAndFocusNode(node!));
                      },
                    ),
                    _MobileEditorLauncher(
                      icon: Icons.link,
                      title: 'Node links',
                      description: 'Relationships, backlinks, and node links.',
                      enabled: node != null,
                      onOpen: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_selectAndFocusNode(node!));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSelectedNodeTools(MindmapNode node) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _SelectedNodeMissionActions(
          node: node,
          actions: _selectedNodeActions(node),
          isMission: isTodayMission(node),
          isFocusRunning: _focusNodeId == node.id && _focusStartedAt != null,
          isCollapsed: false,
          focusElapsed: _focusElapsed,
          focusRemaining: _focusRemaining,
          onToggleCollapsed: () => Navigator.of(sheetContext).pop(),
          onToggleMission: () => _toggleTodayMission(node),
          onStartFocus: () => _startFocusSession(node),
          onStartPomodoro: (minutes) =>
              _startFocusSession(node, targetMinutes: minutes),
          onStartCustomFocus: () => _showCustomFocusDialog(node),
          onStopFocus: () => _stopFocusSession(node),
        ),
      ),
    );
  }

  void _focusOrCreateNode(NodeType type) {
    final currentNodes =
        ref.read(nodesForDayProvider(widget.date.dateOnly)).valueOrNull ??
        const <MindmapNode>[];
    _createNodeOfType(
      context,
      ref,
      widget.date.dateOnly,
      currentNodes,
      type,
      null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedDate = widget.date.dateOnly;
    final collabState = ref.watch(collaborationProvider);
    final variant = ref.watch(themeVariantProvider);
    final nodes = ref.watch(nodesForDayProvider(normalizedDate));
    final dailyCanvasBoard = ref.watch(
      dailyCanvasBoardProvider(normalizedDate),
    );
    final dailyCanvasBoards = ref.watch(
      dailyCanvasBoardsProvider(normalizedDate),
    );
    final linkedBoard = widget.initialBoardId == null
        ? null
        : ref
              .watch(canvasBoardByIdProvider(widget.initialBoardId!))
              .valueOrNull;
    final allDayBoards = <CanvasBoard>[
      ...dailyCanvasBoards.valueOrNull ??
          (dailyCanvasBoard.valueOrNull == null
              ? const <CanvasBoard>[]
              : <CanvasBoard>[dailyCanvasBoard.valueOrNull!]),
      if (linkedBoard != null &&
          !(dailyCanvasBoards.valueOrNull ?? const <CanvasBoard>[]).any(
            (board) => board.id == linkedBoard.id,
          ))
        linkedBoard,
    ];
    final activeCanvasBoard =
        allDayBoards.where((board) => board.id == _activeBoardId).firstOrNull ??
        dailyCanvasBoard.valueOrNull;
    final allNodes = ref.watch(allMindmapNodesProvider);
    final workspaceContexts = ref.watch(workspaceContextsProvider);
    final activeWorkspaceContext = _workspaceContextForKey(
      workspaceContexts.valueOrNull,
      _workspaceContextKey,
    );
    final automationSuggestions = ref.watch(automationSuggestionsProvider);
    final workshopBoard = dailyCanvasBoard.valueOrNull;
    if (workshopBoard?.workshopSession.isActive ?? false) {
      final maintained = _workshop.maintain(workshopBoard!, DateTime.now());
      final signature =
          '${maintained.workshopSession.sessionId}:${maintained.workshopSession.status.name}:${maintained.workshopSession.activeStageIndex}:${maintained.workshopSession.awaitingAdvance}';
      if (maintained != workshopBoard &&
          _workshopMaintenanceSignature != signature) {
        _workshopMaintenanceSignature = signature;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await ref.read(canvasBoardRepositoryProvider).saveBoard(maintained);
          ref.invalidate(dailyCanvasBoardProvider(normalizedDate));
        });
      }
    }

    MindmapNode? selectedNode;
    if (_selectedNodeId != null) {
      final all = allNodes.valueOrNull ?? const <MindmapNode>[];
      selectedNode = all.where((n) => n.id == _selectedNodeId).firstOrNull;
    }

    return PopScope<Object?>(
      canPop: _allowBackPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleBackPop(result));
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
            _focusOrCreateNode(NodeType.task);
          },
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (selectedNode != null) {
              unawaited(_clearSelectedNode(selectedNode));
            }
          },
          const _NonTextEditingActivator(
            SingleActivator(LogicalKeyboardKey.keyF),
          ): () {
            _canvasKey.currentState?.focusOnPosition(
              const CanvasPosition(0, 0),
            );
          },
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
            if (selectedNode != null) {
              unawaited(_selectAndFocusNode(selectedNode));
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (selectedNode != null) {
              unawaited(_selectAndFocusNode(selectedNode));
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
            setState(() => _isLifeExplorerExpanded = !_isLifeExplorerExpanded);
          },
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
            _undo();
          },
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): () {
            _redo();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            floatingActionButton: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 840) {
                  return const SizedBox.shrink();
                }
                return _DayQuickCreateFab(
                  onMore: () => _showQuickCreateSheet(context),
                  onSelectType: (type) {
                    final currentNodes =
                        ref
                            .read(nodesForDayProvider(widget.date.dateOnly))
                            .valueOrNull ??
                        const <MindmapNode>[];
                    unawaited(
                      _createNodeOfType(
                        context,
                        ref,
                        widget.date.dateOnly,
                        currentNodes,
                        type,
                        null,
                      ),
                    );
                  },
                );
              },
            ),
            appBar: _viewMode != _DayViewMode.canvas && _isFloatingTopBarVisible
                ? AppBar(
                    automaticallyImplyLeading: false,
                    titleSpacing: 16,
                    title: Consumer(
                      builder: (context, ref, child) {
                        final titleMap = ref.watch(workspaceTitleProvider);
                        final titleKey =
                            '${WorkspaceContextType.daily.name}_${dayKey(normalizedDate)}';
                        final customTitle = titleMap[titleKey];
                        final displayTitle =
                            (customTitle != null && customTitle.isNotEmpty)
                            ? customTitle
                            : dayKey(normalizedDate);

                        return Row(
                          children: [
                            Flexible(
                              child: _InlineWorkspaceTitle(
                                customTitle: customTitle,
                                displayTitle: displayTitle,
                                onTitleChanged: (String title) => ref
                                    .read(workspaceTitleProvider.notifier)
                                    .setTitle(
                                      WorkspaceContextType.daily,
                                      dayKey(normalizedDate),
                                      title,
                                    ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    bottom: _isDayTabsHidden
                        ? null
                        : PreferredSize(
                            preferredSize: const Size.fromHeight(56),
                            child: _DayTopTabStrip(
                              selectedDay: normalizedDate,
                              isCollapsed: _isDayTabsCollapsed,
                              onDaySelected: (day) => unawaited(() async {
                                if (await _flushInlineWorkspace() &&
                                    context.mounted) {
                                  goToDay(context, day);
                                }
                              }()),
                              onCollapsedChanged: (value) {
                                setState(() => _isDayTabsCollapsed = value);
                              },
                            ),
                          ),
                    actions: [
                      Builder(
                        builder: (context) {
                          final tokens = AppDesignTokens.of(context);
                          final actionWidth =
                              MediaQuery.sizeOf(context).width * 0.62;
                          final showViewToggle =
                              MediaQuery.sizeOf(context).width >= 900;
                          return SizedBox(
                            width: actionWidth,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (MediaQuery.sizeOf(context).width >=
                                      1100) ...[
                                    CollaborationRoomBar(
                                      nodes:
                                          nodes.valueOrNull ??
                                          const <MindmapNode>[],
                                      followingId: _followingCollaboratorId,
                                      onFollowChanged: (id) {
                                        setState(
                                          () => _followingCollaboratorId = id,
                                        );
                                        _canvasKey.currentState
                                            ?.followCollaborator(id);
                                      },
                                    ),
                                    SizedBox(width: tokens.spacing[4]),
                                  ],
                                  if (showViewToggle) ...[
                                    _DayViewModeToggle(
                                      mode: _viewMode,
                                      onChanged: (value) {
                                        _setViewMode(value);
                                      },
                                    ),
                                    SizedBox(width: tokens.spacing[4]),
                                  ],
                                  _DayContextSwitcher(
                                    filter: _contextFilter,
                                    workspaceContext: activeWorkspaceContext,
                                    workspaceContexts:
                                        workspaceContexts.valueOrNull,
                                    onChanged: _setContextFilter,
                                    onWorkspaceChanged:
                                        _setWorkspaceContextFilter,
                                  ),
                                  SizedBox(width: tokens.spacing[4]),
                                  _DayToolbarGroup(
                                    children: [
                                      IconButton(
                                        tooltip: 'Copy day markdown',
                                        onPressed: () => unawaited(
                                          _copyDayMarkdown(
                                            normalizedDate,
                                            allNodes.valueOrNull ??
                                                const <MindmapNode>[],
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.ios_share_outlined,
                                          size: 18,
                                        ),
                                      ),
                                      _CanvasViewSettingsButton(
                                        isRibbonToolbarCollapsed:
                                            _isRibbonToolbarCollapsed,
                                        isDayTabsHidden: _isDayTabsHidden,
                                        onSelected: (value) {
                                          setState(() {
                                            if (value == 'ribbon') {
                                              _isFloatingRibbonVisible =
                                                  !_isFloatingRibbonVisible;
                                            } else if (value == 'tabs') {
                                              _isFloatingBoardTabsVisible =
                                                  !_isFloatingBoardTabsVisible;
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  SizedBox(width: tokens.spacing[4]),
                                  _UndoRedoIndicator(
                                    undoCount: _undoStack.length,
                                    redoCount: _redoStack.length,
                                    onUndo: _undoStack.isEmpty ? null : _undo,
                                    onRedo: _redoStack.isEmpty ? null : _redo,
                                    onHistory: _showActivityLog,
                                  ),
                                  SizedBox(width: tokens.spacing[4]),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  )
                : null,
            body: nodes.when(
              data: (value) {
                final canvasNodes = _canvasNodesFor(
                  activeNodes: value,
                  allNodes: allNodes.valueOrNull ?? const <MindmapNode>[],
                  day: normalizedDate,
                  highlightedNodeId: widget.highlightNodeId,
                );

                final allNodeList =
                    allNodes.valueOrNull ?? const <MindmapNode>[];
                final readyRoutineCount =
                    normalizedDate == DateTime.now().dateOnly
                    ? automationSuggestions.valueOrNull?.readyCount ?? 0
                    : 0;
                final planningSuggestions = _dailyPlanningSuggestions(
                  day: normalizedDate,
                  nodes: allNodeList,
                  dayNodes: value,
                  readyRoutineCount: readyRoutineCount,
                );
                final missionStats = _buildDailyMissionStats(
                  value,
                  normalizedDate,
                  readyRoutineCount: readyRoutineCount,
                );

                final miniInsights = buildDayMiniInsights(
                  nodes: allNodeList,
                  selectedDay: normalizedDate,
                );
                final inboxNodes = inboxNodesForDay(
                  allNodeList,
                  normalizedDate,
                );
                final filteredDayNodes = value
                    .where(_matchesActiveContext)
                    .toList();
                final filteredCanvasNodes = canvasNodes
                    .where(
                      (node) =>
                          node.id == widget.highlightNodeId ||
                          _matchesActiveContext(node),
                    )
                    .toList();
                final missionNodes = filteredDayNodes
                    .where(isTodayMission)
                    .toList();
                final visibleCanvasNodes =
                    _isMissionMode && missionNodes.isNotEmpty
                    ? filteredCanvasNodes.where(isTodayMission).toList()
                    : filteredCanvasNodes;
                final selectedNodeId = _selectedNodeId;
                final expandedNodeDraft = selectedNodeId == null
                    ? null
                    : ref.watch(
                        inlineNodeWorkspaceControllerProvider.select(
                          (state) => state.nodes[selectedNodeId]?.draft,
                        ),
                      );

                final isShortScreen = MediaQuery.sizeOf(context).height < 500;
                return Column(
                  children: [
                    if (!isShortScreen &&
                        (_viewMode != _DayViewMode.canvas ||
                            MediaQuery.sizeOf(context).width < 840))
                      _DayToolsBar(
                        stats: missionStats,
                        planningSuggestions: planningSuggestions,
                        miniInsights: miniInsights,
                        selectedDay: normalizedDate,
                        isMissionMode: _isMissionMode,
                        isFocusRunning: _focusStartedAt != null,
                        focusElapsed: _focusElapsed,
                        focusRemaining: _focusRemaining,
                        inboxCount: inboxNodes.length,
                        onShowStatus: () => _showDayStatusSheet(missionStats),
                        onShowPlan: () =>
                            _showDayPlanSheet(planningSuggestions),
                        onShowPulse: () => _showDayPulseSheet(
                          insights: miniInsights,
                          selectedDay: normalizedDate,
                        ),
                        onToggleMissionMode: missionNodes.isEmpty
                            ? null
                            : () => setState(
                                () => _isMissionMode = !_isMissionMode,
                              ),
                        onStopFocus:
                            _focusStartedAt == null || missionNodes.isEmpty
                            ? null
                            : () => _stopFocusSession(
                                missionNodes.firstWhere(
                                  (node) => node.id == _focusNodeId,
                                  orElse: () => missionNodes.first,
                                ),
                              ),
                        onInboxPressed: inboxNodes.isEmpty
                            ? null
                            : () => _showInboxSheet(
                                context,
                                inboxNodes,
                                normalizedDate,
                              ),
                        onQuickCapture: _showQuickCaptureSheet,
                      ),
                    if (!isShortScreen)
                      DailyCockpitPanel(
                        day: normalizedDate,
                        nodes: value,
                        onRescheduleRequested: (overloadedTasks) async {
                          final balancePlan = buildWorkloadBalancePlan(
                            candidateDays: List.generate(
                              7,
                              (i) => DateTime.now().add(Duration(days: i)),
                            ),
                            nodes: value,
                          );
                          final mutation = ref.read(
                            mindmapMutationControllerProvider,
                          );
                          for (final move in balancePlan.moves) {
                            if (move.fromDay.isSameDay(normalizedDate)) {
                              await mutation.rescheduleNode(
                                move.node,
                                day: move.toDay,
                              );
                            }
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Berhasil memindahkan ${balancePlan.moves.length} task!',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    if (_viewMode == _DayViewMode.canvas &&
                        MediaQuery.sizeOf(context).width >= 840 &&
                        !_isRibbonToolbarCollapsed &&
                        _isFloatingRibbonVisible)
                      _MindmapDocumentCanvasToolbar(
                        selectedNode: selectedNode,
                        homeTools: _DayToolsBar(
                          embedded: true,
                          stats: missionStats,
                          planningSuggestions: planningSuggestions,
                          miniInsights: miniInsights,
                          selectedDay: normalizedDate,
                          isMissionMode: _isMissionMode,
                          isFocusRunning: _focusStartedAt != null,
                          focusElapsed: _focusElapsed,
                          focusRemaining: _focusRemaining,
                          inboxCount: inboxNodes.length,
                          onShowStatus: () => _showDayStatusSheet(missionStats),
                          onShowPlan: () =>
                              _showDayPlanSheet(planningSuggestions),
                          onShowPulse: () => _showDayPulseSheet(
                            insights: miniInsights,
                            selectedDay: normalizedDate,
                          ),
                          onToggleMissionMode: missionNodes.isEmpty
                              ? null
                              : () => setState(
                                  () => _isMissionMode = !_isMissionMode,
                                ),
                          onStopFocus:
                              _focusStartedAt == null || missionNodes.isEmpty
                              ? null
                              : () => _stopFocusSession(
                                  missionNodes.firstWhere(
                                    (node) => node.id == _focusNodeId,
                                    orElse: () => missionNodes.first,
                                  ),
                                ),
                          onInboxPressed: inboxNodes.isEmpty
                              ? null
                              : () => _showInboxSheet(
                                  context,
                                  inboxNodes,
                                  normalizedDate,
                                ),
                          onQuickCapture: _showQuickCaptureSheet,
                        ),
                        selectedTab: _ribbonTab,
                        selectedNodePreset: selectedNode == null
                            ? null
                            : NodeUiStateCodec.read(selectedNode).sizePreset,
                        selectedNodeSaveStatus: selectedNode == null
                            ? NodeSaveStatus.idle
                            : _inlineSaveStatuses[selectedNode.id] ??
                                  NodeSaveStatus.idle,
                        isSelectedNodeEditing:
                            selectedNode != null &&
                            _inlineEditingNodeIds.contains(selectedNode.id),
                        canExportSelectedMedia:
                            selectedNode != null &&
                            switch (selectedNode.type) {
                              NodeType.image => ImagePayload.fromNode(
                                selectedNode,
                              ).attachmentId.isNotEmpty,
                              NodeType.video => VideoPayload.fromNode(
                                selectedNode,
                              ).attachmentId.isNotEmpty,
                              _ => false,
                            },
                        canOpenSelectedMedia:
                            selectedNode != null &&
                            _hasSafeMediaUrl(selectedNode),
                        onTabChanged: (tab) => unawaited(_setRibbonTab(tab)),
                        isExplorerVisible: _isLifeExplorerExpanded,
                        canUndo: _undoStack.isNotEmpty,
                        canRedo: _redoStack.isNotEmpty,
                        onToggleExplorer: () => setState(
                          () => _isLifeExplorerExpanded =
                              !_isLifeExplorerExpanded,
                        ),
                        onCreateType: (type) => _createNodeOfType(
                          context,
                          ref,
                          normalizedDate,
                          canvasNodes,
                          type,
                          null,
                        ),
                        onCanvasAction: (action) =>
                            unawaited(_runCanvasAction(action)),
                        isGridVisible:
                            _canvasKey.currentState?.isGridVisible ?? true,
                        isSnapEnabled:
                            _canvasKey.currentState?.isSnapEnabled ?? false,
                        isMinimapVisible:
                            _canvasKey.currentState?.isMinimapVisible ?? false,
                        areCompletedVisible:
                            _canvasKey.currentState?.areCompletedNodesVisible ??
                            true,
                        onAddNode: (anchor) => _showCanvasAddNodeMenuAtAnchor(
                          ref,
                          normalizedDate,
                          canvasNodes,
                          anchor,
                        ),
                        onUndo: _undo,
                        onRedo: _redo,
                        onFitCanvas: () => _canvasKey.currentState
                            ?.focusOnPosition(const CanvasPosition(0, 0)),
                        onToggleGrid: () => unawaited(
                          _canvasKey.currentState?.runContextAction(
                                CanvasContextAction.toggleGrid,
                              ) ??
                              Future<void>.value(),
                        ),
                        onToggleSnap: () => unawaited(
                          _canvasKey.currentState?.runContextAction(
                                CanvasContextAction.toggleSnap,
                              ) ??
                              Future<void>.value(),
                        ),
                        onToggleMinimap: () => unawaited(
                          _canvasKey.currentState?.runContextAction(
                                CanvasContextAction.toggleMinimap,
                              ) ??
                              Future<void>.value(),
                        ),
                        onResetZoom: () => unawaited(
                          _canvasKey.currentState?.runContextAction(
                                CanvasContextAction.resetZoom,
                              ) ??
                              Future<void>.value(),
                        ),
                        onNodeTools: selectedNode == null
                            ? null
                            : () => _showSelectedNodeTools(selectedNode!),
                        onEditNode: selectedNode == null
                            ? null
                            : () => _beginSelectedNodeEdit(selectedNode!),
                        onDoneEditing: selectedNode == null
                            ? null
                            : () => unawaited(
                                _finishSelectedNodeEdit(selectedNode!),
                              ),
                        onPresetChanged: selectedNode == null
                            ? null
                            : (preset) => unawaited(
                                _setSelectedNodePreset(selectedNode!, preset),
                              ),
                        onReplaceMedia: selectedNode == null
                            ? null
                            : () => unawaited(_replaceMedia(selectedNode!)),
                        onExportMedia: selectedNode == null
                            ? null
                            : () => unawaited(
                                _exportSelectedMedia(selectedNode!),
                              ),
                        onOpenMedia: selectedNode == null
                            ? null
                            : () => unawaited(_openMediaSource(selectedNode!)),
                        onClearSelection: selectedNode == null
                            ? null
                            : () =>
                                  unawaited(_clearSelectedNode(selectedNode!)),
                      ),
                    if (_viewMode == _DayViewMode.canvas &&
                        MediaQuery.sizeOf(context).width < 840)
                      _MindmapMobileToolbar(
                        selectedNode: selectedNode,
                        onTools: () => _showMobileToolsSheet(
                          selectedNode,
                          normalizedDate,
                          ref,
                          canvasNodes,
                        ),
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          if (_viewMode == _DayViewMode.canvas &&
                              MediaQuery.sizeOf(context).width >= 1100)
                            SizedBox(
                              width: _isLifeExplorerExpanded ? 316 : 52,
                              child: _isLifeExplorerExpanded
                                  ? LifeExplorer(
                                      day: normalizedDate,
                                      nodes: filteredDayNodes,
                                      selectedNodeId: _selectedNodeId,
                                      onNodeSelected: (node) =>
                                          unawaited(_selectAndFocusNode(node)),
                                      onCreateNode: (type) => _createNodeOfType(
                                        context,
                                        ref,
                                        normalizedDate,
                                        canvasNodes,
                                        type,
                                        null,
                                      ),
                                      onNodeUpdated: (node) async {
                                        if (!await _flushInlineWorkspace(
                                          node.id,
                                        )) {
                                          return;
                                        }
                                        await ref
                                            .read(mindmapRepositoryProvider)
                                            .saveNode(node);
                                        invalidateMindmapState(
                                          ref,
                                          day: normalizedDate,
                                        );
                                      },
                                      onNodeDeleted: (node) async {
                                        if (!await _flushInlineWorkspace(
                                          node.id,
                                        )) {
                                          return;
                                        }
                                        await ref
                                            .read(mindmapRepositoryProvider)
                                            .deleteNode(node.id);
                                        invalidateMindmapState(
                                          ref,
                                          day: normalizedDate,
                                        );
                                      },
                                      onCollapse: () =>
                                          _setLifeExplorerExpanded(false),
                                    )
                                  : Material(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            top: 10,
                                          ),
                                          child: IconButton(
                                            key: const ValueKey(
                                              'day-life-explorer-toggle',
                                            ),
                                            tooltip: 'Open Life Explorer',
                                            onPressed: () =>
                                                _setLifeExplorerExpanded(true),
                                            icon: const Icon(
                                              Icons.account_tree_outlined,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          Expanded(
                            child: Column(
                              children: [
                                if (_viewMode == _DayViewMode.canvas &&
                                    allDayBoards.isNotEmpty &&
                                    _isFloatingBoardTabsVisible)
                                  DayCanvasTabHeader(
                                    boards: allDayBoards,
                                    activeBoardId: activeCanvasBoard?.id,
                                    onSelectBoard: (String id) =>
                                        setState(() => _activeBoardId = id),
                                    onAddBoard: () => unawaited(
                                      _createDailySubBoard(normalizedDate),
                                    ),
                                    onRenameBoard: (board) =>
                                        unawaited(_renameDailyBoard(board)),
                                    onDeleteBoard: (board) => unawaited(
                                      _deleteDailyBoard(board, allDayBoards),
                                    ),
                                    onAssistantRequested:
                                        activeCanvasBoard == null
                                        ? null
                                        : () => unawaited(
                                            _openDailyCanvasAssistant(
                                              activeCanvasBoard,
                                              visibleCanvasNodes,
                                              collabState
                                                      .currentRole
                                                      ?.canWriteNodes ??
                                                  true,
                                            ),
                                          ),
                                    onVotingRequested: activeCanvasBoard == null
                                        ? null
                                        : () => unawaited(
                                            _openDailyVotingDialog(
                                              activeCanvasBoard,
                                            ),
                                          ),
                                    onWorkshopRequested:
                                        activeCanvasBoard == null
                                        ? null
                                        : () => unawaited(
                                            _openDailyWorkshopMenu(
                                              activeCanvasBoard,
                                            ),
                                          ),
                                    onTemplatesRequested:
                                        activeCanvasBoard == null
                                        ? null
                                        : () => unawaited(
                                            _openDailyBoardTemplates(
                                              activeCanvasBoard,
                                            ),
                                          ),
                                    onActivityHistoryRequested:
                                        activeCanvasBoard == null
                                        ? null
                                        : () => unawaited(
                                            _showDailyActivityHistory(
                                              activeCanvasBoard,
                                            ),
                                          ),
                                    onExportRequested: activeCanvasBoard == null
                                        ? null
                                        : () => unawaited(
                                            _exportDailyBoard(
                                              activeCanvasBoard,
                                            ),
                                          ),
                                    votingVotesLeft:
                                        activeCanvasBoard
                                                ?.votingSession
                                                .isActive ==
                                            true
                                        ? activeCanvasBoard!.votingSession
                                              .remainingVotesFor('local')
                                        : null,
                                  ),
                                Expanded(
                                  child: _viewMode == _DayViewMode.timeline
                                      ? DailyTimelineSchedule(
                                          day: normalizedDate,
                                          nodes: filteredDayNodes,
                                          onNodeSelected: (node) {
                                            unawaited(_selectNode(node));
                                          },
                                          onTaskDoneChanged:
                                              (node, isDone) async {
                                                final repository = ref.read(
                                                  mindmapRepositoryProvider,
                                                );
                                                final updatedNode = node
                                                    .copyWith(
                                                      isDone: isDone,
                                                      status: isDone
                                                          ? NodeStatus.done
                                                          : NodeStatus.open,
                                                      progress: isDone
                                                          ? 1
                                                          : node.progress,
                                                      updatedAt: DateTime.now(),
                                                    );
                                                _pushUndo(
                                                  _UndoEntry(
                                                    kind: _UndoKind.save,
                                                    nodeId: node.id,
                                                    before: node,
                                                    after: updatedNode,
                                                  ),
                                                );
                                                try {
                                                  await repository.saveNode(
                                                    updatedNode,
                                                  );
                                                  invalidateMindmapState(
                                                    ref,
                                                    day: normalizedDate,
                                                  );
                                                  if (context.mounted) {
                                                    _showSnackBar(
                                                      isDone
                                                          ? 'Task completed'
                                                          : 'Task reopened',
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    _showSnackBar(
                                                      'Failed to update task: $e',
                                                    );
                                                  }
                                                }
                                              },
                                        )
                                      : _viewMode == _DayViewMode.board
                                      ? _DayNodeBoardView(
                                          nodes: filteredDayNodes,
                                          selectedNodeId: _selectedNodeId,
                                          onNodeSelected: (node) {
                                            unawaited(_selectNode(node));
                                          },
                                          onNodeUpdated: (updatedNode) async {
                                            final currentNode = value
                                                .firstWhere(
                                                  (node) =>
                                                      node.id == updatedNode.id,
                                                  orElse: () => updatedNode,
                                                );
                                            final actionPatch =
                                                InlineNodeDraftPatch.between(
                                                  currentNode,
                                                  updatedNode,
                                                );
                                            await _withLatestNodeAfterFlush(
                                              updatedNode.id,
                                              (latest) async {
                                                final saved = actionPatch
                                                    .mergeInto(
                                                      latest,
                                                      DateTime.now(),
                                                    );
                                                _pushUndo(
                                                  _UndoEntry(
                                                    kind: _UndoKind.save,
                                                    nodeId: saved.id,
                                                    before: latest,
                                                    after: saved,
                                                  ),
                                                );
                                                await ref
                                                    .read(
                                                      mindmapRepositoryProvider,
                                                    )
                                                    .saveNode(saved);
                                                invalidateMindmapState(
                                                  ref,
                                                  day: normalizedDate,
                                                );
                                              },
                                            );
                                            if (context.mounted) {
                                              _showSnackBar('Board updated');
                                            }
                                          },
                                        )
                                      : _viewMode == _DayViewMode.table
                                      ? _DayNodeTableView(
                                          nodes: filteredDayNodes,
                                          selectedNodeId: _selectedNodeId,
                                          view: _tableQuickView,
                                          sortMode: _tableSortMode,
                                          onViewChanged: _setTableQuickView,
                                          onSortModeChanged: _setTableSortMode,
                                          onNodeSelected: (node) {
                                            unawaited(_selectNode(node));
                                          },
                                          onNodeUpdated: (updatedNode) async {
                                            final currentNode = value
                                                .firstWhere(
                                                  (node) =>
                                                      node.id == updatedNode.id,
                                                  orElse: () => updatedNode,
                                                );
                                            final actionPatch =
                                                InlineNodeDraftPatch.between(
                                                  currentNode,
                                                  updatedNode,
                                                );
                                            await _withLatestNodeAfterFlush(
                                              updatedNode.id,
                                              (latest) async {
                                                final saved = actionPatch
                                                    .mergeInto(
                                                      latest,
                                                      DateTime.now(),
                                                    );
                                                _pushUndo(
                                                  _UndoEntry(
                                                    kind: _UndoKind.save,
                                                    nodeId: saved.id,
                                                    before: latest,
                                                    after: saved,
                                                  ),
                                                );
                                                await ref
                                                    .read(
                                                      mindmapRepositoryProvider,
                                                    )
                                                    .saveNode(saved);
                                                invalidateMindmapState(
                                                  ref,
                                                  day: normalizedDate,
                                                );
                                              },
                                            );
                                            if (context.mounted) {
                                              _showSnackBar('Table updated');
                                            }
                                          },
                                        )
                                      : Stack(
                                          children: [
                                            Positioned.fill(
                                              child: MindmapCanvas(
                                                key: _canvasKey,
                                                nodes: visibleCanvasNodes,
                                                board: activeCanvasBoard,
                                                workshopSession:
                                                    dailyCanvasBoard
                                                        .valueOrNull
                                                        ?.workshopSession,
                                                workshopViewerUid: 'local',
                                                isWorkshopHost: true,
                                                onViewportChanged:
                                                    dailyCanvasBoard
                                                                .valueOrNull !=
                                                            null &&
                                                        (collabState
                                                                .currentRole
                                                                ?.canWriteNodes ??
                                                            true)
                                                    ? (viewport) => unawaited(
                                                        _saveDailyCanvasViewport(
                                                          dailyCanvasBoard
                                                              .valueOrNull!,
                                                          viewport,
                                                        ),
                                                      )
                                                    : null,
                                                assistantPreviewObjects:
                                                    _assistantPreviewObjects,
                                                onCanvasAssistantRequested:
                                                    dailyCanvasBoard
                                                            .valueOrNull ==
                                                        null
                                                    ? null
                                                    : () => unawaited(
                                                        _openDailyCanvasAssistant(
                                                          dailyCanvasBoard
                                                              .valueOrNull!,
                                                          visibleCanvasNodes,
                                                          collabState
                                                                  .currentRole
                                                                  ?.canWriteNodes ??
                                                              true,
                                                        ),
                                                      ),
                                                canUndo: _undoStack.isNotEmpty,
                                                canRedo: _redoStack.isNotEmpty,
                                                onUndo: () =>
                                                    unawaited(_undo()),
                                                onRedo: () =>
                                                    unawaited(_redo()),
                                                onProductivityNodeCreateRequested:
                                                    (canvasPosition) =>
                                                        _showCanvasProductivityNodeMenu(
                                                          ref,
                                                          normalizedDate,
                                                          visibleCanvasNodes,
                                                          canvasPosition:
                                                              canvasPosition,
                                                        ),
                                                onCanvasObjectCreated: (object) =>
                                                    _createNativeCanvasObject(
                                                      normalizedDate,
                                                      object,
                                                    ),
                                                onCanvasObjectUpdated: (object) =>
                                                    _updateNativeCanvasObject(
                                                      normalizedDate,
                                                      object,
                                                    ),
                                                onCanvasObjectDeleted: (object) =>
                                                    _deleteNativeCanvasObject(
                                                      normalizedDate,
                                                      object,
                                                    ),
                                                onCanvasObjectsCreated:
                                                    (objects) =>
                                                        _createNativeCanvasObjects(
                                                          normalizedDate,
                                                          objects,
                                                        ),
                                                onCanvasObjectsUpdated:
                                                    (objects) =>
                                                        _updateNativeCanvasObjects(
                                                          normalizedDate,
                                                          objects,
                                                        ),
                                                onCanvasObjectsDeleted:
                                                    (objects) =>
                                                        _deleteNativeCanvasObjects(
                                                          normalizedDate,
                                                          objects,
                                                        ),
                                                onCanvasVoteChanged:
                                                    (objects, delta) async {
                                                      final board =
                                                          activeCanvasBoard;
                                                      if (board == null ||
                                                          !board
                                                              .votingSession
                                                              .isActive) {
                                                        return;
                                                      }
                                                      var session =
                                                          board.votingSession;
                                                      for (final object
                                                          in objects) {
                                                        session = session
                                                            .changeVote(
                                                              participantId:
                                                                  'local',
                                                              objectId:
                                                                  object.id,
                                                              add: delta > 0,
                                                            );
                                                      }
                                                      if (session ==
                                                          board.votingSession) {
                                                        return;
                                                      }
                                                      await _saveWorkshopBoard(
                                                        board,
                                                        board.copyWith(
                                                          votingSession:
                                                              session,
                                                          updatedAt:
                                                              DateTime.now(),
                                                        ),
                                                      );
                                                    },
                                                onCanvasImageImport:
                                                    _importNativeCanvasImage,
                                                loadCanvasAttachmentBytes:
                                                    _loadNativeCanvasAttachment,
                                                variant: variant,
                                                highlightedNodeId:
                                                    _selectedNodeId,
                                                expandedNodeId: _selectedNodeId,
                                                expandedNodeOverride:
                                                    expandedNodeDraft,
                                                expandedNodeBuilder:
                                                    _buildExpandedNode,
                                                onExpandedSelectionChanging:
                                                    _guardExpandedSelectionChange,
                                                onStatusMessage: _showSnackBar,
                                                onNodeContextMenu:
                                                    (node, position) =>
                                                        _showCanvasNodeMenu(
                                                          node,
                                                          position,
                                                        ),
                                                collaborationState: collabState,
                                                onLocalCursorChanged: (pos) =>
                                                    ref
                                                        .read(
                                                          collaborationProvider
                                                              .notifier,
                                                        )
                                                        .updateLocalCursor(pos),
                                                onLocalSelectionChanged:
                                                    (nodeId) => ref
                                                        .read(
                                                          collaborationProvider
                                                              .notifier,
                                                        )
                                                        .updateLocalSelection(
                                                          nodeId,
                                                        ),
                                                onLocalPingRequested: (pos) =>
                                                    ref
                                                        .read(
                                                          collaborationProvider
                                                              .notifier,
                                                        )
                                                        .broadcastPing(pos),
                                                pingStream: ref
                                                    .read(
                                                      collaborationProvider
                                                          .notifier,
                                                    )
                                                    .pingStream,
                                                onNodeDropped: (type, offset) {
                                                  _createNodeOfType(
                                                    context,
                                                    ref,
                                                    normalizedDate,
                                                    canvasNodes,
                                                    type,
                                                    offset,
                                                  );
                                                },
                                                onNodeQuickCreate:
                                                    (
                                                      type,
                                                      title, {
                                                      priority,
                                                      tags,
                                                    }) {
                                                      _createNodeOfType(
                                                        context,
                                                        ref,
                                                        normalizedDate,
                                                        canvasNodes,
                                                        type,
                                                        null,
                                                        title: title,
                                                        priority:
                                                            priority ??
                                                            NodePriority.none,
                                                        tags: tags ?? const [],
                                                      );
                                                    },
                                                onClearNodes: () =>
                                                    _clearMindmapNodes(
                                                      context,
                                                      ref,
                                                      normalizedDate,
                                                      canvasNodes,
                                                    ),
                                                onCanvasContextMenu:
                                                    (
                                                      globalPosition,
                                                      canvasPosition,
                                                    ) {
                                                      _showCanvasAddNodeMenu(
                                                        context,
                                                        ref,
                                                        normalizedDate,
                                                        canvasNodes,
                                                        globalPosition,
                                                        canvasPosition,
                                                      );
                                                    },
                                                onConnectedNodeCreate:
                                                    (
                                                      source,
                                                      type,
                                                      canvasPosition,
                                                    ) {
                                                      return _createNodeOfType(
                                                        context,
                                                        ref,
                                                        normalizedDate,
                                                        canvasNodes,
                                                        type,
                                                        canvasPosition,
                                                        title:
                                                            '${source.title} ·${type.label}',
                                                      );
                                                    },
                                                onNodeSelected: (node) async {
                                                  if (node.isDone &&
                                                      filteredDayNodes.length ==
                                                          1) {
                                                    await _createSelectedNodeFollowUp(
                                                      node,
                                                    );
                                                    return;
                                                  }
                                                  await _selectNode(node);
                                                },
                                                onSelectionCleared: () {
                                                  final selected = selectedNode;
                                                  if (selected != null) {
                                                    unawaited(
                                                      _clearSelectedNode(
                                                        selected,
                                                      ),
                                                    );
                                                  }
                                                },
                                                onInlineEditStateChanged:
                                                    (
                                                      nodeId,
                                                      isEditing,
                                                      status,
                                                    ) {
                                                      if (!mounted) return;
                                                      setState(() {
                                                        _inlineSaveStatuses[nodeId] =
                                                            status;
                                                        if (isEditing) {
                                                          _inlineEditingNodeIds
                                                              .add(nodeId);
                                                        } else {
                                                          _inlineEditingNodeIds
                                                              .remove(nodeId);
                                                        }
                                                      });
                                                    },
                                                onNodeConnected: (source, target) async {
                                                  final repository = ref.read(
                                                    mindmapRepositoryProvider,
                                                  );
                                                  final relatedNodeIds = {
                                                    ...source.relatedNodeIds,
                                                    target.id,
                                                  }.toList();
                                                  final updatedNode = source
                                                      .copyWith(
                                                        relatedNodeIds:
                                                            relatedNodeIds,
                                                        data: {
                                                          ...source.data,
                                                          'relations':
                                                              _relationDataForIds(
                                                                source,
                                                                relatedNodeIds,
                                                              ),
                                                        },
                                                        updatedAt:
                                                            DateTime.now(),
                                                      );
                                                  _pushUndo(
                                                    _UndoEntry(
                                                      kind: _UndoKind.save,
                                                      nodeId: source.id,
                                                      before: source,
                                                      after: updatedNode,
                                                    ),
                                                  );
                                                  try {
                                                    await repository.saveNode(
                                                      updatedNode,
                                                    );
                                                    await _persistCanvasNodeGeometry(
                                                      updatedNode,
                                                    );
                                                    invalidateMindmapState(
                                                      ref,
                                                      day: normalizedDate,
                                                    );
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Connected ${source.title} →${target.title}',
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to connect nodes: $e',
                                                      );
                                                    }
                                                  }
                                                },
                                                onNodeDisconnected: (source, target) async {
                                                  final repository = ref.read(
                                                    mindmapRepositoryProvider,
                                                  );
                                                  MindmapNode nodeToUpdate;
                                                  List<String> relatedNodeIds;
                                                  if (source.relatedNodeIds
                                                      .contains(target.id)) {
                                                    nodeToUpdate = source;
                                                    relatedNodeIds = source
                                                        .relatedNodeIds
                                                        .where(
                                                          (id) =>
                                                              id != target.id,
                                                        )
                                                        .toList();
                                                  } else if (target
                                                      .relatedNodeIds
                                                      .contains(source.id)) {
                                                    nodeToUpdate = target;
                                                    relatedNodeIds = target
                                                        .relatedNodeIds
                                                        .where(
                                                          (id) =>
                                                              id != source.id,
                                                        )
                                                        .toList();
                                                  } else {
                                                    return;
                                                  }
                                                  final updatedNode =
                                                      nodeToUpdate.copyWith(
                                                        relatedNodeIds:
                                                            relatedNodeIds,
                                                        data: {
                                                          ...nodeToUpdate.data,
                                                          'relations':
                                                              _relationDataForIds(
                                                                nodeToUpdate,
                                                                relatedNodeIds,
                                                              ),
                                                        },
                                                        updatedAt:
                                                            DateTime.now(),
                                                      );
                                                  _pushUndo(
                                                    _UndoEntry(
                                                      kind: _UndoKind.save,
                                                      nodeId: nodeToUpdate.id,
                                                      before: nodeToUpdate,
                                                      after: updatedNode,
                                                    ),
                                                  );
                                                  try {
                                                    await repository.saveNode(
                                                      updatedNode,
                                                    );
                                                    invalidateMindmapState(
                                                      ref,
                                                      day: normalizedDate,
                                                    );
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Disconnected ${source.title} ↔${target.title}',
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to disconnect nodes: $e',
                                                      );
                                                    }
                                                  }
                                                },
                                                onNodeUpdated: (updatedNode) async {
                                                  final previousNode =
                                                      canvasNodes
                                                          .where(
                                                            (node) =>
                                                                node.id ==
                                                                updatedNode.id,
                                                          )
                                                          .firstOrNull;
                                                  final actionPatch =
                                                      InlineNodeDraftPatch.between(
                                                        previousNode ??
                                                            updatedNode,
                                                        updatedNode,
                                                      );
                                                  try {
                                                    await _withLatestNodeAfterFlush(
                                                      updatedNode.id,
                                                      (latest) async {
                                                        final saved = actionPatch
                                                            .mergeInto(
                                                              latest,
                                                              DateTime.now(),
                                                            );
                                                        _pushUndo(
                                                          _UndoEntry(
                                                            kind:
                                                                _UndoKind.save,
                                                            nodeId: saved.id,
                                                            before: latest,
                                                            after: saved,
                                                          ),
                                                        );
                                                        await ref
                                                            .read(
                                                              mindmapRepositoryProvider,
                                                            )
                                                            .saveNode(saved);
                                                        invalidateMindmapState(
                                                          ref,
                                                          day: normalizedDate,
                                                        );
                                                      },
                                                    );
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Node updated',
                                                      );
                                                    }
                                                  } catch (error) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to update node: $error',
                                                      );
                                                    }
                                                    rethrow;
                                                  }
                                                },
                                                onNodesDeleted:
                                                    _deleteCanvasNodes,
                                                onTaskDoneChanged: (node, isDone) async {
                                                  final repository = ref.read(
                                                    mindmapRepositoryProvider,
                                                  );
                                                  final updatedNode = node
                                                      .copyWith(
                                                        isDone: isDone,
                                                        status: isDone
                                                            ? NodeStatus.done
                                                            : NodeStatus.open,
                                                        progress: isDone
                                                            ? 1
                                                            : node.progress,
                                                        updatedAt:
                                                            DateTime.now(),
                                                      );
                                                  _pushUndo(
                                                    _UndoEntry(
                                                      kind: _UndoKind.save,
                                                      nodeId: node.id,
                                                      before: node,
                                                      after: updatedNode,
                                                    ),
                                                  );
                                                  try {
                                                    await repository.saveNode(
                                                      updatedNode,
                                                    );
                                                    invalidateMindmapState(
                                                      ref,
                                                      day: normalizedDate,
                                                    );
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        isDone
                                                            ? 'Task completed'
                                                            : 'Task reopened',
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to update task: $e',
                                                      );
                                                    }
                                                  }
                                                },
                                                onTaskChecklistItemCompleted: (node) async {
                                                  final repository = ref.read(
                                                    mindmapRepositoryProvider,
                                                  );
                                                  final updatedNode =
                                                      completeNextChecklistItem(
                                                        node,
                                                        now: DateTime.now(),
                                                      );
                                                  if (updatedNode == node) {
                                                    return;
                                                  }

                                                  _pushUndo(
                                                    _UndoEntry(
                                                      kind: _UndoKind.save,
                                                      nodeId: node.id,
                                                      before: node,
                                                      after: updatedNode,
                                                    ),
                                                  );
                                                  try {
                                                    await repository.saveNode(
                                                      updatedNode,
                                                    );
                                                    invalidateMindmapState(
                                                      ref,
                                                      day: normalizedDate,
                                                    );
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Checklist item completed',
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to update checklist: $e',
                                                      );
                                                    }
                                                  }
                                                },
                                                onKanbanCardAdvanced:
                                                    (node, cardId) async {
                                                      final board =
                                                          KanbanBoard.fromNodeData(
                                                            node.data,
                                                          );
                                                      final updatedBoard = board
                                                          .moveCardToNextColumn(
                                                            cardId,
                                                          );
                                                      final repository = ref.read(
                                                        mindmapRepositoryProvider,
                                                      );
                                                      final updatedNode = node
                                                          .copyWith(
                                                            data: {
                                                              ...node.data,
                                                              'kanban':
                                                                  updatedBoard
                                                                      .toJson(),
                                                            },
                                                            updatedAt:
                                                                DateTime.now(),
                                                          );
                                                      _pushUndo(
                                                        _UndoEntry(
                                                          kind: _UndoKind.save,
                                                          nodeId: node.id,
                                                          before: node,
                                                          after: updatedNode,
                                                        ),
                                                      );
                                                      try {
                                                        await repository
                                                            .saveNode(
                                                              updatedNode,
                                                            );
                                                        invalidateMindmapState(
                                                          ref,
                                                          day: normalizedDate,
                                                        );
                                                        if (context.mounted) {
                                                          _showSnackBar(
                                                            'Card moved',
                                                          );
                                                        }
                                                      } catch (e) {
                                                        if (context.mounted) {
                                                          _showSnackBar(
                                                            'Failed to move card: $e',
                                                          );
                                                        }
                                                      }
                                                    },
                                                onHabitCompleted: (node) async {
                                                  final repository = ref.read(
                                                    mindmapRepositoryProvider,
                                                  );
                                                  final updatedNode =
                                                      logHabitCompletion(
                                                        node,
                                                        normalizedDate,
                                                        now: DateTime.now(),
                                                      );
                                                  if (updatedNode == node) {
                                                    return;
                                                  }

                                                  _pushUndo(
                                                    _UndoEntry(
                                                      kind: _UndoKind.save,
                                                      nodeId: node.id,
                                                      before: node,
                                                      after: updatedNode,
                                                    ),
                                                  );
                                                  try {
                                                    await repository.saveNode(
                                                      updatedNode,
                                                    );
                                                    invalidateMindmapState(
                                                      ref,
                                                      day: normalizedDate,
                                                    );
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Habit logged',
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to log habit: $e',
                                                      );
                                                    }
                                                  }
                                                },
                                                onGoalMilestoneAdvanced: (node) async {
                                                  final repository = ref.read(
                                                    mindmapRepositoryProvider,
                                                  );
                                                  final updatedNode =
                                                      advanceGoalMilestone(
                                                        node,
                                                        now: DateTime.now(),
                                                      );
                                                  if (updatedNode == node) {
                                                    return;
                                                  }

                                                  _pushUndo(
                                                    _UndoEntry(
                                                      kind: _UndoKind.save,
                                                      nodeId: node.id,
                                                      before: node,
                                                      after: updatedNode,
                                                    ),
                                                  );
                                                  try {
                                                    await repository.saveNode(
                                                      updatedNode,
                                                    );
                                                    invalidateMindmapState(
                                                      ref,
                                                      day: normalizedDate,
                                                    );
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Milestone advanced',
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to advance milestone: $e',
                                                      );
                                                    }
                                                  }
                                                },
                                                onPlanStepAdvanced: (node) async {
                                                  final repository = ref.read(
                                                    mindmapRepositoryProvider,
                                                  );
                                                  final updatedNode =
                                                      advancePlanStep(
                                                        node,
                                                        now: DateTime.now(),
                                                      );
                                                  if (updatedNode == node) {
                                                    return;
                                                  }

                                                  _pushUndo(
                                                    _UndoEntry(
                                                      kind: _UndoKind.save,
                                                      nodeId: node.id,
                                                      before: node,
                                                      after: updatedNode,
                                                    ),
                                                  );
                                                  try {
                                                    await repository.saveNode(
                                                      updatedNode,
                                                    );
                                                    invalidateMindmapState(
                                                      ref,
                                                      day: normalizedDate,
                                                    );
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Step advanced',
                                                      );
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to advance step: $e',
                                                      );
                                                    }
                                                  }
                                                },
                                                onNodeMoved: (node, position) async {
                                                  try {
                                                    await _serializeNodeMutation(
                                                      node.id,
                                                      () async {
                                                        final repository = ref.read(
                                                          mindmapRepositoryProvider,
                                                        );
                                                        final latest =
                                                            await repository
                                                                .getNode(
                                                                  node.id,
                                                                );
                                                        if (latest == null) {
                                                          return;
                                                        }
                                                        final updatedNode =
                                                            latest.copyWith(
                                                              position:
                                                                  position,
                                                              updatedAt:
                                                                  DateTime.now(),
                                                            );
                                                        _pushUndo(
                                                          _UndoEntry(
                                                            kind:
                                                                _UndoKind.save,
                                                            nodeId: latest.id,
                                                            before: latest,
                                                            after: updatedNode,
                                                          ),
                                                        );
                                                        await ref
                                                            .read(
                                                              mindmapMutationControllerProvider,
                                                            )
                                                            .saveNode(
                                                              updatedNode,
                                                            );
                                                        await _persistCanvasNodeGeometry(
                                                          updatedNode,
                                                        );
                                                      },
                                                    );
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      _showSnackBar(
                                                        'Failed to save position: $e',
                                                      );
                                                    }
                                                  }
                                                },
                                                onNodeResize: (node, change) =>
                                                    unawaited(
                                                      _resizeCanvasNode(
                                                        node,
                                                        change,
                                                      ),
                                                    ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 12,
                                              left: 12,
                                              right: 12,
                                              child: Align(
                                                alignment: Alignment.topCenter,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (_isFloatingTopBarVisible)
                                                      Container(
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 8,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 6,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .surface
                                                                  .withValues(
                                                                    alpha: 0.90,
                                                                  ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors
                                                                  .black
                                                                  .withValues(
                                                                    alpha: 0.25,
                                                                  ),
                                                              blurRadius: 10,
                                                              offset:
                                                                  const Offset(
                                                                    0,
                                                                    4,
                                                                  ),
                                                            ),
                                                          ],
                                                          border: Border.all(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .outlineVariant
                                                                    .withValues(
                                                                      alpha:
                                                                          0.5,
                                                                    ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Consumer(
                                                              builder: (context, ref, child) {
                                                                final titleMap =
                                                                    ref.watch(
                                                                      workspaceTitleProvider,
                                                                    );
                                                                final titleKey =
                                                                    '${WorkspaceContextType.daily.name}_${dayKey(normalizedDate)}';
                                                                final customTitle =
                                                                    titleMap[titleKey];
                                                                final displayTitle =
                                                                    (customTitle !=
                                                                            null &&
                                                                        customTitle
                                                                            .isNotEmpty)
                                                                    ? customTitle
                                                                    : dayKey(
                                                                        normalizedDate,
                                                                      );
                                                                return _InlineWorkspaceTitle(
                                                                  customTitle:
                                                                      customTitle,
                                                                  displayTitle:
                                                                      displayTitle,
                                                                  onTitleChanged: (String title) => ref
                                                                      .read(
                                                                        workspaceTitleProvider
                                                                            .notifier,
                                                                      )
                                                                      .setTitle(
                                                                        WorkspaceContextType
                                                                            .daily,
                                                                        dayKey(
                                                                          normalizedDate,
                                                                        ),
                                                                        title,
                                                                      ),
                                                                );
                                                              },
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            if (MediaQuery.sizeOf(
                                                                  context,
                                                                ).width >=
                                                                1100) ...[
                                                              CollaborationRoomBar(
                                                                nodes:
                                                                    nodes
                                                                        .valueOrNull ??
                                                                    const <
                                                                      MindmapNode
                                                                    >[],
                                                                followingId:
                                                                    _followingCollaboratorId,
                                                                onFollowChanged: (id) {
                                                                  setState(
                                                                    () =>
                                                                        _followingCollaboratorId =
                                                                            id,
                                                                  );
                                                                  _canvasKey
                                                                      .currentState
                                                                      ?.followCollaborator(
                                                                        id,
                                                                      );
                                                                },
                                                              ),
                                                              const SizedBox(
                                                                width: 12,
                                                              ),
                                                            ],
                                                            _DayViewModeToggle(
                                                              mode: _viewMode,
                                                              onChanged: (value) =>
                                                                  _setViewMode(
                                                                    value,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            _DayContextSwitcher(
                                                              filter:
                                                                  _contextFilter,
                                                              workspaceContext:
                                                                  activeWorkspaceContext,
                                                              workspaceContexts:
                                                                  workspaceContexts
                                                                      .valueOrNull,
                                                              onChanged:
                                                                  _setContextFilter,
                                                              onWorkspaceChanged:
                                                                  _setWorkspaceContextFilter,
                                                            ),
                                                            const SizedBox(
                                                              width: 12,
                                                            ),
                                                            IconButton(
                                                              tooltip:
                                                                  'Copy day markdown',
                                                              onPressed: () => unawaited(
                                                                _copyDayMarkdown(
                                                                  normalizedDate,
                                                                  allNodes.valueOrNull ??
                                                                      const <
                                                                        MindmapNode
                                                                      >[],
                                                                ),
                                                              ),
                                                              icon: const Icon(
                                                                Icons
                                                                    .ios_share_outlined,
                                                                size: 18,
                                                              ),
                                                            ),
                                                            IconButton(
                                                              tooltip:
                                                                  _isFloatingTopBarVisible
                                                                  ? 'Collapse Topbar'
                                                                  : 'Expand Topbar',
                                                              icon: const Icon(
                                                                Icons
                                                                    .keyboard_arrow_up_rounded,
                                                                size: 18,
                                                              ),
                                                              onPressed: () =>
                                                                  setState(
                                                                    () => _isFloatingTopBarVisible =
                                                                        false,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (activeCanvasBoard
                                                case final board?)
                                              if (board
                                                      .workshopSession
                                                      .activeStage
                                                  case final stage?)
                                                Positioned(
                                                  key: const ValueKey(
                                                    'workspace-workshop-stage-banner',
                                                  ),
                                                  top: 12,
                                                  left: 12,
                                                  right: 260,
                                                  child: Align(
                                                    alignment:
                                                        Alignment.topCenter,
                                                    child: Card(
                                                      margin: EdgeInsets.zero,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 8,
                                                            ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              stage.contributionsPrivate &&
                                                                      !board
                                                                          .workshopSession
                                                                          .revealedStageIds
                                                                          .contains(
                                                                            stage.id,
                                                                          )
                                                                  ? Icons
                                                                        .visibility_off_outlined
                                                                  : Icons
                                                                        .flag_outlined,
                                                              size: 18,
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Flexible(
                                                              child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    'Stage ${board.workshopSession.activeStageIndex + 1}/${board.workshopSession.agenda.length}: ${stage.title}',
                                                                    style: Theme.of(
                                                                      context,
                                                                    ).textTheme.labelLarge,
                                                                  ),
                                                                  if (stage
                                                                      .instructions
                                                                      .isNotEmpty)
                                                                    Text(
                                                                      stage
                                                                          .instructions,
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                ],
                                                              ),
                                                            ),
                                                            if (board
                                                                .workshopSession
                                                                .awaitingAdvance) ...[
                                                              const SizedBox(
                                                                width: 12,
                                                              ),
                                                              FilledButton.tonal(
                                                                key: const ValueKey(
                                                                  'workspace-workshop-confirm-advance',
                                                                ),
                                                                onPressed: () => unawaited(
                                                                  _handleDailyWorkshopAction(
                                                                    board,
                                                                    board
                                                                            .workshopSession
                                                                            .isLastStage
                                                                        ? 'end'
                                                                        : 'advance',
                                                                  ),
                                                                ),
                                                                child: Text(
                                                                  board
                                                                          .workshopSession
                                                                          .isLastStage
                                                                      ? 'End workshop'
                                                                      : 'Next stage',
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            if (activeCanvasBoard
                                                case final board?)
                                              Positioned(
                                                top: 16,
                                                right:
                                                    MediaQuery.sizeOf(
                                                          context,
                                                        ).width <
                                                        1100
                                                    ? 72
                                                    : 16,
                                                child: Card(
                                                  margin: EdgeInsets.zero,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (board
                                                          .workshopSession
                                                          .isActive)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                left: 12,
                                                              ),
                                                          child: Text(
                                                            _dailyWorkshopTime(
                                                              board
                                                                  .workshopSession,
                                                            ),
                                                            key: const ValueKey(
                                                              'day-workshop-timer',
                                                            ),
                                                          ),
                                                        ),
                                                      PopupMenuButton<String>(
                                                        key: const ValueKey(
                                                          'day-workshop-menu',
                                                        ),
                                                        tooltip:
                                                            'Workshop controls',
                                                        icon: Icon(
                                                          board
                                                                  .workshopSession
                                                                  .isActive
                                                              ? Icons.groups
                                                              : Icons
                                                                    .groups_outlined,
                                                        ),
                                                        onSelected: (action) =>
                                                            unawaited(
                                                              _handleDailyWorkshopAction(
                                                                board,
                                                                action,
                                                              ),
                                                            ),
                                                        itemBuilder: (context) => [
                                                          if (!board
                                                              .workshopSession
                                                              .isActive) ...[
                                                            const PopupMenuItem(
                                                              value:
                                                                  'brainstorm',
                                                              child: Text(
                                                                'Start brainstorm',
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value:
                                                                  'retrospective',
                                                              child: Text(
                                                                'Start retrospective',
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value: 'decision',
                                                              child: Text(
                                                                'Start decision',
                                                              ),
                                                            ),
                                                          ],
                                                          PopupMenuItem(
                                                            value:
                                                                board
                                                                        .workshopSession
                                                                        .status ==
                                                                    CanvasWorkshopStatus
                                                                        .paused
                                                                ? 'resume'
                                                                : 'pause',
                                                            enabled: board
                                                                .workshopSession
                                                                .isActive,
                                                            child: Text(
                                                              board.workshopSession.status ==
                                                                      CanvasWorkshopStatus
                                                                          .paused
                                                                  ? 'Resume'
                                                                  : 'Pause',
                                                            ),
                                                          ),
                                                          PopupMenuItem(
                                                            value: 'advance',
                                                            enabled:
                                                                board
                                                                    .workshopSession
                                                                    .isActive &&
                                                                !board
                                                                    .workshopSession
                                                                    .isLastStage,
                                                            child: const Text(
                                                              'Advance stage',
                                                            ),
                                                          ),
                                                          PopupMenuItem(
                                                            value: 'reveal',
                                                            enabled:
                                                                board
                                                                    .workshopSession
                                                                    .isActive &&
                                                                board
                                                                        .workshopSession
                                                                        .activeStage
                                                                        ?.contributionsPrivate ==
                                                                    true,
                                                            child: const Text(
                                                              'Reveal contributions',
                                                            ),
                                                          ),
                                                          PopupMenuItem(
                                                            value: 'end',
                                                            enabled: board
                                                                .workshopSession
                                                                .isActive,
                                                            child: const Text(
                                                              'End workshop',
                                                            ),
                                                          ),
                                                          PopupMenuItem(
                                                            value: 'summary',
                                                            enabled:
                                                                board
                                                                    .workshopSession
                                                                    .summary !=
                                                                null,
                                                            child: const Text(
                                                              'Show summary',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            if (MediaQuery.sizeOf(
                                                  context,
                                                ).width <
                                                1100)
                                              Positioned(
                                                right: 16,
                                                top: 16,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    FloatingActionButton.small(
                                                      key: const ValueKey(
                                                        'day-life-explorer-toggle',
                                                      ),
                                                      tooltip:
                                                          'Open Life Explorer',
                                                      heroTag:
                                                          'day-life-explorer-toggle',
                                                      onPressed: () =>
                                                          _showLifeExplorerSheet(
                                                            day: normalizedDate,
                                                            nodes:
                                                                filteredDayNodes,
                                                            canvasNodes:
                                                                canvasNodes,
                                                          ),
                                                      child: const Icon(
                                                        Icons
                                                            .account_tree_outlined,
                                                      ),
                                                    ),
                                                    if (isShortScreen) ...[
                                                      const SizedBox(height: 8),
                                                      FloatingActionButton.small(
                                                        key: const ValueKey(
                                                          'day-landscape-tools-toggle',
                                                        ),
                                                        tooltip: 'Canvas Tools',
                                                        heroTag:
                                                            'day-landscape-tools-toggle',
                                                        onPressed: () =>
                                                            _showMobileToolsSheet(
                                                              selectedNode,
                                                              normalizedDate,
                                                              ref,
                                                              canvasNodes,
                                                            ),
                                                        child: const Icon(
                                                          Icons.tune_rounded,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            if (value.isEmpty &&
                                                !_isBlankBoardHidden)
                                              Center(
                                                child: _DayEmptyStateCockpit(
                                                  onDismiss: () => setState(
                                                    () => _isBlankBoardHidden =
                                                        true,
                                                  ),
                                                  onPlanDay: () => unawaited(
                                                    _showDayTemplateSheet(
                                                      normalizedDate,
                                                      value,
                                                    ),
                                                  ),
                                                  onImportLeftovers: () => unawaited(
                                                    _showCarryOverSheet(
                                                      normalizedDate,
                                                      buildCarryOverCandidates(
                                                        nodes: allNodeList,
                                                        selectedDay:
                                                            normalizedDate,
                                                      ),
                                                      title:
                                                          'Import yesterday leftovers',
                                                    ),
                                                  ),
                                                  onStartJournal: () =>
                                                      unawaited(
                                                        _openOrCreateDailyReview(
                                                          normalizedDate,
                                                          value,
                                                        ),
                                                      ),
                                                  onApplyRoutine: () =>
                                                      unawaited(
                                                        _applyRoutines(
                                                          context,
                                                          ref,
                                                          normalizedDate,
                                                        ),
                                                      ),
                                                  onUseTemplate: () =>
                                                      unawaited(
                                                        _showDayTemplateSheet(
                                                          normalizedDate,
                                                          value,
                                                        ),
                                                      ),
                                                  onQuickCapture:
                                                      _showQuickCaptureSheet,
                                                ),
                                              ),

                                            if (widget.highlightNodeId != null)
                                              Positioned(
                                                left: 20,
                                                bottom: 20,
                                                child: _NodeRelationsDock(
                                                  nodeId:
                                                      widget.highlightNodeId!,
                                                  onSelect: (node) => unawaited(
                                                    _navigateToNode(node),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorMessage(
                message: 'Unable to load ${dayKey(normalizedDate)}',
                onRetry: () =>
                    ref.invalidate(nodesForDayProvider(normalizedDate)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleBackPop(Object? result) async {
    if (_isHandlingBackPop || _allowBackPop) return;
    _isHandlingBackPop = true;
    final saved = await _flushInlineWorkspace();
    if (!mounted) return;
    _isHandlingBackPop = false;
    if (!saved) return;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null) return;
    if (!navigator.canPop()) return;
    setState(() => _allowBackPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !navigator.mounted) return;
    navigator.pop(result);
  }

  Future<void> _navigateToNode(MindmapNode node) async {
    if (!await _flushInlineWorkspace() || !mounted) return;
    goToDay(context, node.day, highlightNodeId: node.id);
  }

  void _showDayStatusSheet(_DailyMissionStats stats) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: _DailyMissionDashboard(stats: stats),
          ),
        );
      },
    );
  }

  void _showDayPlanSheet(List<_DailyPlanningSuggestion> suggestions) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: suggestions.isEmpty
                ? ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Plan'),
                    subtitle: Text(
                      'No suggestions now.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : _DailyPlanningSuggestionsBar(suggestions: suggestions),
          ),
        );
      },
    );
  }

  void _showDayPulseSheet({
    required List<DayMiniInsight> insights,
    required DateTime selectedDay,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: _DayMiniInsightsStrip(
              insights: insights,
              selectedDay: selectedDay,
              onDaySelected: (day) => unawaited(() async {
                if (!await _flushInlineWorkspace()) return;
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) goToDay(context, day);
              }()),
            ),
          ),
        );
      },
    );
  }

  void _showQuickCaptureSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        void submit() {
          final query = _quickCaptureController.text.trim();
          if (query.isEmpty) return;
          Navigator.of(sheetContext).pop();
          unawaited(_submitQuickCapture(query));
        }

        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              left: 16,
              right: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Quick capture',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Type fast command. Example: task bayar listrik p1 #home.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('day-quick-capture-field'),
                    controller: _quickCaptureController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'task bayar listrik p1 #home',
                      prefixIcon: Icon(Icons.keyboard_command_key_rounded),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _QuickCaptureHint(
                        text: 'event meeting 14:00-15:00 @work',
                        controller: _quickCaptureController,
                      ),
                      _QuickCaptureHint(
                        text: 'habit workout daily',
                        controller: _quickCaptureController,
                      ),
                      _QuickCaptureHint(
                        text: 'note idea aplikasi baru #product',
                        controller: _quickCaptureController,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: submit,
                    icon: const Icon(Icons.bolt_outlined),
                    label: const Text('Capture'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitQuickCapture(String query) async {
    await _createNodeFromQuickCapture(query);
    _quickCaptureController.clear();
  }

  Future<void> _setLifeExplorerExpanded(bool expanded) async {
    setState(() => _isLifeExplorerExpanded = expanded);
    try {
      await _preferences.setBool(_lifeExplorerPreferenceKey, expanded);
    } catch (_) {
      // Platform preferences can be unavailable in widget tests.
    }
  }

  Future<void> _bindNode(MindmapNode node) async {
    if (!await _flushInlineWorkspace(node.id) || !mounted) return;
    final latest = await ref.read(mindmapRepositoryProvider).getNode(node.id);
    if (latest == null) return;
    try {
      await ref.read(collaborationProvider.notifier).bindNode(latest);
      if (mounted) _showSnackBar('Node bound to room');
    } on Object catch (error) {
      if (mounted) _showSnackBar(error.toString());
    }
  }

  Future<void> _unbindNode(MindmapNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unbind from room?'),
        content: const Text(
          'Local and room copies remain. Future sync stops, and pending local collaboration changes are discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unbind'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(collaborationProvider.notifier).unbindNode(node.id);
      if (mounted) _showSnackBar('Node unbound from room');
    } on Object catch (error) {
      if (mounted) _showSnackBar(error.toString());
    }
  }

  Future<void> _showNodeComments(MindmapNode node) async {
    final roomId = ref.read(collaborationProvider).roomId;
    if (roomId == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comments'),
        content: SizedBox(
          width: 520,
          height: 520,
          child: NodeCommentsPanel(roomId: roomId, localNodeId: node.id),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showNodeHistory(MindmapNode node) async {
    final roomId = ref.read(collaborationProvider).roomId;
    final binding = roomId == null
        ? null
        : await ref.read(
            collaborationNodeBindingProvider(
              NodeCommentThreadKey(roomId, node.id),
            ).future,
          );
    final session = ref.read(activeCollaborationSessionProvider);
    final canRestore = binding == null || session?.canWriteNodes == true;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => NodeRevisionHistoryDialog(
        nodeId: node.id,
        canRestore: canRestore,
        restoreDisabledReason: 'Commenter and viewer roles cannot restore.',
      ),
    );
  }

  Future<void> _showCanvasNodeMenu(MindmapNode node, Offset position) async {
    final session = ref.read(activeCollaborationSessionProvider);
    final binding = session == null
        ? null
        : await ref
              .read(collaborationSyncStoreProvider)
              .getBindingByLocal(session.roomId, node.id);
    final canBind =
        session?.canWriteNodes == true && dayKey(node.day) == session!.dayKey;
    if (!mounted) return;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, 0),
      items: [
        const PopupMenuItem(
          key: ValueKey('canvas-node-menu-open'),
          value: 'open',
          child: Text('Open / edit'),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Text(node.isPinned ? 'Unpin' : 'Pin'),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Text(node.isArchived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuDivider(),
        if (session != null && binding == null)
          PopupMenuItem(
            value: canBind ? 'bind' : null,
            child: const Text('Bind to room'),
          ),
        if (binding != null)
          PopupMenuItem(
            value: session!.canWriteNodes ? 'unbind' : null,
            child: const Text('Unbind from room'),
          ),
        PopupMenuItem(
          value: binding == null ? null : 'comments',
          child: const Text('Comments'),
        ),
        const PopupMenuItem(value: 'history', child: Text('Version History')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      await _selectAndFocusNode(node);
      return;
    }
    if (action == 'bind') return _bindNode(node);
    if (action == 'unbind') return _unbindNode(node);
    if (action == 'comments') return _showNodeComments(node);
    if (action == 'history') return _showNodeHistory(node);
    if (action == 'pin' || action == 'archive') {
      if (!await _withLatestNodeAfterFlush(node.id, (latest) async {
        await ref
            .read(mindmapRepositoryProvider)
            .saveNode(
              latest.copyWith(
                isPinned: action == 'pin' ? !latest.isPinned : latest.isPinned,
                isArchived: action == 'archive'
                    ? !latest.isArchived
                    : latest.isArchived,
                updatedAt: DateTime.now(),
              ),
            );
      })) {
        return;
      }
    }
    if (action == 'delete') {
      if (!await _flushInlineWorkspace(node.id)) return;
      if (!mounted) return;
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete node?'),
              content: Text('Delete “${node.title}”? This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
      if (_selectedNodeId == node.id) {
        FocusManager.instance.primaryFocus?.unfocus();
        await _clearSelectedNode(node);
        if (!mounted || _selectedNodeId == node.id) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await ref.read(mindmapRepositoryProvider).deleteNode(node.id);
    }
    invalidateMindmapState(ref, day: node.day);
  }

  Future<void> _showLifeExplorerSheet({
    required DateTime day,
    required List<MindmapNode> nodes,
    required List<MindmapNode> canvasNodes,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.88,
        child: LifeExplorer(
          day: day,
          nodes: nodes,
          selectedNodeId: _selectedNodeId,
          onNodeSelected: (node) => unawaited(() async {
            final selected = await _selectAndFocusNode(node);
            if (!selected || !sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
          }()),
          onCreateNode: (type) {
            Navigator.of(sheetContext).pop();
            unawaited(
              _createNodeOfType(context, ref, day, canvasNodes, type, null),
            );
          },
          onNodeUpdated: (node) async {
            if (!await _flushInlineWorkspace(node.id)) return;
            await ref.read(mindmapRepositoryProvider).saveNode(node);
            invalidateMindmapState(ref, day: day);
          },
          onNodeDeleted: (node) async {
            if (!await _flushInlineWorkspace(node.id)) return;
            await ref.read(mindmapRepositoryProvider).deleteNode(node.id);
            invalidateMindmapState(ref, day: day);
          },
          onCollapse: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }

  void _showQuickCreateSheet(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final titleController = TextEditingController();
        final bodyController = TextEditingController();
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Quick Create',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Node title...'),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.pop(sheetContext, 'command:${value.trim()}');
                    }
                  },
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(sheetContext).width >= 520
                      ? 5
                      : 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.25,
                  children: NodeType.values
                      .map(
                        (type) => InkWell(
                          onTap: () => Navigator.pop(
                            sheetContext,
                            '${type.name}:${titleController.text.trim()}|${bodyController.text.trim()}',
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(NodeVisuals.icon(type), size: 22),
                              const SizedBox(height: 4),
                              Text(type.label),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Optional inbox notes, context, links...',
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ).then((result) {
      if (!mounted || result == null) return;
      if (result.startsWith('command:')) {
        unawaited(
          _createNodeFromQuickCapture(
            result.substring('command:'.length).trim(),
          ),
        );
        return;
      }
      final colonIndex = result.indexOf(':');
      if (colonIndex < 0) return;
      final payload = result.substring(colonIndex + 1);
      final separatorIndex = payload.indexOf('|');
      final title = separatorIndex < 0
          ? payload.trim()
          : payload.substring(0, separatorIndex).trim();
      final body = separatorIndex < 0
          ? null
          : payload.substring(separatorIndex + 1).trim();
      final type = NodeType.values.firstWhere(
        (value) => value.name == result.substring(0, colonIndex),
        orElse: () => NodeType.task,
      );
      final day = widget.date.dateOnly;
      final currentNodes =
          ref.read(nodesForDayProvider(day)).valueOrNull ??
          const <MindmapNode>[];
      unawaited(
        _createNodeOfType(
          this.context,
          ref,
          day,
          currentNodes,
          type,
          null,
          title: title,
          body: body,
        ),
      );
    });
  }

  Future<void> _createNodeFromQuickCapture(String query) async {
    final day = widget.date.dateOnly;
    final command = quickCreateCommandFromQuery(
      query,
      today: DateTime.now().dateOnly,
      defaultDay: day,
    );
    final now = DateTime.now();
    final nodeDay = command?.day ?? day;
    final currentNodes =
        ref.read(nodesForDayProvider(nodeDay)).valueOrNull ??
        const <MindmapNode>[];
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: command?.type ?? NodeType.note,
      title: command?.title ?? query,
      day: nodeDay,
      body: command?.body ?? '',
      position: _nextNodePosition(currentNodes.length),
      status: command?.status ?? NodeStatus.open,
      priority: command?.priority ?? NodePriority.none,
      project: command?.project ?? '',
      area: command?.area ?? '',
      tags: command?.tags ?? const [],
      dueDate: command?.dueDate,
      progress: command?.progress ?? 0,
      isPinned: command?.isPinned ?? false,
      isArchived: command?.isArchived ?? false,
      checklist: [
        for (final title in command?.checklistTitles ?? const <String>[])
          TaskChecklistItem(id: const Uuid().v4(), title: title),
      ],
      relatedNodeIds: command?.relatedNodeIds ?? const [],
      data: command?.data ?? const {},
      now: now,
    );
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(node);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    invalidateMindmapState(ref, day: nodeDay, extraDay: day);
    if (mounted) {
      if (nodeDay != day) {
        if (!await _flushInlineWorkspace() || !mounted) return;
        context.go('/calendar/${dayKey(nodeDay)}?highlight=${node.id}');
        _showSnackBar(
          'Captured ${node.type.label.toLowerCase()} for ${dayKey(nodeDay)}',
        );
        return;
      }
      if (await _selectNode(node) && mounted) {
        _showSnackBar('Captured ${node.type.label.toLowerCase()}');
      }
    }
  }

  Future<void> _applyRoutines(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final plan = await previewRecurringRoutines(
      repository: repository,
      day: day,
      now: DateTime.now(),
    );
    if (!context.mounted) return;

    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (context) => _RoutinePreviewDialog(plan: plan),
    );
    if (shouldApply != true || !context.mounted) return;

    await applyRecurringRoutines(
      repository: repository,
      day: day,
      now: DateTime.now(),
    );
    invalidateMindmapState(ref, day: day);
    if (context.mounted) _showSnackBar('Routines applied');
  }

  Future<void> _showCanvasProductivityNodeMenu(
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> currentNodes, {
    Offset canvasPosition = const Offset(96, 96),
  }) => _showCanvasAddNodeMenuAtAnchor(
    ref,
    day,
    currentNodes,
    const Offset(80, 96),
    canvasPosition: canvasPosition,
  );

  Future<void> _showCanvasAddNodeMenuAtAnchor(
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> currentNodes,
    Offset panelAnchor, {
    Offset canvasPosition = const Offset(96, 96),
  }) async {
    if (_isCanvasAddNodeMenuOpen) return;
    _isCanvasAddNodeMenuOpen = true;
    try {
      await _showCanvasAddNodeMenu(
        context,
        ref,
        day,
        currentNodes,
        panelAnchor,
        canvasPosition,
        direct: true,
      );
    } finally {
      _isCanvasAddNodeMenuOpen = false;
    }
  }

  Future<CanvasContextAction?> _showCanvasContextFolderMenu(
    BuildContext context,
    Offset globalPosition,
  ) {
    final tokens = AppDesignTokens.of(context);
    return showGeneralDialog<CanvasContextAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss canvas menu',
      barrierColor: Colors.transparent,
      transitionDuration: tokens.effectiveDuration(context, tokens.motionFast),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _CanvasContextCascadeMenu(origin: globalPosition);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  Future<void> _showCanvasAddNodeMenu(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> currentNodes,
    Offset globalPosition,
    Offset canvasPosition, {
    bool direct = false,
  }) async {
    final action = direct
        ? CanvasContextAction.createNode
        : await _showCanvasContextFolderMenu(context, globalPosition);
    if (action == null || !context.mounted) return;
    if (action == CanvasContextAction.quickTask ||
        action == CanvasContextAction.quickNote) {
      await _createNodeOfType(
        context,
        ref,
        day,
        currentNodes,
        action == CanvasContextAction.quickTask ? NodeType.task : NodeType.note,
        canvasPosition,
      );
      return;
    }
    if (action != CanvasContextAction.createNode) {
      await _canvasKey.currentState?.runContextAction(
        action,
        scenePosition: canvasPosition,
      );
      return;
    }

    const panelWidth = 560.0;
    const panelHeight = 374.0;
    const margin = 12.0;
    final screenSize = MediaQuery.sizeOf(context);
    final left = globalPosition.dx.clamp(
      margin,
      (screenSize.width - panelWidth - margin).clamp(margin, screenSize.width),
    );
    final top = globalPosition.dy.clamp(
      margin,
      (screenSize.height - panelHeight - margin).clamp(
        margin,
        screenSize.height,
      ),
    );

    final selectedType = await showGeneralDialog<NodeType>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              child: _CanvasAddNodeContextPanel(
                types: const [
                  ..._canvasPrimaryAddTypes,
                  ..._canvasMoreAddTypes,
                ],
                onSelect: (NodeType type) => Navigator.of(context).pop(type),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
    );
    if (selectedType == null || !context.mounted) return;
    await _createNodeOfType(
      context,
      ref,
      day,
      currentNodes,
      selectedType,
      canvasPosition,
    );
  }

  static const List<NodeType> _canvasPrimaryAddTypes = [
    NodeType.task,
    NodeType.note,
    NodeType.event,
    NodeType.idea,
    NodeType.question,
    NodeType.bookmark,
  ];

  static const List<NodeType> _canvasMoreAddTypes = [
    NodeType.decision,
    NodeType.resource,
    NodeType.plan,
    NodeType.habit,
    NodeType.goal,
    NodeType.contact,
    NodeType.metric,
    NodeType.expense,
    NodeType.routine,
    NodeType.kanban,
    NodeType.mood,
    NodeType.timer,
    NodeType.quote,
    NodeType.audio,
    NodeType.checklist,
    NodeType.canvas,
    NodeType.weather,
    NodeType.fit,
    NodeType.itinerary,
    NodeType.image,
    NodeType.video,
  ];

  Future<void> _clearMindmapNodes(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> nodes,
  ) async {
    if (nodes.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear mindmap nodes?'),
        content: Text(
          'This will delete ${nodes.length} node${nodes.length == 1 ? '' : 's'} from this day. You can undo them one by one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear nodes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!await _flushInlineWorkspace()) return;

    final repository = ref.read(mindmapRepositoryProvider);
    for (final node in nodes) {
      _pushUndo(
        _UndoEntry(kind: _UndoKind.delete, nodeId: node.id, before: node),
      );
      await repository.deleteNode(node.id);
    }
    invalidateMindmapState(ref, day: day);
    if (!context.mounted) return;
    await _clearSelection();
    _showSnackBar('Cleared ${nodes.length} nodes');
  }

  Future<MindmapNode?> _createNodeOfType(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> currentNodes,
    NodeType type,
    Offset? position, {
    String? title,
    String? body,
    NodePriority priority = NodePriority.none,
    List<String> tags = const [],
  }) async {
    ImagePayload? imagePayload;
    VideoPayload? videoPayload;
    if (type == NodeType.image) {
      imagePayload = await _showImageUrlImportDialog(context);
      if (imagePayload == null) return null;
    }
    if (type == NodeType.video) {
      if (!context.mounted) return null;
      videoPayload = await _showVideoUrlImportDialog(context);
      if (videoPayload == null) return null;
    }
    final now = DateTime.now();

    // Default values
    final nodeTitle = title == null || title.trim().isEmpty
        ? 'New ${type.label}'
        : title.trim();

    // If no position is provided (clicked from palette), use the viewport center
    final CanvasPosition pos;
    if (position != null) {
      pos = CanvasPosition(position.dx, position.dy);
    } else {
      final center = _canvasKey.currentState?.viewportCenter;
      if (center != null) {
        // Offset slightly if there are many nodes to prevent perfect overlap
        final offsetNodes = currentNodes.length * 10.0;
        pos = CanvasPosition(center.dx + offsetNodes, center.dy + offsetNodes);
      } else {
        pos = _nextNodePosition(currentNodes.length);
      }
    }

    final String bodyTemplate = switch (type) {
      NodeType.task => '- [ ] ',
      NodeType.kanban => 'Add description or context for this kanban board...',
      NodeType.plan => '## Objectives\n- \n\n## Action Items\n- [ ] ',
      NodeType.note => 'Write your notes here...',
      NodeType.journal => '## Daily Entry\n\nHow was your day?',
      NodeType.habit => 'Track your habit progress here.',
      NodeType.goal => '## Target\n\n## Motivation\n',
      NodeType.link => 'https://',
      NodeType.event => '## Agenda\n- \n\n## Notes\n',
      NodeType.decision => '## Decision\n\n## Options\n- \n\n## Rationale\n',
      NodeType.resource => '## Resource\n\nURL or reference:\n',
      NodeType.idea => '## Spark\n\n## Why it matters\n\n## Next experiment\n',
      NodeType.question =>
        '## Question\n\n## Context\n\n## Possible answers\n- ',
      NodeType.contact => '## Contact\n\nName:\nRole:\nEmail:\nNotes:\n',
      NodeType.metric => '## Metric\n\nValue:\nUnit:\nTrend:\n',
      NodeType.expense => '## Expense\n\nAmount:\nCategory:\nNotes:\n',
      NodeType.bookmark => '## Bookmark\n\nURL:\nWhy saved:\n',
      NodeType.routine => '## Routine\n\nTrigger:\nSteps:\n- ',
      NodeType.mood =>
        '## Mood & Energy\n\nMood: 🙂\nEnergy: 3/5\nTrigger:\nNotes:',
      NodeType.timer =>
        '## Focus Session\n\nFocus: \nDistraction log:\n- \nDone: false',
      NodeType.quote => '“Quote text here.”',
      NodeType.audio =>
        '## Voice Recording\n\nPath: \nDuration: 0:00\nNotes/Transcript:\n- ',
      NodeType.checklist =>
        '## Checklist\n- [ ] Task 1\n- [ ] Task 2\n- [ ] Task 3',
      NodeType.canvas => '## Sketchpad\n\nDrawings & sketches.',
      NodeType.weather =>
        '## Weather Report\n\nTemp: 25°C\nWeather: Sunny\nMood impact: ',
      NodeType.fit => '## Fitness Notes\n\nHow it felt:\nRecovery:',
      NodeType.empty => '',
      NodeType.itinerary =>
        '## Trip\n\nDestination:\nStart date:\nEnd date:\n\n## Agenda\n- ',
      NodeType.image => '## Image\n\nSource:\nAlt text:\nCaption:',
      NodeType.video => '## Video\n\nSource:\nCaption:\nDuration:',
      NodeType.frame => '## Frame\n\nNotes:',
      _ => '',
    };

    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: type,
      title: nodeTitle,
      body: body == null || body.trim().isEmpty ? bodyTemplate : body.trim(),
      day: day,
      position: pos,
      priority: priority,
      tags: tags,
      data: imagePayload?.toData() ?? videoPayload?.toData() ?? const {},
      now: now,
    );

    final repository = ref.read(mindmapRepositoryProvider);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    try {
      await repository.saveNode(node);
      invalidateMindmapState(ref, day: day);

      if (context.mounted) {
        if (await _selectNode(node) && mounted) {
          _showSnackBar('${type.label} created');
        }
      }

      // Automatically pan the mindmap to focus on the newly created node
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _canvasKey.currentState?.focusOnPosition(pos);
      });
      return node;
    } catch (e) {
      if (context.mounted) _showSnackBar('Failed to create node: $e');
      return null;
    }
  }

  Future<ImagePayload?> _showImageUrlImportDialog(
    BuildContext context, {
    ImagePayload existing = const ImagePayload(),
  }) async {
    var url = existing.url;
    var caption = existing.caption;
    var altText = existing.altText;
    String? error;
    var importing = false;
    final result = await showDialog<ImagePayload>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add image'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('image-import-url'),
                  initialValue: url,
                  onChanged: (value) => url = value,
                  decoration: InputDecoration(
                    labelText: 'Image URL',
                    hintText: 'https://example.com/image.png',
                    errorText: error,
                  ),
                ),
                TextFormField(
                  key: const ValueKey('image-import-caption'),
                  initialValue: caption,
                  onChanged: (value) => caption = value,
                  decoration: const InputDecoration(labelText: 'Caption'),
                ),
                TextFormField(
                  key: const ValueKey('image-import-alt'),
                  initialValue: altText,
                  onChanged: (value) => altText = value,
                  decoration: const InputDecoration(
                    labelText: 'Alt text',
                    helperText: 'Describe image for accessibility',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  key: const ValueKey('image-import-local'),
                  enabled: !importing,
                  leading: importing
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  title: const Text('Import local image'),
                  subtitle: const Text('GIF, JPG, PNG, or WebP up to 100 MB'),
                  onTap: () async {
                    setDialogState(() {
                      importing = true;
                      error = null;
                    });
                    try {
                      final service = await ref.read(
                        mediaFileImportServiceProvider.future,
                      );
                      final payload = await service.pickImage(
                        existing: existing.copyWith(
                          caption: caption.trim(),
                          altText: altText.trim(),
                        ),
                      );
                      if (payload != null && dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(payload);
                        return;
                      }
                    } on FormatException catch (exception) {
                      error = exception.message;
                    } on Object {
                      error = 'Unable to import selected image.';
                    }
                    if (dialogContext.mounted) {
                      setDialogState(() => importing = false);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('image-import-submit'),
              onPressed: () {
                final payload = existing.copyWith(
                  url: url.trim(),
                  caption: caption.trim(),
                  altText: altText.trim(),
                  mimeType: '',
                  fileName: '',
                  clearAttachment: true,
                );
                final errors = payload.validate(title: 'Image');
                if (errors.isNotEmpty) {
                  setDialogState(() => error = errors.first);
                  return;
                }
                Navigator.of(dialogContext).pop(payload);
              },
              child: const Text('Add image'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<VideoPayload?> _showVideoUrlImportDialog(
    BuildContext context, {
    VideoPayload existing = const VideoPayload(),
  }) async {
    var url = existing.url;
    var caption = existing.caption;
    var altText = existing.altText;
    String? error;
    var importing = false;
    return showDialog<VideoPayload>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add video'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('video-import-url'),
                  initialValue: url,
                  onChanged: (value) => url = value,
                  decoration: InputDecoration(
                    labelText: 'Video URL',
                    hintText: 'https://example.com/video.mp4',
                    errorText: error,
                  ),
                ),
                TextFormField(
                  key: const ValueKey('video-import-caption'),
                  initialValue: caption,
                  onChanged: (value) => caption = value,
                  decoration: const InputDecoration(labelText: 'Caption'),
                ),
                TextFormField(
                  key: const ValueKey('video-import-alt'),
                  initialValue: altText,
                  onChanged: (value) => altText = value,
                  decoration: const InputDecoration(labelText: 'Alt text'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  key: const ValueKey('video-import-local'),
                  enabled: !importing,
                  leading: importing
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.video_file_outlined),
                  title: const Text('Import local video'),
                  subtitle: const Text('MP4, MOV, or WebM up to 100 MB'),
                  onTap: () async {
                    setDialogState(() {
                      importing = true;
                      error = null;
                    });
                    try {
                      final service = await ref.read(
                        mediaFileImportServiceProvider.future,
                      );
                      final payload = await service.pickVideo(
                        existing: existing.copyWith(
                          caption: caption.trim(),
                          altText: altText.trim(),
                        ),
                      );
                      if (payload != null && dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(payload);
                        return;
                      }
                    } on FormatException catch (exception) {
                      error = exception.message;
                    } on Object {
                      error = 'Unable to import selected video.';
                    }
                    if (dialogContext.mounted) {
                      setDialogState(() => importing = false);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('video-import-submit'),
              onPressed: () {
                final payload = existing.copyWith(
                  url: url.trim(),
                  caption: caption.trim(),
                  altText: altText.trim(),
                  mimeType: '',
                  fileName: '',
                  clearAttachment: true,
                );
                final errors = payload.validate(title: 'Video');
                if (errors.isNotEmpty) {
                  setDialogState(() => error = errors.first);
                  return;
                }
                Navigator.of(dialogContext).pop(payload);
              },
              child: const Text('Add video'),
            ),
          ],
        ),
      ),
    );
  }

  Duration get _focusElapsed {
    final startedAt = _focusStartedAt;
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt);
  }

  Duration? get _focusRemaining {
    final targetMinutes = _focusTargetMinutes;
    if (targetMinutes == null || _focusStartedAt == null) return null;
    final remaining = Duration(minutes: targetMinutes) - _focusElapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _showInboxSheet(
    BuildContext context,
    List<MindmapNode> inboxNodes,
    DateTime day,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: inboxNodes.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('Inbox'),
                  subtitle: Text('${inboxNodes.length} loose captures'),
                );
              }
              final node = inboxNodes[index - 1];
              return ListTile(
                leading: Icon(NodeVisuals.icon(node.type)),
                title: Text(
                  node.title.trim().isEmpty ? 'Untitled' : node.title,
                ),
                subtitle: Text(node.type.label),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Assign today',
                      icon: const Icon(Icons.today_outlined),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _assignInboxNode(node, day);
                      },
                    ),
                    IconButton(
                      tooltip: 'Assign tomorrow',
                      icon: const Icon(Icons.event_available_outlined),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _assignInboxNode(
                          node,
                          day.add(const Duration(days: 1)),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Archive',
                      icon: const Icon(Icons.archive_outlined),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _archiveInboxNode(node, day);
                      },
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_selectNode(node));
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _assignInboxNode(MindmapNode node, DateTime day) async {
    await _withLatestNodeAfterFlush(node.id, (latest) async {
      final updated = assignInboxNodeToDay(latest, day);
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.save,
          nodeId: latest.id,
          before: latest,
          after: updated,
        ),
      );
      await ref.read(mindmapRepositoryProvider).saveNode(updated);
      invalidateMindmapState(ref, day: latest.day, extraDay: updated.day);
      if (mounted) _showSnackBar('Inbox item assigned');
    });
  }

  Future<void> _archiveInboxNode(MindmapNode node, DateTime day) async {
    await _withLatestNodeAfterFlush(node.id, (latest) async {
      final updated = latest.copyWith(
        isArchived: true,
        updatedAt: DateTime.now(),
      );
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.save,
          nodeId: latest.id,
          before: latest,
          after: updated,
        ),
      );
      await ref.read(mindmapRepositoryProvider).saveNode(updated);
      invalidateMindmapState(ref, day: latest.day, extraDay: day);
      if (mounted) _showSnackBar('Inbox item archived');
    });
  }

  List<_SelectedNodeAction> _selectedNodeActions(MindmapNode node) {
    return [
      if (!node.isDone)
        _SelectedNodeAction(
          icon: Icons.check_circle_outline,
          label: 'Mark done',
          onPressed: () => unawaited(_markSelectedNodeDone(node)),
        ),
      if (node.type != NodeType.task)
        _SelectedNodeAction(
          icon: Icons.check_box_outlined,
          label: 'Convert to task',
          onPressed: () => unawaited(_convertSelectedNodeToTask(node)),
        ),
      _SelectedNodeAction(
        icon: Icons.event_available_outlined,
        label: 'Schedule',
        onPressed: () => unawaited(_scheduleSelectedNode(node)),
      ),
      if (node.checklist.isEmpty)
        _SelectedNodeAction(
          icon: Icons.playlist_add_check_outlined,
          label: 'Split checklist',
          onPressed: () => unawaited(_splitSelectedNodeIntoChecklist(node)),
        ),
      _SelectedNodeAction(
        icon: Icons.add_task_outlined,
        label: 'Follow-up',
        onPressed: () => unawaited(_createSelectedNodeFollowUp(node)),
      ),
      _SelectedNodeAction(
        icon: Icons.hub_outlined,
        label: 'Link related',
        onPressed: () => unawaited(_showNodeLinkPicker(node)),
      ),
      _SelectedNodeAction(
        icon: Icons.next_plan_outlined,
        label: 'Tomorrow',
        onPressed: () => unawaited(_moveSelectedNodeToTomorrow(node)),
      ),
      _SelectedNodeAction(
        icon: Icons.rate_review_outlined,
        label: 'Review note',
        onPressed: () => unawaited(_createSelectedNodeReviewNote(node)),
      ),
    ];
  }

  Future<void> _saveSelectedNodeAction(
    MindmapNode before,
    MindmapNode after,
    String message, {
    DateTime? extraDay,
  }) async {
    final actionPatch = InlineNodeDraftPatch.between(before, after);
    await _withLatestNodeAfterFlush(before.id, (latest) async {
      final updated = actionPatch.mergeInto(latest, DateTime.now());
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.save,
          nodeId: latest.id,
          before: latest,
          after: updated,
        ),
      );
      await ref.read(mindmapRepositoryProvider).saveNode(updated);
      invalidateMindmapState(
        ref,
        day: latest.day,
        extraDay: extraDay ?? updated.day,
      );
      if (mounted) _showSnackBar(message);
    });
  }

  Future<bool> _withLatestNodeAfterFlush(
    String nodeId,
    Future<void> Function(MindmapNode latest) action,
  ) async {
    if (!await _flushInlineWorkspace()) return false;
    final saved = await _inlineWorkspaceController.flushThenMutateLatest(
      nodeId,
      action,
    );
    if (!saved && mounted) _showSnackBar('Node no longer exists');
    return saved;
  }

  Future<bool> _flushInlineWorkspace([String? nodeId]) async {
    final saved = await ref
        .read(inlineNodeWorkspaceControllerProvider.notifier)
        .flush(nodeId);
    if (!saved && mounted) _showSnackBar('Save draft before continuing');
    return saved;
  }

  Future<void> _convertSelectedNodeToTask(MindmapNode node) async {
    await _saveSelectedNodeAction(
      node,
      node.copyWith(type: NodeType.task, updatedAt: DateTime.now()),
      'Converted to task',
    );
  }

  Future<void> _scheduleSelectedNode(MindmapNode node) async {
    final pickedDay = await showDatePicker(
      context: context,
      initialDate: node.day,
      firstDate: DateTime(node.day.year - 1),
      lastDate: DateTime(node.day.year + 3),
    );
    if (pickedDay == null) return;
    await _saveSelectedNodeAction(
      node,
      node.copyWith(
        day: pickedDay.dateOnly,
        dueDate: pickedDay.dateOnly,
        updatedAt: DateTime.now(),
      ),
      'Scheduled to ${dayKey(pickedDay)}',
      extraDay: pickedDay.dateOnly,
    );
  }

  Future<void> _splitSelectedNodeIntoChecklist(MindmapNode node) async {
    await _withLatestNodeAfterFlush(node.id, (latest) async {
      final lines = latest.body
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^[-*]\s*'), '').trim())
          .where((line) => line.isNotEmpty)
          .take(8)
          .toList();
      final titles = lines.isEmpty ? [latest.title] : lines;
      final updated = latest.copyWith(
        checklist: [
          for (final title in titles)
            TaskChecklistItem(id: const Uuid().v4(), title: title),
        ],
        updatedAt: DateTime.now(),
      );
      await ref.read(mindmapRepositoryProvider).saveNode(updated);
      invalidateMindmapState(ref, day: latest.day);
      if (mounted) _showSnackBar('Checklist created');
    });
  }

  Future<void> _createSelectedNodeFollowUp(MindmapNode node) async {
    await _withLatestNodeAfterFlush(node.id, (latest) async {
      final now = DateTime.now();
      final followUp = MindmapNode.create(
        id: const Uuid().v4(),
        type: NodeType.task,
        title: 'Follow-up: ${latest.title}',
        day: latest.day,
        position: CanvasPosition(
          latest.position.dx + 260,
          latest.position.dy + 80,
        ),
        priority: latest.priority,
        project: latest.project,
        area: latest.area,
        tags: latest.tags,
        relatedNodeIds: [latest.id],
        dueDate: latest.dueDate,
        now: now,
      );
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.create,
          nodeId: followUp.id,
          after: followUp,
        ),
      );
      await ref.read(mindmapRepositoryProvider).saveNode(followUp);
      invalidateMindmapState(ref, day: latest.day);
      if (mounted) _showSnackBar('Follow-up created');
    });
  }

  Future<void> _moveSelectedNodeToTomorrow(MindmapNode node) async {
    final tomorrow = node.day.add(const Duration(days: 1)).dateOnly;
    await _saveSelectedNodeAction(
      node,
      node.copyWith(
        day: tomorrow,
        dueDate: tomorrow,
        updatedAt: DateTime.now(),
      ),
      'Moved to tomorrow',
      extraDay: tomorrow,
    );
  }

  Future<void> _markSelectedNodeDone(MindmapNode node) async {
    await _saveSelectedNodeAction(
      node,
      node.copyWith(
        isDone: true,
        status: NodeStatus.done,
        progress: 1,
        updatedAt: DateTime.now(),
      ),
      'Marked done',
    );
  }

  Future<void> _createSelectedNodeReviewNote(MindmapNode node) async {
    await _withLatestNodeAfterFlush(node.id, (latest) async {
      final now = DateTime.now();
      final review = MindmapNode.create(
        id: const Uuid().v4(),
        type: NodeType.journal,
        title: 'Review: ${latest.title}',
        day: latest.day,
        body:
            '## Review\n\n- What happened?\n- What changed?\n- Next action?\n',
        position: CanvasPosition(
          latest.position.dx + 260,
          latest.position.dy + 160,
        ),
        tags: const ['review'],
        relatedNodeIds: [latest.id],
        now: now,
      );
      _pushUndo(
        _UndoEntry(kind: _UndoKind.create, nodeId: review.id, after: review),
      );
      await ref.read(mindmapRepositoryProvider).saveNode(review);
      invalidateMindmapState(ref, day: latest.day);
      if (mounted) _showSnackBar('Review note created');
    });
  }

  Future<void> _showNodeLinkPicker(MindmapNode node) async {
    final nodes = (ref.read(nodesForDayProvider(node.day)).valueOrNull ?? [])
        .where((candidate) => candidate.id != node.id && !candidate.isArchived)
        .toList();
    if (nodes.isEmpty) {
      _showSnackBar('No nodes to link');
      return;
    }
    final picked = await showModalBottomSheet<MindmapNode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              leading: Icon(Icons.hub_outlined),
              title: Text('Link related node'),
            ),
            for (final candidate in nodes.take(12))
              ListTile(
                leading: Icon(NodeVisuals.icon(candidate.type)),
                title: Text(candidate.title),
                subtitle: Text(candidate.type.label),
                onTap: () => Navigator.of(context).pop(candidate),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final related = {...node.relatedNodeIds, picked.id}.toList();
    await _saveSelectedNodeAction(
      node,
      node.copyWith(relatedNodeIds: related, updatedAt: DateTime.now()),
      'Linked related node',
    );
  }

  Future<void> _showCustomFocusDialog(MindmapNode node) async {
    final controller = TextEditingController(text: '30');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Custom focus'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minutes',
              hintText: '30',
            ),
            onSubmitted: (_) {
              final value = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                Navigator.of(context).pop(value);
              },
              child: const Text('Start'),
            ),
          ],
        );
      },
    );
    _disposeTextControllerAfterRouteFrame(controller);
    if (minutes == null || minutes <= 0) return;
    _startFocusSession(node, targetMinutes: minutes);
  }

  void _startFocusSession(MindmapNode node, {int? targetMinutes}) {
    _focusTicker?.cancel();
    setState(() {
      _focusStartedAt = DateTime.now();
      _focusNodeId = node.id;
      _focusTargetMinutes = targetMinutes;
      _focusTargetNotified = false;
    });
    _focusTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _focusRemaining;
      if (remaining == Duration.zero && !_focusTargetNotified) {
        _focusTargetNotified = true;
        _showSnackBar('Focus block complete');
      }
      setState(() {});
    });
  }

  Future<void> _toggleTodayMission(MindmapNode node) async {
    final willAdd = !isTodayMission(node);
    if (willAdd) {
      final dayNodes = ref.read(nodesForDayProvider(node.day)).valueOrNull;
      if (dayNodes != null && !canAddTodayMission(dayNodes, node)) {
        if (mounted) _showSnackBar('Mission limit reached (3 nodes)');
        return;
      }
    }
    final repository = ref.read(mindmapRepositoryProvider);
    final updated = markTodayMission(node, isMission: willAdd);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.save,
        nodeId: node.id,
        before: node,
        after: updated,
      ),
    );
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day);
    if (mounted) {
      _showSnackBar(
        isTodayMission(updated) ? 'Added to mission' : 'Removed from mission',
      );
    }
  }

  Future<void> _stopFocusSession(MindmapNode node) async {
    final startedAt = _focusStartedAt;
    if (startedAt == null) return;
    final endedAt = DateTime.now();
    final updated = addFocusSession(
      node,
      startedAt: startedAt,
      endedAt: endedAt,
    );
    _focusTicker?.cancel();
    setState(() {
      _focusStartedAt = null;
      _focusNodeId = null;
      _focusTargetMinutes = null;
      _focusTargetNotified = false;
    });
    if (updated == node) return;
    final repository = ref.read(mindmapRepositoryProvider);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.save,
        nodeId: node.id,
        before: node,
        after: updated,
      ),
    );
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day);
    if (mounted) _showSnackBar('Focus session saved');
  }
}

List<MindmapNode> _canvasNodesFor({
  required List<MindmapNode> activeNodes,
  required List<MindmapNode> allNodes,
  required DateTime day,
  required String? highlightedNodeId,
}) {
  if (highlightedNodeId == null ||
      activeNodes.any((node) => node.id == highlightedNodeId)) {
    return activeNodes;
  }

  for (final node in allNodes) {
    if (node.id == highlightedNodeId &&
        node.isArchived &&
        node.day.isSameDay(day)) {
      return List.unmodifiable([...activeNodes, node]);
    }
  }

  return activeNodes;
}

class _InlineWorkspaceTitle extends StatefulWidget {
  const _InlineWorkspaceTitle({
    required this.customTitle,
    required this.displayTitle,
    required this.onTitleChanged,
  });

  final String? customTitle;
  final String displayTitle;
  final Future<void> Function(String title) onTitleChanged;

  @override
  State<_InlineWorkspaceTitle> createState() => _InlineWorkspaceTitleState();
}

class _InlineWorkspaceTitleState extends State<_InlineWorkspaceTitle> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  bool _isEditing = false;
  bool _isSaving = false;
  String _lastSubmitted = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.customTitle ?? '');
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
    _lastSubmitted = widget.customTitle ?? '';
  }

  @override
  void didUpdateWidget(covariant _InlineWorkspaceTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTitle = widget.customTitle ?? '';
    if (!_isEditing && _controller.text != nextTitle) {
      _controller.text = nextTitle;
      _lastSubmitted = nextTitle;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus && _isEditing) {
      _submit();
    }
  }

  void _startEditing() {
    setState(() => _isEditing = true);
    _controller.text = widget.customTitle ?? widget.displayTitle;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    final nextTitle = _controller.text.trim();
    if (_isSaving || nextTitle == _lastSubmitted) {
      setState(() => _isEditing = false);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.onTitleChanged(nextTitle);
      _lastSubmitted = nextTitle;
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _cancelEditing() {
    _controller.text = widget.customTitle ?? '';
    setState(() => _isEditing = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final active = _isEditing || _isHovered;
    final borderColor = _isEditing
        ? semantic.focusRing
        : active
        ? semantic.borderStrong
        : semantic.border;
    final bgColor = _isEditing
        ? semantic.surfaceRaised
        : active
        ? semantic.accentMuted
        : semantic.surfaceRaised;

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: tokens.effectiveDuration(context, tokens.motionFast),
        curve: tokens.motionCurve,
        constraints: BoxConstraints(minHeight: tokens.minimumTarget),
        padding: EdgeInsets.only(
          left: _isEditing ? tokens.spacing[4] : tokens.spacing[5],
          right: _isEditing ? tokens.spacing[3] : tokens.spacing[4],
        ),
        decoration: ShapeDecoration(
          color: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppDesignTokens.of(context).radiusContainer,
            ),
            side: BorderSide(color: borderColor),
          ),
        ),
        child: _isEditing
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: semantic.surfaceSunken,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusElement,
                            ),
                            side: BorderSide(color: semantic.border),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.spacing[3],
                          ),
                          child: TextField(
                            key: const ValueKey('day-inline-title-field'),
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            minLines: 1,
                            maxLines: 1,
                            textInputAction: TextInputAction.done,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: semantic.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                            cursorColor: semantic.accent,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Rename day',
                              hintStyle: TextStyle(
                                color: semantic.textDisabled,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: tokens.spacing[2],
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_isSaving) ...[
                    const SizedBox(width: 8),
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ] else ...[
                    SizedBox(width: tokens.spacing[2]),
                    IconButton.filled(
                      tooltip: 'Save title',
                      style: IconButton.styleFrom(
                        minimumSize: Size.square(tokens.controlMedium),
                        maximumSize: Size.square(tokens.controlMedium),
                        backgroundColor: semantic.accent,
                        foregroundColor: semantic.onAccent,
                      ),
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded, size: 17),
                    ),
                    SizedBox(width: tokens.spacing[2]),
                    IconButton(
                      tooltip: 'Cancel',
                      style: IconButton.styleFrom(
                        minimumSize: Size.square(tokens.controlMedium),
                        maximumSize: Size.square(tokens.controlMedium),
                        backgroundColor: semantic.surfaceSunken,
                        foregroundColor: semantic.textSecondary,
                        side: BorderSide(color: semantic.border),
                      ),
                      onPressed: _cancelEditing,
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                  ],
                ],
              )
            : InkWell(
                key: const ValueKey('day-inline-title-display'),
                borderRadius: BorderRadius.circular(tokens.radiusElement),
                onTap: _startEditing,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: tokens.effectiveDuration(
                          context,
                          tokens.motionFast,
                        ),
                        opacity: active ? 1 : 0,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _CanvasAddNodeContextPanel extends StatefulWidget {
  const _CanvasAddNodeContextPanel({
    required this.types,
    required this.onSelect,
  });

  final List<NodeType> types;
  final ValueChanged<NodeType> onSelect;

  @override
  State<_CanvasAddNodeContextPanel> createState() =>
      _CanvasAddNodeContextPanelState();
}

class _CanvasAddNodeContextPanelState
    extends State<_CanvasAddNodeContextPanel> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _listScrollController;
  String _query = '';
  _CanvasAddNodeFolder? _hoveredFolder;
  _CanvasAddNodeFolder? _lockedFolder;
  int _activeTypeIndex = 0;

  static const List<_CanvasAddNodeFolder> _folders = [
    _CanvasAddNodeFolder('Action', Icons.bolt_outlined, [
      NodeType.task,
      NodeType.kanban,
      NodeType.plan,
      NodeType.checklist,
      NodeType.routine,
    ]),
    _CanvasAddNodeFolder('Thinking', Icons.psychology_alt_outlined, [
      NodeType.note,
      NodeType.idea,
      NodeType.question,
      NodeType.decision,
      NodeType.quote,
    ]),
    _CanvasAddNodeFolder('Knowledge', Icons.menu_book_outlined, [
      NodeType.resource,
      NodeType.bookmark,
      NodeType.link,
      NodeType.journal,
      NodeType.audio,
    ]),
    _CanvasAddNodeFolder('Life', Icons.local_florist_outlined, [
      NodeType.habit,
      NodeType.routine,
      NodeType.goal,
      NodeType.event,
      NodeType.mood,
      NodeType.fit,
      NodeType.weather,
      NodeType.canvas,
    ]),
    _CanvasAddNodeFolder('People & Data', Icons.scatter_plot_outlined, [
      NodeType.contact,
      NodeType.metric,
      NodeType.expense,
      NodeType.timer,
      NodeType.empty,
    ]),
    _CanvasAddNodeFolder('Media & Travel', Icons.travel_explore_outlined, [
      NodeType.itinerary,
      NodeType.image,
      NodeType.video,
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _listScrollController = ScrollController();
    _searchController.addListener(
      () => setState(() {
        _query = _searchController.text.trim().toLowerCase();
        _activeTypeIndex = 0;
      }),
    );
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  List<NodeType> get _allFolderTypes => [
    for (final f in _folders)
      for (final t in f.types)
        if (widget.types.contains(t)) t,
  ];
  static const Map<NodeType, List<String>> _synonyms = {
    NodeType.mood: [
      'mood',
      'feelings',
      'journal',
      'emotion',
      'mental',
      'energy',
    ],
    NodeType.timer: [
      'timer',
      'pomodoro',
      'focus',
      'countdown',
      'clock',
      'time',
    ],
    NodeType.quote: ['quote', 'inspiration', 'author', 'words', 'motivation'],
    NodeType.audio: ['audio', 'voice', 'record', 'recording', 'memo', 'sound'],
    NodeType.checklist: ['checklist', 'todo', 'list', 'tasks', 'items'],
    NodeType.canvas: ['canvas', 'draw', 'sketch', 'paint', 'art'],
    NodeType.weather: ['weather', 'temp', 'forecast', 'temperature', 'sky'],
    NodeType.fit: [
      'fit',
      'steps',
      'water',
      'workout',
      'health',
      'exercise',
      'gym',
    ],
  };

  List<NodeType> get _visibleTypes {
    if (_query.isNotEmpty) {
      return _allFolderTypes
          .where(
            (t) =>
                t.label.toLowerCase().contains(_query) ||
                t.name.contains(_query) ||
                (_synonyms[t]?.any((s) => s.contains(_query)) ?? false),
          )
          .toList(growable: false);
    }
    return (_lockedFolder ?? _hoveredFolder)?.types
            .where(widget.types.contains)
            .toList(growable: false) ??
        const [];
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.slash) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    final types = _visibleTypes;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && types.isNotEmpty) {
      setState(() => _activeTypeIndex = (_activeTypeIndex + 1) % types.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && types.isNotEmpty) {
      setState(() => _activeTypeIndex = (_activeTypeIndex - 1) % types.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && types.isNotEmpty) {
      widget.onSelect(types[_activeTypeIndex.clamp(0, types.length - 1)]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_query.isNotEmpty) {
        _searchController.clear();
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 600;
    final panelWidth = isCompact ? size.width - 24 : 560.0;
    final types = _visibleTypes;
    if (_activeTypeIndex >= types.length) _activeTypeIndex = 0;
    final activeFolder = _query.isEmpty
        ? _lockedFolder ?? _hoveredFolder
        : null;

    final folderListWidget = Column(
      children: [
        for (final folder in _folders) ...[
          _CanvasAddNodeFolderTile(
            folder: folder,
            selected: _lockedFolder == folder,
            previewed: _hoveredFolder == folder,
            onEnter: () => setState(() {
              _hoveredFolder = folder;
              _activeTypeIndex = 0;
            }),
            onExit: () => setState(() => _hoveredFolder = null),
            onPressed: () => setState(() {
              _lockedFolder = folder;
              _activeTypeIndex = 0;
            }),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );

    final typeListWidget = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: isCompact ? 180 : 252),
      child: types.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  _query.isEmpty ? 'Pick a folder' : 'No node type found',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Scrollbar(
              controller: _listScrollController,
              thumbVisibility: types.length > 4,
              child: ListView.separated(
                controller: _listScrollController,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: types.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _CanvasAddNodeTypeTile(
                  type: types[i],
                  active: i == _activeTypeIndex,
                  onPressed: () => widget.onSelect(types[i]),
                ),
              ),
            ),
    );

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const ValueKey('canvas-add-node-context-panel'),
          width: panelWidth,
          padding: const EdgeInsets.all(10),
          decoration: ShapeDecoration(
            color: AppSemanticColors.of(context).popover,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppDesignTokens.of(context).radiusContainer,
              ),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
              ),
            ),
            shadows: AppDesignTokens.of(context).shadowHigh,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        activeFolder == null
                            ? 'Create node'
                            : 'Create node - ${activeFolder.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (!isCompact)
                      Text('Right click', style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                minLines: 1,
                maxLines: 1,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search type...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          visualDensity: VisualDensity.compact,
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.of(context).radiusElement,
                    ),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (isCompact) ...[
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _folders.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, idx) {
                      final folder = _folders[idx];
                      final isSel = _lockedFolder == folder;
                      return ChoiceChip(
                        selected: isSel,
                        avatar: Icon(folder.icon, size: 14),
                        label: Text(folder.label),
                        onSelected: (_) => setState(() {
                          _lockedFolder = folder;
                          _activeTypeIndex = 0;
                        }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                typeListWidget,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 178, child: folderListWidget),
                    const SizedBox(width: 10),
                    Expanded(child: typeListWidget),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasAddNodeFolder {
  const _CanvasAddNodeFolder(this.label, this.icon, this.types);
  final String label;
  final IconData icon;
  final List<NodeType> types;
}

class _CanvasAddNodeFolderTile extends StatelessWidget {
  const _CanvasAddNodeFolderTile({
    required this.folder,
    required this.selected,
    required this.previewed,
    required this.onEnter,
    required this.onExit,
    required this.onPressed,
  });
  final _CanvasAddNodeFolder folder;
  final bool selected;
  final bool previewed;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = selected || previewed;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(
          AppDesignTokens.of(context).radiusContainer,
        ),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: active ? 0.7 : 0.42,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppDesignTokens.of(context).radiusContainer,
              ),
              side: BorderSide(
                color: active
                    ? theme.colorScheme.primary.withValues(alpha: 0.72)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.44),
                width: selected ? 1.7 : 1,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(folder.icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${folder.types.length}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasAddNodeTypeTile extends StatefulWidget {
  const _CanvasAddNodeTypeTile({
    required this.type,
    required this.active,
    required this.onPressed,
  });
  final NodeType type;
  final bool active;
  final VoidCallback onPressed;
  @override
  State<_CanvasAddNodeTypeTile> createState() => _CanvasAddNodeTypeTileState();
}

class _CanvasAddNodeTypeTileState extends State<_CanvasAddNodeTypeTile> {
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = NodeVisuals.color(context, widget.type);
    final active = widget.active || _isHovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        decoration: ShapeDecoration(
          color: Color.alphaBlend(
            color.withValues(alpha: active ? 0.18 : 0.08),
            theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: active ? 0.72 : 0.46,
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppDesignTokens.of(context).radiusContainer,
            ),
            side: BorderSide(
              color: color.withValues(alpha: active ? 0.72 : 0.24),
              width: widget.active ? 1.8 : 1,
            ),
          ),
        ),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusContainer,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(NodeVisuals.icon(widget.type), size: 16, color: color),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.type.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: active
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 15, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutinePreviewDialog extends StatelessWidget {
  const _RoutinePreviewDialog({required this.plan});

  final RecurringRoutinePlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Routine preview'),
      content: SizedBox(
        width: 430,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _RoutinePreviewChip(
                      icon: Icons.add_task_outlined,
                      label: 'Ready to create ${plan.readyCount}',
                    ),
                    _RoutinePreviewChip(
                      icon: Icons.history_toggle_off_outlined,
                      label: 'Existing ${plan.skippedCount}',
                    ),
                    _RoutinePreviewChip(
                      icon: Icons.event_busy_outlined,
                      label: 'Not due ${plan.notDueCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (var index = 0; index < plan.items.length; index++) ...[
                  if (index > 0) const Divider(height: 16),
                  _RoutinePreviewRow(item: plan.items[index]),
                ],
                if (plan.items.isEmpty)
                  Text(
                    'No routines configured',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('routine-preview-cancel-button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('routine-preview-apply-button'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.auto_awesome_motion_outlined),
          label: Text(plan.readyCount == 0 ? 'Close' : 'Apply due routines'),
        ),
      ],
    );
  }
}

class _RoutinePreviewChip extends StatelessWidget {
  const _RoutinePreviewChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusElement,
          ),
          side: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 7),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _RoutinePreviewRow extends StatelessWidget {
  const _RoutinePreviewRow({required this.item});

  final RecurringRoutinePlanItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _routineStatusColor(theme, item.status);

    return Row(
      children: [
        Icon(_routineStatusIcon(item.status), size: 20, color: statusColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.routine.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                _routineRuleLabel(item.routine.rule),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          item.statusLabel,
          style: theme.textTheme.labelMedium?.copyWith(color: statusColor),
        ),
      ],
    );
  }
}

class _NodeRelationsDock extends ConsumerStatefulWidget {
  const _NodeRelationsDock({required this.nodeId, required this.onSelect});

  final String nodeId;
  final ValueChanged<MindmapNode> onSelect;

  @override
  ConsumerState<_NodeRelationsDock> createState() => _NodeRelationsDockState();
}

class _NodeRelationsDockState extends ConsumerState<_NodeRelationsDock> {
  bool _closed = false;

  @override
  void didUpdateWidget(covariant _NodeRelationsDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) _closed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    final relations = ref.watch(nodeRelationsProvider(widget.nodeId));

    return relations.when(
      data: (value) {
        if (value.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            key: const ValueKey('node-relations-dock'),
            elevation: 14,
            color: theme.colorScheme.surfaceContainerHigh.withValues(
              alpha: 0.96,
            ),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.hub_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Node links',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close links panel',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _closed = true),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                  if (value.relatedNodes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _RelationsSection(
                      label: 'Related',
                      keyPrefix: 'relation-related',
                      nodes: value.relatedNodes,
                      onSelect: widget.onSelect,
                    ),
                  ],
                  if (value.backlinks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _RelationsSection(
                      label: 'Backlinks',
                      keyPrefix: 'relation-backlink',
                      nodes: value.backlinks,
                      onSelect: widget.onSelect,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _RelationsSection extends StatelessWidget {
  const _RelationsSection({
    required this.label,
    required this.keyPrefix,
    required this.nodes,
    required this.onSelect,
  });

  final String label;
  final String keyPrefix;
  final List<MindmapNode> nodes;
  final ValueChanged<MindmapNode> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final node in nodes)
              ActionChip(
                key: ValueKey('$keyPrefix-${node.id}'),
                avatar: Icon(NodeVisuals.icon(node.type), size: 16),
                label: Text(node.title),
                onPressed: () => onSelect(node),
              ),
          ],
        ),
      ],
    );
  }
}

CanvasPosition _nextNodePosition(int existingCount) {
  final offset = existingCount * 42.0;
  return CanvasPosition(offset - 84, offset - 24);
}

class _DayTopTabStrip extends StatelessWidget {
  const _DayTopTabStrip({
    required this.selectedDay,
    required this.isCollapsed,
    required this.onDaySelected,
    required this.onCollapsedChanged,
  });

  final DateTime selectedDay;
  final bool isCollapsed;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<bool> onCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now().dateOnly;

    if (isCollapsed) {
      return Container(
        height: 56,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        alignment: Alignment.centerLeft,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onCollapsedChanged(false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.62,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.44,
                  ),
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_view_week_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                  dayKey(selectedDay),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayRadius = constraints.maxWidth < 360
            ? 0
            : constraints.maxWidth < 600
            ? 1
            : 3;
        final days = List<DateTime>.generate(
          dayRadius * 2 + 1,
          (index) =>
              selectedDay.add(Duration(days: index - dayRadius)).dateOnly,
        );
        return Container(
          height: 56,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.26),
              ),
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.36),
              ),
            ),
          ),
          child: Row(
            children: [
              _DayNavButton(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: 'Hide day tabs',
                onPressed: () => onCollapsedChanged(true),
              ),
              const SizedBox(width: 6),
              _DayNavButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous day',
                onPressed: () => onDaySelected(
                  selectedDay.subtract(const Duration(days: 1)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    for (final day in days) ...[
                      Expanded(
                        child: _DayTabPill(
                          day: day,
                          isSelected: day == selectedDay.dateOnly,
                          isToday: day == today,
                          onTap: () => onDaySelected(day),
                        ),
                      ),
                      if (day != days.last) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _DayNavButton(
                icon: Icons.today_rounded,
                tooltip: 'Today',
                onPressed: () => onDaySelected(today),
              ),
              const SizedBox(width: 6),
              _DayNavButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next day',
                onPressed: () =>
                    onDaySelected(selectedDay.add(const Duration(days: 1))),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayTabPill extends StatelessWidget {
  const _DayTabPill({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = switch (day.weekday) {
      DateTime.monday => 'Mon',
      DateTime.tuesday => 'Tue',
      DateTime.wednesday => 'Wed',
      DateTime.thursday => 'Thu',
      DateTime.friday => 'Fri',
      DateTime.saturday => 'Sat',
      DateTime.sunday => 'Sun',
      _ => '',
    };
    final bg = isSelected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.46);
    final fg = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Tooltip(
      message: dayKey(day),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(
              color: bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(
                  color: isToday
                      ? theme.colorScheme.tertiary.withValues(alpha: 0.75)
                      : isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.65)
                      : theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.36,
                        ),
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 72;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!compact) ...[
                      Flexible(
                        child: Text(
                          weekday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      '${day.day}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DayNavButton extends StatelessWidget {
  const _DayNavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.62,
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _DayToolsBar extends StatelessWidget {
  const _DayToolsBar({
    this.embedded = false,
    required this.stats,
    required this.planningSuggestions,
    required this.miniInsights,
    required this.selectedDay,
    required this.isMissionMode,
    required this.isFocusRunning,
    required this.focusElapsed,
    required this.focusRemaining,
    required this.inboxCount,
    required this.onShowStatus,
    required this.onShowPlan,
    required this.onShowPulse,
    required this.onToggleMissionMode,
    required this.onStopFocus,
    required this.onInboxPressed,
    required this.onQuickCapture,
  });

  final bool embedded;
  final _DailyMissionStats stats;
  final List<_DailyPlanningSuggestion> planningSuggestions;
  final List<DayMiniInsight> miniInsights;
  final DateTime selectedDay;
  final bool isMissionMode;
  final bool isFocusRunning;
  final Duration focusElapsed;
  final Duration? focusRemaining;
  final int inboxCount;
  final VoidCallback onShowStatus;
  final VoidCallback onShowPlan;
  final VoidCallback onShowPulse;
  final VoidCallback? onToggleMissionMode;
  final VoidCallback? onStopFocus;
  final VoidCallback? onInboxPressed;
  final VoidCallback onQuickCapture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusLabel = focusRemaining == null
        ? _formatFocusDuration(focusElapsed)
        : '${_formatFocusDuration(focusRemaining!)} left';
    final pulseScore = miniInsights
        .where((insight) => insight.day.isSameDay(selectedDay))
        .firstOrNull
        ?.score;
    return Container(
      height: embedded ? 40 : 56,
      margin: embedded
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: ShapeDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.78),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusContainer,
          ),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.52),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: embedded ? 8 : 10,
          vertical: embedded ? 4 : 8,
        ),
        child: Row(
          children: [
            _DayToolActionChip(
              icon: Icons.draw_outlined,
              label: 'Board ${stats.completionPercent}%',
              tooltip: 'Board status',
              onPressed: onShowStatus,
            ),
            const SizedBox(width: 8),
            _DayToolActionChip(
              icon: Icons.analytics_outlined,
              label: pulseScore == null ? 'Pulse' : 'Pulse $pulseScore',
              tooltip: '7-day pulse',
              onPressed: onShowPulse,
            ),
            const SizedBox(width: 8),
            _DayToolActionChip(
              icon: isMissionMode
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: isMissionMode ? 'Show all' : 'Focus only',
              tooltip: 'Show only focused nodes',
              onPressed: onToggleMissionMode,
              accent: theme.colorScheme.tertiary,
            ),
            if (isFocusRunning) ...[
              const SizedBox(width: 8),
              _DayToolActionChip(
                icon: Icons.timer_outlined,
                label: focusLabel,
                tooltip: 'Focus timer',
                onPressed: onStopFocus,
                accent: theme.colorScheme.tertiary,
              ),
            ],
            if (inboxCount > 0) ...[
              const SizedBox(width: 8),
              _DayToolActionChip(
                icon: Icons.inbox_outlined,
                label: 'Inbox $inboxCount',
                onPressed: onInboxPressed,
                accent: theme.colorScheme.secondary,
              ),
            ],
            const SizedBox(width: 8),
            _DayToolActionChip(
              icon: Icons.auto_awesome_outlined,
              label: 'Plan',
              tooltip: planningSuggestions.isEmpty
                  ? 'No plan suggestions'
                  : '${planningSuggestions.length} plan suggestions',
              onPressed: onShowPlan,
              accent: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            _DayToolActionChip(
              icon: Icons.bolt_outlined,
              label: 'Capture',
              tooltip: 'Quick capture',
              onPressed: onQuickCapture,
              accent: theme.colorScheme.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayToolActionChip extends StatelessWidget {
  const _DayToolActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return Tooltip(
      message: tooltip ?? label,
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        backgroundColor: color.withValues(
          alpha: onPressed == null ? 0.05 : 0.12,
        ),
        side: BorderSide(color: color.withValues(alpha: 0.34)),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      ),
    );
  }
}

String _formatFocusDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours <= 0) return '$minutes:$seconds';
  return '$hours:$minutes:$seconds';
}

final class _SelectedNodeAction {
  const _SelectedNodeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _SelectedNodeMissionActions extends StatelessWidget {
  const _SelectedNodeMissionActions({
    required this.node,
    required this.actions,
    required this.isMission,
    required this.isFocusRunning,
    required this.isCollapsed,
    required this.focusElapsed,
    required this.focusRemaining,
    required this.onToggleCollapsed,
    required this.onToggleMission,
    required this.onStartFocus,
    required this.onStartPomodoro,
    required this.onStartCustomFocus,
    required this.onStopFocus,
  });

  final MindmapNode? node;
  final List<_SelectedNodeAction> actions;
  final bool isMission;
  final bool isFocusRunning;
  final bool isCollapsed;
  final Duration focusElapsed;
  final Duration? focusRemaining;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onToggleMission;
  final VoidCallback onStartFocus;
  final ValueChanged<int> onStartPomodoro;
  final VoidCallback onStartCustomFocus;
  final VoidCallback onStopFocus;

  @override
  Widget build(BuildContext context) {
    final currentNode = node;
    if (currentNode == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final minutes = totalFocusMinutes(currentNode);
    final nextAction = nextFocusAction(currentNode);
    final activeToolCount = actions.length + (isFocusRunning ? 3 : 6);
    if (isCollapsed) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.38,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$activeToolCount tools hidden',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                onPressed: onToggleCollapsed,
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Show'),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.construction_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Node tools', style: theme.textTheme.labelLarge),
                ),
                IconButton.outlined(
                  tooltip: 'Hide node tools',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleCollapsed,
                  icon: const Icon(Icons.expand_less_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  avatar: Icon(
                    isMission ? Icons.flag : Icons.outlined_flag,
                    size: 16,
                  ),
                  label: Text(isMission ? 'Mission' : 'Add mission'),
                  selected: isMission,
                  onSelected: (_) => onToggleMission(),
                ),
                Chip(
                  avatar: const Icon(Icons.next_plan_outlined, size: 16),
                  label: Text(
                    nextAction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                ActionChip(
                  avatar: Icon(
                    isFocusRunning
                        ? Icons.timer_off_outlined
                        : Icons.timer_outlined,
                    size: 16,
                  ),
                  label: Text(isFocusRunning ? 'Stop focus' : 'Start focus'),
                  onPressed: isFocusRunning ? onStopFocus : onStartFocus,
                ),
                if (!isFocusRunning) ...[
                  ActionChip(
                    avatar: const Icon(Icons.av_timer_outlined, size: 16),
                    label: const Text('25/5'),
                    onPressed: () => onStartPomodoro(25),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.av_timer_outlined, size: 16),
                    label: const Text('50/10'),
                    onPressed: () => onStartPomodoro(50),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.tune_outlined, size: 16),
                    label: const Text('Custom'),
                    onPressed: onStartCustomFocus,
                  ),
                ],
                Chip(
                  avatar: const Icon(Icons.timelapse_outlined, size: 16),
                  label: Text('${minutes}m focus'),
                  visualDensity: VisualDensity.compact,
                ),
                for (final action in actions)
                  ActionChip(
                    avatar: Icon(action.icon, size: 16),
                    label: Text(action.label),
                    onPressed: action.onPressed,
                  ),
                if (isFocusRunning)
                  Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 16),
                    label: Text(
                      focusRemaining == null
                          ? _formatFocusDuration(focusElapsed)
                          : '${_formatFocusDuration(focusRemaining!)} left',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayEmptyStateCockpit extends StatelessWidget {
  const _DayEmptyStateCockpit({
    required this.onDismiss,
    required this.onPlanDay,
    required this.onImportLeftovers,
    required this.onStartJournal,
    required this.onApplyRoutine,
    required this.onUseTemplate,
    required this.onQuickCapture,
  });

  final VoidCallback onDismiss;
  final VoidCallback onPlanDay;
  final VoidCallback onImportLeftovers;
  final VoidCallback onStartJournal;
  final VoidCallback onApplyRoutine;
  final VoidCallback onUseTemplate;
  final VoidCallback onQuickCapture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actions = [
      _DayEmptyAction(
        icon: Icons.flash_on_outlined,
        label: 'Quick capture',
        description: 'Type a fast command',
        onTap: onQuickCapture,
      ),
      _DayEmptyAction(
        icon: Icons.rate_review_outlined,
        label: 'Start journal',
        description: 'Open a daily review note',
        onTap: onStartJournal,
      ),
      _DayEmptyAction(
        icon: Icons.auto_awesome_outlined,
        label: 'Plan my day',
        description: 'Start from a proven template',
        onTap: onPlanDay,
      ),
      _DayEmptyAction(
        icon: Icons.move_down_outlined,
        label: 'Import yesterday leftovers',
        description: 'Review unfinished work',
        onTap: onImportLeftovers,
      ),
      _DayEmptyAction(
        icon: Icons.auto_awesome_motion_outlined,
        label: 'Apply routine',
        description: 'Materialize ready routines',
        onTap: onApplyRoutine,
      ),
      _DayEmptyAction(
        icon: Icons.dashboard_customize_outlined,
        label: 'Use template',
        description: 'Workday, study, reset, review',
        onTap: onUseTemplate,
      ),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Card(
        elevation: 0,
        color: colorScheme.surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusPage,
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.edit_note_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Blank board',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Pick one handwritten starter.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hide blank board starters',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: onDismiss,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final action in actions)
                      _DayEmptyActionCard(action: action),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _DayEmptyAction {
  const _DayEmptyAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
}

class _DayEmptyActionCard extends StatelessWidget {
  const _DayEmptyActionCard({required this.action});

  final _DayEmptyAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 184,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: action.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 22),
                const SizedBox(height: 10),
                Text(
                  action.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickCaptureHint extends StatelessWidget {
  const _QuickCaptureHint({required this.text, required this.controller});

  final String text;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size(0, AppDesignTokens.of(context).minimumTarget),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundColor: theme.colorScheme.onSurfaceVariant,
      ),
      onPressed: () {
        controller.text = text;
        controller.selection = TextSelection.collapsed(offset: text.length);
      },
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

final class _DailyMissionStats {
  const _DailyMissionStats({
    required this.totalNodes,
    required this.openTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.highPriorityCount,
    required this.readyRoutineCount,
    required this.appliedRoutineCount,
    required this.completedHabits,
    required this.totalHabits,
    required this.completionPercent,
    required this.statusLabel,
  });

  final int totalNodes;
  final int openTasks;
  final int completedTasks;
  final int overdueTasks;
  final int highPriorityCount;
  final int readyRoutineCount;
  final int appliedRoutineCount;
  final int completedHabits;
  final int totalHabits;
  final int completionPercent;
  final String statusLabel;
}

_DailyMissionStats _buildDailyMissionStats(
  List<MindmapNode> nodes,
  DateTime day, {
  required int readyRoutineCount,
}) {
  final activeNodes = nodes.where((node) => !node.isArchived).toList();
  final tasks = activeNodes
      .where((node) => node.type == NodeType.task)
      .toList();
  final completedTasks = tasks
      .where((node) => node.isDone || node.status == NodeStatus.done)
      .length;
  final openTasks = tasks.length - completedTasks;
  final overdueTasks = tasks.where((node) {
    final dueDate = node.dueDate;
    if (dueDate == null || node.isDone || node.status == NodeStatus.done) {
      return false;
    }
    return dueDate.dateOnly.isBefore(day.dateOnly);
  }).length;
  final highPriorityCount = activeNodes
      .where(
        (node) =>
            !node.isDone &&
            node.status != NodeStatus.done &&
            (node.priority == NodePriority.high ||
                node.priority == NodePriority.urgent),
      )
      .length;
  final habits = activeNodes
      .where((node) => node.type == NodeType.habit)
      .toList();
  final completedHabits = habits
      .where((node) => hasHabitCompletionOn(node, day))
      .length;
  final appliedRoutineCount = activeNodes
      .where(
        (node) =>
            node.type == NodeType.routine &&
            (node.isDone ||
                node.status == NodeStatus.done ||
                node.progress >= 1),
      )
      .length;
  final completableCount = tasks.length + habits.length;
  final completedCount = completedTasks + completedHabits;
  final completionPercent = completableCount == 0
      ? 0
      : ((completedCount / completableCount) * 100).round().clamp(0, 100);
  final statusLabel = overdueTasks > 0 || highPriorityCount >= 4
      ? 'Needs care'
      : openTasks >= 6
      ? 'Busy board'
      : 'Clear board';

  return _DailyMissionStats(
    totalNodes: activeNodes.length,
    openTasks: openTasks,
    completedTasks: completedTasks,
    overdueTasks: overdueTasks,
    highPriorityCount: highPriorityCount,
    readyRoutineCount: readyRoutineCount,
    appliedRoutineCount: appliedRoutineCount,
    completedHabits: completedHabits,
    totalHabits: habits.length,
    completionPercent: completionPercent,
    statusLabel: statusLabel,
  );
}

class _DailyMissionDashboard extends StatefulWidget {
  const _DailyMissionDashboard({required this.stats});

  final _DailyMissionStats stats;

  @override
  State<_DailyMissionDashboard> createState() => _DailyMissionDashboardState();
}

class _DailyMissionDashboardState extends State<_DailyMissionDashboard> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final accent = switch (widget.stats.statusLabel) {
      'Needs care' => semantic.danger,
      'Busy board' => semantic.warning,
      _ => semantic.success,
    };

    if (_isCollapsed) {
      return Material(
        color: Colors.transparent,
        child: _SmartPlanCockpitPanel(
          accent: accent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _isCollapsed = false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.draw_outlined, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  '${widget.stats.statusLabel} ·${widget.stats.completionPercent}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: _SmartPlanCockpitPanel(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(10),
        accent: accent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.draw_outlined, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  'Board status',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.34)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      widget.stats.statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Minimize board status',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _isCollapsed = true),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: widget.stats.completionPercent / 100,
              minHeight: 5,
              borderRadius: BorderRadius.circular(999),
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MissionMetricChip(
                  icon: Icons.hub_outlined,
                  label: 'Nodes',
                  value: '${widget.stats.totalNodes}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.radio_button_unchecked,
                  label: 'Open',
                  value: '${widget.stats.openTasks}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.check_circle_outline,
                  label: 'Done',
                  value: '${widget.stats.completedTasks}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.warning_amber_rounded,
                  label: 'Overdue',
                  value: '${widget.stats.overdueTasks}',
                  accent: widget.stats.overdueTasks > 0
                      ? theme.colorScheme.error
                      : accent,
                ),
                _MissionMetricChip(
                  icon: Icons.priority_high_rounded,
                  label: 'High',
                  value: '${widget.stats.highPriorityCount}',
                  accent: widget.stats.highPriorityCount > 0
                      ? semantic.warning
                      : accent,
                ),
                _MissionMetricChip(
                  icon: Icons.auto_awesome_motion_outlined,
                  label: 'Routines',
                  value:
                      '${widget.stats.appliedRoutineCount}/${widget.stats.readyRoutineCount}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Habits',
                  value:
                      '${widget.stats.completedHabits}/${widget.stats.totalHabits}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.percent_rounded,
                  label: 'Day',
                  value: '${widget.stats.completionPercent}%',
                  accent: accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayMiniInsightsStrip extends StatelessWidget {
  const _DayMiniInsightsStrip({
    required this.insights,
    required this.selectedDay,
    required this.onDaySelected,
  });

  final List<DayMiniInsight> insights;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 16),
                const SizedBox(width: 8),
                Text(
                  '7-day pulse',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final insight in insights)
                  Expanded(
                    child: _DayMiniInsightBar(
                      insight: insight,
                      isSelected: insight.day.isSameDay(selectedDay),
                      onTap: () => onDaySelected(insight.day),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayMiniInsightBar extends StatelessWidget {
  const _DayMiniInsightBar({
    required this.insight,
    required this.isSelected,
    required this.onTap,
  });

  final DayMiniInsight insight;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = insight.score;
    final color = score >= 70
        ? theme.colorScheme.tertiary
        : score >= 35
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final height = 18.0 + (score / 100 * 44);
    return Tooltip(
      message:
          '${dayKey(insight.day)} ·${insight.completedTasks}/${insight.totalTasks} tasks ·${insight.completedHabits}/${insight.totalHabits} habits ·${insight.focusMinutes}m focus${insight.hasReview ? ' ·review' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 66,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 18,
                    height: height,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isSelected ? 0.95 : 0.62),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _weekdayShort(insight.day),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
              if (insight.hasReview)
                Icon(
                  Icons.rate_review_outlined,
                  size: 11,
                  color: theme.colorScheme.tertiary,
                )
              else
                const SizedBox(height: 11),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionMetricChip extends StatelessWidget {
  const _MissionMetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(
          AppDesignTokens.of(context).radiusContainer,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DailyPlanningSuggestion {
  const _DailyPlanningSuggestion({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _DailyPlanningSuggestionsBar extends StatefulWidget {
  const _DailyPlanningSuggestionsBar({required this.suggestions});

  final List<_DailyPlanningSuggestion> suggestions;

  @override
  State<_DailyPlanningSuggestionsBar> createState() =>
      _DailyPlanningSuggestionsBarState();
}

class _DailyPlanningSuggestionsBarState
    extends State<_DailyPlanningSuggestionsBar> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isCollapsed) {
      return _SmartPlanMiniToggle(
        count: widget.suggestions.length,
        onPressed: () => setState(() => _isCollapsed = false),
      );
    }
    return Material(
      color: Colors.transparent,
      child: _SmartPlanCockpitPanel(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(10),
        accent: theme.colorScheme.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Smart plan',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Minimize smart plan',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _isCollapsed = true),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in widget.suggestions)
                  _SmartPlanActionChip(
                    icon: suggestion.icon,
                    label: suggestion.label,
                    onPressed: suggestion.onPressed,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartPlanCockpitPanel extends StatelessWidget {
  const _SmartPlanCockpitPanel({
    required this.child,
    required this.accent,
    this.constraints,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 18,
  });

  final Widget child;
  final Color accent;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: AppSemanticColors.of(context).card,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: accent.withValues(alpha: 0.34), width: 1.5),
        boxShadow: AppDesignTokens.of(context).shadowLow,
      ),
      child: child,
    );
  }
}

class _SmartPlanActionChip extends StatelessWidget {
  const _SmartPlanActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.38,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartPlanMiniToggle extends StatelessWidget {
  const _SmartPlanMiniToggle({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: _SmartPlanCockpitPanel(
          borderRadius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          accent: theme.colorScheme.primary,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Smart plan ·$count',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayNodeBoardView extends StatelessWidget {
  const _DayNodeBoardView({
    required this.nodes,
    required this.selectedNodeId,
    required this.onNodeSelected,
    required this.onNodeUpdated,
  });

  final List<MindmapNode> nodes;
  final String? selectedNodeId;
  final ValueChanged<MindmapNode> onNodeSelected;
  final NodeUpdateCallback onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (nodes.isEmpty) {
      return Center(
        child: Text('No nodes yet', style: theme.textTheme.bodyMedium),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final status in NodeStatus.values)
              _DayBoardColumn(
                status: status,
                nodes: nodes.where((node) => node.status == status).toList(),
                selectedNodeId: selectedNodeId,
                onNodeSelected: onNodeSelected,
                onNodeUpdated: onNodeUpdated,
              ),
          ],
        ),
      ),
    );
  }
}

class _DayBoardColumn extends StatelessWidget {
  const _DayBoardColumn({
    required this.status,
    required this.nodes,
    required this.selectedNodeId,
    required this.onNodeSelected,
    required this.onNodeUpdated,
  });

  final NodeStatus status;
  final List<MindmapNode> nodes;
  final String? selectedNodeId;
  final ValueChanged<MindmapNode> onNodeSelected;
  final NodeUpdateCallback onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<MindmapNode>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) {
        final node = details.data;
        onNodeUpdated(
          node.copyWith(
            status: status,
            isDone: status == NodeStatus.done,
            progress: status == NodeStatus.done ? 1 : node.progress,
            updatedAt: DateTime.now(),
          ),
        );
      },
      builder: (context, candidateNodes, rejectedNodes) {
        final isHovering = candidateNodes.isNotEmpty;
        return Container(
          width: 280,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: isHovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
                : theme.colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isHovering
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    Icon(_statusIcon(status), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${nodes.length}'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: nodes.isEmpty
                    ? Center(
                        child: Text(
                          isHovering ? 'Drop here' : 'Empty',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: nodes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final node = nodes[index];
                          final card = _DayBoardCard(
                            node: node,
                            selected: node.id == selectedNodeId,
                            onTap: () => onNodeSelected(node),
                            onNodeUpdated: onNodeUpdated,
                          );
                          return LongPressDraggable<MindmapNode>(
                            data: node,
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(
                                width: 260,
                                child: _DayBoardCard(
                                  node: node,
                                  selected: true,
                                  onTap: () {},
                                  onNodeUpdated: onNodeUpdated,
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.35,
                              child: card,
                            ),
                            child: card,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayBoardCard extends StatelessWidget {
  const _DayBoardCard({
    required this.node,
    required this.selected,
    required this.onTap,
    required this.onNodeUpdated,
  });

  final MindmapNode node;
  final bool selected;
  final VoidCallback onTap;
  final NodeUpdateCallback onNodeUpdated;

  Future<void> _applyPriority(NodePriority priority) async {
    await onNodeUpdated(
      node.copyWith(priority: priority, updatedAt: DateTime.now()),
    );
  }

  Future<void> _togglePinned() async {
    await onNodeUpdated(
      node.copyWith(isPinned: !node.isPinned, updatedAt: DateTime.now()),
    );
  }

  Future<void> _archive() async {
    await onNodeUpdated(
      node.copyWith(isArchived: true, updatedAt: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = NodeVisuals.color(context, node.type);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(NodeVisuals.icon(node.type), color: accent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.type.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                      ),
                    ),
                  ),
                  if (node.priority != NodePriority.none)
                    Text(
                      node.priority.label,
                      style: theme.textTheme.labelSmall,
                    ),
                  if (node.isPinned) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.push_pin_outlined, size: 14),
                  ],
                  SizedBox.square(
                    dimension: 28,
                    child: PopupMenuButton<String>(
                      key: ValueKey('day-board-card-menu-${node.id}'),
                      tooltip: 'Card actions',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      onSelected: (value) async {
                        switch (value) {
                          case 'pin':
                            await _togglePinned();
                          case 'archive':
                            await _archive();
                          case 'priority-none':
                            await _applyPriority(NodePriority.none);
                          case 'priority-low':
                            await _applyPriority(NodePriority.low);
                          case 'priority-medium':
                            await _applyPriority(NodePriority.medium);
                          case 'priority-high':
                            await _applyPriority(NodePriority.high);
                          case 'priority-urgent':
                            await _applyPriority(NodePriority.urgent);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'pin',
                          child: Text(node.isPinned ? 'Unpin' : 'Pin'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-none',
                          child: Text('Priority: None'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-low',
                          child: Text('Priority: Low'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-medium',
                          child: Text('Priority: Medium'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-high',
                          child: Text('Priority: High'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-urgent',
                          child: Text('Priority: Urgent'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Archive'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                node.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (node.project.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  node.project,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (node.relatedNodeIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.hub_outlined, size: 14),
                    const SizedBox(width: 4),
                    Text('${node.relatedNodeIds.length} links'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

IconData _statusIcon(NodeStatus status) {
  return switch (status) {
    NodeStatus.inbox => Icons.inbox_outlined,
    NodeStatus.open => Icons.radio_button_unchecked,
    NodeStatus.next => Icons.skip_next_outlined,
    NodeStatus.planned => Icons.event_note_outlined,
    NodeStatus.doing => Icons.timelapse_rounded,
    NodeStatus.waiting => Icons.hourglass_empty_rounded,
    NodeStatus.someday => Icons.schedule_outlined,
    NodeStatus.done => Icons.check_circle_outline,
  };
}

void _disposeTextControllerAfterRouteFrame(TextEditingController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
}

class _DayNodeTableView extends StatelessWidget {
  const _DayNodeTableView({
    required this.nodes,
    required this.selectedNodeId,
    required this.view,
    required this.sortMode,
    required this.onViewChanged,
    required this.onSortModeChanged,
    required this.onNodeSelected,
    required this.onNodeUpdated,
  });

  final List<MindmapNode> nodes;
  final String? selectedNodeId;
  final _TableQuickView view;
  final _TableSortMode sortMode;
  final ValueChanged<_TableQuickView> onViewChanged;
  final ValueChanged<_TableSortMode> onSortModeChanged;
  final ValueChanged<MindmapNode> onNodeSelected;
  final NodeUpdateCallback onNodeUpdated;

  List<MindmapNode> get _filteredNodes {
    final filtered = switch (view) {
      _TableQuickView.all => nodes,
      _TableQuickView.open =>
        nodes
            .where((node) => node.status != NodeStatus.done && !node.isDone)
            .toList(),
      _TableQuickView.done =>
        nodes
            .where((node) => node.status == NodeStatus.done || node.isDone)
            .toList(),
      _TableQuickView.tasks =>
        nodes.where((node) => node.type == NodeType.task).toList(),
      _TableQuickView.priority =>
        nodes
            .where(
              (node) =>
                  node.priority == NodePriority.high ||
                  node.priority == NodePriority.urgent,
            )
            .toList(),
      _TableQuickView.due =>
        nodes
            .where(
              (node) =>
                  node.dueDate != null &&
                  node.status != NodeStatus.done &&
                  !node.isDone,
            )
            .toList(),
      _TableQuickView.pinned => nodes.where((node) => node.isPinned).toList(),
      _TableQuickView.archived =>
        nodes.where((node) => node.isArchived).toList(),
      _TableQuickView.linked =>
        nodes.where((node) => node.relatedNodeIds.isNotEmpty).toList(),
    };
    return _sortNodes(filtered);
  }

  List<MindmapNode> _sortNodes(List<MindmapNode> input) {
    final sorted = [...input];
    int compareNullableDates(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    sorted.sort(
      (a, b) => switch (sortMode) {
        _TableSortMode.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
        _TableSortMode.titleAsc => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        _TableSortMode.priorityDesc => b.priority.index.compareTo(
          a.priority.index,
        ),
        _TableSortMode.dueAsc => compareNullableDates(a.dueDate, b.dueDate),
      },
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (nodes.isEmpty) {
      return Center(
        child: Text('No nodes yet', style: theme.textTheme.bodyMedium),
      );
    }
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final view in _TableQuickView.values)
                  ChoiceChip(
                    selected: this.view == view,
                    avatar: Icon(view.icon, size: 16),
                    label: Text('${view.label} (${_countFor(view)})'),
                    onSelected: (_) => onViewChanged(view),
                  ),
                const SizedBox(width: 8),
                DropdownButton<_TableSortMode>(
                  value: sortMode,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final mode in _TableSortMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text('Sort: ${mode.label}'),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) onSortModeChanged(mode);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStatePropertyAll(
                      theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      ),
                    ),
                    columns: const [
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Title')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Priority')),
                      DataColumn(label: Text('Project')),
                      DataColumn(label: Text('Area')),
                      DataColumn(label: Text('Tags')),
                      DataColumn(label: Text('Due')),
                      DataColumn(label: Text('Links')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: [
                      for (final node in _filteredNodes)
                        DataRow(
                          selected: node.id == selectedNodeId,
                          onSelectChanged: (_) => onNodeSelected(node),
                          cells: [
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    NodeVisuals.icon(node.type),
                                    color: NodeVisuals.color(
                                      context,
                                      node.type,
                                    ),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(node.type.label),
                                ],
                              ),
                            ),
                            DataCell(
                              Text(node.title),
                              showEditIcon: true,
                              onTap: () => _editTitle(context, node),
                            ),
                            DataCell(
                              DropdownButton<NodeStatus>(
                                value: node.status,
                                underline: const SizedBox.shrink(),
                                items: [
                                  for (final status in NodeStatus.values)
                                    DropdownMenuItem(
                                      value: status,
                                      child: Text(status.label),
                                    ),
                                ],
                                onChanged: (status) {
                                  if (status == null || status == node.status) {
                                    return;
                                  }
                                  onNodeUpdated(
                                    node.copyWith(
                                      status: status,
                                      isDone: status == NodeStatus.done,
                                      progress: status == NodeStatus.done
                                          ? 1
                                          : node.progress,
                                      updatedAt: DateTime.now(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            DataCell(
                              DropdownButton<NodePriority>(
                                value: node.priority,
                                underline: const SizedBox.shrink(),
                                items: [
                                  for (final priority in NodePriority.values)
                                    DropdownMenuItem(
                                      value: priority,
                                      child: Text(priority.label),
                                    ),
                                ],
                                onChanged: (priority) {
                                  if (priority == null ||
                                      priority == node.priority) {
                                    return;
                                  }
                                  onNodeUpdated(
                                    node.copyWith(
                                      priority: priority,
                                      updatedAt: DateTime.now(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            DataCell(
                              Text(node.project.isEmpty ? '-' : node.project),
                              showEditIcon: true,
                              onTap: () => _editProject(context, node),
                            ),
                            DataCell(
                              Text(node.area.isEmpty ? '-' : node.area),
                              showEditIcon: true,
                              onTap: () => _editArea(context, node),
                            ),
                            DataCell(
                              Text(
                                node.tags.isEmpty ? '-' : node.tags.join(', '),
                              ),
                              showEditIcon: true,
                              onTap: () => _editTags(context, node),
                            ),
                            DataCell(
                              Text(
                                node.dueDate == null
                                    ? '-'
                                    : dayKey(node.dueDate!),
                              ),
                              showEditIcon: true,
                              onTap: () => _editDueDate(context, node),
                            ),
                            DataCell(Text('${node.relatedNodeIds.length}')),
                            DataCell(
                              _TableNodeActions(
                                node: node,
                                onNodeUpdated: onNodeUpdated,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTitle(BuildContext context, MindmapNode node) async {
    final controller = TextEditingController(text: node.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _disposeTextControllerAfterRouteFrame(controller);
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == node.title) return;
    await onNodeUpdated(
      node.copyWith(title: trimmed, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editDueDate(BuildContext context, MindmapNode node) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: node.dueDate ?? node.day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    await onNodeUpdated(
      node.copyWith(dueDate: picked.dateOnly, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editProject(BuildContext context, MindmapNode node) async {
    final controller = TextEditingController(text: node.project);
    final project = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project',
            helperText: 'Leave empty to clear project.',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _disposeTextControllerAfterRouteFrame(controller);
    final trimmed = project?.trim();
    if (trimmed == null || trimmed == node.project) return;
    await onNodeUpdated(
      node.copyWith(project: trimmed, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editArea(BuildContext context, MindmapNode node) async {
    final controller = TextEditingController(text: node.area);
    final area = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit area'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Area',
            helperText: 'Leave empty to clear area.',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _disposeTextControllerAfterRouteFrame(controller);
    final trimmed = area?.trim();
    if (trimmed == null || trimmed == node.area) return;
    await onNodeUpdated(
      node.copyWith(area: trimmed, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editTags(BuildContext context, MindmapNode node) async {
    final controller = TextEditingController(text: node.tags.join(', '));
    final tagsText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit tags'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tags',
            helperText: 'Comma separated. Empty clears tags.',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _disposeTextControllerAfterRouteFrame(controller);
    if (tagsText == null) return;
    final tags = tagsText
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (tags.join(',') == node.tags.join(',')) return;
    await onNodeUpdated(node.copyWith(tags: tags, updatedAt: DateTime.now()));
  }

  int _countFor(_TableQuickView view) {
    return switch (view) {
      _TableQuickView.all => nodes.length,
      _TableQuickView.open =>
        nodes
            .where((node) => node.status != NodeStatus.done && !node.isDone)
            .length,
      _TableQuickView.done =>
        nodes
            .where((node) => node.status == NodeStatus.done || node.isDone)
            .length,
      _TableQuickView.tasks =>
        nodes.where((node) => node.type == NodeType.task).length,
      _TableQuickView.priority =>
        nodes
            .where(
              (node) =>
                  node.priority == NodePriority.high ||
                  node.priority == NodePriority.urgent,
            )
            .length,
      _TableQuickView.due =>
        nodes
            .where(
              (node) =>
                  node.dueDate != null &&
                  node.status != NodeStatus.done &&
                  !node.isDone,
            )
            .length,
      _TableQuickView.pinned => nodes.where((node) => node.isPinned).length,
      _TableQuickView.archived => nodes.where((node) => node.isArchived).length,
      _TableQuickView.linked =>
        nodes.where((node) => node.relatedNodeIds.isNotEmpty).length,
    };
  }
}

class _TableNodeActions extends StatelessWidget {
  const _TableNodeActions({required this.node, required this.onNodeUpdated});

  final MindmapNode node;
  final NodeUpdateCallback onNodeUpdated;

  Future<void> _togglePinned() async {
    await onNodeUpdated(
      node.copyWith(isPinned: !node.isPinned, updatedAt: DateTime.now()),
    );
  }

  Future<void> _clearDueDate() async {
    await onNodeUpdated(
      node.copyWith(clearDueDate: true, updatedAt: DateTime.now()),
    );
  }

  Future<void> _archive() async {
    await onNodeUpdated(
      node.copyWith(isArchived: true, updatedAt: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: ValueKey('day-table-node-actions-${node.id}'),
      tooltip: 'Node actions',
      onSelected: (value) async {
        switch (value) {
          case 'pin':
            await _togglePinned();
          case 'clear-due':
            await _clearDueDate();
          case 'archive':
            await _archive();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'pin',
          child: Text(node.isPinned ? 'Unpin' : 'Pin'),
        ),
        PopupMenuItem(
          value: 'clear-due',
          enabled: node.dueDate != null,
          child: const Text('Clear due date'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'archive', child: Text('Archive')),
      ],
    );
  }
}

enum _TableQuickView {
  all('All', Icons.table_rows_outlined),
  open('Open', Icons.radio_button_unchecked),
  done('Done', Icons.check_circle_outline),
  tasks('Tasks', Icons.check_box_outlined),
  priority('Priority', Icons.priority_high_rounded),
  due('Due', Icons.event_available_outlined),
  pinned('Pinned', Icons.push_pin_outlined),
  archived('Archived', Icons.archive_outlined),
  linked('Linked', Icons.hub_outlined);

  const _TableQuickView(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _TableSortMode {
  updatedDesc('Updated'),
  titleAsc('Title'),
  priorityDesc('Priority'),
  dueAsc('Due');

  const _TableSortMode(this.label);

  final String label;
}

enum _DayViewMode { canvas, timeline, board, table }

enum _DayContextFilter {
  all('All', Icons.all_inclusive_rounded),
  open('Open', Icons.radio_button_unchecked_rounded),
  high('High', Icons.priority_high_rounded),
  done('Done', Icons.check_circle_outline_rounded),
  work('Work', Icons.work_outline_rounded),
  personal('Personal', Icons.self_improvement_outlined),
  missions('Missions', Icons.flag_outlined);

  const _DayContextFilter(this.label, this.icon);

  final String label;
  final IconData icon;

  bool matches(MindmapNode node) {
    return switch (this) {
      _DayContextFilter.all => true,
      _DayContextFilter.open => !node.isDone && !node.isArchived,
      _DayContextFilter.high => node.priority == NodePriority.high,
      _DayContextFilter.done => node.isDone,
      _DayContextFilter.work => _hasContext(node, 'work'),
      _DayContextFilter.personal => _hasContext(node, 'personal'),
      _DayContextFilter.missions => isTodayMission(node),
    };
  }
}

bool _hasContext(MindmapNode node, String context) {
  final normalized = context.toLowerCase();
  return node.project.toLowerCase() == normalized ||
      node.area.toLowerCase() == normalized ||
      node.tags.any((tag) => tag.toLowerCase() == normalized);
}

String _workspaceContextFilterKey(WorkspaceContext context) {
  return _workspaceContextFilterKeyFor(context.type, context.name);
}

String _workspaceContextFilterKeyFor(WorkspaceContextType type, String name) {
  return '${type.name}:${workspaceContextKey(name)}';
}

WorkspaceContext? _workspaceContextForKey(
  WorkspaceContexts? contexts,
  String? key,
) {
  if (contexts == null || key == null) return null;
  for (final context in [...contexts.projects, ...contexts.areas]) {
    if (_workspaceContextFilterKey(context) == key) return context;
  }
  return null;
}

const String _defaultRelationLabel = 'relates to';

List<Map<String, Object?>> _relationDataForIds(
  MindmapNode source,
  Iterable<String> ids,
) {
  final existing = _relationLabelMap(source);
  return [
    for (final id in ids)
      {'targetId': id, 'label': existing[id] ?? _defaultRelationLabel},
  ];
}

Map<String, String> _relationLabelMap(MindmapNode node) {
  final raw = node.data['relations'];
  if (raw is! List<Object?>) return const {};
  return {
    for (final item in raw)
      if (item is Map<Object?, Object?> && item['targetId'] is String)
        item['targetId']! as String:
            item['label'] is String && (item['label']! as String).isNotEmpty
            ? item['label']! as String
            : _defaultRelationLabel,
  };
}

_DayViewMode? _dayViewModeFromName(String? name) {
  for (final mode in _DayViewMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

_DayContextFilter? _dayContextFilterFromName(String? name) {
  for (final filter in _DayContextFilter.values) {
    if (filter.name == name) return filter;
  }
  return null;
}

_TableQuickView? _tableQuickViewFromName(String? name) {
  for (final view in _TableQuickView.values) {
    if (view.name == name) return view;
  }
  return null;
}

_TableSortMode? _tableSortModeFromName(String? name) {
  for (final mode in _TableSortMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

class _DayToolbarGroup extends StatelessWidget {
  const _DayToolbarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    return Container(
      height: tokens.minimumTarget,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing[1]),
      decoration: ShapeDecoration(
        color: semantic.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusElement),
          side: BorderSide(color: semantic.border),
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _CanvasViewSettingsButton extends StatelessWidget {
  const _CanvasViewSettingsButton({
    required this.isRibbonToolbarCollapsed,
    required this.isDayTabsHidden,
    required this.onSelected,
  });

  final bool isRibbonToolbarCollapsed;
  final bool isDayTabsHidden;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Canvas View Settings',
      icon: const Icon(Icons.tune_outlined, size: 18),
      constraints: BoxConstraints(
        minWidth: 240,
        minHeight: tokens.minimumTarget,
      ),
      color: semantic.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        side: BorderSide(color: semantic.border),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        _settingsItem(
          context,
          value: 'ribbon',
          icon: isRibbonToolbarCollapsed
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          label: isRibbonToolbarCollapsed
              ? 'Show Ribbon Toolbar'
              : 'Hide Ribbon Toolbar',
        ),
        _settingsItem(
          context,
          value: 'tabs',
          icon: isDayTabsHidden
              ? Icons.calendar_view_week_outlined
              : Icons.calendar_today_outlined,
          label: isDayTabsHidden
              ? 'Show Day Tabs (7 Days)'
              : 'Hide Day Tabs (7 Days)',
        ),
      ],
    );
  }

  PopupMenuItem<String> _settingsItem(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
  }) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    return PopupMenuItem<String>(
      value: value,
      height: tokens.minimumTarget,
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing[5]),
      child: Row(
        children: [
          Icon(icon, size: 18, color: semantic.textSecondary),
          SizedBox(width: tokens.spacing[5]),
          Text(label),
        ],
      ),
    );
  }
}

class _DayContextSwitcher extends StatelessWidget {
  const _DayContextSwitcher({
    required this.filter,
    required this.workspaceContext,
    required this.workspaceContexts,
    required this.onChanged,
    required this.onWorkspaceChanged,
  });

  final _DayContextFilter filter;
  final WorkspaceContext? workspaceContext;
  final WorkspaceContexts? workspaceContexts;
  final ValueChanged<_DayContextFilter> onChanged;
  final ValueChanged<WorkspaceContext> onWorkspaceChanged;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final activeLabel = workspaceContext == null
        ? filter.label
        : '${workspaceContext!.type.label}: ${workspaceContext!.name}';
    final activeIcon = workspaceContext?.type == WorkspaceContextType.project
        ? Icons.workspaces_outline
        : workspaceContext?.type == WorkspaceContextType.area
        ? Icons.category_outlined
        : filter.icon;
    final dynamicContexts = workspaceContexts == null
        ? const <WorkspaceContext>[]
        : [
            ...workspaceContexts!.projects,
            ...workspaceContexts!.areas,
          ].where((context) => context.activeNodeCount > 0).take(8).toList();

    return PopupMenuButton<Object>(
      tooltip: 'Day context',
      constraints: BoxConstraints(
        minWidth: 280,
        minHeight: tokens.minimumTarget,
      ),
      color: semantic.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        side: BorderSide(color: semantic.border),
      ),
      onSelected: (value) {
        if (value is _DayContextFilter) onChanged(value);
        if (value is WorkspaceContext) onWorkspaceChanged(value);
      },
      itemBuilder: (context) => [
        for (final item in _DayContextFilter.values)
          PopupMenuItem<Object>(
            value: item,
            height: tokens.minimumTarget,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing[2]),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.icon, size: 18),
              title: Text(item.label),
              trailing: workspaceContext == null && item == filter
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
            ),
          ),
        if (dynamicContexts.isNotEmpty) const PopupMenuDivider(),
        for (final item in dynamicContexts)
          PopupMenuItem<Object>(
            value: item,
            height: tokens.minimumTarget,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing[2]),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                item.type == WorkspaceContextType.project
                    ? Icons.workspaces_outline
                    : Icons.category_outlined,
                size: 18,
              ),
              title: Text('${item.type.label}: ${item.name}'),
              subtitle: Text('${item.activeNodeCount} active'),
              trailing: item == workspaceContext
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
            ),
          ),
      ],
      child: Chip(
        avatar: Icon(activeIcon, size: 16, color: semantic.accent),
        label: Text('Context: $activeLabel'),
        visualDensity: VisualDensity.compact,
        backgroundColor: semantic.surfaceRaised,
        side: BorderSide(color: semantic.border),
      ),
    );
  }
}

class _DayViewModeToggle extends StatelessWidget {
  const _DayViewModeToggle({required this.mode, required this.onChanged});

  final _DayViewMode mode;
  final ValueChanged<_DayViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    return SegmentedButton<_DayViewMode>(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(tokens.minimumTarget, tokens.minimumTarget),
        ),
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? semantic.accentMuted
              : semantic.surfaceRaised;
        }),
        side: WidgetStatePropertyAll(BorderSide(color: semantic.border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusElement),
          ),
        ),
      ),
      segments: const [
        ButtonSegment<_DayViewMode>(
          value: _DayViewMode.canvas,
          label: Text('Canvas', key: ValueKey('day-view-canvas')),
          icon: Icon(Icons.hub_outlined, size: 16),
        ),
        ButtonSegment<_DayViewMode>(
          value: _DayViewMode.timeline,
          label: Text('Timeline'),
          icon: Icon(Icons.calendar_view_day_outlined, size: 16),
        ),
        ButtonSegment<_DayViewMode>(
          value: _DayViewMode.board,
          label: Text('Board'),
          icon: Icon(Icons.view_kanban_outlined, size: 16),
        ),
        ButtonSegment<_DayViewMode>(
          value: _DayViewMode.table,
          label: Text('Table'),
          icon: Icon(Icons.table_rows_outlined, size: 16),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _ActivityLogSheet extends StatelessWidget {
  const _ActivityLogSheet({
    required this.undoEntries,
    required this.redoEntries,
    required this.onUndo,
    required this.onRedo,
  });

  final List<_UndoEntry> undoEntries;
  final List<_UndoEntry> redoEntries;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = [
      for (final entry in undoEntries)
        _ActivityEntry(entry: entry, isRedo: false),
      for (final entry in redoEntries)
        _ActivityEntry(entry: entry, isRedo: true),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.manage_history_rounded),
              title: const Text('Activity log'),
              subtitle: Text(
                '${undoEntries.length} undo / ${redoEntries.length} redo',
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Undo latest',
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Redo latest',
                    onPressed: onRedo,
                    icon: const Icon(Icons.redo_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No recent activity yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemBuilder: (context, index) {
                    final item = entries[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(item.icon),
                      title: Text(item.title),
                      subtitle: Text(item.subtitle),
                      trailing: item.isRedo
                          ? const Chip(label: Text('Redo'))
                          : const Chip(label: Text('Undo')),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemCount: entries.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _ActivityEntry {
  const _ActivityEntry({required this.entry, required this.isRedo});

  final _UndoEntry entry;
  final bool isRedo;

  IconData get icon {
    return switch (entry.kind) {
      _UndoKind.create => Icons.add_circle_outline,
      _UndoKind.delete => Icons.delete_outline,
      _UndoKind.save => _saveIcon,
      _UndoKind.canvasCreate => Icons.note_add_outlined,
      _UndoKind.canvasDelete => Icons.layers_clear_outlined,
      _UndoKind.canvasUpdate => Icons.dashboard_customize_outlined,
      _UndoKind.canvasBatch => Icons.select_all_outlined,
      _UndoKind.canvasBoard => Icons.auto_awesome_outlined,
    };
  }

  IconData get _saveIcon {
    final before = entry.before;
    final after = entry.after;
    if (before != null && after != null) {
      if (!before.isDone && after.isDone) return Icons.check_circle_outline;
      if (before.day != after.day) return Icons.drive_file_move_outline;
      if (before.status != after.status) return Icons.change_circle_outlined;
    }
    return Icons.edit_outlined;
  }

  String get title {
    return switch (entry.kind) {
      _UndoKind.create => 'Created node',
      _UndoKind.delete => 'Deleted node',
      _UndoKind.save => _saveTitle,
      _UndoKind.canvasCreate => 'Created canvas object',
      _UndoKind.canvasDelete => 'Deleted canvas object',
      _UndoKind.canvasUpdate => 'Edited canvas object',
      _UndoKind.canvasBatch => 'Edited canvas selection',
      _UndoKind.canvasBoard => 'Applied canvas assistant',
    };
  }

  String get _saveTitle {
    final before = entry.before;
    final after = entry.after;
    if (before != null && after != null) {
      if (!before.isDone && after.isDone) return 'Completed task';
      if (before.day != after.day) return 'Moved node';
      if (before.status != after.status) return 'Edited status';
    }
    return 'Edited node';
  }

  String get subtitle => isRedo ? 'Redo available' : 'Undo available';
}

class _UndoRedoIndicator extends StatelessWidget {
  const _UndoRedoIndicator({
    required this.undoCount,
    required this.redoCount,
    required this.onUndo,
    required this.onRedo,
    required this.onHistory,
  });

  final int undoCount;
  final int redoCount;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    if (undoCount == 0 && redoCount == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Undo ()',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onUndo,
              icon: const Icon(Icons.undo_rounded),
            ),
          ),
          Text('$undoCount / $redoCount', style: theme.textTheme.labelSmall),
          Tooltip(
            message: 'Redo ()',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onRedo,
              icon: const Icon(Icons.redo_rounded),
            ),
          ),
          Tooltip(
            message: 'Activity log',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onHistory,
              icon: const Icon(Icons.manage_history_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _routineStatusIcon(RecurringRoutinePlanItemStatus status) {
  return switch (status) {
    RecurringRoutinePlanItemStatus.ready => Icons.add_task_outlined,
    RecurringRoutinePlanItemStatus.skippedExisting =>
      Icons.check_circle_outline,
    RecurringRoutinePlanItemStatus.skippedToday => Icons.block_outlined,
    RecurringRoutinePlanItemStatus.snoozedToday => Icons.snooze_outlined,
    RecurringRoutinePlanItemStatus.notDue => Icons.event_busy_outlined,
  };
}

Color _routineStatusColor(
  ThemeData theme,
  RecurringRoutinePlanItemStatus status,
) {
  return switch (status) {
    RecurringRoutinePlanItemStatus.ready => theme.colorScheme.primary,
    RecurringRoutinePlanItemStatus.skippedExisting =>
      theme.colorScheme.tertiary,
    RecurringRoutinePlanItemStatus.skippedToday => theme.colorScheme.outline,
    RecurringRoutinePlanItemStatus.snoozedToday => theme.colorScheme.outline,
    RecurringRoutinePlanItemStatus.notDue => theme.colorScheme.outline,
  };
}

String _routineRuleLabel(RecurringRule rule) {
  return switch (rule.frequency) {
    RecurringFrequency.daily => 'Every day',
    RecurringFrequency.weekly => 'Weekly on ${_weekdayName(rule.weekday)}',
    RecurringFrequency.monthly => 'Monthly on day ${rule.dayOfMonth}',
  };
}

String _weekdayShort(DateTime day) {
  return switch (day.weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => '',
  };
}

String _weekdayName(int? weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'schedule',
  };
}

/// Kinds of mutations tracked by the undo/redo system.
enum _UndoKind {
  save,
  delete,
  create,
  canvasUpdate,
  canvasDelete,
  canvasCreate,
  canvasBatch,
  canvasBoard,
}

/// A single entry in the undo/redo stack.
///
/// Keeps snapshots of the node [before] and [after] the mutation so we can
/// reverse or re-apply the operation.
final class _UndoEntry {
  const _UndoEntry({
    required this.kind,
    required this.nodeId,
    this.before,
    this.after,
    this.canvasBefore,
    this.canvasAfter,
    this.canvasBeforeBatch = const <CanvasObject>[],
    this.canvasAfterBatch = const <CanvasObject>[],
    this.canvasBoardBefore,
    this.canvasBoardAfter,
  });

  final _UndoKind kind;
  final String nodeId;
  final MindmapNode? before;
  final MindmapNode? after;
  final CanvasObject? canvasBefore;
  final CanvasObject? canvasAfter;
  final List<CanvasObject> canvasBeforeBatch;
  final List<CanvasObject> canvasAfterBatch;
  final CanvasBoard? canvasBoardBefore;
  final CanvasBoard? canvasBoardAfter;
}

class _MindmapDocumentCanvasToolbar extends StatelessWidget {
  const _MindmapDocumentCanvasToolbar({
    required this.selectedNode,
    required this.homeTools,
    required this.selectedTab,
    required this.selectedNodePreset,
    required this.selectedNodeSaveStatus,
    required this.isSelectedNodeEditing,
    required this.canExportSelectedMedia,
    required this.canOpenSelectedMedia,
    required this.onTabChanged,
    required this.isExplorerVisible,
    required this.canUndo,
    required this.canRedo,
    required this.onToggleExplorer,
    required this.onAddNode,
    required this.onCreateType,
    required this.onCanvasAction,
    required this.isGridVisible,
    required this.isSnapEnabled,
    required this.isMinimapVisible,
    required this.areCompletedVisible,
    required this.onUndo,
    required this.onRedo,
    required this.onFitCanvas,
    required this.onToggleGrid,
    required this.onToggleSnap,
    required this.onToggleMinimap,
    required this.onResetZoom,
    required this.onNodeTools,
    required this.onEditNode,
    required this.onDoneEditing,
    required this.onPresetChanged,
    required this.onReplaceMedia,
    required this.onExportMedia,
    required this.onOpenMedia,
    required this.onClearSelection,
  });

  final MindmapNode? selectedNode;
  final Widget homeTools;
  final _MindmapRibbonTab selectedTab;
  final NodeSizePreset? selectedNodePreset;
  final NodeSaveStatus selectedNodeSaveStatus;
  final bool isSelectedNodeEditing;
  final bool canExportSelectedMedia;
  final bool canOpenSelectedMedia;
  final ValueChanged<_MindmapRibbonTab> onTabChanged;
  final bool isExplorerVisible;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onToggleExplorer;
  final ValueChanged<Offset> onAddNode;
  final ValueChanged<NodeType> onCreateType;
  final ValueChanged<CanvasContextAction> onCanvasAction;
  final bool isGridVisible;
  final bool isSnapEnabled;
  final bool isMinimapVisible;
  final bool areCompletedVisible;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onFitCanvas;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleSnap;
  final VoidCallback onToggleMinimap;
  final VoidCallback onResetZoom;
  final VoidCallback? onNodeTools;
  final VoidCallback? onEditNode;
  final VoidCallback? onDoneEditing;
  final ValueChanged<NodeSizePreset>? onPresetChanged;
  final VoidCallback? onReplaceMedia;
  final VoidCallback? onExportMedia;
  final VoidCallback? onOpenMedia;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_MindmapRibbonTab>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _MindmapRibbonTab.home,
                    label: Text('Home', key: ValueKey('ribbon-tab-home')),
                  ),
                  ButtonSegment(
                    value: _MindmapRibbonTab.insert,
                    label: Text('Insert', key: ValueKey('ribbon-tab-insert')),
                  ),
                  ButtonSegment(
                    value: _MindmapRibbonTab.node,
                    label: Text('Node', key: ValueKey('ribbon-tab-node')),
                  ),
                  ButtonSegment(
                    value: _MindmapRibbonTab.canvas,
                    label: Text('Canvas', key: ValueKey('ribbon-tab-canvas')),
                  ),
                  ButtonSegment(
                    value: _MindmapRibbonTab.view,
                    label: Text('View', key: ValueKey('ribbon-tab-view')),
                  ),
                ],
                selected: {selectedTab},
                onSelectionChanged: (selection) =>
                    onTabChanged(selection.first),
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: 8),
            SizedBox(
              key: const ValueKey('ribbon-active-tools'),
              height: 48,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(children: _toolsForSelectedTab(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _toolsForSelectedTab(BuildContext context) {
    final node = selectedNode;
    return switch (selectedTab) {
      _MindmapRibbonTab.home => [
        SizedBox(height: 40, child: homeTools),
        const _ToolbarSeparator(),
        IconButton(
          tooltip: 'Undo (Ctrl+Z)',
          onPressed: canUndo ? onUndo : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Redo (Ctrl+Shift+Z)',
          onPressed: canRedo ? onRedo : null,
          icon: const Icon(Icons.redo),
        ),
      ],
      _MindmapRibbonTab.insert => [
        Builder(
          builder: (buttonContext) => FilledButton.tonalIcon(
            key: const ValueKey('ribbon-all-types'),
            onPressed: () {
              final renderObject = buttonContext.findRenderObject();
              if (renderObject is! RenderBox || !renderObject.hasSize) return;
              final topLeft = renderObject.localToGlobal(Offset.zero);
              onAddNode(
                Offset(topLeft.dx, topLeft.dy + renderObject.size.height + 8),
              );
            },
            icon: const Icon(Icons.add_box_outlined, size: 18),
            label: const Text('All types'),
          ),
        ),
        const SizedBox(width: 6),
        for (final type in const [
          NodeType.task,
          NodeType.note,
          NodeType.plan,
          NodeType.goal,
          NodeType.habit,
          NodeType.kanban,
        ])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: Icon(NodeVisuals.icon(type), size: 16),
              label: Text(type.label),
              onPressed: () => onCreateType(type),
            ),
          ),
      ],
      _MindmapRibbonTab.node =>
        node == null
            ? [
                const Icon(Icons.touch_app_outlined),
                const SizedBox(width: 8),
                const Text('Select a node to show node tools'),
              ]
            : [
                Chip(
                  avatar: Icon(NodeVisuals.icon(node.type), size: 16),
                  label: Text(node.type.label),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                SegmentedButton<NodeSizePreset>(
                  key: const ValueKey('ribbon-node-size-presets'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: NodeSizePreset.auto,
                      label: Text('Auto'),
                    ),
                    ButtonSegment(
                      value: NodeSizePreset.compact,
                      label: Text('Compact'),
                    ),
                    ButtonSegment(
                      value: NodeSizePreset.standard,
                      label: Text('Standard'),
                    ),
                    ButtonSegment(
                      value: NodeSizePreset.large,
                      label: Text('Large'),
                    ),
                    ButtonSegment(
                      value: NodeSizePreset.wide,
                      label: Text('Wide'),
                    ),
                  ],
                  selected: {selectedNodePreset ?? NodeSizePreset.auto},
                  onSelectionChanged: (selection) =>
                      onPresetChanged?.call(selection.first),
                ),
                const SizedBox(width: 6),
                Semantics(
                  key: const ValueKey('ribbon-node-save-status'),
                  label: 'Inline save status',
                  value: selectedNodeSaveStatus.name,
                  liveRegion: true,
                  child: Chip(
                    avatar: Icon(
                      _saveStatusIcon(selectedNodeSaveStatus),
                      size: 16,
                    ),
                    label: Text(_saveStatusLabel(selectedNodeSaveStatus)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.tonalIcon(
                  key: const ValueKey('ribbon-node-edit-toggle'),
                  onPressed: isSelectedNodeEditing ? onDoneEditing : onEditNode,
                  icon: Icon(
                    isSelectedNodeEditing
                        ? Icons.check_rounded
                        : Icons.edit_outlined,
                    size: 18,
                  ),
                  label: Text(isSelectedNodeEditing ? 'Done' : 'Edit'),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  key: const ValueKey('ribbon-node-actions'),
                  onPressed: onNodeTools,
                  icon: const Icon(Icons.construction_outlined, size: 18),
                  label: const Text('Actions'),
                ),
                if (node.type == NodeType.image ||
                    node.type == NodeType.video) ...[
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    key: const ValueKey('ribbon-media-replace'),
                    onPressed: onReplaceMedia,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Replace'),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: canExportSelectedMedia
                        ? 'Export local attachment'
                        : 'Export requires a local attachment',
                    child: Semantics(
                      button: true,
                      enabled: canExportSelectedMedia,
                      child: OutlinedButton.icon(
                        key: const ValueKey('ribbon-media-export'),
                        onPressed: canExportSelectedMedia
                            ? onExportMedia
                            : null,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Export'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: canOpenSelectedMedia
                        ? 'Open safe external URL'
                        : 'Open requires a valid http or https URL',
                    child: Semantics(
                      button: true,
                      enabled: canOpenSelectedMedia,
                      child: OutlinedButton.icon(
                        key: const ValueKey('ribbon-media-open'),
                        onPressed: canOpenSelectedMedia ? onOpenMedia : null,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open'),
                      ),
                    ),
                  ),
                ],
                IconButton(
                  key: const ValueKey('ribbon-clear-node-selection'),
                  tooltip: 'Clear selection',
                  onPressed: onClearSelection,
                  icon: const Icon(Icons.close),
                ),
              ],
      _MindmapRibbonTab.canvas => [
        _RibbonAction(
          icon: Icons.fit_screen_outlined,
          label: 'Fit',
          onPressed: onFitCanvas,
        ),
        FilterChip(
          selected: isGridVisible,
          avatar: const Icon(Icons.grid_on_outlined, size: 16),
          label: const Text('Grid'),
          onSelected: (_) => onToggleGrid(),
        ),
        const SizedBox(width: 6),
        FilterChip(
          selected: isSnapEnabled,
          avatar: const Icon(Icons.grid_4x4, size: 16),
          label: const Text('Snap'),
          onSelected: (_) => onToggleSnap(),
        ),
        const SizedBox(width: 6),
        _RibbonAction(
          icon: Icons.center_focus_strong,
          label: '100%',
          onPressed: onResetZoom,
        ),
        _RibbonAction(
          icon: Icons.auto_fix_high,
          label: 'Tidy',
          onPressed: () => onCanvasAction(CanvasContextAction.tidyLayout),
        ),
        _CanvasMoreMenu(onSelected: onCanvasAction),
      ],
      _MindmapRibbonTab.view => [
        _ToolbarTextButton(
          icon: isExplorerVisible
              ? Icons.view_sidebar_outlined
              : Icons.menu_open_outlined,
          label: 'Explorer',
          tooltip: 'Show or hide Life Explorer (Ctrl+B)',
          selected: isExplorerVisible,
          onPressed: onToggleExplorer,
        ),
        const SizedBox(width: 6),
        FilterChip(
          selected: isMinimapVisible,
          avatar: const Icon(Icons.map_outlined, size: 16),
          label: const Text('Minimap'),
          onSelected: (_) => onToggleMinimap(),
        ),
        const SizedBox(width: 6),
        FilterChip(
          selected: areCompletedVisible,
          avatar: const Icon(Icons.task_alt, size: 16),
          label: const Text('Completed'),
          onSelected: (_) =>
              onCanvasAction(CanvasContextAction.toggleCompleted),
        ),
        const SizedBox(width: 6),
        _RibbonAction(
          icon: Icons.terminal,
          label: 'Commands',
          onPressed: () => onCanvasAction(CanvasContextAction.commandPalette),
        ),
      ],
    };
  }

  IconData _saveStatusIcon(NodeSaveStatus status) => switch (status) {
    NodeSaveStatus.idle => Icons.circle_outlined,
    NodeSaveStatus.dirty => Icons.edit_note_outlined,
    NodeSaveStatus.saving => Icons.sync,
    NodeSaveStatus.saved => Icons.cloud_done_outlined,
    NodeSaveStatus.error => Icons.error_outline,
  };

  String _saveStatusLabel(NodeSaveStatus status) => switch (status) {
    NodeSaveStatus.idle => 'Idle',
    NodeSaveStatus.dirty => 'Unsaved',
    NodeSaveStatus.saving => 'Saving',
    NodeSaveStatus.saved => 'Saved',
    NodeSaveStatus.error => 'Save error',
  };
}

class _CanvasMoreMenu extends StatelessWidget {
  const _CanvasMoreMenu({required this.onSelected});

  final ValueChanged<CanvasContextAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CanvasContextAction>(
      tooltip: 'More canvas tools',
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: CanvasContextAction.radialLayout,
          child: Text('Mindmap layout'),
        ),
        PopupMenuItem(
          value: CanvasContextAction.typeLayout,
          child: Text('Group by type'),
        ),
        PopupMenuItem(
          value: CanvasContextAction.timelineLayout,
          child: Text('Timeline layout'),
        ),
        PopupMenuItem(
          value: CanvasContextAction.groupSelection,
          child: Text('Group selection'),
        ),
        PopupMenuItem(
          value: CanvasContextAction.ungroupSelection,
          child: Text('Ungroup selection'),
        ),
        PopupMenuItem(
          value: CanvasContextAction.cycleBackground,
          child: Text('Change background'),
        ),
        PopupMenuItem(
          value: CanvasContextAction.importClipboard,
          child: Text('Import clipboard'),
        ),
        PopupMenuItem(
          value: CanvasContextAction.exportJson,
          child: Text('Copy canvas JSON'),
        ),
        PopupMenuItem(
          value: CanvasContextAction.exportPng,
          child: Text('Export PNG'),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [Icon(Icons.more_horiz), SizedBox(width: 6), Text('More')],
        ),
      ),
    );
  }
}

class _RibbonAction extends StatelessWidget {
  const _RibbonAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _DayQuickCreateFab extends StatefulWidget {
  const _DayQuickCreateFab({required this.onSelectType, required this.onMore});

  final ValueChanged<NodeType> onSelectType;
  final VoidCallback onMore;

  @override
  State<_DayQuickCreateFab> createState() => _DayQuickCreateFabState();
}

class _DayQuickCreateFabState extends State<_DayQuickCreateFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isOpen = false;

  static const _types = <NodeType>[
    NodeType.task,
    NodeType.note,
    NodeType.kanban,
    NodeType.habit,
    NodeType.event,
    NodeType.idea,
    NodeType.question,
    NodeType.bookmark,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _select(NodeType type) {
    _toggle();
    widget.onSelectType(type);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      SizeTransition(
        sizeFactor: CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        ),
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final type in _types)
                    ActionChip(
                      avatar: Icon(NodeVisuals.icon(type), size: 16),
                      label: Text(type.label),
                      onPressed: () => _select(type),
                    ),
                  TextButton.icon(
                    onPressed: widget.onMore,
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text('More'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      GestureDetector(
        onLongPress: _toggle,
        child: FloatingActionButton.small(
          key: const ValueKey('day-fab'),
          tooltip: _isOpen
              ? 'Close quick create menu'
              : 'Quick create (long press for menu)',
          onPressed: widget.onMore,
          child: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 180),
            child: Icon(_isOpen ? Icons.close_rounded : Icons.add_rounded),
          ),
        ),
      ),
    ],
  );
}

class _ToolbarTextButton extends StatelessWidget {
  const _ToolbarTextButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
        ),
      ),
    );
  }
}

class _ToolbarSeparator extends StatelessWidget {
  const _ToolbarSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

enum _MindmapRibbonTab { home, insert, node, canvas, view }

class _MindmapMobileToolbar extends StatelessWidget {
  const _MindmapMobileToolbar({
    required this.selectedNode,
    required this.onTools,
  });

  final MindmapNode? selectedNode;
  final VoidCallback onTools;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedNode?.title.trim().isNotEmpty == true
                    ? selectedNode!.title
                    : 'Mindmap tools',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onTools,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Tools'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileToolList extends StatelessWidget {
  const _MobileToolList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: children,
    );
  }
}

class _MobileEditorLauncher extends StatelessWidget {
  const _MobileEditorLauncher({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: enabled ? onOpen : null,
                    icon: const Icon(Icons.open_in_full, size: 16),
                    label: Text(
                      enabled ? 'Open editor' : 'Select a node first',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
