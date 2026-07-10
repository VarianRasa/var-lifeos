/// Interactive daily mindmap canvas.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/widgets/doodle_border.dart';
import '../../calendar/domain/calendar_node_payload.dart';
import '../application/collaboration_controller.dart';
import '../domain/canvas_position.dart';
import '../domain/goal_progress.dart';
import '../domain/habit_completion.dart';
import '../domain/kanban_board.dart';
import '../domain/life_os_summary.dart';
import '../domain/mindmap_node.dart';
import '../domain/plan_progress.dart';
import '../domain/task_checklist_progress.dart';
import 'collaborator_cursor_widget.dart';

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
    this.variant = AppThemeVariant.blackboard,
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
    this.onNodeQuickCreate,
    this.collaborationState,
    this.onLocalCursorChanged,
    this.onLocalSelectionChanged,
    this.onLocalPingRequested,
    this.pingStream,
    super.key,
  });

  static const Size canvasSize = Size(20000, 14000);
  static const Size nodeSize = Size(340, 320);
  static const Size kanbanNodeSize = Size(500, 320);

  final List<MindmapNode> nodes;
  final AppThemeVariant variant;
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
  final void Function(
    NodeType type,
    String title, {
    NodePriority? priority,
    List<String>? tags,
  })?
  onNodeQuickCreate;

  final CollaborationState? collaborationState;
  final void Function(Offset position)? onLocalCursorChanged;
  final void Function(String? nodeId)? onLocalSelectionChanged;
  final void Function(Offset scenePosition)? onLocalPingRequested;
  final Stream<PingEvent>? pingStream;

  @override
  State<MindmapCanvas> createState() => MindmapCanvasState();
}

class MindmapCanvasState extends State<MindmapCanvas>
    with TickerProviderStateMixin {
  final Map<String, CanvasPosition> _dragPositions = {};
  final TransformationController _transformationController =
      TransformationController();
  bool _didSetInitialTransform = false;
  String? _followingCollaboratorId;

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
  NodeReviewState? _reviewStateFilter;
  bool _nextActionOnly = false;
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

  StreamSubscription<PingEvent>? _pingSub;
  final List<_ActivePing> _activePings = <_ActivePing>[];
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
    _listenForPings(widget.pingStream);
  }

  void _listenForPings(Stream<PingEvent>? stream) {
    _pingSub?.cancel();
    _pingSub = stream?.listen(_showPing);
  }

  void _showPing(PingEvent event) {
    if (!mounted) return;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final ping = _ActivePing(event: event, controller: controller);
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (mounted) {
        setState(() => _activePings.remove(ping));
      } else {
        _activePings.remove(ping);
      }
      controller.dispose();
    });
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _activePings.add(ping));
    controller.forward();
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
    _pingSub?.cancel();
    for (final ping in _activePings) {
      ping.controller.dispose();
    }
    _activePings.clear();
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

  void _handleCanvasPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_isCtrlPressed) return;
    _zoomAt(event.localPosition, event.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12);
  }

  void _navigateSelection(LogicalKeyboardKey key) {
    if (widget.nodes.isEmpty) return;

    final sourceId =
        _lastSelectedNodeId ??
        (_selectedNodeIds.isNotEmpty ? _selectedNodeIds.first : null);
    if (sourceId == null) {
      final target = widget.nodes.first;
      _selectNode(target);
      focusOnPosition(target.position);
      return;
    }

    final sourceNode = widget.nodes.firstWhere((n) => n.id == sourceId);
    final sourcePos = sourceNode.position;

    MindmapNode? bestTarget;
    double bestScore = double.infinity;

    for (final node in widget.nodes) {
      if (node.id == sourceId) continue;

      final dx = node.position.dx - sourcePos.dx;
      final dy = node.position.dy - sourcePos.dy;

      bool inDirection = false;
      switch (key) {
        case LogicalKeyboardKey.arrowUp:
          inDirection = dy < -10 && dx.abs() < dy.abs() * 1.8;
          break;
        case LogicalKeyboardKey.arrowDown:
          inDirection = dy > 10 && dx.abs() < dy.abs() * 1.8;
          break;
        case LogicalKeyboardKey.arrowLeft:
          inDirection = dx < -10 && dy.abs() < dx.abs() * 1.8;
          break;
        case LogicalKeyboardKey.arrowRight:
          inDirection = dx > 10 && dy.abs() < dx.abs() * 1.8;
          break;
      }

      if (inDirection) {
        final dist = dx * dx + dy * dy;
        if (dist < bestScore) {
          bestScore = dist;
          bestTarget = node;
        }
      }
    }

    if (bestTarget != null) {
      _selectNode(bestTarget);
      focusOnPosition(bestTarget.position);
    }
  }

  KeyEventResult _handleCanvasKeyEvent(FocusNode node, KeyEvent event) {
    // Control / Meta Key zoom state tracking
    if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight) {
      final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
      if (_isCtrlZoomActive != isDown) {
        setState(() => _isCtrlZoomActive = isDown);
      }
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Delete or Backspace to delete selected nodes
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_selectedNodeIds.isNotEmpty) {
        unawaited(_archiveSelectedNodes());
        return KeyEventResult.handled;
      }
    }

    // Zoom shortcuts (+, -, 0)
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.add) {
      _zoomIn();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _zoomReset();
      return KeyEventResult.handled;
    }

    // Navigation and Panning via Arrows
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (isShift || _selectedNodeIds.isEmpty) {
        // Pan canvas
        final val = _transformationController.value.clone();
        final translation = val.getTranslation();
        double dx = 0;
        double dy = 0;
        const panSpeed = 35.0;

        if (key == LogicalKeyboardKey.arrowUp) dy = panSpeed;
        if (key == LogicalKeyboardKey.arrowDown) dy = -panSpeed;
        if (key == LogicalKeyboardKey.arrowLeft) dx = panSpeed;
        if (key == LogicalKeyboardKey.arrowRight) dx = -panSpeed;

        val.setTranslationRaw(
          translation.x + dx,
          translation.y + dy,
          translation.z,
        );
        _transformationController.value = val;
        return KeyEventResult.handled;
      } else {
        // Navigate nodes selection
        _navigateSelection(key);
        return KeyEventResult.handled;
      }
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
      _reviewStateFilter = null;
      _nextActionOnly = false;
    });
  }

  void _setSearchTypeFilter(NodeType? type) {
    setState(() => _searchTypeFilter = type);
  }

  void _setReviewStateFilter(NodeReviewState? state) {
    setState(() => _reviewStateFilter = state);
  }

  void _setNextActionOnly(bool value) {
    setState(() => _nextActionOnly = value);
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

  void _openCommandPalette() {
    if (widget.onNodeQuickCreate == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => _CommandPaletteDialog(
        onSubmitted: (type, title, {priority, tags}) {
          widget.onNodeQuickCreate?.call(
            type,
            title,
            priority: priority,
            tags: tags,
          );
        },
      ),
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
    if (event.buttons == kPrimaryMouseButton) {
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

  void _broadcastCanvasPing() {
    final callback = widget.onLocalPingRequested;
    if (callback == null) return;
    final position =
        _mousePos ??
        _transformationController.toScene(
          Offset(
            (context.size?.width ?? 0) / 2,
            (context.size?.height ?? 0) / 2,
          ),
        );
    callback(position);
    _showPing(
      PingEvent(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        fromId: widget.collaborationState?.localUserId ?? 'local',
        fromName: widget.collaborationState?.localName ?? 'You',
        color: widget.collaborationState?.localColor ?? Colors.cyanAccent,
        scenePosition: position,
        createdAt: DateTime.now(),
      ),
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

  void _followPeerPosition(Offset peerPos) {
    final size = context.size;
    if (size == null) return;

    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();

    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );

    final sceneX = origin.dx + peerPos.dx;
    final sceneY = origin.dy + peerPos.dy;

    final targetX = -sceneX * currentScale + size.width / 2;
    final targetY = -sceneY * currentScale + size.height / 2;

    final targetMatrix = Matrix4.identity()
      ..translateByDouble(targetX, targetY, 0, 1)
      ..scaleByDouble(currentScale, currentScale, 1, 1);

    _zoomAnimController.stop();
    _startZoomMatrix = _transformationController.value.clone();
    _targetZoomMatrix = targetMatrix;
    _zoomAnimController.forward(from: 0.0);
  }

  @override
  void didUpdateWidget(covariant MindmapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pingStream != widget.pingStream) {
      _listenForPings(widget.pingStream);
    }
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

    if (_followingCollaboratorId != null) {
      final oldPeer =
          oldWidget.collaborationState?.collaborators[_followingCollaboratorId];
      final newPeer =
          widget.collaborationState?.collaborators[_followingCollaboratorId];
      if (newPeer != null && newPeer.cursorPosition != null) {
        if (oldPeer == null ||
            oldPeer.cursorPosition != newPeer.cursorPosition) {
          _followPeerPosition(newPeer.cursorPosition!);
        }
      }
    }
  }

  Widget _buildPingRipple(_ActivePing ping) {
    final t = Curves.easeOutCubic.transform(ping.controller.value);
    final radius = 24.0 + (96.0 * t);
    final color = ping.event.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
    final position = ping.event.scenePosition;
    return Positioned(
      left: position.dx - radius,
      top: position.dy - radius,
      width: radius * 2,
      height: radius * 2,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18),
                blurRadius: 22,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _collabSelectionsForNode(
    MindmapNode node,
    CollaborationState collabState,
    Offset origin,
  ) {
    final widgets = <Widget>[];
    for (final collaborator in collabState.collaborators.values) {
      if (collaborator.selectedNodeId != node.id) continue;
      final pos = _positionFor(node);
      final size = _nodeSizeFor(node);
      // Badge lives above the node so it never gets clipped by node content.
      const badgeHeight = 18.0;
      const borderInset = 4.0;
      widgets.add(
        Positioned(
          left: pos.dx + origin.dx - borderInset,
          top: pos.dy + origin.dy - borderInset,
          width: size.width + (borderInset * 2),
          height: size.height + (borderInset * 2) + badgeHeight + 4,
          child: IgnorePointer(
            child: _CollaboratorSelectionOverlay(
              color: collaborator.color,
              name: collaborator.name,
              isEditing: collaborator.isEditing,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final collabState =
        widget.collaborationState ??
        CollaborationState(
          collaborators: {},
          isDemoMode: false,
          isConnected: false,
          localUserId: '',
          localName: '',
          localColor: Colors.transparent,
        );
    final variant = widget.variant;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                final matchesReview =
                    _reviewStateFilter == null ||
                    node.reviewState == _reviewStateFilter;
                final matchesNextAction =
                    !_nextActionOnly ||
                    node.isNextActionCandidate(DateTime.now());
                final matchesFocus =
                    focusNode == null || focusIds.contains(node.id);
                return matchesText &&
                    matchesType &&
                    matchesReview &&
                    matchesNextAction &&
                    matchesFocus;
              }).toList();
              if (_nextActionOnly) {
                filteredNodes.sort(
                  (a, b) => b
                      .nextActionScore(DateTime.now())
                      .compareTo(a.nextActionScore(DateTime.now())),
                );
              }
              final isSearchActive =
                  _searchQuery.isNotEmpty ||
                  _searchTypeFilter != null ||
                  _reviewStateFilter != null ||
                  _nextActionOnly;
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
                  const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                      _openCommandPalette,
                  const SingleActivator(LogicalKeyboardKey.slash):
                      _openCommandPalette,
                  const SingleActivator(LogicalKeyboardKey.space, shift: true):
                      _broadcastCanvasPing,
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
                                  widget.onLocalCursorChanged?.call(
                                    event.localPosition,
                                  );
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
                                          variant: variant,
                                          isDark: isDark,
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
                                    for (final node in visibleNodes) ...[
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
                                      ..._collabSelectionsForNode(
                                        node,
                                        collabState,
                                        origin,
                                      ),
                                    ],
                                    for (final entry
                                        in collabState.collaborators.entries)
                                      if (entry.value.cursorPosition != null)
                                        CollaboratorCursorWidget(
                                          name: entry.value.name,
                                          color: entry.value.color,
                                          position: entry.value.cursorPosition!,
                                        ),
                                    for (final ping in _activePings)
                                      _buildPingRipple(ping),
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
                          selectedReviewState: _reviewStateFilter,
                          nextActionOnly: _nextActionOnly,
                          isCollapsed: _isSearchOverlayCollapsed,
                          onClearSearch: _clearSearch,
                          onTypeSelected: _setSearchTypeFilter,
                          onReviewStateSelected: _setReviewStateFilter,
                          onNextActionOnlyChanged: _setNextActionOnly,
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

                      // Collaboration Room Bar
                      if (widget.collaborationState != null)
                        Positioned(
                          top: 86,
                          left: 16,
                          child: _CollaborationRoomBar(
                            nodes: widget.nodes,
                            followingId: _followingCollaboratorId,
                            onFollowChanged: (id) {
                              setState(() {
                                _followingCollaboratorId = id;
                                if (id != null) {
                                  final peer = widget
                                      .collaborationState
                                      ?.collaborators[id];
                                  if (peer != null &&
                                      peer.cursorPosition != null) {
                                    _followPeerPosition(peer.cursorPosition!);
                                  }
                                }
                              });
                            },
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
    widget.onLocalSelectionChanged?.call(node.id);
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
    widget.onLocalSelectionChanged?.call(null);
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
        node.contextTags.any((t) => t.toLowerCase().contains(query)) ||
        node.status.name.toLowerCase().contains(query) ||
        node.priority.name.toLowerCase().contains(query) ||
        node.effort.name.toLowerCase().contains(query) ||
        node.reviewState.name.toLowerCase().contains(query);
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
      decoration: ShapeDecoration(
        color: theme.colorScheme.surface,
        shape: DoodleShapeBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
          radius: 999,
          wobble: 0.8,
        ),
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
    required this.selectedReviewState,
    required this.nextActionOnly,
    required this.isCollapsed,
    required this.onClearSearch,
    required this.onTypeSelected,
    required this.onReviewStateSelected,
    required this.onNextActionOnlyChanged,
    required this.onCollapsedChanged,
    required this.onSubmitted,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearchActive;
  final int filteredCount;
  final NodeType? selectedType;
  final NodeReviewState? selectedReviewState;
  final bool nextActionOnly;
  final bool isCollapsed;
  final VoidCallback onClearSearch;
  final ValueChanged<NodeType?> onTypeSelected;
  final ValueChanged<NodeReviewState?> onReviewStateSelected;
  final ValueChanged<bool> onNextActionOnlyChanged;
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
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            key: const ValueKey('mindmap-next-action-filter'),
                            avatar: const Icon(Icons.bolt_outlined, size: 16),
                            label: const Text('Next actions'),
                            selected: nextActionOnly,
                            onSelected: onNextActionOnlyChanged,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _CanvasSearchFilters(
                          selectedType: selectedType,
                          onSelected: onTypeSelected,
                        ),
                        const SizedBox(height: 8),
                        _CanvasReviewFilters(
                          selectedState: selectedReviewState,
                          onSelected: onReviewStateSelected,
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

class _CanvasReviewFilters extends StatelessWidget {
  const _CanvasReviewFilters({
    required this.selectedState,
    required this.onSelected,
  });

  final NodeReviewState? selectedState;
  final ValueChanged<NodeReviewState?> onSelected;

  static const _filters = <NodeReviewState>[
    NodeReviewState.needsReview,
    NodeReviewState.stale,
    NodeReviewState.someday,
    NodeReviewState.parked,
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
              key: const ValueKey('mindmap-review-filter-all'),
              icon: Icons.fact_check_outlined,
              label: 'Review all',
              color: theme.colorScheme.secondary,
              isSelected: selectedState == null,
              onTap: () => onSelected(null),
            );
          }

          final state = _filters[index - 1];
          return _CanvasFilterPill(
            key: ValueKey('mindmap-review-filter-${state.name}'),
            icon: _reviewIcon(state),
            label: state.label,
            color: theme.colorScheme.tertiary,
            isSelected: selectedState == state,
            onTap: () => onSelected(state),
          );
        },
      ),
    );
  }

  IconData _reviewIcon(NodeReviewState state) {
    return switch (state) {
      NodeReviewState.needsReview => Icons.rate_review_outlined,
      NodeReviewState.stale => Icons.history_toggle_off_outlined,
      NodeReviewState.someday => Icons.inbox_outlined,
      NodeReviewState.parked => Icons.local_parking_outlined,
      NodeReviewState.none => Icons.fact_check_outlined,
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
  DateTime? _lastTapTime;

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
            final now = DateTime.now();
            if (_lastTapTime != null &&
                now.difference(_lastTapTime!) <
                    const Duration(milliseconds: 300)) {
              if (widget.canToggleDone) {
                widget.onTaskDoneChanged(!widget.isDone);
              }
            } else {
              widget.onSelect();
            }
            _lastTapTime = now;
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
  NodeType.mood => const _DoodleCardStyle(_DoodleCardKind.note),
  NodeType.timer => const _DoodleCardStyle(_DoodleCardKind.ticket),
  NodeType.quote => const _DoodleCardStyle(_DoodleCardKind.torn),
  NodeType.audio => const _DoodleCardStyle(_DoodleCardKind.label),
  NodeType.checklist => const _DoodleCardStyle(_DoodleCardKind.rounded),
  NodeType.canvas => const _DoodleCardStyle(_DoodleCardKind.note),
  NodeType.weather => const _DoodleCardStyle(_DoodleCardKind.label),
  NodeType.fit => const _DoodleCardStyle(_DoodleCardKind.pill),
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
                  Flexible(
                    child: _NodeTypeSpecificContent(
                      node: node,
                      onNodeUpdated: widget.onNodeUpdated,
                    ),
                  ),
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
    required this.variant,
    required this.isDark,
  });

  final Offset? mousePos;
  final List<Offset> cursorTrail;
  final double animationValue;
  final bool showGrid;
  final AppThemeVariant variant;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final chalkOffset = mousePos != null
        ? (mousePos! - center) * 0.004
        : Offset.zero;
    final rect = Offset.zero & size;

    final List<Color> bgColors;
    if (isDark) {
      switch (variant) {
        case AppThemeVariant.blueprint:
          bgColors = [
            const Color(0xFF070C16),
            const Color(0xFF111B2B),
            const Color(0xFF090F19),
          ];
          break;
        case AppThemeVariant.schoolboard:
          bgColors = [
            const Color(0xFF061410),
            const Color(0xFF0C241D),
            const Color(0xFF05110E),
          ];
          break;
        case AppThemeVariant.midnight:
          bgColors = [
            const Color(0xFF040208),
            const Color(0xFF110A21),
            const Color(0xFF05030A),
          ];
          break;
        case AppThemeVariant.cardboard:
          bgColors = [
            const Color(0xFF241910),
            const Color(0xFF302216),
            const Color(0xFF20160F),
          ];
          break;
        case AppThemeVariant.blackboard:
          bgColors = [
            const Color(0xFF090B09),
            const Color(0xFF10120E),
            const Color(0xFF070807),
          ];
          break;
      }
    } else {
      switch (variant) {
        case AppThemeVariant.blueprint:
          bgColors = [
            const Color(0xFFECF3FA),
            const Color(0xFFF2F7FD),
            const Color(0xFFE5EEF8),
          ];
          break;
        case AppThemeVariant.schoolboard:
          bgColors = [
            const Color(0xFFF3FBF8),
            const Color(0xFFF8FCFA),
            const Color(0xFFECF7F3),
          ];
          break;
        case AppThemeVariant.midnight:
          bgColors = [
            const Color(0xFFFAF8FF),
            const Color(0xFFFCFAFF),
            const Color(0xFFF5F2FD),
          ];
          break;
        case AppThemeVariant.cardboard:
          bgColors = [
            const Color(0xFFE8DBCA),
            const Color(0xFFECDDCB),
            const Color(0xFFE2D3BF),
          ];
          break;
        case AppThemeVariant.blackboard:
          bgColors = [
            const Color(0xFFFFF7E2),
            const Color(0xFFFCF4DC),
            const Color(0xFFFAF1D7),
          ];
          break;
      }
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bgColors,
        ).createShader(rect),
    );

    if (variant == AppThemeVariant.blackboard ||
        variant == AppThemeVariant.schoolboard ||
        variant == AppThemeVariant.cardboard) {
      _drawPaperFibers(canvas, size, chalkOffset);
      _drawChalkDust(canvas, size, chalkOffset);
    }

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
    final borderColor = isDark
        ? AppThemeVariantColors.of(variant).darkBorder
        : AppThemeVariantColors.of(variant).lightBorder;

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
        ..color = borderColor.withValues(alpha: alpha)
        ..strokeWidth = 0.5 + _unitNoise(i * 59 + 19) * 0.9;
      canvas.drawLine(
        start,
        start + Offset(math.cos(angle) * length, math.sin(angle) * length),
        fiberPaint,
      );
    }
  }

  void _drawPaperGuides(Canvas canvas, Size size, Offset chalkOffset) {
    final borderColor = isDark
        ? AppThemeVariantColors.of(variant).darkBorder
        : AppThemeVariantColors.of(variant).lightBorder;
    final guideColor = borderColor.withValues(alpha: isDark ? 0.035 : 0.08);

    final guidePaint = Paint()
      ..color = guideColor
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    if (variant == AppThemeVariant.blueprint) {
      const step = 48.0;
      final startX = (chalkOffset.dx % step) - step;
      for (var x = startX; x <= size.width + step; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), guidePaint);
      }
      final startY = (chalkOffset.dy % step) - step;
      for (var y = startY; y <= size.height + step; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
      }
    } else if (variant == AppThemeVariant.midnight) {
      final dotPaint = Paint()
        ..color = guideColor.withValues(alpha: 0.15)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      const step = 48.0;
      final startX = (chalkOffset.dx % step) - step;
      final startY = (chalkOffset.dy % step) - step;
      for (var x = startX; x <= size.width + step; x += step) {
        for (var y = startY; y <= size.height + step; y += step) {
          canvas.drawPoints(ui.PointMode.points, [Offset(x, y)], dotPaint);
        }
      }
    } else {
      const step = 96.0;
      final startY = (chalkOffset.dy % step) - step;
      final isWobbly =
          variant == AppThemeVariant.blackboard ||
          variant == AppThemeVariant.cardboard;
      final amp = variant == AppThemeVariant.cardboard ? 3.5 : 2.2;

      for (var y = startY; y <= size.height + step; y += step) {
        final wobble = isWobbly ? math.sin(y * 0.013) * amp : 0.0;
        final endWobble = isWobbly ? math.sin(y * 0.021) * (amp * 0.7) : 0.0;
        canvas.drawLine(
          Offset(0, y + wobble),
          Offset(size.width, y + wobble + endWobble),
          guidePaint,
        );
      }
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
    final borderColor = isDark
        ? AppThemeVariantColors.of(variant).darkBorder
        : AppThemeVariantColors.of(variant).lightBorder;

    for (var i = 0; i < dustCount; i++) {
      final seedA = _unitNoise(i * 17 + 3);
      final seedB = _unitNoise(i * 29 + 11);
      final position =
          Offset(seedA * size.width, seedB * size.height) + chalkOffset;
      final width = 2 + _unitNoise(i * 43 + 7) * 12;
      final alpha = 0.018 + _unitNoise(i * 53 + 19) * 0.04;
      dustPaint
        ..color = borderColor.withValues(alpha: alpha)
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
        oldDelegate.variant != variant ||
        oldDelegate.isDark != isDark ||
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

/// Painted overlay shown on a node that a collaborator currently has selected
/// or is editing. Pulses softly while editing, static while merely selected.
class _CollaboratorSelectionOverlay extends StatefulWidget {
  const _CollaboratorSelectionOverlay({
    required this.color,
    required this.name,
    required this.isEditing,
  });

  final Color color;
  final String name;
  final bool isEditing;

  @override
  State<_CollaboratorSelectionOverlay> createState() =>
      _CollaboratorSelectionOverlayState();
}

class _CollaboratorSelectionOverlayState
    extends State<_CollaboratorSelectionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _CollaboratorSelectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isEditing != widget.isEditing) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.isEditing) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              // Border breathes between 2.0 and 3.5 px while editing; steady 2.5 otherwise.
              final width = widget.isEditing ? 2.0 + (1.5 * t) : 2.5;
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: widget.color, width: width),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: widget.isEditing
                      ? [
                          BoxShadow(
                            color: widget.color.withValues(
                              alpha: 0.18 + (0.18 * t),
                            ),
                            blurRadius: 14,
                            spreadRadius: 1.5,
                          ),
                        ]
                      : null,
                ),
              );
            },
          ),
        ),
        Positioned(
          top: -18,
          left: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isEditing) ...[
                  const _EditingDots(color: Colors.black, size: 6),
                  const SizedBox(width: 4),
                ] else
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  widget.isEditing ? '${widget.name} editing' : widget.name,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Three-dot pulsing loader rendered while a collaborator is editing.
class _EditingDots extends StatefulWidget {
  const _EditingDots({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_EditingDots> createState() => _EditingDotsState();
}

class _EditingDotsState extends State<_EditingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dot;

  @override
  void initState() {
    super.initState();
    _dot = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dot,
      builder: (context, _) {
        // Stagger opacity across three dots using a phase offset.
        Widget dot(int index) {
          final phase = (_dot.value - (index * 0.25)) % 1.0;
          final alpha = (phase < 0 ? phase + 1 : phase).clamp(0.0, 1.0);
          final intensity = alpha < 0.5 ? alpha * 2 : (1 - alpha) * 2;
          return Container(
            width: widget.size,
            height: widget.size,
            margin: EdgeInsets.only(right: index < 2 ? 2 : 0),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.3 + (0.7 * intensity)),
              shape: BoxShape.circle,
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [dot(0), dot(1), dot(2)],
        );
      },
    );
  }
}

/// Transient ping ripple data driven by an [AnimationController].
class _ActivePing {
  _ActivePing({required this.event, required this.controller});

  final PingEvent event;
  final AnimationController controller;
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
  NodeType.mood => Icons.mood,
  NodeType.timer => Icons.timer_outlined,
  NodeType.quote => Icons.format_quote_outlined,
  NodeType.audio => Icons.mic_none_outlined,
  NodeType.checklist => Icons.checklist_rtl_outlined,
  NodeType.canvas => Icons.gesture_outlined,
  NodeType.weather => Icons.wb_sunny_outlined,
  NodeType.fit => Icons.directions_run_outlined,
  NodeType.empty => Icons.circle_outlined,
};

Color nodeColor(NodeType type) {
  final palette = AppThemeVariantColors.of(ThemeVariantConfig.active);
  return palette.nodeColors[type] ?? Colors.grey;
}

List<String> _metadataLabelsFor(MindmapNode node) {
  return [
    if (node.priority != NodePriority.none) node.priority.label,
    if (node.status != NodeStatus.open) node.status.label,
    if (node.effort != NodeEffort.unspecified) node.effort.label,
    if (node.reviewState != NodeReviewState.none) node.reviewState.label,
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
  const _NodeTypeSpecificContent({required this.node, this.onNodeUpdated});

  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

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
        NodeType.mood => _MoodNodeInfo(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.timer => _TimerNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.quote => _QuoteNodeDetails(node: node),
        NodeType.audio => _AudioNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.checklist => _ChecklistNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.canvas => _CanvasNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.weather => _WeatherNodeDetails(node: node),
        NodeType.fit => _FitNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _MoodNodeInfo extends StatelessWidget {
  const _MoodNodeInfo({required this.node, required this.onNodeUpdated});
  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final mood = node.data['mood'] as String? ?? '😊';
    final energy = (node.data['energy'] as num?)?.toDouble() ?? 3.0;
    final moodList = ['😢', '😔', '😐', '😊', '😁', '🔥'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('Mood: ', style: Theme.of(context).textTheme.bodySmall),
            for (final m in moodList)
              GestureDetector(
                onTap: onNodeUpdated == null
                    ? null
                    : () {
                        final newData = Map<String, Object?>.from(node.data)
                          ..['mood'] = m;
                        onNodeUpdated!(
                          node.copyWith(
                            data: newData,
                            updatedAt: DateTime.now(),
                          ),
                        );
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: Opacity(
                    opacity: m == mood ? 1.0 : 0.4,
                    child: Text(m, style: const TextStyle(fontSize: 18)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('Energy: ', style: Theme.of(context).textTheme.bodySmall),
            Expanded(
              child: Slider(
                min: 1,
                max: 5,
                divisions: 4,
                value: energy.clamp(1.0, 5.0),
                activeColor: nodeColor(node.type),
                onChanged: onNodeUpdated == null
                    ? null
                    : (val) {
                        final newData = Map<String, Object?>.from(node.data)
                          ..['energy'] = val.round();
                        onNodeUpdated!(
                          node.copyWith(
                            data: newData,
                            updatedAt: DateTime.now(),
                          ),
                        );
                      },
              ),
            ),
            Text(
              '${energy.round()}/5',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _TimerNodeDetails extends StatefulWidget {
  const _TimerNodeDetails({required this.node, required this.onNodeUpdated});
  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  State<_TimerNodeDetails> createState() => _TimerNodeDetailsState();
}

class _TimerNodeDetailsState extends State<_TimerNodeDetails> {
  Timer? _timer;
  late int _secondsLeft;
  late String _status;

  int get _initialSeconds =>
      (widget.node.data['timerInitialSeconds'] as num?)?.toInt() ??
      (widget.node.data['timerSeconds'] as num?)?.toInt() ??
      1500;

  @override
  void initState() {
    super.initState();
    _secondsLeft = (widget.node.data['timerSeconds'] as num?)?.toInt() ?? 1500;
    _status = widget.node.data['timerStatus'] as String? ?? 'stopped';
    if (_status == 'running') {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(_TimerNodeDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSeconds =
        (widget.node.data['timerSeconds'] as num?)?.toInt() ?? 1500;
    final newStatus = widget.node.data['timerStatus'] as String? ?? 'stopped';
    if (newSeconds != _secondsLeft || newStatus != _status) {
      _secondsLeft = newSeconds;
      _status = newStatus;
      _timer?.cancel();
      if (_status == 'running') {
        _startTimer();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        _updateState(0, 'stopped');
      } else {
        setState(() {
          _secondsLeft--;
        });
        if (_secondsLeft % 10 == 0) {
          _updateState(_secondsLeft, 'running');
        }
      }
    });
  }

  void _updateState(int seconds, String status) {
    if (widget.onNodeUpdated == null) return;
    final newData = Map<String, Object?>.from(widget.node.data)
      ..['timerInitialSeconds'] = _initialSeconds
      ..['timerSeconds'] = seconds
      ..['timerStatus'] = status;
    widget.onNodeUpdated!(
      widget.node.copyWith(
        data: newData,
        isDone: seconds == 0,
        updatedAt: DateTime.now(),
      ),
    );
  }

  String _formatTime(int totalSecs) {
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = nodeColor(widget.node.type);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            _formatTime(_secondsLeft),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                _status == 'running' ? Icons.pause_circle : Icons.play_circle,
              ),
              iconSize: 32,
              color: color,
              onPressed: () {
                if (_status == 'running') {
                  _timer?.cancel();
                  _updateState(_secondsLeft, 'paused');
                } else {
                  _updateState(_secondsLeft, 'running');
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.replay_circle_filled),
              iconSize: 32,
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () {
                _timer?.cancel();
                _updateState(_initialSeconds, 'stopped');
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _QuoteNodeDetails extends StatelessWidget {
  const _QuoteNodeDetails({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final author = node.data['author'] as String? ?? 'Unknown';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            '“${node.body.isNotEmpty ? node.body : "No quote text yet."}”',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.bottomRight,
          child: Text(
            '— $author',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: nodeColor(node.type),
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioNodeDetails extends StatefulWidget {
  const _AudioNodeDetails({required this.node, required this.onNodeUpdated});
  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  State<_AudioNodeDetails> createState() => _AudioNodeDetailsState();
}

class _AudioNodeDetailsState extends State<_AudioNodeDetails> {
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    final path = widget.node.data['audioPath'] as String? ?? '';
    final duration = widget.node.data['audioDuration'] as String? ?? '0:00';
    final transcript = widget.node.data['audioTranscript'] as String? ?? '';
    final color = nodeColor(widget.node.type);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              ),
              iconSize: 40,
              color: color,
              onPressed: path.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _isPlaying = !_isPlaying;
                      });
                    },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    path.isEmpty ? 'No recording' : path.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _isPlaying ? 0.4 : 0.0,
                          backgroundColor: color.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        duration,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (transcript.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            transcript.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }
}

class _ChecklistNodeDetails extends StatefulWidget {
  const _ChecklistNodeDetails({
    required this.node,
    required this.onNodeUpdated,
  });
  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  State<_ChecklistNodeDetails> createState() => _ChecklistNodeDetailsState();
}

class _ChecklistNodeDetailsState extends State<_ChecklistNodeDetails> {
  final _todoInputController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _todoInputController.dispose();
    super.dispose();
  }

  void _addTodo() {
    final text = _todoInputController.text.trim();
    if (text.isEmpty || widget.onNodeUpdated == null) return;
    final newItem = TaskChecklistItem(
      id: const Uuid().v4(),
      title: text,
      isDone: false,
    );
    final newChecklist = List<TaskChecklistItem>.from(widget.node.checklist)
      ..add(newItem);
    widget.onNodeUpdated!(
      widget.node.copyWith(checklist: newChecklist, updatedAt: DateTime.now()),
    );
    _todoInputController.clear();
    setState(() {
      _isAdding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = nodeColor(widget.node.type);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.node.checklist.isEmpty && !_isAdding)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                'Empty checklist',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          )
        else
          ...widget.node.checklist.take(4).map((item) {
            final index = widget.node.checklist.indexOf(item);
            return Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: item.isDone,
                    activeColor: color,
                    onChanged: widget.onNodeUpdated == null
                        ? null
                        : (val) {
                            final newChecklist = List<TaskChecklistItem>.from(
                              widget.node.checklist,
                            );
                            newChecklist[index] = TaskChecklistItem(
                              id: item.id,
                              title: item.title,
                              isDone: val ?? false,
                            );
                            widget.onNodeUpdated!(
                              widget.node.copyWith(
                                checklist: newChecklist,
                                updatedAt: DateTime.now(),
                              ),
                            );
                          },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration: item.isDone
                          ? TextDecoration.lineThrough
                          : null,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            );
          }),
        if (widget.node.checklist.length > 4)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              '+ ${widget.node.checklist.length - 4} more items',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.grey),
            ),
          ),
        const SizedBox(height: 4),
        if (_isAdding)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _todoInputController,
                    style: const TextStyle(fontSize: 12),
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'New item...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    onSubmitted: (_) => _addTodo(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.check, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: _addTodo,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _isAdding = false),
              ),
            ],
          )
        else
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 24),
              alignment: Alignment.centerLeft,
            ),
            icon: Icon(Icons.add, size: 14, color: color),
            label: Text(
              'Add item',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
            onPressed: () => setState(() => _isAdding = true),
          ),
      ],
    );
  }
}

class _CanvasNodeDetails extends StatefulWidget {
  const _CanvasNodeDetails({required this.node, required this.onNodeUpdated});
  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  State<_CanvasNodeDetails> createState() => _CanvasNodeDetailsState();
}

class _CanvasNodeDetailsState extends State<_CanvasNodeDetails> {
  List<Offset> _currentLine = [];
  List<List<Offset>> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  @override
  void didUpdateWidget(_CanvasNodeDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.data != widget.node.data) {
      _loadLines();
    }
  }

  void _loadLines() {
    final serialized = widget.node.data['lines'] as List?;
    if (serialized == null) {
      _lines = [];
      return;
    }
    _lines = serialized.map((lineData) {
      final points = lineData as List;
      return points.map((p) {
        final map = p as Map;
        return Offset(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
        );
      }).toList();
    }).toList();
  }

  void _saveLines() {
    if (widget.onNodeUpdated == null) return;
    final serialized = _lines.map((line) {
      return line.map((p) => {'x': p.dx, 'y': p.dy}).toList();
    }).toList();
    final newData = Map<String, Object?>.from(widget.node.data)
      ..['lines'] = serialized;
    widget.onNodeUpdated!(
      widget.node.copyWith(data: newData, updatedAt: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = nodeColor(widget.node.type);

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          GestureDetector(
            onPanStart: (details) {
              setState(() {
                _currentLine = [details.localPosition];
                _lines.add(_currentLine);
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _currentLine.add(details.localPosition);
              });
            },
            onPanEnd: (_) {
              _saveLines();
            },
            child: CustomPaint(
              painter: _SketchpadPainter(lines: _lines, color: color),
              size: Size.infinite,
            ),
          ),
          if (_lines.isEmpty)
            Center(
              child: IgnorePointer(
                child: Text(
                  'Draw here',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color.withValues(alpha: 0.55),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 4,
            top: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _lines.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _lines.removeLast();
                            _currentLine = _lines.isEmpty ? [] : _lines.last;
                          });
                          _saveLines();
                        },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.undo,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: _lines.isEmpty
                      ? null
                      : () async {
                          final clear = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear sketch?'),
                              content: const Text(
                                'This removes all strokes from this canvas node.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                          if (clear != true) return;
                          setState(() {
                            _lines.clear();
                            _currentLine.clear();
                          });
                          _saveLines();
                        },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.clear,
                      size: 14,
                      color: Colors.white,
                    ),
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

class _SketchpadPainter extends CustomPainter {
  final List<List<Offset>> lines;
  final Color color;
  const _SketchpadPainter({required this.lines, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final line in lines) {
      for (var i = 0; i < line.length - 1; i++) {
        canvas.drawLine(line[i], line[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SketchpadPainter oldDelegate) => true;
}

class _WeatherNodeDetails extends StatelessWidget {
  const _WeatherNodeDetails({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final temp = node.data['temp'] as String? ?? '25°C';
    final condition = node.data['weather'] as String? ?? 'Sunny';
    final color = nodeColor(node.type);

    IconData weatherIcon() {
      final value = condition.toLowerCase();
      if (value.contains('storm') || value.contains('thunder')) {
        return Icons.thunderstorm_outlined;
      }
      if (value.contains('rain') || value.contains('drizzle')) {
        return Icons.grain_outlined;
      }
      if (value.contains('snow')) return Icons.ac_unit_outlined;
      if (value.contains('wind')) return Icons.air_outlined;
      if (value.contains('cloud') || value.contains('overcast')) {
        return Icons.cloud_outlined;
      }
      if (value.contains('fog') || value.contains('mist')) return Icons.foggy;
      return Icons.wb_sunny_outlined;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(weatherIcon(), size: 36, color: color),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              temp,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(condition, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _FitNodeDetails extends StatelessWidget {
  const _FitNodeDetails({required this.node, required this.onNodeUpdated});
  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final steps = (node.data['steps'] as num?)?.toInt() ?? 0;
    final water = (node.data['water'] as num?)?.toInt() ?? 0;
    final workout = node.data['workout'] as String? ?? 'None';
    final stepTarget = (node.data['stepTarget'] as num?)?.toInt() ?? 10000;
    final waterTarget = (node.data['waterTarget'] as num?)?.toInt() ?? 8;

    final color = nodeColor(node.type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.directions_run_outlined, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Steps: $steps / $stepTarget',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 14),
              visualDensity: VisualDensity.compact,
              onPressed: onNodeUpdated == null
                  ? null
                  : () {
                      final newData = Map<String, Object?>.from(node.data)
                        ..['steps'] = steps + 1000;
                      onNodeUpdated!(
                        node.copyWith(data: newData, updatedAt: DateTime.now()),
                      );
                    },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22, right: 8, bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (steps / stepTarget).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.local_drink_outlined, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Water: $water / $waterTarget cups',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 14),
              visualDensity: VisualDensity.compact,
              onPressed: onNodeUpdated == null
                  ? null
                  : () {
                      final newData = Map<String, Object?>.from(node.data)
                        ..['water'] = water + 1;
                      onNodeUpdated!(
                        node.copyWith(data: newData, updatedAt: DateTime.now()),
                      );
                    },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22, right: 8, bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (water / waterTarget).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        if (workout != 'None' && workout.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '🏋️ Workout: $workout',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ],
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

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({required this.onSubmitted});
  final void Function(
    NodeType type,
    String title, {
    NodePriority? priority,
    List<String>? tags,
  })
  onSubmitted;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final parsed = _parseCommand(text);
    widget.onSubmitted(
      parsed.type,
      parsed.title,
      priority: parsed.priority,
      tags: parsed.tags,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Command Palette',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('command-palette-input'),
              controller: _controller,
              autofocus: true,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: '/task Buy groceries #high @home',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.hintColor,
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Text(
              'Syntax: /type Title #priority @tag1 @tag2\n'
              'Types: /task, /note, /decision, /plan, /habit, /goal, /event\n'
              'Priorities: #urgent, #high, #medium, #low\n'
              'Example: /decision Pick database #high @tech @backend',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedCommand {
  const _ParsedCommand({
    required this.type,
    required this.title,
    this.priority,
    required this.tags,
  });

  final NodeType type;
  final String title;
  final NodePriority? priority;
  final List<String> tags;
}

_ParsedCommand _parseCommand(String input) {
  final clean = input.trim();
  if (clean.isEmpty) {
    return const _ParsedCommand(type: NodeType.task, title: '', tags: []);
  }

  final words = clean.split(RegExp(r'\s+'));

  var type = NodeType.task;
  var startIdx = 0;
  if (words.isNotEmpty && words[0].startsWith('/')) {
    final possibleTypeName = words[0].substring(1).toLowerCase();
    for (final t in NodeType.values) {
      if (t.name == possibleTypeName ||
          t.label.toLowerCase() == possibleTypeName) {
        type = t;
        startIdx = 1;
        break;
      }
    }
  }

  NodePriority? priority;
  final tags = <String>[];
  final titleWords = <String>[];

  for (var i = startIdx; i < words.length; i++) {
    final word = words[i];
    if (word.startsWith('#')) {
      final pName = word.substring(1).toLowerCase();
      switch (pName) {
        case 'urgent':
          priority = NodePriority.urgent;
        case 'high':
          priority = NodePriority.high;
        case 'medium':
          priority = NodePriority.medium;
        case 'low':
          priority = NodePriority.low;
        case 'none':
          priority = NodePriority.none;
        default:
          titleWords.add(word);
      }
    } else if (word.startsWith('@')) {
      final tag = word.substring(1);
      if (tag.isNotEmpty) {
        tags.add(tag);
      }
    } else {
      titleWords.add(word);
    }
  }

  final title = titleWords.join(' ');
  return _ParsedCommand(
    type: type,
    title: title.isEmpty ? 'New ${type.label}' : title,
    priority: priority,
    tags: tags,
  );
}

class _CollaborationRoomBar extends ConsumerWidget {
  const _CollaborationRoomBar({
    required this.nodes,
    this.followingId,
    this.onFollowChanged,
  });

  final List<MindmapNode> nodes;
  final String? followingId;
  final ValueChanged<String?>? onFollowChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collabState = ref.watch(collaborationProvider);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        shape: DoodleShapeBorder(
          side: BorderSide(color: theme.dividerColor, width: 1.5),
          radius: 12,
          wobble: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                final rId = collabState.roomId;
                if (rId != null && rId.isNotEmpty) {
                  final url = 'var-collab://var.app/room/$rId?key=collab-key';
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Collab URL copied: $url')),
                    );
                  }
                }
              },
              child: Text(
                collabState.isDemoMode
                    ? 'Demo Collab'
                    : (collabState.roomId != null &&
                              collabState.roomId!.isNotEmpty
                          ? 'Room: ${collabState.roomId}'
                          : 'Collab Mode'),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  decoration: collabState.roomId != null
                      ? TextDecoration.underline
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            for (final peer in collabState.collaborators.values) ...[
              _PeerAvatar(
                peer: peer,
                isFollowing: followingId == peer.id,
                onTap: () {
                  if (onFollowChanged == null) return;
                  onFollowChanged!(followingId == peer.id ? null : peer.id);
                },
              ),
            ],
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                collabState.isDemoMode
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_fill_outlined,
                size: 16,
              ),
              tooltip: collabState.isDemoMode
                  ? 'Disable simulation'
                  : 'Enable simulation',
              onPressed: () {
                ref
                    .read(collaborationProvider.notifier)
                    .toggleDemoMode(!collabState.isDemoMode);
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 16),
              tooltip: 'Copy collab link',
              onPressed: () async {
                var rId = collabState.roomId;
                if (rId == null || rId.isEmpty) {
                  rId = const Uuid().v4().substring(0, 8);
                  final targetDay = nodes.isNotEmpty
                      ? nodes.first.day
                      : DateTime.now();
                  final dKey = dayKey(targetDay);
                  await ref
                      .read(collaborationProvider.notifier)
                      .joinRoom(rId, dayKey: dKey);
                }
                final url = 'var-collab://var.app/room/$rId?key=collab-key';
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Collab link copied: $url')),
                  );
                }
              },
            ),
            if (collabState.roomId == null || collabState.roomId!.isEmpty)
              IconButton(
                icon: const Icon(Icons.login, size: 16),
                tooltip: 'Join with Code',
                onPressed: () {
                  _showJoinCodeDialog(context, ref);
                },
              ),
          ],
        ),
      ),
    );
  }
}

void _showJoinCodeDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  final theme = Theme.of(context);

  showDialog<void>(
    context: context,
    builder: (context) {
      return Consumer(
        builder: (context, ref, child) {
          final collabState = ref.watch(collaborationProvider);
          final history = collabState.roomHistory;

          void handleJoin(String code) {
            final val = code.trim();
            if (val.isEmpty) return;

            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Connecting to room...'),
                duration: Duration(seconds: 2),
              ),
            );

            ref.read(collaborationProvider.notifier).joinRoom(val).then((
              success,
            ) {
              messenger.hideCurrentSnackBar();
              if (success) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Successfully joined room!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Failed to join room. Check internet or platform support.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            });

            Navigator.of(context).pop();
          }

          return AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            shape: DoodleShapeBorder(
              side: BorderSide(color: theme.dividerColor, width: 1.5),
              radius: 16,
              wobble: 1.0,
            ),
            title: Text(
              'Join Collab Room',
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'Doodle',
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter Room Code (ID) or link:',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'e.g., a1b2c3d4',
                    hintStyle: TextStyle(
                      color: theme.hintColor.withValues(alpha: 0.5),
                    ),
                    border: const OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  autofocus: true,
                  onSubmitted: handleJoin,
                ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Recent Rooms:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final code in history)
                        ActionChip(
                          padding: EdgeInsets.zero,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          label: Text(
                            code,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                          onPressed: () => handleJoin(code),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => handleJoin(controller.text),
                child: const Text('Join'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Compact avatar shown in the collaboration toolbar. Communicates the peer's
/// current activity (idle / selecting / editing), supports click-to-follow, and
/// exposes a richer tooltip that explains both the action and the live state.
class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({
    required this.peer,
    required this.isFollowing,
    required this.onTap,
  });

  final Collaborator peer;
  final bool isFollowing;
  final VoidCallback onTap;

  IconData? get _statusIcon {
    if (peer.isEditing) return Icons.edit;
    if (peer.selectedNodeId != null) return Icons.touch_app;
    return null;
  }

  String get _tooltipMessage {
    final base = isFollowing
        ? 'Following ${peer.name} (click to stop)'
        : 'Follow ${peer.name}';
    final activity = peer.isEditing
        ? ' • currently editing'
        : peer.selectedNodeId != null
        ? ' • has a node selected'
        : '';
    return '$base$activity';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isFollowing ? peer.color : Colors.transparent;
    // Subtle ring tint when peer is actively doing something, even if not
    // followed — gives the toolbar some life at a glance.
    final ambientRing = peer.isEditing
        ? peer.color
        : peer.selectedNodeId != null
        ? peer.color.withValues(alpha: 0.45)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: _tooltipMessage,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 250),
        child: InkResponse(
          onTap: onTap,
          radius: 16,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 2),
                    ),
                    padding: const EdgeInsets.all(1.5),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: peer.color,
                      child: Text(
                        peer.name.isEmpty ? '?' : peer.name[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                if (ambientRing != Colors.transparent)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: ambientRing, width: 1),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_statusIcon != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: peer.color, width: 1.2),
                      ),
                      child: Icon(_statusIcon, size: 8, color: peer.color),
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
