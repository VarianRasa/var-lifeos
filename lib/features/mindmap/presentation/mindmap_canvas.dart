/// Interactive daily mindmap canvas.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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
typedef NodeContextMenuCallback =
    FutureOr<void> Function(MindmapNode node, Offset globalPosition);
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
typedef NodeConnectionCallback =
    FutureOr<void> Function(MindmapNode source, MindmapNode target);
typedef NodeUpdateCallback = FutureOr<void> Function(MindmapNode node);
typedef CanvasContextMenuCallback =
    FutureOr<void> Function(Offset globalPosition, Offset scenePosition);
typedef ConnectedNodeCreateCallback =
    FutureOr<MindmapNode?> Function(
      MindmapNode source,
      NodeType type,
      Offset canvasPosition,
    );

const int _inlineBodyMaxWords = 1200;

enum _CanvasLayoutMode { tidy, radial, byType }

class MindmapCanvas extends StatefulWidget {
  const MindmapCanvas({
    required this.nodes,
    this.highlightedNodeId,
    this.onNodeMoved,
    this.onNodeSelected,
    this.onNodeContextMenu,
    this.onTaskDoneChanged,
    this.onTaskChecklistItemCompleted,
    this.onKanbanCardAdvanced,
    this.onHabitCompleted,
    this.onGoalMilestoneAdvanced,
    this.onPlanStepAdvanced,
    this.onNodeConnected,
    this.onNodeDisconnected,
    this.onNodeUpdated,
    this.onNodeDropped,
    this.onClearNodes,
    this.onCanvasContextMenu,
    this.onConnectedNodeCreate,
    super.key,
  });

  static const Size canvasSize = Size(20000, 14000);
  static const Size nodeSize = Size(340, 320);
  static const Size kanbanNodeSize = Size(500, 320);

  final List<MindmapNode> nodes;
  final String? highlightedNodeId;
  final NodeMoveCallback? onNodeMoved;
  final NodeSelectionCallback? onNodeSelected;
  final NodeContextMenuCallback? onNodeContextMenu;
  final TaskDoneCallback? onTaskDoneChanged;
  final TaskChecklistItemCompletedCallback? onTaskChecklistItemCompleted;
  final KanbanCardAdvanceCallback? onKanbanCardAdvanced;
  final HabitCompletedCallback? onHabitCompleted;
  final GoalMilestoneAdvanceCallback? onGoalMilestoneAdvanced;
  final PlanStepAdvanceCallback? onPlanStepAdvanced;
  final NodeConnectionCallback? onNodeConnected;
  final NodeConnectionCallback? onNodeDisconnected;
  final NodeUpdateCallback? onNodeUpdated;
  final void Function(NodeType type, Offset scenePosition)? onNodeDropped;
  final FutureOr<void> Function()? onClearNodes;
  final CanvasContextMenuCallback? onCanvasContextMenu;
  final ConnectedNodeCreateCallback? onConnectedNodeCreate;

  @override
  State<MindmapCanvas> createState() => MindmapCanvasState();
}

class MindmapCanvasState extends State<MindmapCanvas>
    with TickerProviderStateMixin {
  final Map<String, CanvasPosition> _dragPositions = {};
  final TransformationController _transformationController =
      TransformationController();
  bool _didSetInitialTransform = false;

  Offset? _mousePos;
  final List<Offset> _cursorTrail = [];
  bool _showGrid = true;
  bool _snapToGrid = false;
  bool _isCtrlZoomActive = false;
  bool _isCanvasToolbarCollapsed = true;
  bool _isMinimapCollapsed = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  NodeType? _searchTypeFilter;
  bool _isSearchOverlayCollapsed = true;
  String? _lastSelectedNodeId;
  final Set<String> _selectedNodeIds = <String>{};
  final Set<String> _editingNodeIds = <String>{};
  String? _focusedNodeId;
  late AnimationController _zoomAnimController;
  late AnimationController _cursorAnimController;
  Matrix4 _startZoomMatrix = Matrix4.identity();
  Matrix4 _targetZoomMatrix = Matrix4.identity();
  DateTime? _lastCanvasTapAt;
  DateTime? _lastHoverPaintAt;
  Offset? _lastCanvasTapLocal;
  List<MindmapNode> _copiedNodes = const [];
  Offset? _lassoStartLocal;
  Offset? _lassoCurrentLocal;
  Offset? _middlePanLastLocal;
  _ConnectionDrag? _connectionDrag;
  Rect? _visibleSceneRect;
  Timer? _viewportUpdateTimer;
  bool _viewportUpdateQueued = false;
  bool get _isHeavyCanvas => widget.nodes.length > 60;

  @override
  void initState() {
    super.initState();
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _zoomAnimController.addListener(_onZoomAnimUpdate);
    _transformationController.addListener(_scheduleViewportUpdate);
    _cursorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _cursorAnimController.addListener(_onCursorAnimUpdate);
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  void _scheduleViewportUpdate() {
    if (_viewportUpdateQueued || !mounted) return;
    _viewportUpdateQueued = true;
    _viewportUpdateTimer?.cancel();
    _viewportUpdateTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      _viewportUpdateQueued = false;
      final size = context.size;
      if (size == null) return;
      final topLeft = _transformationController.toScene(Offset.zero);
      final bottomRight = _transformationController.toScene(
        Offset(size.width, size.height),
      );
      setState(() {
        _visibleSceneRect = Rect.fromPoints(topLeft, bottomRight).inflate(520);
      });
    });
  }

  bool _isNodeVisible(MindmapNode node, Offset origin) {
    final rect = _visibleSceneRect;
    if (rect == null) return true;
    if (_selectedNodeIds.contains(node.id) ||
        node.id == widget.highlightedNodeId ||
        _dragPositions.containsKey(node.id)) {
      return true;
    }
    final position = _positionFor(node);
    final nodeRect = Rect.fromLTWH(
      origin.dx + position.dx,
      origin.dy + position.dy,
      _nodeSizeFor(node).width,
      _nodeSizeFor(node).height,
    );
    return rect.overlaps(nodeRect);
  }

  void _onCursorAnimUpdate() {
    if (!mounted) return;
    if (_mousePos == null && _cursorTrail.isEmpty) {
      _cursorAnimController.stop();
      return;
    }
    setState(() {
      if (_mousePos == null && _cursorTrail.isNotEmpty) {
        _cursorTrail.removeAt(0);
      }
    });
  }

  @override
  void dispose() {
    _viewportUpdateTimer?.cancel();
    _zoomAnimController.dispose();
    _cursorAnimController.dispose();
    _transformationController.removeListener(_scheduleViewportUpdate);
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

    final targetMatrix =
        Matrix4.translationValues(tx, ty, 0) *
                Matrix4.diagonal3Values(scale, scale, 1)
            as Matrix4;

    _zoomAnimController.stop();
    _startZoomMatrix = _transformationController.value.clone();
    _targetZoomMatrix = targetMatrix;
    _zoomAnimController.forward(from: 0.0);
  }

  void _zoomToSelected() {
    final viewportSize = context.size;
    if (viewportSize == null || _selectedNodeIds.isEmpty) return;
    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );
    Rect? bounds;
    for (final node in widget.nodes) {
      if (!_selectedNodeIds.contains(node.id)) continue;
      final position = _positionFor(node);
      final rect =
          (origin + Offset(position.dx, position.dy)) & _nodeSizeFor(node);
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    if (bounds == null) return;
    final padded = bounds.inflate(120);
    final scaleX = viewportSize.width / padded.width;
    final scaleY = viewportSize.height / padded.height;
    final scale = math.min(scaleX, scaleY).clamp(0.25, 1.8).toDouble();
    final tx = viewportSize.width / 2 - padded.center.dx * scale;
    final ty = viewportSize.height / 2 - padded.center.dy * scale;
    final targetMatrix =
        Matrix4.translationValues(tx, ty, 0) *
                Matrix4.diagonal3Values(scale, scale, 1)
            as Matrix4;
    _zoomAnimController.stop();
    _startZoomMatrix = _transformationController.value.clone();
    _targetZoomMatrix = targetMatrix;
    _zoomAnimController.forward(from: 0.0);
  }

  void _zoom(double factor) {
    final viewportSize = context.size;
    if (viewportSize == null) return;
    _zoomAt(Offset(viewportSize.width / 2, viewportSize.height / 2), factor);
  }

  void _zoomAt(Offset localFocalPoint, double factor) {
    final sceneFocalPoint = _transformationController.toScene(localFocalPoint);
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * factor).clamp(0.04, 2.4).toDouble();
    final tx = localFocalPoint.dx - sceneFocalPoint.dx * newScale;
    final ty = localFocalPoint.dy - sceneFocalPoint.dy * newScale;
    final targetMatrix = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(newScale, newScale, newScale, 1);

    _zoomAnimController.stop();
    _transformationController.value = targetMatrix;
  }

  bool get _isCtrlPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return _isCtrlZoomActive ||
        HardwareKeyboard.instance.isControlPressed ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  bool get _isLassoModifierPressed => HardwareKeyboard.instance.isShiftPressed;

  void _handleCanvasPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_isCtrlPressed) return;
    _zoomAt(event.localPosition, event.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12);
  }

  KeyEventResult _handleCanvasKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.controlLeft &&
        event.logicalKey != LogicalKeyboardKey.controlRight &&
        event.logicalKey != LogicalKeyboardKey.metaLeft &&
        event.logicalKey != LogicalKeyboardKey.metaRight) {
      return KeyEventResult.ignored;
    }
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    if (_isCtrlZoomActive != isDown) {
      setState(() => _isCtrlZoomActive = isDown);
    }
    return KeyEventResult.ignored;
  }

  void _zoomIn() => _zoom(1.2);
  void _zoomOut() => _zoom(1 / 1.2);

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchTypeFilter = null;
    });
  }

  void _setSearchTypeFilter(NodeType? type) {
    setState(() => _searchTypeFilter = type);
  }

  void _setSearchOverlayCollapsed(bool value) {
    setState(() => _isSearchOverlayCollapsed = value);
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

    final targetMatrix = Matrix4.translationValues(
      (viewportSize.width - MindmapCanvas.canvasSize.width) / 2,
      (viewportSize.height - MindmapCanvas.canvasSize.height) / 2,
      0,
    );

    _zoomAnimController.stop();
    _startZoomMatrix = _transformationController.value.clone();
    _targetZoomMatrix = targetMatrix;
    _zoomAnimController.forward(from: 0.0);
  }

  void _onZoomAnimUpdate() {
    final t = Curves.easeOut.transform(_zoomAnimController.value);
    _transformationController.value = Matrix4Tween(
      begin: _startZoomMatrix,
      end: _targetZoomMatrix,
    ).transform(t);
  }

  Rect _viewportRectInSceneOf(Size viewportSize) {
    if (viewportSize == Size.zero) return Rect.zero;

    final topLeftScene = _transformationController.toScene(Offset.zero);
    final bottomRightScene = _transformationController.toScene(
      Offset(viewportSize.width, viewportSize.height),
    );

    return Rect.fromPoints(topLeftScene, bottomRightScene);
  }

  Offset _alignedCanvasPositionFromLocal(Offset localPosition) {
    final sceneOffset = _transformationController.toScene(localPosition);
    return _alignedCanvasPositionFromScene(sceneOffset, NodeType.task);
  }

  Offset _alignedCanvasPositionFromScene(Offset scenePosition, NodeType type) {
    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );
    final nodeSize = type == NodeType.kanban
        ? MindmapCanvas.kanbanNodeSize
        : MindmapCanvas.nodeSize;
    return scenePosition -
        origin -
        Offset(nodeSize.width / 2, nodeSize.height / 2);
  }

  void _openCanvasContextMenu(PointerDownEvent event) {
    if (event.buttons == kMiddleMouseButton) {
      _middlePanLastLocal = event.localPosition;
      return;
    }
    if (event.buttons == kPrimaryMouseButton && _isLassoModifierPressed) {
      final scenePosition = _transformationController.toScene(
        event.localPosition,
      );
      if (_nodeAtScene(scenePosition) != null) return;
      setState(() {
        _lassoStartLocal = event.localPosition;
        _lassoCurrentLocal = event.localPosition;
      });
      return;
    }
    if (event.buttons != kSecondaryMouseButton ||
        widget.onCanvasContextMenu == null) {
      return;
    }
    widget.onCanvasContextMenu!(
      event.position,
      _alignedCanvasPositionFromLocal(event.localPosition),
    );
  }

  void _handleCanvasPointerMove(PointerMoveEvent event) {
    final middlePanLastLocal = _middlePanLastLocal;
    if (middlePanLastLocal != null) {
      final delta = event.localPosition - middlePanLastLocal;
      _middlePanLastLocal = event.localPosition;
      _transformationController.value = Matrix4.translationValues(
        delta.dx,
        delta.dy,
        0,
      )..multiply(_transformationController.value);
      return;
    }
    if (_lassoStartLocal == null) return;
    setState(() => _lassoCurrentLocal = event.localPosition);
  }

  void _finishLasso(PointerUpEvent event, Offset origin) {
    final start = _lassoStartLocal;
    final current = _lassoCurrentLocal;
    if (start == null || current == null) return;
    final localRect = Rect.fromPoints(start, current);
    final sceneA = _transformationController.toScene(localRect.topLeft);
    final sceneB = _transformationController.toScene(localRect.bottomRight);
    final sceneRect = Rect.fromPoints(sceneA, sceneB);
    final selected = <String>{};
    for (final node in widget.nodes) {
      final position = _positionFor(node);
      final nodeTopLeft = Offset(
        position.dx + origin.dx,
        position.dy + origin.dy,
      );
      final nodeRect = nodeTopLeft & _nodeSizeFor(node);
      if (sceneRect.overlaps(nodeRect)) selected.add(node.id);
    }
    setState(() {
      _lassoStartLocal = null;
      _lassoCurrentLocal = null;
      _selectedNodeIds
        ..clear()
        ..addAll(selected);
      if (selected.isNotEmpty) _lastSelectedNodeId = selected.last;
    });
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

    // Keep optimistic drag positions visible while persistence catches up.
    // Dropping them on any refresh makes nodes snap back before the saved
    // position arrives.
    for (final node in widget.nodes) {
      final dragPosition = _dragPositions[node.id];
      if (dragPosition == null) continue;
      final persistedPosition = node.position;
      if (dragPosition.dx == persistedPosition.dx &&
          dragPosition.dy == persistedPosition.dy) {
        _dragPositions.remove(node.id);
      }
    }
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
                widget.onNodeDropped!(
                  details.data,
                  _alignedCanvasPositionFromLocal(localOffset),
                );
              }
            },
            builder: (context, candidateData, rejectedData) {
              final focusNode = _focusedNode();
              final focusIds = focusNode == null
                  ? const <String>{}
                  : <String>{
                      focusNode.id,
                      ...focusNode.relatedNodeIds,
                      for (final node in widget.nodes)
                        if (node.relatedNodeIds.contains(focusNode.id)) node.id,
                    };
              final filteredNodes = widget.nodes.where((node) {
                final matchesText =
                    _searchQuery.isEmpty ||
                    _nodeMatchesSearch(node, _searchQuery);
                final matchesType =
                    _searchTypeFilter == null || node.type == _searchTypeFilter;
                final matchesFocus =
                    focusNode == null || focusIds.contains(node.id);
                return matchesText && matchesType && matchesFocus;
              }).toList();
              final isSearchActive =
                  _searchQuery.isNotEmpty || _searchTypeFilter != null;
              final isFocusActive = focusNode != null;
              final visibleNodes = filteredNodes
                  .where((node) => _isNodeVisible(node, origin))
                  .toList(growable: false);
              final scale = _transformationController.value.getMaxScaleOnAxis();
              final useCompactCards = _isHeavyCanvas || scale < 0.45;
              final highlightedNodeIds = {
                if (isSearchActive)
                  for (final node in filteredNodes) node.id,
                ..._selectedNodeIds,
                if (widget.highlightedNodeId != null) widget.highlightedNodeId!,
              };
              final compactNodeIds = {
                if (useCompactCards)
                  for (final node in visibleNodes)
                    if (!_selectedNodeIds.contains(node.id) &&
                        !_editingNodeIds.contains(node.id) &&
                        node.id != widget.highlightedNodeId)
                      node.id,
              };

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
                    LogicalKeyboardKey.keyC,
                    control: true,
                  ): () =>
                      unawaited(_copySelectedNodes()),
                  const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    control: true,
                  ): () =>
                      unawaited(_pasteCopiedNodes()),
                  const SingleActivator(
                    LogicalKeyboardKey.keyD,
                    control: true,
                  ): () =>
                      unawaited(_duplicateSelectedNodes()),
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    if (_lassoStartLocal != null ||
                        _selectedNodeIds.isNotEmpty) {
                      setState(() {
                        _lassoStartLocal = null;
                        _lassoCurrentLocal = null;
                        _selectedNodeIds.clear();
                      });
                    } else if (_focusedNodeId != null) {
                      setState(() => _focusedNodeId = null);
                    } else {
                      _clearSearch();
                    }
                  },
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
                  onKeyEvent: _handleCanvasKeyEvent,
                  child: Stack(
                    children: [
                      if (widget.nodes.isEmpty)
                        Center(
                          child: _CanvasEmptyHint(
                            onAddHint: widget.onCanvasContextMenu == null
                                ? 'Drop a type here to add your first node'
                                : 'Right click empty canvas to add a node',
                          ),
                        ),
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerSignal: _handleCanvasPointerSignal,
                        onPointerDown: _openCanvasContextMenu,
                        onPointerMove: _handleCanvasPointerMove,
                        onPointerUp: (event) {
                          if (_middlePanLastLocal != null) {
                            _middlePanLastLocal = null;
                            return;
                          }
                          if (_lassoStartLocal != null) {
                            _finishLasso(event, origin);
                            return;
                          }
                          final now = DateTime.now();
                          final previousTapAt = _lastCanvasTapAt;
                          final previousTapLocal = _lastCanvasTapLocal;
                          _lastCanvasTapAt = now;
                          _lastCanvasTapLocal = event.localPosition;
                          if (previousTapAt == null ||
                              previousTapLocal == null ||
                              now.difference(previousTapAt) >
                                  const Duration(milliseconds: 320) ||
                              (event.localPosition - previousTapLocal)
                                      .distance >
                                  28) {
                            return;
                          }

                          final scenePosition = _transformationController
                              .toScene(event.localPosition);
                          final canvasOrigin = Offset(
                            MindmapCanvas.canvasSize.width / 2,
                            MindmapCanvas.canvasSize.height / 2,
                          );
                          focusOnPosition(
                            CanvasPosition(
                              scenePosition.dx - canvasOrigin.dx,
                              scenePosition.dy - canvasOrigin.dy,
                            ),
                            scale: 1.5,
                          );
                        },
                        child: InteractiveViewer(
                          key: const ValueKey('mindmap-canvas'),
                          transformationController: _transformationController,
                          constrained: false,
                          boundaryMargin: EdgeInsets.all(
                            MindmapCanvas.canvasSize.shortestSide * 0.2,
                          ),
                          minScale: 0.04,
                          maxScale: 2.4,
                          panEnabled: false,
                          scaleEnabled: _isCtrlPressed,
                          trackpadScrollCausesScale: _isCtrlPressed,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerSignal: _handleCanvasPointerSignal,
                            child: SizedBox(
                              width: MindmapCanvas.canvasSize.width,
                              height: MindmapCanvas.canvasSize.height,
                              child: MouseRegion(
                                onHover: (event) {
                                  if (_isHeavyCanvas) return;
                                  final now = DateTime.now();
                                  if (_lastHoverPaintAt != null &&
                                      now.difference(_lastHoverPaintAt!) <
                                          const Duration(milliseconds: 48)) {
                                    return;
                                  }
                                  _lastHoverPaintAt = now;
                                  setState(() {
                                    _mousePos = event.localPosition;
                                    _cursorTrail.clear();
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
                                          mousePos: _isHeavyCanvas
                                              ? null
                                              : _mousePos,
                                          cursorTrail: _isHeavyCanvas
                                              ? const []
                                              : List<Offset>.unmodifiable(
                                                  _cursorTrail,
                                                ),
                                          animationValue: _isHeavyCanvas
                                              ? 0
                                              : _cursorAnimController.value,
                                          showGrid:
                                              _showGrid && !_isHeavyCanvas,
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _ConnectionLinesPainter(
                                          nodes:
                                              _isHeavyCanvas &&
                                                  _selectedNodeIds.isEmpty &&
                                                  highlightedNodeIds.isEmpty
                                              ? const <MindmapNode>[]
                                              : visibleNodes,
                                          dragPositions: _dragPositions,
                                          origin: origin,
                                          compactNodeIds: compactNodeIds,
                                        ),
                                      ),
                                    ),
                                    if (_connectionDrag != null)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: CustomPaint(
                                            painter: _ConnectionDragPainter(
                                              drag: _connectionDrag!,
                                            ),
                                          ),
                                        ),
                                      ),
                                    for (final node in visibleNodes)
                                      _PositionedNode(
                                        node: node,
                                        position: _positionFor(node),
                                        size: _nodeSizeFor(node),
                                        origin: origin,
                                        isMovementLocked: _editingNodeIds
                                            .contains(node.id),
                                        enableHoverEffects: false,
                                        onInlineEditingChanged: (isEditing) {
                                          setState(() {
                                            if (isEditing) {
                                              _editingNodeIds.add(node.id);
                                            } else {
                                              _editingNodeIds.remove(node.id);
                                            }
                                          });
                                        },
                                        isHighlighted: highlightedNodeIds
                                            .contains(node.id),
                                        isCompact: compactNodeIds.contains(
                                          node.id,
                                        ),
                                        onPointerDown: () {},
                                        onPointerUp: () {},
                                        onPanUpdate: (delta) =>
                                            _moveNode(node, delta),
                                        onPanEnd: () => _finishMove(node),
                                        onConnectionStart: (globalPosition) =>
                                            _startConnectionDrag(
                                              node,
                                              globalPosition,
                                            ),
                                        onConnectionUpdate:
                                            _updateConnectionDrag,
                                        onConnectionEnd: _finishConnectionDrag,
                                        onNodeUpdated: widget.onNodeUpdated,
                                        onSelect: () => _selectNode(node),
                                        onContextMenu: (globalPosition) =>
                                            widget.onNodeContextMenu?.call(
                                              node,
                                              globalPosition,
                                            ),
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
                                            : () => widget.onHabitCompleted
                                                  ?.call(node),
                                        onGoalMilestoneAdvanced:
                                            widget.onGoalMilestoneAdvanced ==
                                                null
                                            ? null
                                            : () => widget
                                                  .onGoalMilestoneAdvanced
                                                  ?.call(node),
                                        onPlanStepAdvanced:
                                            widget.onPlanStepAdvanced == null
                                            ? null
                                            : () => widget.onPlanStepAdvanced
                                                  ?.call(node),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: _CanvasSearchOverlay(
                          searchController: _searchController,
                          searchFocusNode: _searchFocusNode,
                          isSearchActive: isSearchActive,
                          filteredCount: filteredNodes.length,
                          selectedType: _searchTypeFilter,
                          isCollapsed: _isSearchOverlayCollapsed,
                          onClearSearch: _clearSearch,
                          onTypeSelected: _setSearchTypeFilter,
                          onCollapsedChanged: _setSearchOverlayCollapsed,
                          onSubmitted: () =>
                              _focusFirstSearchResult(filteredNodes),
                        ),
                      ),
                      if (_lassoStartLocal != null &&
                          _lassoCurrentLocal != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _LassoSelectionPainter(
                                rect: Rect.fromPoints(
                                  _lassoStartLocal!,
                                  _lassoCurrentLocal!,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_selectedNodeIds.length > 1)
                        Positioned(
                          top: 86,
                          right: 16,
                          child: _MultiSelectToolbar(
                            count: _selectedNodeIds.length,
                            onComplete: () =>
                                unawaited(_completeSelectedNodes()),
                            onStatusChanged: (status) =>
                                unawaited(_setSelectedStatus(status)),
                            onPriorityChanged: (priority) =>
                                unawaited(_setSelectedPriority(priority)),
                            onTag: () => unawaited(_tagSelectedNodes()),
                            onProject: () => unawaited(_setSelectedProject()),
                            onClearProject: () =>
                                unawaited(_clearSelectedProject()),
                            onArea: () => unawaited(_setSelectedArea()),
                            onClearArea: () => unawaited(_clearSelectedArea()),
                            onClearTags: () => unawaited(_clearSelectedTags()),
                            onDueDate: () => unawaited(_setSelectedDueDate()),
                            onClearDueDate: () =>
                                unawaited(_clearSelectedDueDate()),
                            onAlignHorizontal: () => unawaited(
                              _alignSelectedNodes(horizontal: true),
                            ),
                            onAlignVertical: () => unawaited(
                              _alignSelectedNodes(horizontal: false),
                            ),
                            onDistributeHorizontal: () => unawaited(
                              _distributeSelectedNodes(horizontal: true),
                            ),
                            onDistributeVertical: () => unawaited(
                              _distributeSelectedNodes(horizontal: false),
                            ),
                            onZoomToSelected: _zoomToSelected,
                            onCopy: () => unawaited(_copySelectedNodes()),
                            onPaste: () => unawaited(_pasteCopiedNodes()),
                            onDuplicate: () =>
                                unawaited(_duplicateSelectedNodes()),
                            onArchive: () => unawaited(_archiveSelectedNodes()),
                            onClear: _clearMultiSelection,
                          ),
                        ),
                      if (isFocusActive)
                        Positioned(
                          top: 86,
                          left: 16,
                          child: _FocusModeBanner(
                            title: focusNode.title,
                            visibleCount: filteredNodes.length,
                            onClear: () =>
                                setState(() => _focusedNodeId = null),
                          ),
                        ),
                      if (isSearchActive && filteredNodes.isEmpty)
                        Center(
                          child: _CanvasSearchEmptyState(
                            query: _searchQuery.isEmpty
                                ? _searchTypeFilter?.label ?? 'filter'
                                : _searchQuery,
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
                      if (!_isHeavyCanvas)
                        ValueListenableBuilder<Matrix4>(
                          valueListenable: _transformationController,
                          builder: (context, value, child) {
                            return Positioned(
                              bottom: 16,
                              right: 16,
                              child: _buildMinimap(
                                context,
                                constraints.biggest,
                              ),
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

  void _focusFirstSearchResult(List<MindmapNode> filteredNodes) {
    if ((_searchQuery.isEmpty && _searchTypeFilter == null) ||
        filteredNodes.isEmpty) {
      return;
    }
    focusOnPosition(filteredNodes.first.position, scale: 1.25);
    _selectNode(filteredNodes.first);
  }

  MindmapNode? _focusedNode() {
    final id = _focusedNodeId;
    if (id == null) return null;
    for (final node in widget.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  MindmapNode? _selectedNode() {
    final id = _lastSelectedNodeId ?? widget.highlightedNodeId;
    if (id == null) return null;
    for (final node in widget.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  void _selectNode(MindmapNode node) {
    final isMultiSelect =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    setState(() {
      _lastSelectedNodeId = node.id;
      if (isMultiSelect) {
        if (!_selectedNodeIds.remove(node.id)) _selectedNodeIds.add(node.id);
      } else {
        _selectedNodeIds
          ..clear()
          ..add(node.id);
      }
    });
    widget.onNodeSelected?.call(node);
  }

  void _clearMultiSelection() {
    setState(_selectedNodeIds.clear);
  }

  Future<void> _completeSelectedNodes() async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final selected = widget.nodes.where(
      (node) =>
          _selectedNodeIds.contains(node.id) &&
          (node.type == NodeType.task || node.type == NodeType.habit),
    );
    for (final node in selected) {
      await callback(
        node.copyWith(
          isDone: true,
          status: NodeStatus.done,
          progress: 1,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _setSelectedStatus(NodeStatus status) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final selected = widget.nodes.where(
      (node) => _selectedNodeIds.contains(node.id),
    );
    for (final node in selected) {
      await callback(
        node.copyWith(
          status: status,
          isDone: status == NodeStatus.done,
          progress: status == NodeStatus.done ? 1 : node.progress,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _setSelectedPriority(NodePriority priority) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final selected = widget.nodes.where(
      (node) => _selectedNodeIds.contains(node.id),
    );
    for (final node in selected) {
      await callback(
        node.copyWith(priority: priority, updatedAt: DateTime.now()),
      );
    }
  }

  Future<void> _tagSelectedNodes() async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tag selected nodes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tag == null || tag.isEmpty) return;
    final selected = widget.nodes.where(
      (node) => _selectedNodeIds.contains(node.id),
    );
    for (final node in selected) {
      if (node.tags.contains(tag)) continue;
      await callback(
        node.copyWith(tags: [...node.tags, tag], updatedAt: DateTime.now()),
      );
    }
  }

  Future<void> _setSelectedProject() async {
    final value = await _promptForBatchText(
      title: 'Set selected project',
      label: 'Project',
    );
    if (value == null) return;
    await _updateSelectedNodes(
      (node) => node.copyWith(project: value, updatedAt: DateTime.now()),
    );
  }

  Future<void> _clearSelectedProject() async {
    await _updateSelectedNodes(
      (node) => node.copyWith(project: '', updatedAt: DateTime.now()),
    );
  }

  Future<void> _setSelectedArea() async {
    final value = await _promptForBatchText(
      title: 'Set selected area',
      label: 'Area',
    );
    if (value == null) return;
    await _updateSelectedNodes(
      (node) => node.copyWith(area: value, updatedAt: DateTime.now()),
    );
  }

  Future<void> _clearSelectedArea() async {
    await _updateSelectedNodes(
      (node) => node.copyWith(area: '', updatedAt: DateTime.now()),
    );
  }

  Future<void> _clearSelectedTags() async {
    await _updateSelectedNodes(
      (node) => node.copyWith(tags: const [], updatedAt: DateTime.now()),
    );
  }

  Future<void> _setSelectedDueDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
    );
    if (picked == null) return;
    await _updateSelectedNodes(
      (node) => node.copyWith(dueDate: picked, updatedAt: DateTime.now()),
    );
  }

  Future<void> _clearSelectedDueDate() async {
    await _updateSelectedNodes(
      (node) => node.copyWith(clearDueDate: true, updatedAt: DateTime.now()),
    );
  }

  Future<String?> _promptForBatchText({
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> _updateSelectedNodes(
    MindmapNode Function(MindmapNode) update,
  ) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final selected = widget.nodes.where(
      (node) => _selectedNodeIds.contains(node.id),
    );
    for (final node in selected) {
      await callback(update(node));
    }
  }

  Future<void> _alignSelectedNodes({required bool horizontal}) async {
    final callback = widget.onNodeMoved;
    if (callback == null) return;
    final selected = widget.nodes
        .where((node) => _selectedNodeIds.contains(node.id))
        .toList(growable: false);
    if (selected.length < 2) return;
    final average = horizontal
        ? selected.map((node) => node.position.dy).reduce((a, b) => a + b) /
              selected.length
        : selected.map((node) => node.position.dx).reduce((a, b) => a + b) /
              selected.length;
    for (final node in selected) {
      await callback(
        node,
        horizontal
            ? CanvasPosition(node.position.dx, average)
            : CanvasPosition(average, node.position.dy),
      );
    }
  }

  Future<void> _distributeSelectedNodes({required bool horizontal}) async {
    final callback = widget.onNodeMoved;
    if (callback == null) return;
    final selected =
        widget.nodes
            .where((node) => _selectedNodeIds.contains(node.id))
            .toList(growable: false)
          ..sort(
            (a, b) => horizontal
                ? a.position.dx.compareTo(b.position.dx)
                : a.position.dy.compareTo(b.position.dy),
          );
    if (selected.length < 3) return;
    final first = horizontal
        ? selected.first.position.dx
        : selected.first.position.dy;
    final last = horizontal
        ? selected.last.position.dx
        : selected.last.position.dy;
    final step = (last - first) / (selected.length - 1);
    for (var index = 0; index < selected.length; index++) {
      final node = selected[index];
      final value = first + step * index;
      await callback(
        node,
        horizontal
            ? CanvasPosition(value, node.position.dy)
            : CanvasPosition(node.position.dx, value),
      );
    }
  }

  List<MindmapNode> _selectedNodes() {
    return widget.nodes
        .where((node) => _selectedNodeIds.contains(node.id))
        .toList(growable: false);
  }

  Future<void> _copySelectedNodes() async {
    final selected = _selectedNodes();
    if (selected.isEmpty) return;
    _copiedNodes = selected;
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode({
          'kind': 'var.mindmap.nodes',
          'nodes': [for (final node in selected) node.toJson()],
        }),
      ),
    );
  }

  Future<void> _pasteCopiedNodes() async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    var nodes = _copiedNodes;
    if (nodes.isEmpty) {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      nodes = _decodeCopiedNodes(clipboard?.text);
    }
    if (nodes.isEmpty) return;
    await _insertNodeCopies(nodes, offset: const Offset(36, 36));
  }

  Future<void> _duplicateSelectedNodes() async {
    final selected = _selectedNodes();
    if (selected.isEmpty) return;
    await _insertNodeCopies(selected, offset: const Offset(42, 42));
  }

  Future<void> _insertNodeCopies(
    List<MindmapNode> nodes, {
    required Offset offset,
  }) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final now = DateTime.now();
    final createdIds = <String>{};
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final copy = node.copyWith(
        id: 'copy-${now.microsecondsSinceEpoch}-$index',
        title: node.title.endsWith(' copy') ? node.title : '${node.title} copy',
        position: CanvasPosition(
          node.position.dx + offset.dx,
          node.position.dy + offset.dy,
        ),
        relatedNodeIds: const [],
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );
      await callback(copy);
      createdIds.add(copy.id);
    }
    if (mounted) {
      setState(() {
        _selectedNodeIds
          ..clear()
          ..addAll(createdIds);
        _lastSelectedNodeId = createdIds.isEmpty ? null : createdIds.last;
      });
    }
  }

  List<MindmapNode> _decodeCopiedNodes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const [];
      final nodes = decoded['nodes'];
      if (decoded['kind'] != 'var.mindmap.nodes' || nodes is! List<Object?>) {
        return const [];
      }
      return nodes
          .whereType<Map<Object?, Object?>>()
          .map((node) => MindmapNode.fromJson(node.cast<String, Object?>()))
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> _archiveSelectedNodes() async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final selected = widget.nodes.where(
      (node) => _selectedNodeIds.contains(node.id),
    );
    for (final node in selected) {
      await callback(
        node.copyWith(isArchived: true, updatedAt: DateTime.now()),
      );
    }
    if (mounted) setState(_selectedNodeIds.clear);
  }

  void _toggleFocusMode() {
    final focusNode = _focusedNode();
    if (focusNode != null) {
      setState(() => _focusedNodeId = null);
      return;
    }
    final selectedNode = _selectedNode();
    if (selectedNode == null) return;
    setState(() => _focusedNodeId = selectedNode.id);
    focusOnPosition(selectedNode.position, scale: 1.18);
  }

  bool _nodeMatchesSearch(MindmapNode node, String query) {
    return node.title.toLowerCase().contains(query) ||
        node.body.toLowerCase().contains(query) ||
        node.type.name.contains(query) ||
        node.type.label.toLowerCase().contains(query) ||
        node.project.toLowerCase().contains(query) ||
        node.area.toLowerCase().contains(query) ||
        node.tags.any((t) => t.toLowerCase().contains(query)) ||
        node.status.name.toLowerCase().contains(query) ||
        node.priority.name.toLowerCase().contains(query);
  }

  Widget _buildCanvasToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    if (_isCanvasToolbarCollapsed) {
      return _OverlayMiniToggle(
        tooltip: 'Show canvas controls',
        icon: Icons.tune_rounded,
        label: '${(currentScale * 100).round()}%',
        onPressed: () => setState(() => _isCanvasToolbarCollapsed = false),
      );
    }

    return Material(
      color: Colors.transparent,
      child: _ChalkPanel(
        accent: theme.colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom Out',
              icon: const Icon(Icons.zoom_out, size: 20),
              onPressed: _zoomOut,
            ),
            _ToolbarPill(label: '${(currentScale * 100).round()}%'),
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
            PopupMenuButton<_CanvasLayoutMode>(
              tooltip: 'Auto layout',
              icon: const Icon(Icons.auto_awesome_motion_outlined, size: 20),
              enabled: widget.nodes.length > 1 && widget.onNodeMoved != null,
              onSelected: _applyAutoLayout,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _CanvasLayoutMode.tidy,
                  child: Text('Tidy grid'),
                ),
                PopupMenuItem(
                  value: _CanvasLayoutMode.radial,
                  child: Text('Radial'),
                ),
                PopupMenuItem(
                  value: _CanvasLayoutMode.byType,
                  child: Text('By type'),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Zoom to selected',
              icon: const Icon(Icons.fit_screen_outlined, size: 20),
              onPressed: _selectedNodeIds.isEmpty ? null : _zoomToSelected,
            ),
            IconButton(
              tooltip: _focusedNodeId == null
                  ? 'Focus selected node'
                  : 'Clear focus mode',
              icon: Icon(
                _focusedNodeId == null
                    ? Icons.filter_center_focus_outlined
                    : Icons.filter_center_focus,
                size: 20,
                color: _focusedNodeId == null
                    ? null
                    : theme.colorScheme.primary,
              ),
              onPressed: _selectedNode() == null && _focusedNodeId == null
                  ? null
                  : _toggleFocusMode,
            ),
            IconButton(
              key: const ValueKey('mindmap-clear-nodes'),
              tooltip: 'Clear all nodes',
              icon: Icon(
                Icons.cleaning_services_outlined,
                size: 20,
                color: widget.nodes.isEmpty ? null : theme.colorScheme.error,
              ),
              onPressed: widget.nodes.isEmpty ? null : widget.onClearNodes,
            ),
            IconButton(
              tooltip: 'Minimize canvas controls',
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              onPressed: () {
                setState(() => _isCanvasToolbarCollapsed = true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimap(BuildContext context, Size viewportSize) {
    if (_isMinimapCollapsed) {
      return _OverlayMiniToggle(
        tooltip: 'Show minimap',
        icon: Icons.map_outlined,
        label: 'Map',
        onPressed: () => setState(() => _isMinimapCollapsed = false),
      );
    }

    return Material(
      color: Colors.transparent,
      child: _ChalkPanel(
        width: 180,
        height: 120,
        accent: Theme.of(context).colorScheme.tertiary,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onPanUpdate: (details) =>
                      _onMinimapPan(details.localPosition),
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
            Positioned(
              top: 6,
              right: 6,
              child: _TinyOverlayButton(
                tooltip: 'Minimize minimap',
                icon: Icons.remove_rounded,
                onPressed: () => setState(() => _isMinimapCollapsed = true),
              ),
            ),
          ],
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

  Future<void> _applyAutoLayout(_CanvasLayoutMode mode) async {
    final callback = widget.onNodeMoved;
    if (callback == null || widget.nodes.length < 2) return;

    final positions = switch (mode) {
      _CanvasLayoutMode.tidy => _tidyGridPositions(widget.nodes),
      _CanvasLayoutMode.radial => _radialPositions(widget.nodes),
      _CanvasLayoutMode.byType => _typeGroupedPositions(widget.nodes),
    };

    setState(() {
      for (final entry in positions.entries) {
        _dragPositions[entry.key] = entry.value;
      }
    });

    for (final node in widget.nodes) {
      final position = positions[node.id];
      if (position == null) continue;
      await callback(node, position);
    }
  }

  Map<String, CanvasPosition> _tidyGridPositions(List<MindmapNode> nodes) {
    final sorted = [...nodes]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final columns = math.max(1, math.sqrt(sorted.length).ceil());
    const spacingX = 310.0;
    const spacingY = 230.0;
    final originX = -((columns - 1) * spacingX) / 2;
    return {
      for (var index = 0; index < sorted.length; index++)
        sorted[index].id: CanvasPosition(
          originX + (index % columns) * spacingX,
          -220 + (index ~/ columns) * spacingY,
        ),
    };
  }

  Map<String, CanvasPosition> _radialPositions(List<MindmapNode> nodes) {
    final sorted = [...nodes]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final radius = math.max(260.0, sorted.length * 34.0);
    return {
      for (var index = 0; index < sorted.length; index++)
        sorted[index].id: CanvasPosition(
          math.cos((math.pi * 2 * index) / sorted.length) * radius,
          math.sin((math.pi * 2 * index) / sorted.length) * radius,
        ),
    };
  }

  Map<String, CanvasPosition> _typeGroupedPositions(List<MindmapNode> nodes) {
    final groups = <NodeType, List<MindmapNode>>{};
    for (final node in nodes) {
      groups.putIfAbsent(node.type, () => []).add(node);
    }
    final positions = <String, CanvasPosition>{};
    var column = 0;
    for (final type in NodeType.values) {
      final group = groups[type];
      if (group == null || group.isEmpty) continue;
      group.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (var row = 0; row < group.length; row++) {
        positions[group[row].id] = CanvasPosition(
          -520 + column * 330,
          -260 + row * 210,
        );
      }
      column++;
    }
    return positions;
  }

  void _moveNode(MindmapNode node, Offset delta) {
    final movingNodes = _movingSelectionFor(node);
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final sceneDelta = scale == 0 ? delta : delta / scale;
    setState(() {
      for (final movingNode in movingNodes) {
        final current = _positionFor(movingNode);
        _dragPositions[movingNode.id] = CanvasPosition(
          current.dx + sceneDelta.dx,
          current.dy + sceneDelta.dy,
        );
      }
    });
  }

  List<MindmapNode> _movingSelectionFor(MindmapNode node) {
    if (_selectedNodeIds.length <= 1 || !_selectedNodeIds.contains(node.id)) {
      return [node];
    }
    return [
      for (final candidate in widget.nodes)
        if (_selectedNodeIds.contains(candidate.id)) candidate,
    ];
  }

  void _finishMove(MindmapNode node) {
    final callback = widget.onNodeMoved;
    if (callback == null) return;
    final movingNodes = _movingSelectionFor(node);
    final finalPositions = <String, CanvasPosition>{};
    for (final movingNode in movingNodes) {
      finalPositions[movingNode.id] = _snappedPosition(
        _positionFor(movingNode),
      );
    }
    if (_snapToGrid) {
      setState(() {
        for (final entry in finalPositions.entries) {
          _dragPositions[entry.key] = entry.value;
        }
      });
    }
    unawaited(_persistMovedNodes(movingNodes, finalPositions));
  }

  CanvasPosition _snappedPosition(CanvasPosition position) {
    if (!_snapToGrid) return position;
    const gridSize = 20.0;
    final snappedX = (position.dx / gridSize).round() * gridSize;
    final snappedY = (position.dy / gridSize).round() * gridSize;
    return CanvasPosition(snappedX, snappedY);
  }

  Future<void> _persistMovedNodes(
    List<MindmapNode> nodes,
    Map<String, CanvasPosition> positions,
  ) async {
    final callback = widget.onNodeMoved;
    if (callback == null) return;
    for (final node in nodes) {
      final position = positions[node.id];
      if (position == null) continue;
      await callback(node, position);
    }
  }

  void _startConnectionDrag(MindmapNode source, Offset globalPosition) {
    final start = _nodeOutputScenePoint(source);
    final end = _globalToScene(globalPosition);
    setState(() {
      _connectionDrag = _ConnectionDrag(
        source: source,
        startScene: start,
        currentScene: end,
        target: _nodeAtScene(end, source.id),
      );
    });
  }

  void _updateConnectionDrag(Offset globalPosition) {
    final drag = _connectionDrag;
    if (drag == null) return;
    final scene = _globalToScene(globalPosition);
    setState(() {
      _connectionDrag = drag.copyWith(
        currentScene: scene,
        target: _nodeAtScene(scene, drag.source.id),
      );
    });
  }

  Future<void> _finishConnectionDrag(Offset globalPosition) async {
    final drag = _connectionDrag;
    if (drag == null) return;
    final scene = _globalToScene(globalPosition);
    final target = _nodeAtScene(scene, drag.source.id) ?? drag.target;
    setState(() => _connectionDrag = null);
    if (target != null) {
      if (!_isAlreadyConnected(drag.source, target)) {
        await widget.onNodeConnected?.call(drag.source, target);
      } else {
        await widget.onNodeDisconnected?.call(drag.source, target);
      }
      return;
    }
    if (!mounted) return;
    final selected = await _showConnectionTargetMenu(
      drag.source,
      globalPosition,
    );
    if (selected is MindmapNode &&
        !_isAlreadyConnected(drag.source, selected)) {
      await widget.onNodeConnected?.call(drag.source, selected);
      return;
    }
    if (selected is NodeType) {
      final createdNode = await widget.onConnectedNodeCreate?.call(
        drag.source,
        selected,
        _alignedCanvasPositionFromScene(scene, selected),
      );
      if (createdNode != null &&
          !_isAlreadyConnected(drag.source, createdNode)) {
        await widget.onNodeConnected?.call(drag.source, createdNode);
      }
    }
  }

  Offset _globalToScene(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    final local = box.globalToLocal(globalPosition);
    return _transformationController.toScene(local);
  }

  Offset _nodeOutputScenePoint(MindmapNode node) {
    final position = _positionFor(node);
    final size = _nodeSizeFor(node);
    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );
    return origin + Offset(position.dx + size.width, position.dy + 96);
  }

  MindmapNode? _nodeAtScene(Offset scenePosition, [String? sourceId]) {
    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );
    for (final node in widget.nodes.reversed) {
      if (sourceId != null && node.id == sourceId) continue;
      final pos = _positionFor(node);
      final size = _nodeSizeFor(node);
      final rect = Rect.fromLTWH(
        origin.dx + pos.dx,
        origin.dy + pos.dy,
        size.width,
        size.height,
      ).inflate(18);
      if (rect.contains(scenePosition)) return node;
    }
    return null;
  }

  bool _isAlreadyConnected(MindmapNode source, MindmapNode target) {
    return source.relatedNodeIds.contains(target.id) ||
        target.relatedNodeIds.contains(source.id);
  }

  Future<Object?> _showConnectionTargetMenu(
    MindmapNode source,
    Offset globalPosition,
  ) {
    final compatibleTypes = compatibleNodeTypes(
      source.type,
    ).where((type) => type != NodeType.empty).toList();
    final compatibleNodes = widget.nodes
        .where(
          (node) =>
              node.id != source.id &&
              !node.isArchived &&
              !_isAlreadyConnected(source, node) &&
              compatibleTypes.contains(node.type),
        )
        .toList();
    final fallbackNodes = widget.nodes
        .where(
          (node) =>
              node.id != source.id &&
              !node.isArchived &&
              !_isAlreadyConnected(source, node) &&
              !compatibleNodes.any((candidate) => candidate.id == node.id),
        )
        .take(8)
        .toList();
    final targets = [...compatibleNodes.take(12), ...fallbackNodes];
    final createTypes = widget.onConnectedNodeCreate == null
        ? const <NodeType>[]
        : compatibleTypes.take(6).toList();
    if (targets.isEmpty && createTypes.isEmpty) return Future<Object?>.value();

    const panelWidth = 320.0;
    const panelMaxHeight = 430.0;
    const margin = 12.0;
    final screenSize = MediaQuery.sizeOf(context);
    final left = globalPosition.dx.clamp(
      margin,
      (screenSize.width - panelWidth - margin).clamp(margin, screenSize.width),
    );
    final top = globalPosition.dy.clamp(
      margin,
      (screenSize.height - panelMaxHeight - margin).clamp(
        margin,
        screenSize.height,
      ),
    );

    return showGeneralDialog<Object>(
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
              child: _ConnectionTargetMenuPanel(
                source: source,
                targets: targets,
                createTypes: createTypes,
                compatibleTypes: compatibleTypes,
                onSelect: (value) => Navigator.of(context).pop(value),
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
  }

  Size _nodeSizeFor(MindmapNode node) {
    return node.type == NodeType.kanban
        ? MindmapCanvas.kanbanNodeSize
        : MindmapCanvas.nodeSize;
  }
}

class _ConnectionTargetMenuPanel extends StatefulWidget {
  const _ConnectionTargetMenuPanel({
    required this.source,
    required this.targets,
    required this.createTypes,
    required this.compatibleTypes,
    required this.onSelect,
  });

  final MindmapNode source;
  final List<MindmapNode> targets;
  final List<NodeType> createTypes;
  final List<NodeType> compatibleTypes;
  final ValueChanged<Object> onSelect;

  @override
  State<_ConnectionTargetMenuPanel> createState() =>
      _ConnectionTargetMenuPanelState();
}

class _ConnectionTargetMenuPanelState
    extends State<_ConnectionTargetMenuPanel> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targets = _query.isEmpty
        ? widget.targets
        : widget.targets
              .where((node) {
                final haystack = '${node.title} ${node.type.label} ${node.body}'
                    .toLowerCase();
                return haystack.contains(_query);
              })
              .toList(growable: false);
    final createTypes = _query.isEmpty
        ? widget.createTypes
        : widget.createTypes
              .where((type) {
                final label = type.label.toLowerCase();
                return label.contains(_query) || type.name.contains(_query);
              })
              .toList(growable: false);

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('connection-target-menu-panel'),
        width: 320,
        constraints: const BoxConstraints(maxHeight: 430),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.62),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
                child: Text(
                  'Connect ${widget.source.title} to...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextField(
                controller: _searchController,
                autofocus: true,
                minLines: 1,
                maxLines: 1,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search node or type...',
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (targets.isNotEmpty) ...[
                const _ConnectionMenuSectionLabel(label: 'Existing nodes'),
                for (final node in targets)
                  _ConnectionTargetTile(
                    icon: nodeIcon(node.type),
                    color: nodeColor(node.type),
                    title: node.title,
                    subtitle: widget.compatibleTypes.contains(node.type)
                        ? 'Suggested ${node.type.label}'
                        : node.type.label,
                    onTap: () => widget.onSelect(node),
                  ),
              ],
              if (createTypes.isNotEmpty) ...[
                if (targets.isNotEmpty) const SizedBox(height: 8),
                _ConnectionMenuSectionLabel(
                  label: targets.isEmpty
                      ? 'Recommended new nodes'
                      : 'Create linked node',
                ),
                for (final type in createTypes)
                  _ConnectionTargetTile(
                    icon: nodeIcon(type),
                    color: nodeColor(type),
                    title: 'Create ${type.label}',
                    subtitle: 'Recommended for ${widget.source.type.label}',
                    onTap: () => widget.onSelect(type),
                  ),
              ],
              if (targets.isEmpty && createTypes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No connection target found',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionMenuSectionLabel extends StatelessWidget {
  const _ConnectionMenuSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ConnectionTargetTile extends StatelessWidget {
  const _ConnectionTargetTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, color: color),
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class _FocusModeBanner extends StatelessWidget {
  const _FocusModeBanner({
    required this.title,
    required this.visibleCount,
    required this.onClear,
  });

  final String title;
  final int visibleCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_center_focus,
              color: theme.colorScheme.onPrimaryContainer,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Focus: $title · $visibleCount nodes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Clear focus',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

class _LassoSelectionPainter extends CustomPainter {
  const _LassoSelectionPainter({required this.rect});

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = Colors.lightBlueAccent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.lightBlueAccent.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LassoSelectionPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}

class _MultiSelectToolbar extends StatelessWidget {
  const _MultiSelectToolbar({
    required this.count,
    required this.onComplete,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onTag,
    required this.onProject,
    required this.onClearProject,
    required this.onArea,
    required this.onClearArea,
    required this.onClearTags,
    required this.onDueDate,
    required this.onClearDueDate,
    required this.onAlignHorizontal,
    required this.onAlignVertical,
    required this.onDistributeHorizontal,
    required this.onDistributeVertical,
    required this.onZoomToSelected,
    required this.onCopy,
    required this.onPaste,
    required this.onDuplicate,
    required this.onArchive,
    required this.onClear,
  });

  final int count;
  final VoidCallback onComplete;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<NodePriority> onPriorityChanged;
  final VoidCallback onTag;
  final VoidCallback onProject;
  final VoidCallback onClearProject;
  final VoidCallback onArea;
  final VoidCallback onClearArea;
  final VoidCallback onClearTags;
  final VoidCallback onDueDate;
  final VoidCallback onClearDueDate;
  final VoidCallback onAlignHorizontal;
  final VoidCallback onAlignVertical;
  final VoidCallback onDistributeHorizontal;
  final VoidCallback onDistributeVertical;
  final VoidCallback onZoomToSelected;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onDuplicate;
  final VoidCallback onArchive;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$count selected', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Complete selected tasks/habits',
              visualDensity: VisualDensity.compact,
              onPressed: onComplete,
              icon: const Icon(Icons.check_circle_outline, size: 18),
            ),
            PopupMenuButton<NodeStatus>(
              tooltip: 'Set selected status',
              icon: const Icon(Icons.tune_outlined, size: 18),
              onSelected: onStatusChanged,
              itemBuilder: (context) => [
                for (final status in NodeStatus.values)
                  PopupMenuItem(value: status, child: Text(status.label)),
              ],
            ),
            PopupMenuButton<NodePriority>(
              tooltip: 'Set selected priority',
              icon: const Icon(Icons.priority_high_outlined, size: 18),
              onSelected: onPriorityChanged,
              itemBuilder: (context) => [
                for (final priority in NodePriority.values)
                  PopupMenuItem(value: priority, child: Text(priority.label)),
              ],
            ),
            IconButton.filledTonal(
              tooltip: 'Tag selected',
              visualDensity: VisualDensity.compact,
              onPressed: onTag,
              icon: const Icon(Icons.sell_outlined, size: 18),
            ),
            PopupMenuButton<VoidCallback>(
              tooltip: 'More batch edits',
              icon: const Icon(Icons.more_horiz, size: 18),
              onSelected: (callback) => callback(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: onProject,
                  child: const Text('Set project'),
                ),
                PopupMenuItem(
                  value: onClearProject,
                  child: const Text('Clear project'),
                ),
                PopupMenuItem(value: onArea, child: const Text('Set area')),
                PopupMenuItem(
                  value: onClearArea,
                  child: const Text('Clear area'),
                ),
                PopupMenuItem(
                  value: onClearTags,
                  child: const Text('Clear tags'),
                ),
                PopupMenuItem(
                  value: onDueDate,
                  child: const Text('Set due date'),
                ),
                PopupMenuItem(
                  value: onClearDueDate,
                  child: const Text('Clear due date'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: onAlignHorizontal,
                  child: const Text('Align horizontal'),
                ),
                PopupMenuItem(
                  value: onAlignVertical,
                  child: const Text('Align vertical'),
                ),
                PopupMenuItem(
                  value: onDistributeHorizontal,
                  child: const Text('Distribute horizontal'),
                ),
                PopupMenuItem(
                  value: onDistributeVertical,
                  child: const Text('Distribute vertical'),
                ),
                PopupMenuItem(
                  value: onZoomToSelected,
                  child: const Text('Zoom to selected'),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(value: onCopy, child: const Text('Copy')),
                PopupMenuItem(value: onPaste, child: const Text('Paste')),
                PopupMenuItem(
                  value: onDuplicate,
                  child: const Text('Duplicate'),
                ),
              ],
            ),
            IconButton.filledTonal(
              tooltip: 'Archive selected',
              visualDensity: VisualDensity.compact,
              onPressed: onArchive,
              icon: const Icon(Icons.archive_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Clear selection',
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChalkPanel extends StatelessWidget {
  const _ChalkPanel({
    required this.child,
    required this.accent,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 14,
  });

  final Widget child;
  final Color accent;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _ChalkPanelPainter(
          accent: accent,
          surface: theme.colorScheme.surface,
          radius: borderRadius,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _ChalkPanelPainter extends CustomPainter {
  const _ChalkPanelPainter({
    required this.accent,
    required this.surface,
    required this.radius,
  });

  final Color accent;
  final Color surface;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    canvas.drawRRect(rrect, Paint()..color = surface.withValues(alpha: 0.94));

    canvas.save();
    canvas.clipPath(path);
    final chalk = Paint()
      ..color = NeutralColors.darkBorder.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var y = 10.0; y < size.height; y += 11) {
      canvas.drawLine(
        Offset(8, y),
        Offset(size.width - 8, y + math.sin(y) * 0.8),
        chalk,
      );
    }
    canvas.restore();

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..color = NeutralColors.darkBorder.withValues(alpha: 0.86);
    canvas.drawRRect(rrect.deflate(1), border);

    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = accent.withValues(alpha: 0.78);
    canvas.drawLine(
      const Offset(12, 8),
      Offset(size.width * 0.3, 6),
      accentPaint,
    );
    canvas.drawCircle(Offset(size.width - 14, 12), 4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _ChalkPanelPainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.surface != surface ||
        oldDelegate.radius != radius;
  }
}

class _OverlayMiniToggle extends StatelessWidget {
  const _OverlayMiniToggle({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: _ChalkPanel(
            accent: theme.colorScheme.primary,
            borderRadius: 999,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: theme.colorScheme.primary),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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

class _TinyOverlayButton extends StatelessWidget {
  const _TinyOverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Container(
            width: 26,
            height: 24,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Icon(
              icon,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
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
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.18),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.36),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            blurRadius: 10,
          ),
        ],
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

class _CanvasSearchOverlay extends StatelessWidget {
  const _CanvasSearchOverlay({
    required this.searchController,
    required this.searchFocusNode,
    required this.isSearchActive,
    required this.filteredCount,
    required this.selectedType,
    required this.isCollapsed,
    required this.onClearSearch,
    required this.onTypeSelected,
    required this.onCollapsedChanged,
    required this.onSubmitted,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearchActive;
  final int filteredCount;
  final NodeType? selectedType;
  final bool isCollapsed;
  final VoidCallback onClearSearch;
  final ValueChanged<NodeType?> onTypeSelected;
  final ValueChanged<bool> onCollapsedChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    const left = 16.0;
    const bottom = 76.0;
    final overlayWidth = math.min(380.0, width - left - 24).clamp(260.0, 380.0);
    if (isCollapsed) {
      return SizedBox.expand(
        child: Stack(
          children: [
            Positioned(
              bottom: bottom,
              left: left,
              child: MouseRegion(
                onEnter: (_) => onCollapsedChanged(false),
                child: _CollapsedSearchPill(
                  isSearchActive: isSearchActive,
                  filteredCount: filteredCount,
                  selectedType: selectedType,
                  onExpand: () => onCollapsedChanged(false),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            bottom: bottom,
            left: left,
            width: overlayWidth,
            child: MouseRegion(
              onExit: (_) {
                if (!searchFocusNode.hasFocus) {
                  onCollapsedChanged(true);
                }
              },
              child: Material(
                color: Colors.transparent,
                child: _ChalkPanel(
                  accent: isSearchActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 38,
                          child: TextField(
                            controller: searchController,
                            focusNode: searchFocusNode,
                            onSubmitted: (_) => onSubmitted(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search title, body, tag, project...',
                              filled: true,
                              fillColor: theme
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.48),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 34,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: isSearchActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSearchActive) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(right: 2),
                                      child: Text(
                                        '$filteredCount',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Clear search',
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                      ),
                                      onPressed: onClearSearch,
                                    ),
                                  ],
                                  IconButton(
                                    tooltip: 'Hide search filters',
                                    icon: const Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      searchFocusNode.unfocus();
                                      onCollapsedChanged(true);
                                    },
                                  ),
                                ],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 9,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _CanvasSearchFilters(
                          selectedType: selectedType,
                          onSelected: onTypeSelected,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedSearchPill extends StatelessWidget {
  const _CollapsedSearchPill({
    required this.isSearchActive,
    required this.filteredCount,
    required this.selectedType,
    required this.onExpand,
  });

  final bool isSearchActive;
  final int filteredCount;
  final NodeType? selectedType;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = selectedType;
    final accent = type == null ? theme.colorScheme.primary : nodeColor(type);
    final label = type == null ? 'Search' : type.label;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onExpand,
        child: _ChalkPanel(
          accent: accent,
          borderRadius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded, size: 17, color: accent),
              const SizedBox(width: 8),
              Text(
                isSearchActive ? '$label · $filteredCount' : 'Show search',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasSearchFilters extends StatelessWidget {
  const _CanvasSearchFilters({
    required this.selectedType,
    required this.onSelected,
  });

  final NodeType? selectedType;
  final ValueChanged<NodeType?> onSelected;

  static const _filters = <NodeType>[
    NodeType.task,
    NodeType.event,
    NodeType.note,
    NodeType.contact,
    NodeType.metric,
    NodeType.expense,
    NodeType.bookmark,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CanvasFilterPill(
              key: const ValueKey('mindmap-search-filter-all'),
              icon: Icons.done_all_rounded,
              label: 'All',
              color: theme.colorScheme.primary,
              isSelected: selectedType == null,
              onTap: () => onSelected(null),
            );
          }

          final type = _filters[index - 1];
          return _CanvasFilterPill(
            key: ValueKey('mindmap-search-filter-${type.name}'),
            icon: nodeIcon(type),
            label: _filterLabel(type),
            color: nodeColor(type),
            isSelected: selectedType == type,
            onTap: () => onSelected(type),
          );
        },
      ),
    );
  }

  String _filterLabel(NodeType type) {
    return switch (type) {
      NodeType.task => 'Tasks',
      NodeType.event => 'Events',
      NodeType.note => 'Notes',
      NodeType.contact => 'Contacts',
      NodeType.metric => 'Metrics',
      NodeType.expense => 'Expenses',
      NodeType.bookmark => 'Bookmarks',
      _ => type.label,
    };
  }
}

class _CanvasFilterPill extends StatelessWidget {
  const _CanvasFilterPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = isSelected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final bg = isSelected
        ? color.withValues(alpha: 0.86)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.44);
    final border = isSelected
        ? color.withValues(alpha: 0.95)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.42);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: isSelected ? fg : color),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.05,
                ),
              ),
            ],
          ),
        ),
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

class _CanvasEmptyHint extends StatelessWidget {
  const _CanvasEmptyHint({required this.onAddHint});

  final String onAddHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            key: const ValueKey('mindmap-empty-canvas-hint'),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    onAddHint,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
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

class _PositionedNode extends StatelessWidget {
  const _PositionedNode({
    required this.node,
    required this.position,
    required this.size,
    required this.origin,
    required this.isHighlighted,
    required this.isMovementLocked,
    required this.enableHoverEffects,
    required this.isCompact,
    required this.onInlineEditingChanged,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onSelect,
    required this.onContextMenu,
    required this.onConnectionStart,
    required this.onConnectionUpdate,
    required this.onConnectionEnd,
    required this.onNodeUpdated,
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
  final bool isMovementLocked;
  final bool enableHoverEffects;
  final bool isCompact;
  final ValueChanged<bool> onInlineEditingChanged;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onContextMenu;
  final ValueChanged<Offset> onConnectionStart;
  final ValueChanged<Offset> onConnectionUpdate;
  final ValueChanged<Offset> onConnectionEnd;
  final NodeUpdateCallback? onNodeUpdated;
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
        onContextMenu: onContextMenu,
        onConnectionStart: onConnectionStart,
        onConnectionUpdate: onConnectionUpdate,
        onConnectionEnd: onConnectionEnd,
        canToggleDone: node.type == NodeType.task,
        isDone: node.isDone,
        onTaskDoneChanged: onTaskDoneChanged,
        isMovementLocked: isMovementLocked,
        enableHoverEffects: enableHoverEffects,
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
        child: RepaintBoundary(
          child: _MindmapNodeCard(
            node: node,
            isHighlighted: isHighlighted,
            onTaskChecklistItemCompleted: onTaskChecklistItemCompleted,
            onKanbanCardAdvanced: onKanbanCardAdvanced,
            onHabitCompleted: onHabitCompleted,
            onGoalMilestoneAdvanced: onGoalMilestoneAdvanced,
            onPlanStepAdvanced: onPlanStepAdvanced,
            onNodeUpdated: onNodeUpdated,
            onInlineEditingChanged: onInlineEditingChanged,
            isCompact: isCompact,
          ),
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
    required this.onContextMenu,
    required this.onConnectionStart,
    required this.onConnectionUpdate,
    required this.onConnectionEnd,
    required this.canToggleDone,
    required this.isDone,
    required this.onTaskDoneChanged,
    required this.isMovementLocked,
    required this.enableHoverEffects,
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
  final ValueChanged<Offset> onContextMenu;
  final ValueChanged<Offset> onConnectionStart;
  final ValueChanged<Offset> onConnectionUpdate;
  final ValueChanged<Offset> onConnectionEnd;
  final bool canToggleDone;
  final bool isDone;
  final ValueChanged<bool> onTaskDoneChanged;
  final bool isMovementLocked;
  final bool enableHoverEffects;
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
  bool _isConnecting = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (details) {
        _lastLocalPosition = details.localPosition;
        _isConnecting =
            !widget.isMovementLocked &&
            _isConnectionPortHit(details.localPosition);
        _isDragging = !widget.isMovementLocked;
        if (!_isDragging) return;
        widget.onPointerDown();
        if (_isConnecting) {
          widget.onConnectionStart(details.position);
        }
      },
      onPointerMove: (details) {
        if (_isDragging) {
          _lastLocalPosition = details.localPosition;
          if (_isConnecting) {
            widget.onConnectionUpdate(details.position);
          } else {
            widget.onPanUpdate(details.delta);
          }
        }
      },
      onPointerUp: (details) {
        if (_isDragging) {
          _isDragging = false;
          final wasConnecting = _isConnecting;
          _isConnecting = false;
          widget.onPointerUp();
          if (wasConnecting) {
            widget.onConnectionEnd(details.position);
          } else {
            widget.onPanEnd();
          }
        }
      },
      onPointerCancel: (details) {
        if (_isDragging) {
          _isDragging = false;
          _isConnecting = false;
          widget.onPointerUp();
          widget.onPanEnd();
        }
      },
      child: GestureDetector(
        key: ValueKey('mindmap-node-${widget.nodeId}'),
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) {
          widget.onContextMenu(details.globalPosition);
        },
        onLongPressStart: (details) {
          widget.onContextMenu(details.globalPosition);
        },
        onTapUp: (details) {
          _lastLocalPosition = details.localPosition;
          if (widget.isMovementLocked ||
              (widget.shouldIgnoreTap?.call(_lastLocalPosition) ?? false)) {
            return;
          }
          if (_isToggleHit(_lastLocalPosition)) {
            widget.onTaskDoneChanged(!widget.isDone);
          } else {
            widget.onSelect();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            if (widget.enableHoverEffects) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (widget.enableHoverEffects) setState(() => _isHovered = false);
          },
          child: AnimatedScale(
            scale: widget.enableHoverEffects && _isHovered ? 1.05 : 1.0,
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

  bool _isConnectionPortHit(Offset position) {
    final width = context.size?.width ?? 0;
    return position.dx >= width - 36 && position.dy >= 70 && position.dy <= 122;
  }

  bool _isToggleHit(Offset position) {
    return widget.canToggleDone &&
        position.dx <= _toggleHitSize &&
        position.dy <= _toggleHitSize;
  }
}

List<NodeType> compatibleNodeTypes(NodeType type) {
  final informational = [
    NodeType.note,
    NodeType.resource,
    NodeType.bookmark,
    NodeType.question,
    NodeType.idea,
    NodeType.decision,
  ];
  return switch (type) {
    NodeType.task => [
      NodeType.plan,
      NodeType.goal,
      NodeType.habit,
      NodeType.kanban,
      NodeType.event,
    ],
    NodeType.plan => [
      NodeType.task,
      NodeType.goal,
      NodeType.note,
      NodeType.event,
    ],
    NodeType.goal => [
      NodeType.plan,
      NodeType.task,
      NodeType.habit,
      NodeType.metric,
      NodeType.journal,
    ],
    NodeType.habit => [
      NodeType.goal,
      NodeType.metric,
      NodeType.journal,
      NodeType.routine,
    ],
    NodeType.note => informational,
    NodeType.event => [
      NodeType.task,
      NodeType.plan,
      NodeType.contact,
      NodeType.note,
    ],
    NodeType.contact => [NodeType.event, NodeType.task, NodeType.resource],
    NodeType.metric => [NodeType.goal, NodeType.habit, NodeType.expense],
    NodeType.expense => [NodeType.metric, NodeType.goal, NodeType.note],
    NodeType.bookmark ||
    NodeType.resource => [NodeType.note, NodeType.question, NodeType.idea],
    NodeType.routine => [NodeType.habit, NodeType.task, NodeType.plan],
    NodeType.empty =>
      NodeType.values.where((t) => t != NodeType.empty).toList(),
    _ => informational,
  };
}

String compatibleNodeTypeLabel(NodeType type) {
  return compatibleNodeTypes(type).take(4).map((t) => t.label).join(', ');
}

enum _DoodleCardKind { note, rounded, torn, label, ticket, pill }

class _DoodleCardStyle {
  const _DoodleCardStyle(this.kind);

  final _DoodleCardKind kind;
}

_DoodleCardStyle _doodleCardFor(NodeType type) => switch (type) {
  NodeType.task => const _DoodleCardStyle(_DoodleCardKind.torn),
  NodeType.kanban => const _DoodleCardStyle(_DoodleCardKind.ticket),
  NodeType.plan => const _DoodleCardStyle(_DoodleCardKind.label),
  NodeType.note => const _DoodleCardStyle(_DoodleCardKind.torn),
  NodeType.journal => const _DoodleCardStyle(_DoodleCardKind.note),
  NodeType.habit => const _DoodleCardStyle(_DoodleCardKind.rounded),
  NodeType.goal => const _DoodleCardStyle(_DoodleCardKind.pill),
  NodeType.link => const _DoodleCardStyle(_DoodleCardKind.pill),
  NodeType.event => const _DoodleCardStyle(_DoodleCardKind.label),
  NodeType.decision => const _DoodleCardStyle(_DoodleCardKind.torn),
  NodeType.resource => const _DoodleCardStyle(_DoodleCardKind.note),
  NodeType.idea => const _DoodleCardStyle(_DoodleCardKind.label),
  NodeType.question => const _DoodleCardStyle(_DoodleCardKind.pill),
  NodeType.contact => const _DoodleCardStyle(_DoodleCardKind.ticket),
  NodeType.metric => const _DoodleCardStyle(_DoodleCardKind.rounded),
  NodeType.expense => const _DoodleCardStyle(_DoodleCardKind.torn),
  NodeType.bookmark => const _DoodleCardStyle(_DoodleCardKind.note),
  NodeType.routine => const _DoodleCardStyle(_DoodleCardKind.rounded),
  NodeType.empty => const _DoodleCardStyle(_DoodleCardKind.note),
};

class _DoodleNodeShell extends StatelessWidget {
  const _DoodleNodeShell({
    required this.type,
    required this.color,
    required this.isHighlighted,
    required this.child,
    this.isCompact = false,
  });

  final NodeType type;
  final Color color;
  final bool isHighlighted;
  final bool isCompact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DoodleNodeShellPainter(
        type: type,
        color: color,
        isHighlighted: isHighlighted,
        isCompact: isCompact,
      ),
      child: child,
    );
  }
}

class _DoodleNodeShellPainter extends CustomPainter {
  const _DoodleNodeShellPainter({
    required this.type,
    required this.color,
    required this.isHighlighted,
    required this.isCompact,
  });

  final NodeType type;
  final Color color;
  final bool isHighlighted;
  final bool isCompact;

  @override
  void paint(Canvas canvas, Size size) {
    final object = _doodleCardFor(type);
    final path = _doodleCardPath(size, object.kind, isCompact: isCompact);

    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFF11120E).withValues(alpha: 0.98),
    );

    final paperLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.8
      ..color = NeutralColors.darkBorder.withValues(alpha: 0.12);
    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.26 + i * 0.14);
      canvas.drawLine(
        Offset(size.width * 0.12, y + math.sin(i.toDouble()) * 1.4),
        Offset(size.width * 0.88, y + math.cos(i.toDouble()) * 1.1),
        paperLine,
      );
    }

    final spine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = isCompact ? 1.6 : 2.2
      ..color = color.withValues(alpha: 0.45);
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.16),
      Offset(size.width * 0.08, size.height * 0.82),
      spine,
    );

    final foldPath = Path()
      ..moveTo(size.width * 0.82, size.height * 0.045)
      ..lineTo(size.width * 0.94, size.height * 0.045)
      ..lineTo(size.width * 0.94, size.height * 0.16);
    canvas.drawPath(
      foldPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.2
        ..color = NeutralColors.darkBorder.withValues(alpha: 0.22),
    );

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHighlighted ? 4 : 2.6
      ..strokeJoin = StrokeJoin.round
      ..color = isHighlighted ? color : NeutralColors.darkBorder;
    canvas.drawPath(path, border);

    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.16),
      isCompact ? 3.5 : 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _DoodleNodeShellPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.color != color ||
        oldDelegate.isHighlighted != isHighlighted ||
        oldDelegate.isCompact != isCompact;
  }
}

Path _doodleCardPath(
  Size size,
  _DoodleCardKind kind, {
  required bool isCompact,
}) {
  final w = size.width;
  final h = size.height;
  final wobble = (kind.index % 3 - 1) * 2.0;
  return Path()
    ..moveTo(w * 0.06, h * 0.03 + wobble)
    ..quadraticBezierTo(w * 0.48, -3 - wobble, w * 0.94, h * 0.04)
    ..quadraticBezierTo(w + 4 + wobble, h * 0.48, w * 0.96, h * 0.93)
    ..quadraticBezierTo(w * 0.54, h + 4 + wobble, w * 0.06, h * 0.96)
    ..quadraticBezierTo(-4 - wobble, h * 0.5, w * 0.06, h * 0.03 + wobble)
    ..close();
}

class _CompactMindmapNodeCard extends StatelessWidget {
  const _CompactMindmapNodeCard({
    required this.node,
    required this.color,
    required this.isHighlighted,
  });

  final MindmapNode node;
  final Color color;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 260,
        height: 92,
        child: _DoodleNodeShell(
          type: node.type,
          color: color,
          isHighlighted: isHighlighted,
          isCompact: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(nodeIcon(node.type), color: color, size: 18),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: node.isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        node.type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (node.relatedNodeIds.isNotEmpty)
                  _NodeRelationBadge(count: node.relatedNodeIds.length),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MindmapNodeCard extends StatefulWidget {
  const _MindmapNodeCard({
    required this.node,
    required this.isHighlighted,
    required this.onTaskChecklistItemCompleted,
    required this.onKanbanCardAdvanced,
    required this.onHabitCompleted,
    required this.onGoalMilestoneAdvanced,
    required this.onPlanStepAdvanced,
    required this.onNodeUpdated,
    required this.onInlineEditingChanged,
    required this.isCompact,
  });

  final MindmapNode node;
  final bool isHighlighted;
  final VoidCallback? onTaskChecklistItemCompleted;
  final ValueChanged<String>? onKanbanCardAdvanced;
  final VoidCallback? onHabitCompleted;
  final VoidCallback? onGoalMilestoneAdvanced;
  final VoidCallback? onPlanStepAdvanced;
  final NodeUpdateCallback? onNodeUpdated;
  final ValueChanged<bool> onInlineEditingChanged;
  final bool isCompact;

  @override
  State<_MindmapNodeCard> createState() => _MindmapNodeCardState();
}

class _MindmapNodeCardState extends State<_MindmapNodeCard> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.node.title);
    _bodyController = TextEditingController(text: widget.node.body);
  }

  @override
  void didUpdateWidget(covariant _MindmapNodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.node != widget.node) {
      _titleController.text = widget.node.title;
      _bodyController.text = widget.node.body;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _setInlineEditing(bool value) {
    if (_isEditing == value) return;
    setState(() => _isEditing = value);
    widget.onInlineEditingChanged(value);
  }

  Future<void> _saveInlineEdit() async {
    final title = _titleController.text.trim();
    final body = _trimToWordLimit(_bodyController.text.trim());
    if (title.isEmpty) return;
    _setInlineEditing(false);
    if (title == widget.node.title && body == widget.node.body) return;
    await widget.onNodeUpdated?.call(
      widget.node.copyWith(title: title, body: body, updatedAt: DateTime.now()),
    );
  }

  String _trimToWordLimit(String value) {
    final words = RegExp(
      r'\S+',
    ).allMatches(value).map((m) => m.group(0)!).toList();
    if (words.length <= _inlineBodyMaxWords) return value;
    return words.take(_inlineBodyMaxWords).join(' ');
  }

  String _inlineWordCountLabel() {
    final count = RegExp(r'\S+').allMatches(_bodyController.text).length;
    return '$count/$_inlineBodyMaxWords words';
  }

  void _cancelInlineEdit() {
    setState(() {
      _titleController.text = widget.node.title;
      _bodyController.text = widget.node.body;
      _isEditing = false;
    });
    widget.onInlineEditingChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
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

    final compatibleTypes = compatibleNodeTypes(node.type).take(3).toList();

    if (widget.isCompact) {
      return _CompactMindmapNodeCard(
        node: node,
        color: color,
        isHighlighted: widget.isHighlighted,
      );
    }

    return _DoodleNodeShell(
      type: node.type,
      color: color,
      isHighlighted: widget.isHighlighted,
      child: Stack(
        children: [
          Positioned(
            left: -6,
            top: 88,
            child: _NodePort(color: color, alignment: Alignment.centerLeft),
          ),
          Positioned(
            right: -6,
            top: 88,
            child: _NodePort(color: color, alignment: Alignment.centerRight),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (node.type == NodeType.task) const SizedBox(width: 32),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: color.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          nodeIcon(node.type),
                          color: color,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        node.type.label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 0.4,
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _NodeRelationBadge(count: node.relatedNodeIds.length),
                    IconButton(
                      tooltip: 'Open ${node.type.label} page',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () => context.go(
                        '/calendar/${dayKey(node.day)}/node/${node.id}',
                      ),
                      icon: const Icon(Icons.open_in_full_rounded),
                    ),
                    if (widget.onNodeUpdated != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: _isEditing
                            ? 'Save inline edit'
                            : 'Edit in node',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () => _isEditing
                            ? unawaited(_saveInlineEdit())
                            : _setInlineEditing(true),
                        icon: Icon(
                          _isEditing
                              ? Icons.check_rounded
                              : Icons.edit_outlined,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: widget.onNodeUpdated == null
                      ? null
                      : () => _setInlineEditing(true),
                  child: _isEditing
                      ? TextField(
                          controller: _titleController,
                          autofocus: true,
                          style: theme.textTheme.titleSmall,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          onSubmitted: (_) => _saveInlineEdit(),
                        )
                      : Text(
                          node.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            decoration: node.isDone
                                ? TextDecoration.lineThrough
                                : null,
                            fontWeight: FontWeight.w700,
                            color: node.isDone
                                ? theme.textTheme.bodySmall?.color
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                ),
                _NodeProgressStrip(node: node),
                if (compatibleTypes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Ports', style: theme.textTheme.labelSmall),
                      const SizedBox(width: 6),
                      for (final type in compatibleTypes)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _NodeTypeHintChip(type: type),
                        ),
                    ],
                  ),
                ],
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
                      onCardAdvanced: widget.onKanbanCardAdvanced,
                      onNodeUpdated: widget.onNodeUpdated,
                    ),
                  ),
                ],
                if (_isEditing || node.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _isEditing
                      ? TextField(
                          controller: _bodyController,
                          minLines: 4,
                          maxLines: 7,
                          style: theme.textTheme.bodySmall,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Write rich node content here...',
                            helperText:
                                'Markdown: ##, **bold**, _italic_, lists, links',
                            counterText: _inlineWordCountLabel(),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.all(8),
                          ),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onDoubleTap: widget.onNodeUpdated == null
                              ? null
                              : () => _setInlineEditing(true),
                          child: Text(
                            node.body,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                ],
                if (_isEditing) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _saveInlineEdit,
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Save'),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: _cancelInlineEdit,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
                if (!node.data.containsKey('kanban')) ...[
                  const SizedBox(height: 8),
                  Flexible(child: _NodeTypeSpecificContent(node: node)),
                ],
                if (_hasTypeQuickAction(node) &&
                    !_hasProgressAction(node) &&
                    !node.isDone) ...[
                  const Spacer(),
                  _NodeQuickAction(node: node),
                ],
                if (node.checklist.isNotEmpty &&
                    node.checklist.isNotEmpty &&
                    !node.isDone &&
                    widget.onTaskChecklistItemCompleted != null) ...[
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FilledButton.tonalIcon(
                      key: ValueKey('mindmap-task-checklist-next-${node.id}'),
                      onPressed: nextChecklistItem == null
                          ? null
                          : widget.onTaskChecklistItemCompleted,
                      icon: Icon(
                        nextChecklistItem == null
                            ? Icons.check_circle_outline
                            : Icons.playlist_add_check,
                        size: 16,
                      ),
                      label: Text(
                        nextChecklistItem == null
                            ? 'Checklist done'
                            : 'Next item',
                      ),
                    ),
                  ),
                ],
                if (node.data.containsKey('habit') &&
                    widget.onHabitCompleted != null) ...[
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FilledButton.tonalIcon(
                      key: ValueKey('mindmap-habit-log-${node.id}'),
                      onPressed: isHabitLogged ? null : widget.onHabitCompleted,
                      icon: Icon(
                        isHabitLogged
                            ? Icons.check_circle_outline
                            : Icons.check,
                        size: 16,
                      ),
                      label: Text(isHabitLogged ? 'Logged' : 'Log'),
                    ),
                  ),
                ],
                if (node.data.containsKey('goal') &&
                    widget.onGoalMilestoneAdvanced != null) ...[
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FilledButton.tonalIcon(
                      key: ValueKey('mindmap-goal-advance-${node.id}'),
                      onPressed: nextMilestone == null
                          ? null
                          : widget.onGoalMilestoneAdvanced,
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
                    widget.onPlanStepAdvanced != null) ...[
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FilledButton.tonalIcon(
                      key: ValueKey('mindmap-plan-advance-${node.id}'),
                      onPressed: nextStep == null
                          ? null
                          : widget.onPlanStepAdvanced,
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
        ],
      ),
    );
  }
}

class _NodePort extends StatefulWidget {
  const _NodePort({required this.color, required this.alignment});

  final Color color;
  final Alignment alignment;

  @override
  State<_NodePort> createState() => _NodePortState();
}

class _NodePortState extends State<_NodePort> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final sidePadding = widget.alignment.x < 0
        ? const EdgeInsets.only(left: 1)
        : const EdgeInsets.only(right: 1);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.grab,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        transform: Matrix4.diagonal3Values(
          _isHovered ? 1.35 : 1.0,
          _isHovered ? 1.35 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        width: 18,
        height: 18,
        padding: sidePadding,
        decoration: BoxDecoration(
          color: const Color(0xFF11120E),
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.color.withValues(alpha: _isHovered ? 1.0 : 0.76),
            width: _isHovered ? 2.0 : 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _isHovered ? 0.35 : 0.18),
              blurRadius: _isHovered ? 12 : 6,
              spreadRadius: _isHovered ? 2 : 0,
            ),
          ],
        ),
        child: Align(
          alignment: widget.alignment,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: _isHovered ? 8 : 6,
            height: _isHovered ? 8 : 6,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: _isHovered ? 1.0 : 0.72),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeRelationBadge extends StatelessWidget {
  const _NodeRelationBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: count == 0 ? 'No links yet' : '$count linked nodes',
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.cable_rounded, size: 14),
        label: Text('$count'),
      ),
    );
  }
}

class _NodeTypeHintChip extends StatelessWidget {
  const _NodeTypeHintChip({required this.type});

  final NodeType type;

  @override
  Widget build(BuildContext context) {
    final color = nodeColor(type);
    return Tooltip(
      message: 'Suggested link: ${type.label}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(nodeIcon(type), color: color, size: 12)],
          ),
        ),
      ),
    );
  }
}

bool _hasProgressAction(MindmapNode node) {
  return node.checklist.isNotEmpty ||
      node.data.containsKey('habit') ||
      node.data.containsKey('goal') ||
      node.data.containsKey('plan');
}

bool _hasTypeQuickAction(MindmapNode node) {
  return switch (node.type) {
    NodeType.event ||
    NodeType.decision ||
    NodeType.resource ||
    NodeType.idea ||
    NodeType.question ||
    NodeType.contact ||
    NodeType.metric ||
    NodeType.expense ||
    NodeType.bookmark ||
    NodeType.routine => true,
    _ => false,
  };
}

class _NodeQuickAction extends StatelessWidget {
  const _NodeQuickAction({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final action = _quickActionFor(node);
    if (action == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomLeft,
      child: FilledButton.tonalIcon(
        key: ValueKey('mindmap-node-quick-action-${node.id}'),
        onPressed: () => _runQuickAction(context, action),
        icon: Icon(action.icon, size: 16),
        label: Text(action.label),
      ),
    );
  }

  _QuickAction? _quickActionFor(MindmapNode node) {
    final payload = calendarNodePayloadFromData(node.data);
    return switch (node.type) {
      NodeType.event => _QuickAction(
        label: 'Copy event',
        icon: Icons.event_available_outlined,
        value: _eventSummary(node, payload),
        message: 'Event copied',
      ),
      NodeType.decision => _QuickAction(
        label: payload?.selectedOption?.trim().isNotEmpty == true
            ? 'Copy choice'
            : 'Copy decision',
        icon: Icons.rule_outlined,
        value: _decisionSummary(node, payload),
        message: 'Decision copied',
      ),
      NodeType.resource => _QuickAction(
        label: 'Copy source',
        icon: Icons.inventory_2_outlined,
        value: _resourceSource(node),
        message: 'Resource source copied',
      ),
      NodeType.idea => _QuickAction(
        label: 'Copy idea',
        icon: Icons.lightbulb_outline,
        value: _ideaSummary(node),
        message: 'Idea copied',
      ),
      NodeType.question => _QuickAction(
        label: 'Copy question',
        icon: Icons.help_outline,
        value: _questionSummary(node),
        message: 'Question copied',
      ),
      NodeType.contact => _QuickAction(
        label: _dataText(node, 'email').isNotEmpty
            ? 'Copy email'
            : 'Copy contact',
        icon: Icons.person_outline,
        value: _contactSummary(node),
        message: 'Contact copied',
      ),
      NodeType.metric => _QuickAction(
        label: 'Copy metric',
        icon: Icons.query_stats_outlined,
        value: _metricSummary(node),
        message: 'Metric copied',
      ),
      NodeType.expense => _QuickAction(
        label: 'Copy expense',
        icon: Icons.payments_outlined,
        value: _expenseSummary(node),
        message: 'Expense copied',
      ),
      NodeType.bookmark => _QuickAction(
        label: 'Copy URL',
        icon: Icons.bookmark_border,
        value: _bookmarkUrl(node),
        message: 'Bookmark URL copied',
      ),
      NodeType.routine => _QuickAction(
        label: 'Copy routine',
        icon: Icons.repeat_on_outlined,
        value: _routineSummary(node),
        message: 'Routine copied',
      ),
      _ => null,
    };
  }

  void _runQuickAction(BuildContext context, _QuickAction action) {
    Clipboard.setData(ClipboardData(text: action.value));
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(action.message)));
  }

  String _eventSummary(MindmapNode node, CalendarNodePayload? payload) {
    final parts = [
      node.title,
      if (payload?.location?.trim().isNotEmpty == true)
        'Location: ${payload!.location!.trim()}',
      if (payload?.remindAt?.trim().isNotEmpty == true)
        'Reminder: ${payload!.remindAt!.trim()}',
      if (payload?.participants?.trim().isNotEmpty == true)
        'Participants: ${payload!.participants!.trim()}',
    ];
    return parts.join('\n');
  }

  String _decisionSummary(MindmapNode node, CalendarNodePayload? payload) {
    final parts = [
      node.title,
      if (payload?.selectedOption?.trim().isNotEmpty == true)
        'Decision: ${payload!.selectedOption!.trim()}',
      if (payload?.reason?.trim().isNotEmpty == true)
        'Reason: ${payload!.reason!.trim()}',
      if (payload?.options?.trim().isNotEmpty == true)
        'Options:\n${payload!.options!.trim()}',
    ];
    return parts.join('\n');
  }

  String _resourceSource(MindmapNode node) {
    final note = node.data['note'];
    if (note is Map && note['source']?.toString().trim().isNotEmpty == true) {
      return note['source'].toString().trim();
    }
    final link = node.data['link'];
    if (link is Map && link['url']?.toString().trim().isNotEmpty == true) {
      return link['url'].toString().trim();
    }
    return node.body.trim().isEmpty ? node.title : node.body.trim();
  }

  String _ideaSummary(MindmapNode node) {
    return node.body.trim().isEmpty
        ? node.title
        : '${node.title}\n${node.body.trim()}';
  }

  String _questionSummary(MindmapNode node) {
    final fields = _bodyFields(node.body);
    final parts = [
      fields['question']?.trim().isNotEmpty == true
          ? fields['question']!.trim()
          : node.title,
      if (fields['context']?.trim().isNotEmpty == true)
        'Context: ${fields['context']!.trim()}',
      if (node.checklist.isNotEmpty)
        'Follow-up:\n${node.checklist.map((item) => '- ${item.title}').join('\n')}',
    ];
    return parts.join('\n');
  }

  String _contactSummary(MindmapNode node) {
    final email = _dataText(node, 'email');
    if (email.isNotEmpty) return email;
    return [
      node.title,
      if (_dataText(node, 'role').isNotEmpty) _dataText(node, 'role'),
      if (_dataText(node, 'company').isNotEmpty) _dataText(node, 'company'),
      if (_dataText(node, 'phone').isNotEmpty) _dataText(node, 'phone'),
    ].join('\n');
  }

  String _metricSummary(MindmapNode node) {
    final value = _dataText(node, 'value');
    final unit = _dataText(node, 'unit');
    return [
      node.title,
      if (value.isNotEmpty || unit.isNotEmpty) 'Value: $value $unit'.trim(),
      if (_dataText(node, 'target').isNotEmpty)
        'Target: ${_dataText(node, 'target')}',
      if (_dataText(node, 'trend').isNotEmpty)
        'Trend: ${_dataText(node, 'trend')}',
    ].join('\n');
  }

  String _expenseSummary(MindmapNode node) {
    return [
      node.title,
      if (_dataText(node, 'amount').isNotEmpty)
        'Amount: ${_dataText(node, 'amount')}',
      if (_dataText(node, 'category').isNotEmpty)
        'Category: ${_dataText(node, 'category')}',
      if (_dataText(node, 'merchant').isNotEmpty)
        'Merchant: ${_dataText(node, 'merchant')}',
      if (_dataText(node, 'payment').isNotEmpty)
        'Payment: ${_dataText(node, 'payment')}',
    ].join('\n');
  }

  String _bookmarkUrl(MindmapNode node) {
    final direct = _dataText(node, 'url');
    if (direct.isNotEmpty) return direct;
    final link = node.data['link'];
    if (link is Map && link['url']?.toString().trim().isNotEmpty == true) {
      return link['url'].toString().trim();
    }
    return node.body.trim().isEmpty ? node.title : node.body.trim();
  }

  String _routineSummary(MindmapNode node) {
    if (node.checklist.isEmpty) return node.title;
    return '${node.title}\n${node.checklist.map((item) => '- ${item.title}').join('\n')}';
  }
}

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.value,
    required this.message,
  });

  final String label;
  final IconData icon;
  final String value;
  final String message;
}

class _NodeProgressStrip extends StatelessWidget {
  const _NodeProgressStrip({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final progress = _progressFor(node);
    if (progress == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = nodeColor(node.type);
    final label = _progressLabelFor(node, progress);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.65),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }

  double? _progressFor(MindmapNode node) {
    if (node.progress > 0) return node.progress;
    if (node.checklist.isNotEmpty) {
      return node.completedChecklistCount / node.checklist.length;
    }
    if (node.type == NodeType.plan) {
      final steps = planSteps(node);
      if (steps.isEmpty) return null;
      return _completedStepCount(steps, completedPlanSteps(node)) /
          steps.length;
    }
    if (node.type == NodeType.goal) {
      final data = _sectionData(node.data, 'goal');
      final milestones = _stringListFromData(data['milestones']);
      if (milestones.isEmpty) return null;
      return _completedMilestoneCount(
            milestones,
            _stringListFromData(data['completedMilestones']),
          ) /
          milestones.length;
    }
    if (node.type == NodeType.habit) {
      return hasHabitCompletionOn(node, node.day) ? 1 : 0;
    }
    return null;
  }

  String _progressLabelFor(MindmapNode node, double progress) {
    if (node.checklist.isNotEmpty) {
      return 'Checklist ${node.completedChecklistCount}/${node.checklist.length}';
    }
    if (node.type == NodeType.plan) {
      final steps = planSteps(node);
      return '${_completedStepCount(steps, completedPlanSteps(node))}/${steps.length}';
    }
    if (node.type == NodeType.goal) {
      final data = _sectionData(node.data, 'goal');
      final milestones = _stringListFromData(data['milestones']);
      return '${_completedMilestoneCount(milestones, _stringListFromData(data['completedMilestones']))}/${milestones.length}';
    }
    if (node.type == NodeType.habit) {
      return hasHabitCompletionOn(node, node.day) ? 'Today' : 'Open';
    }
    return '${(progress * 100).round()}%';
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
  const _KanbanNodeBoard({
    required this.node,
    required this.onCardAdvanced,
    required this.onNodeUpdated,
  });

  final MindmapNode node;
  final ValueChanged<String>? onCardAdvanced;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final board = KanbanBoard.fromNodeData(node.data);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final column in KanbanColumn.values) ...[
          Expanded(
            child: _KanbanColumnView(
              node: node,
              column: column,
              cards: board.cardsFor(column),
              onCardAdvanced: onCardAdvanced,
              onNodeUpdated: onNodeUpdated,
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
    required this.node,
    required this.column,
    required this.cards,
    required this.onCardAdvanced,
    required this.onNodeUpdated,
  });

  final MindmapNode node;
  final KanbanColumn column;
  final List<KanbanCard> cards;
  final ValueChanged<String>? onCardAdvanced;
  final NodeUpdateCallback? onNodeUpdated;

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
                        node: node,
                        card: card,
                        onCardAdvanced: onCardAdvanced,
                        onNodeUpdated: onNodeUpdated,
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
    required this.node,
    required this.card,
    required this.onCardAdvanced,
    required this.onNodeUpdated,
  });

  final MindmapNode node;
  final KanbanCard card;
  final ValueChanged<String>? onCardAdvanced;
  final NodeUpdateCallback? onNodeUpdated;

  KanbanColumn? get _previousColumn => switch (card.column) {
    KanbanColumn.todo => null,
    KanbanColumn.doing => KanbanColumn.todo,
    KanbanColumn.done => KanbanColumn.doing,
  };

  Future<void> _updateCard(KanbanCard updatedCard) async {
    final callback = onNodeUpdated;
    if (callback == null) return;
    final board = KanbanBoard.fromNodeData(node.data);
    await callback(
      node.copyWith(
        data: {
          ...node.data,
          'kanban': KanbanBoard(
            cards: [
              for (final item in board.cards)
                if (item.id == card.id) updatedCard else item,
            ],
          ).toJson(),
        },
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _deleteCard() async {
    final callback = onNodeUpdated;
    if (callback == null) return;
    final board = KanbanBoard.fromNodeData(node.data);
    await callback(
      node.copyWith(
        data: {
          ...node.data,
          'kanban': KanbanBoard(
            cards: [
              for (final item in board.cards)
                if (item.id != card.id) item,
            ],
          ).toJson(),
        },
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _renameCard(BuildContext context) async {
    final controller = TextEditingController(text: card.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename card'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Card title'),
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
    controller.dispose();
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == card.title) return;
    await _updateCard(card.copyWith(title: trimmed));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAdvance = card.column.next != null && onCardAdvanced != null;
    final canEdit = onNodeUpdated != null;

    return DecoratedBox(
      key: ValueKey('kanban-card-${node.id}-${card.id}-${card.column.name}'),
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
                  key: ValueKey('kanban-advance-${node.id}-${card.id}'),
                  tooltip: 'Move card',
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  onPressed: () => onCardAdvanced?.call(card.id),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            if (canEdit)
              SizedBox.square(
                dimension: 28,
                child: PopupMenuButton<String>(
                  key: ValueKey('kanban-card-menu-${node.id}-${card.id}'),
                  tooltip: 'Card actions',
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  onSelected: (value) async {
                    switch (value) {
                      case 'back':
                        final previous = _previousColumn;
                        if (previous != null) {
                          await _updateCard(card.copyWith(column: previous));
                        }
                      case 'forward':
                        final next = card.column.next;
                        if (next != null) {
                          await _updateCard(card.copyWith(column: next));
                        }
                      case 'rename':
                        await _renameCard(context);
                      case 'delete':
                        await _deleteCard();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'back',
                      enabled: _previousColumn != null,
                      child: const Text('Move left'),
                    ),
                    PopupMenuItem(
                      value: 'forward',
                      enabled: card.column.next != null,
                      child: const Text('Move right'),
                    ),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
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
    required this.cursorTrail,
    required this.animationValue,
    required this.showGrid,
  });

  final Offset? mousePos;
  final List<Offset> cursorTrail;
  final double animationValue;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final chalkOffset = mousePos != null
        ? (mousePos! - center) * 0.004
        : Offset.zero;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF090B09), Color(0xFF10120E), Color(0xFF070807)],
        ).createShader(rect),
    );

    _drawPaperFibers(canvas, size, chalkOffset);
    _drawChalkDust(canvas, size, chalkOffset);
    if (showGrid) {
      _drawPaperGuides(canvas, size, chalkOffset);
    }
    _drawCanvasVignette(canvas, rect);
  }

  void _drawPaperFibers(Canvas canvas, Size size, Offset chalkOffset) {
    final fiberPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const count = 96;

    for (var i = 0; i < count; i += 1) {
      final start =
          Offset(
            _unitNoise(i * 37 + 5) * size.width,
            _unitNoise(i * 41 + 9) * size.height,
          ) +
          chalkOffset * 0.35;
      final length = 18 + _unitNoise(i * 43 + 11) * 96;
      final angle = (_unitNoise(i * 47 + 13) - 0.5) * 0.35;
      final alpha = 0.012 + _unitNoise(i * 53 + 17) * 0.026;
      fiberPaint
        ..color = NeutralColors.darkBorder.withValues(alpha: alpha)
        ..strokeWidth = 0.5 + _unitNoise(i * 59 + 19) * 0.9;
      canvas.drawLine(
        start,
        start + Offset(math.cos(angle) * length, math.sin(angle) * length),
        fiberPaint,
      );
    }
  }

  void _drawPaperGuides(Canvas canvas, Size size, Offset chalkOffset) {
    final guidePaint = Paint()
      ..color = NeutralColors.darkBorder.withValues(alpha: 0.018)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const step = 96.0;

    final startY = (chalkOffset.dy % step) - step;
    for (var y = startY; y <= size.height + step; y += step) {
      final wobble = math.sin(y * 0.013) * 2.2;
      canvas.drawLine(
        Offset(0, y + wobble),
        Offset(size.width, y + wobble + math.sin(y * 0.021) * 1.5),
        guidePaint,
      );
    }
  }

  void _drawCanvasVignette(Canvas canvas, Rect rect) {
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.2)],
        stops: const [0.55, 1],
      ).createShader(rect);
    canvas.drawRect(rect, vignettePaint);
  }

  void _drawChalkDust(Canvas canvas, Size size, Offset chalkOffset) {
    final dustPaint = Paint();
    const dustCount = 180;

    for (var i = 0; i < dustCount; i++) {
      final seedA = _unitNoise(i * 17 + 3);
      final seedB = _unitNoise(i * 29 + 11);
      final position =
          Offset(seedA * size.width, seedB * size.height) + chalkOffset;
      final width = 2 + _unitNoise(i * 43 + 7) * 12;
      final alpha = 0.018 + _unitNoise(i * 53 + 19) * 0.04;
      dustPaint
        ..color = NeutralColors.darkBorder.withValues(alpha: alpha)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        position,
        position + Offset(width, math.sin(i.toDouble()) * 2),
        dustPaint,
      );
    }
  }

  double _unitNoise(int seed) {
    final value = math.sin(seed * 12.9898) * 43758.5453;
    return value - value.floorToDouble();
  }

  @override
  bool shouldRepaint(covariant _InteractiveBackgroundPainter oldDelegate) {
    return oldDelegate.mousePos != mousePos ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.cursorTrail.length != cursorTrail.length ||
        (oldDelegate.cursorTrail.isNotEmpty &&
            cursorTrail.isNotEmpty &&
            oldDelegate.cursorTrail.last != cursorTrail.last);
  }
}

class _ConnectionDrag {
  const _ConnectionDrag({
    required this.source,
    required this.startScene,
    required this.currentScene,
    required this.target,
  });

  final MindmapNode source;
  final Offset startScene;
  final Offset currentScene;
  final MindmapNode? target;

  _ConnectionDrag copyWith({Offset? currentScene, MindmapNode? target}) {
    return _ConnectionDrag(
      source: source,
      startScene: startScene,
      currentScene: currentScene ?? this.currentScene,
      target: target,
    );
  }
}

class _ConnectionDragPainter extends CustomPainter {
  const _ConnectionDragPainter({required this.drag});

  final _ConnectionDrag drag;

  @override
  void paint(Canvas canvas, Size size) {
    final colorA = nodeColor(drag.source.type);
    final colorB = drag.target == null ? colorA : nodeColor(drag.target!.type);
    final target = drag.currentScene;
    final dx = target.dx - drag.startScene.dx;

    final cp1 = Offset(drag.startScene.dx + dx * 0.55, drag.startScene.dy);
    final cp2 = Offset(target.dx - dx * 0.35, target.dy);

    final path = Path()
      ..moveTo(drag.startScene.dx, drag.startScene.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, target.dx, target.dy);

    final stroke = Paint()
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(colorA, colorB, 0.5)!.withValues(alpha: 0.92);
    canvas.drawPath(path, stroke);

    // Sketchy second trace
    final sketchPaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(colorA, colorB, 0.5)!.withValues(alpha: 0.4);

    final sketchPath = Path()
      ..moveTo(drag.startScene.dx + 1.2, drag.startScene.dy - 0.8);
    final scp1 = Offset(cp1.dx + 2.0, cp1.dy - 1.2);
    final scp2 = Offset(cp2.dx - 1.2, cp2.dy + 1.8);
    sketchPath.cubicTo(
      scp1.dx,
      scp1.dy,
      scp2.dx,
      scp2.dy,
      target.dx + 0.8,
      target.dy - 0.8,
    );
    canvas.drawPath(sketchPath, sketchPaint);

    // Arrowhead when snapped or dragging
    final dir = target - cp2;
    final len = dir.distance;
    if (len > 0) {
      final unitDir = dir / len;
      final arrowTip = target - unitDir * (drag.target == null ? 0.0 : 4.5);
      final normal = Offset(-unitDir.dy, unitDir.dx);
      final arrowLeft = arrowTip - unitDir * 7 + normal * 4.5;
      final arrowRight = arrowTip - unitDir * 7 - normal * 4.5;

      final arrowPath = Path()
        ..moveTo(arrowTip.dx, arrowTip.dy)
        ..lineTo(arrowLeft.dx, arrowLeft.dy)
        ..moveTo(arrowTip.dx, arrowTip.dy)
        ..lineTo(arrowRight.dx, arrowRight.dy);

      final arrowPaint = Paint()
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(colorA, colorB, 0.5)!.withValues(alpha: 0.72);
      canvas.drawPath(arrowPath, arrowPaint);
    }

    canvas.drawCircle(drag.startScene, 5, Paint()..color = colorA);
    canvas.drawCircle(
      target,
      drag.target == null ? 7 : 10,
      Paint()
        ..color = colorB.withValues(alpha: drag.target == null ? 0.55 : 0.9)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectionDragPainter oldDelegate) {
    return oldDelegate.drag != drag;
  }
}

class _ConnectionLinesPainter extends CustomPainter {
  _ConnectionLinesPainter({
    required this.nodes,
    required this.dragPositions,
    required this.origin,
    required this.compactNodeIds,
  });

  final List<MindmapNode> nodes;
  final Map<String, CanvasPosition> dragPositions;
  final Offset origin;
  final Set<String> compactNodeIds;

  CanvasPosition _positionFor(MindmapNode node) {
    return dragPositions[node.id] ?? node.position;
  }

  Size _nodeSizeFor(MindmapNode node) {
    if (compactNodeIds.contains(node.id)) return const Size(260, 92);
    return node.type == NodeType.kanban
        ? MindmapCanvas.kanbanNodeSize
        : MindmapCanvas.nodeSize;
  }

  double _portY(MindmapNode node, Size size) {
    return compactNodeIds.contains(node.id) ? size.height / 2 : 96;
  }

  Offset _getOutputPort(MindmapNode node) {
    final pos = _positionFor(node);
    final size = _nodeSizeFor(node);
    return origin +
        Offset(pos.dx + size.width - 2, pos.dy + _portY(node, size));
  }

  Offset _getInputPort(MindmapNode node) {
    final pos = _positionFor(node);
    final size = _nodeSizeFor(node);
    return origin + Offset(pos.dx + 2, pos.dy + _portY(node, size));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, MindmapNode> nodeMap = {for (final n in nodes) n.id: n};

    final Set<String> drawnConnections = {};

    for (final node in nodes) {
      final pA = _getOutputPort(node);
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
        final pB = _getInputPort(targetNode);
        final colorB = nodeColor(targetNode.type);

        final paint = Paint()
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(colorA, colorB, 0.5)!.withValues(alpha: 0.82);

        final dx = (pB.dx - pA.dx).abs();
        final dy = (pB.dy - pA.dy).abs();

        Offset cp1;
        Offset cp2;
        if (dx > dy) {
          cp1 = Offset(pA.dx + (pB.dx - pA.dx) * 0.5, pA.dy);
          cp2 = Offset(pB.dx - (pB.dx - pA.dx) * 0.5, pB.dy);
        } else {
          cp1 = Offset(pA.dx, pA.dy + (pB.dy - pA.dy) * 0.5);
          cp2 = Offset(pB.dx, pB.dy - (pB.dy - pA.dy) * 0.5);
        }

        final path = Path()
          ..moveTo(pA.dx, pA.dy)
          ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pB.dx, pB.dy);
        canvas.drawPath(path, paint);

        // Doodle secondary sketchy line with minor offset
        final sketchPaint = Paint()
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(colorA, colorB, 0.5)!.withValues(alpha: 0.36);

        final sketchPath = Path()..moveTo(pA.dx + 1.2, pA.dy - 0.8);
        Offset scp1;
        Offset scp2;
        if (dx > dy) {
          scp1 = Offset(cp1.dx + 2.0, cp1.dy - 1.2);
          scp2 = Offset(cp2.dx - 1.2, cp2.dy + 1.8);
        } else {
          scp1 = Offset(cp1.dx - 1.2, cp1.dy + 2.0);
          scp2 = Offset(cp2.dx + 1.8, cp2.dy - 1.2);
        }
        sketchPath.cubicTo(
          scp1.dx,
          scp1.dy,
          scp2.dx,
          scp2.dy,
          pB.dx + 0.8,
          pB.dy - 0.8,
        );
        canvas.drawPath(sketchPath, sketchPaint);

        // Draw small doodle arrowhead pointing at target port pB
        final dir = pB - cp2;
        final len = dir.distance;
        if (len > 0) {
          final unitDir = dir / len;
          final arrowTip = pB - unitDir * 4.5;
          final normal = Offset(-unitDir.dy, unitDir.dx);
          final arrowLeft = arrowTip - unitDir * 7 + normal * 4.5;
          final arrowRight = arrowTip - unitDir * 7 - normal * 4.5;

          final arrowPath = Path()
            ..moveTo(arrowTip.dx, arrowTip.dy)
            ..lineTo(arrowLeft.dx, arrowLeft.dy)
            ..moveTo(arrowTip.dx, arrowTip.dy)
            ..lineTo(arrowRight.dx, arrowRight.dy);

          final arrowPaint = Paint()
            ..strokeWidth = 1.6
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..color = Color.lerp(colorA, colorB, 0.5)!.withValues(alpha: 0.72);
          canvas.drawPath(arrowPath, arrowPaint);
        }

        final endpointPaintA = Paint()..color = colorA.withValues(alpha: 0.95);
        final endpointPaintB = Paint()..color = colorB.withValues(alpha: 0.95);
        canvas.drawCircle(pA, 4.5, endpointPaintA);
        canvas.drawCircle(pB, 4.5, endpointPaintB);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionLinesPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.dragPositions != dragPositions ||
        oldDelegate.origin != origin ||
        oldDelegate.compactNodeIds != compactNodeIds;
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
    return oldDelegate.nodes != nodes ||
        oldDelegate.dragPositions != dragPositions ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.canvasSize != canvasSize;
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
  NodeType.event => Icons.event_outlined,
  NodeType.decision => Icons.rule_outlined,
  NodeType.resource => Icons.inventory_2_outlined,
  NodeType.idea => Icons.lightbulb_outline,
  NodeType.question => Icons.help_outline,
  NodeType.contact => Icons.person_outline,
  NodeType.metric => Icons.query_stats_outlined,
  NodeType.expense => Icons.payments_outlined,
  NodeType.bookmark => Icons.bookmark_border,
  NodeType.routine => Icons.repeat_on_outlined,
  NodeType.empty => Icons.circle_outlined,
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
  NodeType.event => NodeColors.event,
  NodeType.decision => NodeColors.decision,
  NodeType.resource => NodeColors.resource,
  NodeType.idea => NodeColors.idea,
  NodeType.question => NodeColors.question,
  NodeType.contact => NodeColors.contact,
  NodeType.metric => NodeColors.metric,
  NodeType.expense => NodeColors.expense,
  NodeType.bookmark => NodeColors.bookmark,
  NodeType.routine => NodeColors.routine,
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
  switch (node.type) {
    case NodeType.contact:
      labels.addAll(_compactDataLabels(node, ['company', 'role']));
    case NodeType.metric:
      labels.addAll(_compactDataLabels(node, ['value', 'unit', 'target']));
    case NodeType.expense:
      labels.addAll(_compactDataLabels(node, ['amount', 'category']));
    case NodeType.resource:
      labels.addAll(_sourceLabel(node.data['source']));
    case NodeType.bookmark:
      labels.addAll(_sourceLabel(node.data['url']));
    default:
      break;
  }
  return labels;
}

List<String> _compactDataLabels(MindmapNode node, List<String> keys) {
  final labels = <String>[];
  for (final key in keys) {
    final value = node.data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) labels.add(value);
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
        NodeType.note ||
        NodeType.link ||
        NodeType.resource => _NoteNodeSource(node: node),
        NodeType.event => _EventNodeDetails(node: node),
        NodeType.decision => _DecisionNodeDetails(node: node),
        NodeType.idea => _IdeaNodeDetails(node: node),
        NodeType.question => _QuestionNodeDetails(node: node),
        NodeType.contact => _ContactNodeDetails(node: node),
        NodeType.metric => _MetricNodeDetails(node: node),
        NodeType.expense => _ExpenseNodeDetails(node: node),
        NodeType.bookmark => _BookmarkNodeDetails(node: node),
        NodeType.routine => _RoutineNodeDetails(node: node),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _EventNodeDetails extends StatelessWidget {
  const _EventNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = calendarNodePayloadFromData(node.data);
    final details = <String>[
      if (payload?.location?.trim().isNotEmpty == true)
        '📍 ${payload!.location!.trim()}',
      if (payload?.remindAt?.trim().isNotEmpty == true)
        '⏰ ${payload!.remindAt!.trim()}',
      if (payload?.participants?.trim().isNotEmpty == true)
        '👥 ${payload!.participants!.trim()}',
    ];
    return _MiniDetailList(items: details);
  }
}

class _DecisionNodeDetails extends StatelessWidget {
  const _DecisionNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = calendarNodePayloadFromData(node.data);
    final details = <String>[
      if (payload?.selectedOption?.trim().isNotEmpty == true)
        'Chosen: ${payload!.selectedOption!.trim()}',
      if (payload?.reason?.trim().isNotEmpty == true)
        'Why: ${payload!.reason!.trim()}',
      if (payload?.options?.trim().isNotEmpty == true)
        'Options: ${payload!.options!.trim()}',
    ];
    return _MiniDetailList(items: details);
  }
}

class _IdeaNodeDetails extends StatelessWidget {
  const _IdeaNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final lines = node.body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(3)
        .toList();
    return _MiniDetailList(items: lines.map((line) => '💡 $line').toList());
  }
}

class _QuestionNodeDetails extends StatelessWidget {
  const _QuestionNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final fields = _bodyFields(node.body);
    final followUps = node.checklist.map((item) => '↳ ${item.title}').take(2);
    return _MiniDetailList(
      items: [
        if ((fields['question'] ?? '').isNotEmpty) '? ${fields['question']}',
        if ((fields['context'] ?? '').isNotEmpty)
          'Context: ${fields['context']}',
        ...followUps,
      ],
    );
  }
}

class _ContactNodeDetails extends StatelessWidget {
  const _ContactNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    return _MiniDetailList(
      items: [
        if (_dataText(node, 'email').isNotEmpty)
          '✉ ${_dataText(node, 'email')}',
        if (_dataText(node, 'phone').isNotEmpty)
          '☎ ${_dataText(node, 'phone')}',
        if (_dataText(node, 'company').isNotEmpty)
          'Company: ${_dataText(node, 'company')}',
      ],
    );
  }
}

class _MetricNodeDetails extends StatelessWidget {
  const _MetricNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final value = _dataText(node, 'value');
    final unit = _dataText(node, 'unit');
    return _MiniDetailList(
      items: [
        if (value.isNotEmpty || unit.isNotEmpty) 'Value: $value $unit'.trim(),
        if (_dataText(node, 'target').isNotEmpty)
          'Target: ${_dataText(node, 'target')}',
        if (_dataText(node, 'trend').isNotEmpty)
          'Trend: ${_dataText(node, 'trend')}',
      ],
    );
  }
}

class _ExpenseNodeDetails extends StatelessWidget {
  const _ExpenseNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    return _MiniDetailList(
      items: [
        if (_dataText(node, 'amount').isNotEmpty)
          'Amount: ${_dataText(node, 'amount')}',
        if (_dataText(node, 'category').isNotEmpty)
          'Category: ${_dataText(node, 'category')}',
        if (_dataText(node, 'merchant').isNotEmpty)
          'Merchant: ${_dataText(node, 'merchant')}',
      ],
    );
  }
}

class _BookmarkNodeDetails extends StatelessWidget {
  const _BookmarkNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final url = _dataText(node, 'url').isEmpty
        ? _sectionData(node.data, 'link')['url']?.toString() ?? ''
        : _dataText(node, 'url');
    return _MiniDetailList(
      items: [if (url.trim().isNotEmpty) '🔖 ${_displayUrl(url)}'],
    );
  }
}

class _RoutineNodeDetails extends StatelessWidget {
  const _RoutineNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final steps = node.checklist.map((item) => '↻ ${item.title}').take(3);
    return _MiniDetailList(items: steps.toList());
  }
}

String _dataText(MindmapNode node, String key) {
  final value = node.data[key]?.toString().trim();
  if (value != null && value.isNotEmpty) return value;
  return _bodyFields(node.body)[key] ?? '';
}

Map<String, String> _bodyFields(String body) {
  final fields = <String, String>{};
  for (final line in body.split('\n')) {
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) fields[key] = value;
  }
  return fields;
}

String _displayUrl(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || parsed.host.isEmpty) return url.trim();
  return parsed.host.replaceFirst(RegExp(r'^www\.'), '');
}

class _MiniDetailList extends StatelessWidget {
  const _MiniDetailList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              item,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
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
