/// Interactive daily mindmap canvas.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../calendar/domain/calendar_node_payload.dart';
import '../domain/canvas_position.dart';
import '../domain/goal_progress.dart';
import '../domain/habit_completion.dart';
import '../domain/kanban_board.dart';
import '../domain/life_os_summary.dart';
import '../domain/mindmap_node.dart';
import '../domain/plan_progress.dart';
import '../domain/task_checklist_progress.dart';

typedef NodeMoveCallback =
    FutureOr<void> Function(MindmapNode node, CanvasPosition position);
typedef NodeSelectionCallback = FutureOr<void> Function(MindmapNode node);
typedef TaskDoneCallback =
    FutureOr<void> Function(MindmapNode node, bool isDone);
typedef TaskChecklistItemCompletedCallback =
    FutureOr<void> Function(MindmapNode node);
typedef KanbanCardAdvanceCallback =
    FutureOr<void> Function(MindmapNode node, String cardId);
typedef HabitCompletedCallback = FutureOr<void> Function(MindmapNode node);
typedef GoalMilestoneAdvanceCallback =
    FutureOr<void> Function(MindmapNode node);
typedef PlanStepAdvanceCallback = FutureOr<void> Function(MindmapNode node);

class MindmapCanvas extends StatefulWidget {
  const MindmapCanvas({
    required this.nodes,
    this.highlightedNodeId,
    this.onNodeMoved,
    this.onNodeSelected,
    this.onTaskDoneChanged,
    this.onTaskChecklistItemCompleted,
    this.onKanbanCardAdvanced,
    this.onHabitCompleted,
    this.onGoalMilestoneAdvanced,
    this.onPlanStepAdvanced,
    this.onNodeDropped,
    super.key,
  });

  static const Size canvasSize = Size(3600, 2400);
  static const Size nodeSize = Size(276, 256);
  static const Size kanbanNodeSize = Size(420, 232);

  final List<MindmapNode> nodes;
  final String? highlightedNodeId;
  final NodeMoveCallback? onNodeMoved;
  final NodeSelectionCallback? onNodeSelected;
  final TaskDoneCallback? onTaskDoneChanged;
  final TaskChecklistItemCompletedCallback? onTaskChecklistItemCompleted;
  final KanbanCardAdvanceCallback? onKanbanCardAdvanced;
  final HabitCompletedCallback? onHabitCompleted;
  final GoalMilestoneAdvanceCallback? onGoalMilestoneAdvanced;
  final PlanStepAdvanceCallback? onPlanStepAdvanced;
  final void Function(NodeType type, Offset scenePosition)? onNodeDropped;

  @override
  State<MindmapCanvas> createState() => MindmapCanvasState();
}

class MindmapCanvasState extends State<MindmapCanvas> {
  final Map<String, CanvasPosition> _dragPositions = {};
  final TransformationController _transformationController =
      TransformationController();
  bool _didSetInitialTransform = false;

  Offset? _mousePos;
  bool _showGrid = true;
  bool _snapToGrid = false;
  bool _isNodeInteracted = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _dragPositions.clear();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Calculates the center of the viewport relative to the mindmap's custom origin
  Offset get viewportCenter {
    final viewportSize = context.size;
    if (viewportSize == null) return Offset.zero;

    final centerLocal = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final sceneCenter = _transformationController.toScene(centerLocal);

    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );

    return sceneCenter - origin;
  }

  /// Pans the viewport to focus on a specific node position
  void focusOnPosition(CanvasPosition pos, {double scale = 1.0}) {
    final viewportSize = context.size;
    if (viewportSize == null) return;

    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );

    final targetScene = origin + Offset(pos.dx, pos.dy);

    final tx = viewportSize.width / 2 - targetScene.dx * scale;
    final ty = viewportSize.height / 2 - targetScene.dy * scale;

    final translationMatrix = Matrix4.translationValues(tx, ty, 0);
    final scaleMatrix = Matrix4.diagonal3Values(scale, scale, 1);
    _transformationController.value =
        translationMatrix * scaleMatrix as Matrix4;
  }

  void _zoom(double factor) {
    final matrix = _transformationController.value.clone();

    final viewportSize = context.size;
    if (viewportSize == null) return;
    final vpCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);

    final sceneCenter = _transformationController.toScene(vpCenter);

    final currentScale = matrix.getMaxScaleOnAxis();

    var newScale = currentScale * factor;
    newScale = newScale.clamp(0.25, 2.4);

    final tx = vpCenter.dx - sceneCenter.dx * newScale;
    final ty = vpCenter.dy - sceneCenter.dy * newScale;

    final translationMatrix = Matrix4.translationValues(tx, ty, 0);
    final scaleMatrix = Matrix4.diagonal3Values(newScale, newScale, 1);

    setState(() {
      _transformationController.value =
          translationMatrix * scaleMatrix as Matrix4;
    });
  }

  void _zoomIn() => _zoom(1.2);
  void _zoomOut() => _zoom(1 / 1.2);

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _showShortcutHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => const _MindmapShortcutHelpDialog(),
    );
  }

  void _zoomReset() {
    final viewportSize = context.size;
    if (viewportSize == null) return;
    setState(() {
      _transformationController.value = Matrix4.translationValues(
        (viewportSize.width - MindmapCanvas.canvasSize.width) / 2,
        (viewportSize.height - MindmapCanvas.canvasSize.height) / 2,
        0,
      );
    });
  }

  Rect _viewportRectInSceneOf(Size viewportSize) {
    if (viewportSize == Size.zero) return Rect.zero;

    final topLeftScene = _transformationController.toScene(Offset.zero);
    final bottomRightScene = _transformationController.toScene(
      Offset(viewportSize.width, viewportSize.height),
    );

    return Rect.fromPoints(topLeftScene, bottomRightScene);
  }

  void _onMinimapPan(Offset localPos) {
    const miniWidth = 180.0;
    const miniHeight = 120.0;

    final pctX = (localPos.dx / miniWidth).clamp(0.0, 1.0);
    final pctY = (localPos.dy / miniHeight).clamp(0.0, 1.0);

    final targetX = pctX * MindmapCanvas.canvasSize.width;
    final targetY = pctY * MindmapCanvas.canvasSize.height;

    final pos = CanvasPosition(
      targetX - MindmapCanvas.canvasSize.width / 2,
      targetY - MindmapCanvas.canvasSize.height / 2,
    );

    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    focusOnPosition(pos, scale: currentScale);
  }

  @override
  void didUpdateWidget(covariant MindmapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nodeIds = widget.nodes.map((node) => node.id).toSet();
    _dragPositions.removeWhere((id, position) => !nodeIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _setInitialTransform(constraints.biggest);

        final origin = Offset(
          MindmapCanvas.canvasSize.width / 2,
          MindmapCanvas.canvasSize.height / 2,
        );
        return ClipRect(
          child: DragTarget<NodeType>(
            onAcceptWithDetails: (details) {
              if (widget.onNodeDropped == null) return;
              final renderBox = context.findRenderObject() as RenderBox?;
              if (renderBox != null) {
                final localOffset = renderBox.globalToLocal(details.offset);
                final sceneOffset = _transformationController.toScene(
                  localOffset,
                );

                // Align to center of the drop (assuming typical node size of ~276x256)
                // We subtract the origin because the Canvas' origin is in the center of its massive size
                final alignedOffset =
                    sceneOffset - origin - const Offset(276 / 2, 256 / 2);

                widget.onNodeDropped!(details.data, alignedOffset);
              }
            },
            builder: (context, candidateData, rejectedData) {
              final filteredNodes = _searchQuery.isEmpty
                  ? widget.nodes
                  : widget.nodes
                        .where(
                          (n) =>
                              n.title.toLowerCase().contains(_searchQuery) ||
                              n.body.toLowerCase().contains(_searchQuery) ||
                              n.type.name.contains(_searchQuery) ||
                              n.tags.any((t) => t.contains(_searchQuery)) ||
                              n.status.name.toLowerCase().contains(
                                _searchQuery,
                              ),
                        )
                        .toList();

              return CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.keyF,
                    control: true,
                  ): () =>
                      _searchFocusNode.requestFocus(),
                  const SingleActivator(
                    LogicalKeyboardKey.equal,
                    control: true,
                  ): _zoomIn,
                  const SingleActivator(
                    LogicalKeyboardKey.minus,
                    control: true,
                  ): _zoomOut,
                  const SingleActivator(
                    LogicalKeyboardKey.digit0,
                    control: true,
                  ): _zoomReset,
                  const SingleActivator(
                    LogicalKeyboardKey.keyG,
                    control: true,
                  ): () =>
                      setState(() => _showGrid = !_showGrid),
                  const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                  ): () =>
                      setState(() => _snapToGrid = !_snapToGrid),
                },
                child: Focus(
                  autofocus: true,
                  child: Stack(
                    children: [
                      // Search bar overlay at the top
                      Positioned(
                        top: 8,
                        left: MediaQuery.of(context).size.width > 600 ? 240 : 8,
                        right: MediaQuery.of(context).size.width > 600
                            ? 400
                            : 8,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _searchQuery.isNotEmpty
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Search nodes on this day...',
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 36,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 18,
                                  color: _searchQuery.isNotEmpty
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: _clearSearch,
                                      )
                                    : null,
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Search match count badge
                      if (_searchQuery.isNotEmpty)
                        Positioned(
                          top: 52,
                          left: MediaQuery.of(context).size.width > 600
                              ? 240
                              : 8,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${filteredNodes.length} match${filteredNodes.length == 1 ? '' : 'es'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      InteractiveViewer(
                        key: const ValueKey('mindmap-canvas'),
                        transformationController: _transformationController,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(800),
                        minScale: 0.25,
                        maxScale: 2.4,
                        panEnabled: !_isNodeInteracted,
                        scaleEnabled: !_isNodeInteracted,
                        child: SizedBox(
                          width: MindmapCanvas.canvasSize.width,
                          height: MindmapCanvas.canvasSize.height,
                          child: MouseRegion(
                            onHover: (event) {
                              setState(() {
                                _mousePos = event.localPosition;
                              });
                            },
                            onExit: (_) {
                              setState(() {
                                _mousePos = null;
                              });
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _InteractiveBackgroundPainter(
                                      mousePos: _mousePos,
                                      showGrid: _showGrid,
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _ConnectionLinesPainter(
                                      nodes: filteredNodes,
                                      dragPositions: _dragPositions,
                                      origin: origin,
                                    ),
                                  ),
                                ),
                                for (final node in filteredNodes)
                                  _PositionedNode(
                                    node: node,
                                    position: _positionFor(node),
                                    size: _nodeSizeFor(node),
                                    origin: origin,
                                    isHighlighted:
                                        node.id == widget.highlightedNodeId,
                                    onPointerDown: () => setState(
                                      () => _isNodeInteracted = true,
                                    ),
                                    onPointerUp: () => setState(
                                      () => _isNodeInteracted = false,
                                    ),
                                    onPanUpdate: (delta) =>
                                        _moveNode(node, delta),
                                    onPanEnd: () => _finishMove(node),
                                    onSelect: () =>
                                        widget.onNodeSelected?.call(node),
                                    onTaskDoneChanged: (isDone) => widget
                                        .onTaskDoneChanged
                                        ?.call(node, isDone),
                                    onTaskChecklistItemCompleted:
                                        widget.onTaskChecklistItemCompleted ==
                                            null
                                        ? null
                                        : () => widget
                                              .onTaskChecklistItemCompleted
                                              ?.call(node),
                                    onKanbanCardAdvanced:
                                        widget.onKanbanCardAdvanced == null
                                        ? null
                                        : (cardId) => widget
                                              .onKanbanCardAdvanced
                                              ?.call(node, cardId),
                                    onHabitCompleted:
                                        widget.onHabitCompleted == null
                                        ? null
                                        : () => widget.onHabitCompleted?.call(
                                            node,
                                          ),
                                    onGoalMilestoneAdvanced:
                                        widget.onGoalMilestoneAdvanced == null
                                        ? null
                                        : () => widget.onGoalMilestoneAdvanced
                                              ?.call(node),
                                    onPlanStepAdvanced:
                                        widget.onPlanStepAdvanced == null
                                        ? null
                                        : () => widget.onPlanStepAdvanced?.call(
                                            node,
                                          ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty && filteredNodes.isEmpty)
                        Center(
                          child: _CanvasSearchEmptyState(
                            query: _searchQuery,
                            onClearSearch: _clearSearch,
                          ),
                        ),

                      // Zoom & Grid Toolbar Overlay
                      ValueListenableBuilder<Matrix4>(
                        valueListenable: _transformationController,
                        builder: (context, value, child) {
                          return Positioned(
                            bottom: 16,
                            left: 16,
                            child: _buildCanvasToolbar(context),
                          );
                        },
                      ),

                      // Mini-map Overlay
                      ValueListenableBuilder<Matrix4>(
                        valueListenable: _transformationController,
                        builder: (context, value, child) {
                          return Positioned(
                            bottom: 16,
                            right: 16,
                            child: _buildMinimap(context, constraints.biggest),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCanvasToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom Out',
              icon: const Icon(Icons.zoom_out, size: 20),
              onPressed: _zoomOut,
            ),
            Container(
              width: 52,
              alignment: Alignment.center,
              child: Text(
                '${(currentScale * 100).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Zoom In',
              icon: const Icon(Icons.zoom_in, size: 20),
              onPressed: _zoomIn,
            ),
            IconButton(
              tooltip: 'Reset Zoom & Center',
              icon: const Icon(Icons.center_focus_strong, size: 20),
              onPressed: _zoomReset,
            ),
            const SizedBox(
              height: 24,
              child: VerticalDivider(width: 16, thickness: 1),
            ),
            IconButton(
              tooltip: _showGrid ? 'Hide Grid' : 'Show Grid',
              icon: Icon(
                _showGrid ? Icons.grid_on : Icons.grid_off,
                size: 20,
                color: _showGrid ? theme.colorScheme.primary : null,
              ),
              onPressed: () {
                setState(() {
                  _showGrid = !_showGrid;
                });
              },
            ),
            IconButton(
              tooltip: _snapToGrid
                  ? 'Disable Snap-to-Grid'
                  : 'Enable Snap-to-Grid',
              icon: Icon(
                _snapToGrid ? Icons.adjust : Icons.adjust_outlined,
                size: 20,
                color: _snapToGrid ? theme.colorScheme.primary : null,
              ),
              onPressed: () {
                setState(() {
                  _snapToGrid = !_snapToGrid;
                });
              },
            ),
            _ToolbarPill(label: _showGrid ? 'Grid on' : 'Grid off'),
            const SizedBox(width: 6),
            _ToolbarPill(label: _snapToGrid ? 'Snap on' : 'Snap off'),
            const SizedBox(
              height: 24,
              child: VerticalDivider(width: 16, thickness: 1),
            ),
            IconButton(
              key: const ValueKey('mindmap-shortcut-help'),
              tooltip: 'Mindmap shortcuts',
              icon: const Icon(Icons.keyboard_alt_outlined, size: 20),
              onPressed: _showShortcutHelp,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimap(BuildContext context, Size viewportSize) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 180,
        height: 120,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onPanUpdate: (details) => _onMinimapPan(details.localPosition),
            onTapDown: (details) => _onMinimapPan(details.localPosition),
            child: CustomPaint(
              painter: _MinimapPainter(
                nodes: widget.nodes,
                dragPositions: _dragPositions,
                viewportRect: _viewportRectInSceneOf(viewportSize),
                canvasSize: MindmapCanvas.canvasSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setInitialTransform(Size viewport) {
    if (_didSetInitialTransform || !viewport.width.isFinite) return;

    _transformationController.value = Matrix4.translationValues(
      (viewport.width - MindmapCanvas.canvasSize.width) / 2,
      (viewport.height - MindmapCanvas.canvasSize.height) / 2,
      0,
    );
    _didSetInitialTransform = true;
  }

  CanvasPosition _positionFor(MindmapNode node) {
    return _dragPositions[node.id] ?? node.position;
  }

  void _moveNode(MindmapNode node, Offset delta) {
    final current = _positionFor(node);
    setState(() {
      _dragPositions[node.id] = CanvasPosition(
        current.dx + delta.dx,
        current.dy + delta.dy,
      );
    });
  }

  void _finishMove(MindmapNode node) {
    var finalPos = _positionFor(node);
    if (_snapToGrid) {
      const gridSize = 48.0;
      final snappedX = (finalPos.dx / gridSize).round() * gridSize;
      final snappedY = (finalPos.dy / gridSize).round() * gridSize;
      finalPos = CanvasPosition(snappedX, snappedY);
      setState(() {
        _dragPositions[node.id] = finalPos;
      });
    }
    widget.onNodeMoved?.call(node, finalPos);
  }

  Size _nodeSizeFor(MindmapNode node) {
    return node.type == NodeType.kanban
        ? MindmapCanvas.kanbanNodeSize
        : MindmapCanvas.nodeSize;
  }
}

class _ToolbarPill extends StatelessWidget {
  const _ToolbarPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

class _MindmapShortcutHelpDialog extends StatelessWidget {
  const _MindmapShortcutHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mindmap shortcuts'),
      content: const SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MindmapShortcutRow(keys: 'Ctrl+F', action: 'Focus search'),
            _MindmapShortcutRow(keys: 'Ctrl++', action: 'Zoom in'),
            _MindmapShortcutRow(keys: 'Ctrl+-', action: 'Zoom out'),
            _MindmapShortcutRow(keys: 'Ctrl+0', action: 'Reset zoom'),
            _MindmapShortcutRow(keys: 'Ctrl+G', action: 'Toggle grid'),
            _MindmapShortcutRow(keys: 'Ctrl+S', action: 'Toggle snap-to-grid'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _MindmapShortcutRow extends StatelessWidget {
  const _MindmapShortcutRow({required this.keys, required this.action});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 64),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              keys,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(action)),
        ],
      ),
    );
  }
}

class _CanvasSearchEmptyState extends StatelessWidget {
  const _CanvasSearchEmptyState({
    required this.query,
    required this.onClearSearch,
  });

  final String query;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('mindmap-search-empty-state'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text('No nodes match “$query”', style: theme.textTheme.bodyMedium),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              key: const ValueKey('mindmap-search-clear-empty'),
              onPressed: onClearSearch,
              icon: const Icon(Icons.search_off, size: 16),
              label: const Text('Clear search'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PositionedNode extends StatelessWidget {
  const _PositionedNode({
    required this.node,
    required this.position,
    required this.size,
    required this.origin,
    required this.isHighlighted,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onSelect,
    required this.onTaskDoneChanged,
    required this.onTaskChecklistItemCompleted,
    required this.onKanbanCardAdvanced,
    required this.onHabitCompleted,
    required this.onGoalMilestoneAdvanced,
    required this.onPlanStepAdvanced,
  });

  final MindmapNode node;
  final CanvasPosition position;
  final Size size;
  final Offset origin;
  final bool isHighlighted;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onSelect;
  final ValueChanged<bool> onTaskDoneChanged;
  final VoidCallback? onTaskChecklistItemCompleted;
  final ValueChanged<String>? onKanbanCardAdvanced;
  final VoidCallback? onHabitCompleted;
  final VoidCallback? onGoalMilestoneAdvanced;
  final VoidCallback? onPlanStepAdvanced;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: origin.dx + position.dx,
      top: origin.dy + position.dy,
      width: size.width,
      height: size.height,
      child: _NodePointerSurface(
        nodeId: node.id,
        isHighlighted: isHighlighted,
        onPointerDown: onPointerDown,
        onPointerUp: onPointerUp,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        onSelect: onSelect,
        canToggleDone: node.type == NodeType.task,
        isDone: node.isDone,
        onTaskDoneChanged: onTaskDoneChanged,
        shouldIgnoreTap: node.type == NodeType.kanban
            ? _isInsideKanbanControlArea
            : node.type == NodeType.task
            ? _isInsideTaskControlArea
            : node.type == NodeType.habit
            ? _isInsideHabitControlArea
            : node.type == NodeType.goal
            ? _isInsideGoalControlArea
            : node.type == NodeType.plan
            ? _isInsidePlanControlArea
            : null,
        child: _MindmapNodeCard(
          node: node,
          isHighlighted: isHighlighted,
          onTaskChecklistItemCompleted: onTaskChecklistItemCompleted,
          onKanbanCardAdvanced: onKanbanCardAdvanced,
          onHabitCompleted: onHabitCompleted,
          onGoalMilestoneAdvanced: onGoalMilestoneAdvanced,
          onPlanStepAdvanced: onPlanStepAdvanced,
        ),
      ),
    );
  }

  bool _isInsideKanbanControlArea(Offset position) {
    const boardTop = 64.0;
    return position.dy >= boardTop;
  }

  bool _isInsideTaskControlArea(Offset position) {
    const actionTop = 204.0;
    return position.dy >= actionTop;
  }

  bool _isInsideHabitControlArea(Offset position) {
    const actionTop = 204.0;
    return position.dy >= actionTop;
  }

  bool _isInsideGoalControlArea(Offset position) {
    const actionTop = 204.0;
    return position.dy >= actionTop;
  }

  bool _isInsidePlanControlArea(Offset position) {
    const actionTop = 204.0;
    return position.dy >= actionTop;
  }
}

class _NodePointerSurface extends StatefulWidget {
  const _NodePointerSurface({
    required this.nodeId,
    required this.isHighlighted,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onSelect,
    required this.canToggleDone,
    required this.isDone,
    required this.onTaskDoneChanged,
    required this.shouldIgnoreTap,
    required this.child,
  });

  final String nodeId;
  final bool isHighlighted;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onSelect;
  final bool canToggleDone;
  final bool isDone;
  final ValueChanged<bool> onTaskDoneChanged;
  final bool Function(Offset position)? shouldIgnoreTap;
  final Widget child;

  @override
  State<_NodePointerSurface> createState() => _NodePointerSurfaceState();
}

class _NodePointerSurfaceState extends State<_NodePointerSurface> {
  static const double _toggleHitSize = 48;

  Offset _lastLocalPosition = Offset.zero;
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (details) {
        _lastLocalPosition = details.localPosition;
        _isDragging = true;
        widget.onPointerDown();
      },
      onPointerMove: (details) {
        if (_isDragging) {
          _lastLocalPosition = details.localPosition;
          widget.onPanUpdate(details.delta);
        }
      },
      onPointerUp: (details) {
        if (_isDragging) {
          _isDragging = false;
          widget.onPointerUp();
          widget.onPanEnd();
        }
      },
      onPointerCancel: (details) {
        if (_isDragging) {
          _isDragging = false;
          widget.onPointerUp();
          widget.onPanEnd();
        }
      },
      child: GestureDetector(
        key: ValueKey('mindmap-node-${widget.nodeId}'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          _lastLocalPosition = details.localPosition;
          if (widget.shouldIgnoreTap?.call(_lastLocalPosition) ?? false) {
            return;
          }
          if (_isToggleHit(_lastLocalPosition)) {
            widget.onTaskDoneChanged(!widget.isDone);
          } else {
            widget.onSelect();
          }
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Container(
              key: widget.isHighlighted
                  ? ValueKey('mindmap-highlight-${widget.nodeId}')
                  : null,
              child: Stack(
                children: [
                  Positioned.fill(child: widget.child),
                  if (widget.canToggleDone)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _TaskDoneToggle(
                        nodeId: widget.nodeId,
                        isDone: widget.isDone,
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

  bool _isToggleHit(Offset position) {
    return widget.canToggleDone &&
        position.dx <= _toggleHitSize &&
        position.dy <= _toggleHitSize;
  }
}

class _MindmapNodeCard extends StatelessWidget {
  const _MindmapNodeCard({
    required this.node,
    required this.isHighlighted,
    required this.onTaskChecklistItemCompleted,
    required this.onKanbanCardAdvanced,
    required this.onHabitCompleted,
    required this.onGoalMilestoneAdvanced,
    required this.onPlanStepAdvanced,
  });

  final MindmapNode node;
  final bool isHighlighted;
  final VoidCallback? onTaskChecklistItemCompleted;
  final ValueChanged<String>? onKanbanCardAdvanced;
  final VoidCallback? onHabitCompleted;
  final VoidCallback? onGoalMilestoneAdvanced;
  final VoidCallback? onPlanStepAdvanced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = nodeColor(node.type);
    final isHabitLogged =
        node.type == NodeType.habit && hasHabitCompletionOn(node, node.day);
    final nextMilestone = node.type == NodeType.goal
        ? nextGoalMilestone(node)
        : null;
    final nextStep = node.type == NodeType.plan ? nextPlanStep(node) : null;
    final nextChecklistItem = node.type == NodeType.task
        ? nextOpenChecklistItem(node)
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isHighlighted
            ? color.withValues(alpha: 0.18)
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted ? color : color.withValues(alpha: 0.5),
          width: isHighlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (node.type == NodeType.task) const SizedBox(width: 32),
                Icon(nodeIcon(node.type), color: color, size: 18),
                const SizedBox(width: 8),
                Text(node.type.label, style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              node.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                decoration: node.isDone ? TextDecoration.lineThrough : null,
                color: node.isDone ? theme.textTheme.bodySmall?.color : null,
              ),
            ),
            if (_metadataLabelsFor(node).isNotEmpty) ...[
              const SizedBox(height: 8),
              _NodeMetadataChips(node: node),
            ],
            if (calendarNodePayloadFromData(node.data) != null) ...[
              const SizedBox(height: 8),
              _CalendarPayloadSummary(node: node),
            ],
            if (node.data.containsKey('kanban')) ...[
              const SizedBox(height: 10),
              Expanded(
                child: _KanbanNodeBoard(
                  node: node,
                  onCardAdvanced: onKanbanCardAdvanced,
                ),
              ),
            ],
            if (node.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                node.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (!node.data.containsKey('kanban')) ...[
              const SizedBox(height: 8),
              Flexible(child: _NodeTypeSpecificContent(node: node)),
            ],
            if (node.checklist.isNotEmpty &&
                node.checklist.isNotEmpty &&
                !node.isDone &&
                onTaskChecklistItemCompleted != null) ...[
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: FilledButton.tonalIcon(
                  key: ValueKey('mindmap-task-checklist-next-${node.id}'),
                  onPressed: nextChecklistItem == null
                      ? null
                      : onTaskChecklistItemCompleted,
                  icon: Icon(
                    nextChecklistItem == null
                        ? Icons.check_circle_outline
                        : Icons.playlist_add_check,
                    size: 16,
                  ),
                  label: Text(
                    nextChecklistItem == null ? 'Checklist done' : 'Next item',
                  ),
                ),
              ),
            ],
            if (node.data.containsKey('habit') && onHabitCompleted != null) ...[
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: FilledButton.tonalIcon(
                  key: ValueKey('mindmap-habit-log-${node.id}'),
                  onPressed: isHabitLogged ? null : onHabitCompleted,
                  icon: Icon(
                    isHabitLogged ? Icons.check_circle_outline : Icons.check,
                    size: 16,
                  ),
                  label: Text(isHabitLogged ? 'Logged' : 'Log'),
                ),
              ),
            ],
            if (node.data.containsKey('goal') &&
                onGoalMilestoneAdvanced != null) ...[
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: FilledButton.tonalIcon(
                  key: ValueKey('mindmap-goal-advance-${node.id}'),
                  onPressed: nextMilestone == null
                      ? null
                      : onGoalMilestoneAdvanced,
                  icon: Icon(
                    nextMilestone == null
                        ? Icons.check_circle_outline
                        : Icons.flag_outlined,
                    size: 16,
                  ),
                  label: Text(
                    nextMilestone == null ? 'Complete' : 'Next milestone',
                  ),
                ),
              ),
            ],
            if (node.data.containsKey('plan') &&
                !node.isDone &&
                onPlanStepAdvanced != null) ...[
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: FilledButton.tonalIcon(
                  key: ValueKey('mindmap-plan-advance-${node.id}'),
                  onPressed: nextStep == null ? null : onPlanStepAdvanced,
                  icon: Icon(
                    nextStep == null
                        ? Icons.check_circle_outline
                        : Icons.route_outlined,
                    size: 16,
                  ),
                  label: Text(nextStep == null ? 'Plan done' : 'Next step'),
                ),
              ),
            ],
            if (node.isDone) ...[
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: Chip(
                  key: ValueKey('mindmap-node-done-${node.id}'),
                  label: const Text('Done'),
                  avatar: const Icon(Icons.check, size: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NodeMetadataChips extends StatelessWidget {
  const _NodeMetadataChips({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final labels = _metadataLabelsFor(node);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final label in labels) _MetadataPill(label: label)],
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _KanbanNodeBoard extends StatelessWidget {
  const _KanbanNodeBoard({required this.node, required this.onCardAdvanced});

  final MindmapNode node;
  final ValueChanged<String>? onCardAdvanced;

  @override
  Widget build(BuildContext context) {
    final board = KanbanBoard.fromNodeData(node.data);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final column in KanbanColumn.values) ...[
          Expanded(
            child: _KanbanColumnView(
              nodeId: node.id,
              column: column,
              cards: board.cardsFor(column),
              onCardAdvanced: onCardAdvanced,
            ),
          ),
          if (column != KanbanColumn.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _KanbanColumnView extends StatelessWidget {
  const _KanbanColumnView({
    required this.nodeId,
    required this.column,
    required this.cards,
    required this.onCardAdvanced,
  });

  final String nodeId;
  final KanbanColumn column;
  final List<KanbanCard> cards;
  final ValueChanged<String>? onCardAdvanced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              column.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final card in cards) ...[
                      _KanbanCardTile(
                        nodeId: nodeId,
                        card: card,
                        onCardAdvanced: onCardAdvanced,
                      ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanCardTile extends StatelessWidget {
  const _KanbanCardTile({
    required this.nodeId,
    required this.card,
    required this.onCardAdvanced,
  });

  final String nodeId;
  final KanbanCard card;
  final ValueChanged<String>? onCardAdvanced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAdvance = card.column.next != null && onCardAdvanced != null;

    return DecoratedBox(
      key: ValueKey('kanban-card-$nodeId-${card.id}-${card.column.name}'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (canAdvance)
              SizedBox.square(
                dimension: 28,
                child: IconButton(
                  key: ValueKey('kanban-advance-$nodeId-${card.id}'),
                  tooltip: 'Move card',
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  onPressed: () => onCardAdvanced?.call(card.id),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskDoneToggle extends StatelessWidget {
  const _TaskDoneToggle({required this.nodeId, required this.isDone});

  final String nodeId;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      key: ValueKey('mindmap-task-toggle-$nodeId'),
      dimension: 32,
      child: Icon(
        isDone ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isDone
            ? NodeColors.task
            : Theme.of(context).textTheme.bodySmall?.color,
        size: 20,
      ),
    );
  }
}

class _InteractiveBackgroundPainter extends CustomPainter {
  const _InteractiveBackgroundPainter({
    required this.mousePos,
    required this.showGrid,
  });

  final Offset? mousePos;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showGrid) return;

    final center = Offset(size.width / 2, size.height / 2);
    final parallaxOffset = mousePos != null
        ? (mousePos! - center) * 0.012
        : Offset.zero;

    final gridPaint = Paint()
      ..color = NeutralColors.darkBorder.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;

    final majorGridPaint = Paint()
      ..color = NeutralColors.darkBorder.withValues(alpha: 0.18)
      ..strokeWidth = 1.4;

    const step = 48.0;

    // Draw horizontal and vertical grid lines with parallax offset
    // Horizontal lines
    final startY = (parallaxOffset.dy % step) - step;
    for (var y = startY; y <= size.height + step; y += step) {
      final isMajor = ((y - parallaxOffset.dy).round() % (step * 5)).abs() < 1;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? majorGridPaint : gridPaint,
      );
    }

    // Vertical lines
    final startX = (parallaxOffset.dx % step) - step;
    for (var x = startX; x <= size.width + step; x += step) {
      final isMajor = ((x - parallaxOffset.dx).round() % (step * 5)).abs() < 1;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? majorGridPaint : gridPaint,
      );
    }

    // Draw center axes slightly differently
    final axisPaint = Paint()
      ..color = NodeColors.link.withValues(alpha: 0.22)
      ..strokeWidth = 1.6;

    final axisX = size.width / 2 + parallaxOffset.dx;
    final axisY = size.height / 2 + parallaxOffset.dy;

    canvas.drawLine(Offset(axisX, 0), Offset(axisX, size.height), axisPaint);
    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY), axisPaint);
  }

  @override
  bool shouldRepaint(covariant _InteractiveBackgroundPainter oldDelegate) {
    return oldDelegate.mousePos != mousePos || oldDelegate.showGrid != showGrid;
  }
}

class _ConnectionLinesPainter extends CustomPainter {
  _ConnectionLinesPainter({
    required this.nodes,
    required this.dragPositions,
    required this.origin,
  });

  final List<MindmapNode> nodes;
  final Map<String, CanvasPosition> dragPositions;
  final Offset origin;

  CanvasPosition _positionFor(MindmapNode node) {
    return dragPositions[node.id] ?? node.position;
  }

  Size _nodeSizeFor(MindmapNode node) {
    return node.type == NodeType.kanban
        ? MindmapCanvas.kanbanNodeSize
        : MindmapCanvas.nodeSize;
  }

  Offset _getNodeCenter(MindmapNode node) {
    final pos = _positionFor(node);
    final size = _nodeSizeFor(node);
    return origin + Offset(pos.dx + size.width / 2, pos.dy + size.height / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, MindmapNode> nodeMap = {for (final n in nodes) n.id: n};

    final Set<String> drawnConnections = {};

    for (final node in nodes) {
      final pA = _getNodeCenter(node);
      final colorA = nodeColor(node.type);

      for (final relatedId in node.relatedNodeIds) {
        if (!nodeMap.containsKey(relatedId)) continue;

        // Check duplicate
        final connKey = node.id.compareTo(relatedId) < 0
            ? '${node.id}-$relatedId'
            : '$relatedId-${node.id}';
        if (drawnConnections.contains(connKey)) continue;
        drawnConnections.add(connKey);

        final targetNode = nodeMap[relatedId]!;
        final pB = _getNodeCenter(targetNode);
        final colorB = nodeColor(targetNode.type);

        final paint = Paint()
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        // Create beautiful gradient shader
        paint.shader = ui.Gradient.linear(pA, pB, [
          colorA.withValues(alpha: 0.8),
          colorB.withValues(alpha: 0.8),
        ]);

        final path = Path()..moveTo(pA.dx, pA.dy);

        final dx = (pB.dx - pA.dx).abs();
        final dy = (pB.dy - pA.dy).abs();

        if (dx > dy) {
          final cp1 = Offset(pA.dx + (pB.dx - pA.dx) * 0.5, pA.dy);
          final cp2 = Offset(pB.dx - (pB.dx - pA.dx) * 0.5, pB.dy);
          path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pB.dx, pB.dy);
        } else {
          final cp1 = Offset(pA.dx, pA.dy + (pB.dy - pA.dy) * 0.5);
          final cp2 = Offset(pB.dx, pB.dy - (pB.dy - pA.dy) * 0.5);
          path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pB.dx, pB.dy);
        }

        // Draw shadow/glow under the line
        final glowPaint = Paint()
          ..strokeWidth = 6.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4)
          ..shader = ui.Gradient.linear(pA, pB, [
            colorA.withValues(alpha: 0.25),
            colorB.withValues(alpha: 0.25),
          ]);
        canvas.drawPath(path, glowPaint);

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionLinesPainter oldDelegate) {
    return true;
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.nodes,
    required this.dragPositions,
    required this.viewportRect,
    required this.canvasSize,
  });

  final List<MindmapNode> nodes;
  final Map<String, CanvasPosition> dragPositions;
  final Rect viewportRect;
  final Size canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / canvasSize.width;
    final scaleY = size.height / canvasSize.height;

    final origin = Offset(canvasSize.width / 2, canvasSize.height / 2);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    final Map<String, MindmapNode> nodeMap = {for (final n in nodes) n.id: n};

    CanvasPosition positionFor(MindmapNode node) {
      return dragPositions[node.id] ?? node.position;
    }

    Size nodeSizeFor(MindmapNode node) {
      return node.type == NodeType.kanban
          ? MindmapCanvas.kanbanNodeSize
          : MindmapCanvas.nodeSize;
    }

    Offset getNodeCenter(MindmapNode node) {
      final pos = positionFor(node);
      final nodeSize = nodeSizeFor(node);
      return origin +
          Offset(pos.dx + nodeSize.width / 2, pos.dy + nodeSize.height / 2);
    }

    // Draw connections
    final Set<String> drawn = {};
    for (final node in nodes) {
      final pA = getNodeCenter(node);
      for (final relId in node.relatedNodeIds) {
        if (!nodeMap.containsKey(relId)) continue;
        final key = node.id.compareTo(relId) < 0
            ? '${node.id}-$relId'
            : '$relId-${node.id}';
        if (drawn.contains(key)) continue;
        drawn.add(key);

        final pB = getNodeCenter(nodeMap[relId]!);
        canvas.drawLine(
          Offset(pA.dx * scaleX, pA.dy * scaleY),
          Offset(pB.dx * scaleX, pB.dy * scaleY),
          linePaint,
        );
      }
    }

    // Draw nodes as tiny colored rectangles
    for (final node in nodes) {
      final pos = positionFor(node);
      final nodeSize = nodeSizeFor(node);
      final rect = Rect.fromLTWH(
        (origin.dx + pos.dx) * scaleX,
        (origin.dy + pos.dy) * scaleY,
        nodeSize.width * scaleX,
        nodeSize.height * scaleY,
      );

      final color = nodeColor(node.type);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }

    // Draw viewport rectangle (the indicator box)
    final viewportRectScaled = Rect.fromLTRB(
      viewportRect.left * scaleX,
      viewportRect.top * scaleY,
      viewportRect.right * scaleX,
      viewportRect.bottom * scaleY,
    );

    final viewPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final viewBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(viewportRectScaled, viewPaint);
    canvas.drawRect(viewportRectScaled, viewBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return true;
  }
}

IconData nodeIcon(NodeType type) => switch (type) {
  NodeType.task => Icons.check_circle_outline,
  NodeType.kanban => Icons.view_kanban_outlined,
  NodeType.plan => Icons.route_outlined,
  NodeType.note => Icons.notes_outlined,
  NodeType.journal => Icons.book_outlined,
  NodeType.habit => Icons.repeat_outlined,
  NodeType.goal => Icons.flag_outlined,
  NodeType.link => Icons.link_outlined,
  NodeType.empty => Icons.crop_square_outlined,
};

Color nodeColor(NodeType type) => switch (type) {
  NodeType.task => NodeColors.task,
  NodeType.kanban => NodeColors.kanban,
  NodeType.plan => NodeColors.plan,
  NodeType.note => NodeColors.note,
  NodeType.journal => NodeColors.journal,
  NodeType.habit => NodeColors.habit,
  NodeType.goal => NodeColors.goal,
  NodeType.link => NodeColors.link,
  NodeType.empty => Colors.grey,
};

List<String> _metadataLabelsFor(MindmapNode node) {
  return [
    if (node.priority != NodePriority.none) node.priority.label,
    if (node.status != NodeStatus.open) node.status.label,
    if (node.project.isNotEmpty) 'Project: ${node.project}',
    if (node.area.isNotEmpty) 'Area: ${node.area}',
    for (final tag in node.tags.take(2)) '#$tag',
    ..._featureSpecificMetadataLabels(node),
    if (node.dueDate != null) _dueDateLabel(node.dueDate!),
    if (node.progress > 0) '${(node.progress * 100).round()}%',
    if (node.checklist.isNotEmpty)
      '${node.completedChecklistCount}/${node.checklist.length}',
    if (node.relatedNodeIds.isNotEmpty)
      _countLabel(node.relatedNodeIds.length, 'link').single,
    if (node.isPinned) 'Pinned',
    if (node.isArchived) 'Archived',
  ];
}

List<String> _featureSpecificMetadataLabels(MindmapNode node) {
  final labels = <String>[];
  if (node.data.containsKey('habit')) labels.addAll(_habitMetadataLabels(node));
  if (node.data.containsKey('goal')) labels.addAll(_goalMetadataLabels(node));
  if (node.data.containsKey('plan')) labels.addAll(_planMetadataLabels(node));
  if (node.data.containsKey('note')) {
    labels.addAll(_sourceLabel(_sectionData(node.data, 'note')['source']));
  }
  if (node.data.containsKey('journal')) {
    labels.addAll(_journalMetadataLabels(node));
  }
  if (node.data.containsKey('link')) {
    labels.addAll(_sourceLabel(_sectionData(node.data, 'link')['url']));
  }
  return labels;
}

List<String> _habitMetadataLabels(MindmapNode node) {
  final data = _sectionData(node.data, 'habit');
  final labels = <String>[];
  final recurrence = data['recurrence'];
  if (recurrence is String && recurrence.trim().isNotEmpty) {
    labels.add(_titleCase(recurrence.trim()));
  }
  final target = data['target'];
  if (target is String && target.trim().isNotEmpty) {
    labels.add(target.trim());
  }
  final streak = LifeOsSummary.habitStreakFor(node, node.day);
  if (streak > 0) labels.add('$streak streak');
  return labels;
}

List<String> _goalMetadataLabels(MindmapNode node) {
  final data = _sectionData(node.data, 'goal');
  final milestones = _stringListFromData(data['milestones']);
  if (milestones.isEmpty) return const [];

  final completedCount = _completedMilestoneCount(
    milestones,
    _stringListFromData(data['completedMilestones']),
  );
  if (completedCount == 0) return _countLabel(milestones.length, 'milestone');
  return ['$completedCount/${milestones.length} milestones'];
}

List<String> _planMetadataLabels(MindmapNode node) {
  final steps = planSteps(node);
  if (steps.isEmpty) return const [];

  final completedCount = _completedStepCount(steps, completedPlanSteps(node));
  if (completedCount == 0) return _countLabel(steps.length, 'step');
  return ['$completedCount/${steps.length} steps'];
}

List<String> _journalMetadataLabels(MindmapNode node) {
  final data = _sectionData(node.data, 'journal');
  final labels = <String>[];
  final mood = _ratingLabel(data['mood']);
  if (mood != null) labels.add('Mood $mood');
  final energy = _ratingLabel(data['energy']);
  if (energy != null) labels.add('Energy $energy');
  if (data['isWeeklyReview'] == true) labels.add('Weekly Review');
  if (data['isMonthlyReview'] == true) labels.add('Monthly Review');
  return labels;
}

int _completedMilestoneCount(List<String> milestones, List<String> completed) {
  final milestoneKeys = {for (final milestone in milestones) _key(milestone)};
  return {
    for (final milestone in completed)
      if (milestoneKeys.contains(_key(milestone))) _key(milestone),
  }.length;
}

int _completedStepCount(List<String> steps, List<String> completed) {
  final stepKeys = {for (final step in steps) _key(step)};
  return {
    for (final step in completed)
      if (stepKeys.contains(_key(step))) _key(step),
  }.length;
}

String? _ratingLabel(Object? value) {
  final rating = switch (value) {
    num() => value.round(),
    String() => int.tryParse(value.trim()),
    _ => null,
  };
  if (rating == null || rating <= 0) return null;
  return rating.clamp(1, 5).toString();
}

List<String> _countLabel(int count, String singular) {
  if (count == 0) return const [];
  final suffix = count == 1 ? singular : '${singular}s';
  return ['$count $suffix'];
}

List<String> _sourceLabel(Object? value) {
  if (value is! String || value.trim().isEmpty) return const [];
  return ['Source: ${value.trim()}'];
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final section = data[key];
  if (section is Map) return section.cast<String, Object?>();
  return const {};
}

List<String> _stringListFromData(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String _key(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _dueDateLabel(DateTime dueDate) {
  final normalizedDueDate = dueDate.dateOnly;
  final today = DateTime.now().dateOnly;
  if (normalizedDueDate.isSameDay(today)) return 'Due Today';
  return 'Due ${dayKey(normalizedDueDate)}';
}

class _NodeTypeSpecificContent extends StatelessWidget {
  const _NodeTypeSpecificContent({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: switch (node.type) {
        NodeType.task => _TaskNodeChecklist(node: node),
        NodeType.plan => _PlanNodeSteps(node: node),
        NodeType.goal => _GoalNodeMilestones(node: node),
        NodeType.habit => _HabitNodeInfo(node: node),
        NodeType.journal => _JournalNodeDetails(node: node),
        NodeType.note || NodeType.link => _NoteNodeSource(node: node),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _TaskNodeChecklist extends StatelessWidget {
  const _TaskNodeChecklist({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    if (node.checklist.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in node.checklist)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.isDone ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: item.isDone
                      ? theme.colorScheme.primary
                      : theme.iconTheme.color?.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: item.isDone
                          ? TextDecoration.lineThrough
                          : null,
                      color: item.isDone
                          ? theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.6,
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlanNodeSteps extends StatelessWidget {
  const _PlanNodeSteps({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final steps = planSteps(node);
    if (steps.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final completed = completedPlanSteps(node);
    final completedKeys = {for (final step in completed) _key(step)};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: completedKeys.contains(_key(steps[i]))
                        ? theme.colorScheme.primary
                        : theme.textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    steps[i],
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: completedKeys.contains(_key(steps[i]))
                          ? TextDecoration.lineThrough
                          : null,
                      color: completedKeys.contains(_key(steps[i]))
                          ? theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.6,
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GoalNodeMilestones extends StatelessWidget {
  const _GoalNodeMilestones({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final milestones = goalMilestones(node);
    if (milestones.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final completed = completedGoalMilestones(node);
    final completedKeys = {for (final m in completed) _key(m)};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in milestones)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  completedKeys.contains(_key(m))
                      ? Icons.flag
                      : Icons.flag_outlined,
                  size: 16,
                  color: completedKeys.contains(_key(m))
                      ? theme.colorScheme.primary
                      : theme.iconTheme.color?.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    m,
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: completedKeys.contains(_key(m))
                          ? TextDecoration.lineThrough
                          : null,
                      color: completedKeys.contains(_key(m))
                          ? theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.6,
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CalendarPayloadSummary extends StatelessWidget {
  const _CalendarPayloadSummary({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = calendarNodePayloadFromData(node.data);
    if (payload == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final details = _calendarPayloadDetails(payload);

    return Container(
      key: ValueKey('mindmap-calendar-payload-${node.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_calendarPayloadIcon(payload.kind), size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payload.subtitle, style: theme.textTheme.labelMedium),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _calendarPayloadDetails(CalendarNodePayload payload) {
  return switch (payload.kind) {
    CalendarNodeKind.event => payload.participants?.trim() ?? '',
    CalendarNodeKind.reminder => payload.reason?.trim() ?? '',
    CalendarNodeKind.meeting => payload.agenda?.trim() ?? '',
    CalendarNodeKind.decision => payload.reason?.trim() ?? '',
    CalendarNodeKind.metric => payload.value?.trim() ?? '',
  };
}

IconData _calendarPayloadIcon(CalendarNodeKind kind) {
  return switch (kind) {
    CalendarNodeKind.event => Icons.event_outlined,
    CalendarNodeKind.reminder => Icons.notifications_active_outlined,
    CalendarNodeKind.meeting => Icons.groups_outlined,
    CalendarNodeKind.decision => Icons.rule_outlined,
    CalendarNodeKind.metric => Icons.show_chart_outlined,
  };
}

class _HabitNodeInfo extends StatelessWidget {
  const _HabitNodeInfo({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _sectionData(node.data, 'habit');
    final target = data['target'] as String?;
    final recurrence = data['recurrence'] as String?;
    final completions = habitCompletionKeys(node);

    if ((target == null || target.isEmpty) &&
        (recurrence == null || recurrence.isEmpty) &&
        completions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (target != null && target.isNotEmpty) ...[
          Text('Target: $target', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
        ],
        if (recurrence != null && recurrence.isNotEmpty) ...[
          Text(
            'Recurrence: ${_titleCase(recurrence)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
        ],
        if (completions.isNotEmpty)
          Text(
            'Total completions: ${completions.length}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _JournalNodeDetails extends StatelessWidget {
  const _JournalNodeDetails({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _sectionData(node.data, 'journal');
    final prompt = data['prompt'] as String?;
    final gratitude = _stringListFromData(data['gratitude']);

    if ((prompt == null || prompt.isEmpty) && gratitude.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prompt != null && prompt.isNotEmpty) ...[
          Text(
            'Prompt: $prompt',
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (gratitude.isNotEmpty) ...[
          Text(
            'Gratitude:',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          for (final g in gratitude)
            Padding(
              padding: const EdgeInsets.only(bottom: 2, left: 8),
              child: Text('• $g', style: theme.textTheme.bodySmall),
            ),
        ],
      ],
    );
  }
}

class _NoteNodeSource extends StatelessWidget {
  const _NoteNodeSource({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = node.type == NodeType.note
        ? _sectionData(node.data, 'note')
        : _sectionData(node.data, 'link');
    final source = (data['source'] as String?) ?? (data['url'] as String?);

    if (source == null || source.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            source,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
