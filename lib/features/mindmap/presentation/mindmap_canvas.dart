/// Interactive daily mindmap canvas.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/node_visuals.dart';
import '../../../core/utils/date_utils.dart';
import '../../calendar/domain/calendar_node_payload.dart';
import '../application/collaboration_controller.dart';
import '../application/mindmap_providers.dart';
import '../application/node_inline_edit_controller.dart';
import '../data/canvas_export_pdf.dart';
import '../data/canvas_export_stub.dart'
    if (dart.library.io) '../data/canvas_export_io.dart'
    if (dart.library.html) '../data/canvas_export_web.dart';
import '../domain/canvas_board.dart';
import '../domain/canvas_column_layout.dart';
import '../domain/canvas_connector_router.dart';
import '../domain/canvas_navigation.dart';
import '../domain/canvas_object_style.dart';
import '../domain/canvas_position.dart';
import '../domain/canvas_scene_bounds.dart';
import '../domain/canvas_spatial_index.dart' as spatial;
import '../domain/canvas_workshop.dart';
import '../domain/connection_style.dart';
import '../domain/goal_progress.dart';
import '../domain/habit_completion.dart';
import '../domain/hybrid_timer.dart';
import '../domain/inline_node_workspace_policy.dart';
import '../domain/kanban_board.dart';
import '../domain/life_os_summary.dart';
import '../domain/mindmap_node.dart';
import '../domain/node_attachment.dart';
import '../domain/node_presentation.dart';
import '../domain/node_type_payloads.dart';
import '../domain/node_ui_state_codec.dart';
import '../domain/plan_progress.dart';
import '../domain/project_plan.dart';
import '../domain/task_checklist_progress.dart';
import 'canvas_tool_popover.dart';
import 'collaborator_cursor_widget.dart';
import 'node_editors/audio_recording_storage.dart';
import 'node_editors/canvas_document_renderer.dart';
import 'node_editors/media_travel_node_editors.dart';
import 'node_shell.dart';
import 'node_type_content.dart';
import 'node_type_inline_editor.dart';
import 'widgets/connection_style_bar.dart';

Uint8List _attachmentBytes(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

class _CanvasNonTextEditingActivator extends ShortcutActivator {
  const _CanvasNonTextEditingActivator(this.delegate);

  final ShortcutActivator delegate;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => delegate.triggers;

  @override
  String debugDescribeKeys() => delegate.debugDescribeKeys();

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    final context = FocusManager.instance.primaryFocus?.context;
    final isEditingText =
        context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
    return !isEditingText && delegate.accepts(event, state);
  }
}

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
typedef NodesDeleteCallback = FutureOr<void> Function(List<MindmapNode> nodes);
typedef CanvasObjectCallback = FutureOr<void> Function(CanvasObject object);
typedef CanvasObjectsCallback =
    FutureOr<void> Function(List<CanvasObject> objects);
typedef CanvasVoteChangeCallback =
    FutureOr<void> Function(List<CanvasObject> objects, int delta);
typedef CanvasObjectCommentsCallback =
    FutureOr<void> Function(
      String objectId,
      List<CanvasObjectComment> comments,
    );
typedef CanvasImageImportCallback = FutureOr<CanvasImageSource?> Function();
typedef CanvasAttachmentBytesLoader =
    Future<List<int>?> Function(String attachmentId);

final class CanvasImageSource {
  const CanvasImageSource({
    required this.attachmentId,
    required this.fileName,
    required this.mimeType,
    required this.byteLength,
  });

  final String attachmentId;
  final String fileName;
  final String mimeType;
  final int byteLength;

  Map<String, Object?> toPayload() => <String, Object?>{
    'attachmentId': attachmentId,
    'fileName': fileName,
    'mimeType': mimeType,
    'byteLength': byteLength,
  };
}

String _normalizedCanvasHex(String value) {
  final normalized = value.trim().replaceFirst('#', '').toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(normalized)
      ? '#$normalized'
      : '#4F7CFF';
}

Color? _canvasColorFromHex(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
  return Color(int.parse('FF$normalized', radix: 16));
}

@visibleForTesting
double normalizeCanvasRotation(double radians) {
  if (!radians.isFinite) return 0;
  final normalized = (radians + math.pi) % (2 * math.pi) - math.pi;
  return normalized == -math.pi ? math.pi : normalized;
}

double _normalizeCanvasRotation(double radians) =>
    normalizeCanvasRotation(radians);

final class _CanvasToolDraft extends ChangeNotifier {
  final List<Offset> freehandPoints = <Offset>[];
  Offset? connectorStart;
  Offset? connectorCurrent;
  List<Offset> connectorRoute = const <Offset>[];
  int? pointer;

  bool get hasFreehand => freehandPoints.isNotEmpty;
  bool get hasConnector => connectorStart != null && connectorCurrent != null;

  void beginFreehand(int pointer, Offset point) {
    this.pointer = pointer;
    freehandPoints
      ..clear()
      ..add(point);
    connectorStart = null;
    connectorCurrent = null;
    connectorRoute = const <Offset>[];
    notifyListeners();
  }

  void appendFreehand(int pointer, Offset point) {
    if (this.pointer != pointer || freehandPoints.isEmpty) return;
    if ((point - freehandPoints.last).distance < 2) return;
    freehandPoints.add(point);
    notifyListeners();
  }

  void beginConnector(Offset start) {
    pointer = null;
    freehandPoints.clear();
    connectorStart = start;
    connectorCurrent = start;
    connectorRoute = <Offset>[start, start];
    notifyListeners();
  }

  void updateConnector(Offset current, List<Offset> route) {
    if (connectorStart == null) return;
    connectorCurrent = current;
    connectorRoute = route;
    notifyListeners();
  }

  List<Offset> takeFreehand(int pointer) {
    if (this.pointer != pointer) return const <Offset>[];
    final result = List<Offset>.of(freehandPoints);
    clear();
    return result;
  }

  void clear() {
    pointer = null;
    freehandPoints.clear();
    connectorStart = null;
    connectorCurrent = null;
    connectorRoute = const <Offset>[];
    notifyListeners();
  }
}

final class _CanvasSmartGuides {
  const _CanvasSmartGuides({
    this.vertical,
    this.horizontal,
    this.dx = 0,
    this.dy = 0,
    this.distance,
    this.labelPosition,
    this.distanceAxis,
    this.verticalIdentity,
    this.horizontalIdentity,
  });

  final double? vertical;
  final double? horizontal;
  final String? verticalIdentity;
  final String? horizontalIdentity;
  final double dx;
  final double dy;
  final double? distance;
  final Offset? labelPosition;
  final Axis? distanceAxis;
}

final class _SmartGuideGeometry {
  const _SmartGuideGeometry(this.id, this.geometry);

  final String id;
  final CanvasGeometry geometry;
}

_CanvasSmartGuides? _findCanvasSmartGuides(
  CanvasGeometry moving,
  Iterable<_SmartGuideGeometry> candidates, {
  required double screenScale,
  double screenThreshold = 8,
}) {
  final threshold = screenThreshold / math.max(screenScale, 0.01);
  final movingX = <double>[
    moving.x,
    moving.x + moving.width / 2,
    moving.x + moving.width,
  ];
  final movingY = <double>[
    moving.y,
    moving.y + moving.height / 2,
    moving.y + moving.height,
  ];
  double? bestDx;
  double? bestDy;
  double? vertical;
  double? horizontal;
  String? verticalIdentity;
  String? horizontalIdentity;
  double? distance;
  Offset? labelPosition;
  Axis? distanceAxis;
  final candidateList = candidates.toList();
  for (final candidate in candidateList) {
    final geometry = candidate.geometry;
    final candidateX = <double>[
      geometry.x,
      geometry.x + geometry.width / 2,
      geometry.x + geometry.width,
    ];
    final candidateY = <double>[
      geometry.y,
      geometry.y + geometry.height / 2,
      geometry.y + geometry.height,
    ];
    for (var sourceIndex = 0; sourceIndex < movingX.length; sourceIndex++) {
      final source = movingX[sourceIndex];
      for (
        var targetIndex = 0;
        targetIndex < candidateX.length;
        targetIndex++
      ) {
        final target = candidateX[targetIndex];
        final delta = target - source;
        if (delta.abs() <= threshold &&
            (bestDx == null || delta.abs() < bestDx.abs())) {
          bestDx = delta;
          vertical = target;
          verticalIdentity = '${candidate.id}:$sourceIndex:$targetIndex';
        }
      }
    }
    for (var sourceIndex = 0; sourceIndex < movingY.length; sourceIndex++) {
      final source = movingY[sourceIndex];
      for (
        var targetIndex = 0;
        targetIndex < candidateY.length;
        targetIndex++
      ) {
        final target = candidateY[targetIndex];
        final delta = target - source;
        if (delta.abs() <= threshold &&
            (bestDy == null || delta.abs() < bestDy.abs())) {
          bestDy = delta;
          horizontal = target;
          horizontalIdentity = '${candidate.id}:$sourceIndex:$targetIndex';
        }
      }
    }
  }
  for (final isHorizontalSpacing in <bool>[true, false]) {
    final before = candidateList
        .where(
          (candidate) => isHorizontalSpacing
              ? candidate.geometry.x + candidate.geometry.width <= moving.x
              : candidate.geometry.y + candidate.geometry.height <= moving.y,
        )
        .toList();
    final after = candidateList
        .where(
          (candidate) => isHorizontalSpacing
              ? candidate.geometry.x >= moving.x + moving.width
              : candidate.geometry.y >= moving.y + moving.height,
        )
        .toList();
    if (before.isEmpty || after.isEmpty) continue;
    before.sort(
      (left, right) =>
          (isHorizontalSpacing
                  ? right.geometry.x + right.geometry.width
                  : right.geometry.y + right.geometry.height)
              .compareTo(
                isHorizontalSpacing
                    ? left.geometry.x + left.geometry.width
                    : left.geometry.y + left.geometry.height,
              ),
    );
    after.sort(
      (left, right) => (isHorizontalSpacing ? left.geometry.x : left.geometry.y)
          .compareTo(isHorizontalSpacing ? right.geometry.x : right.geometry.y),
    );
    final leading = before.first.geometry;
    final trailing = after.first.geometry;
    final leadingGap = isHorizontalSpacing
        ? moving.x - leading.x - leading.width
        : moving.y - leading.y - leading.height;
    final trailingGap = isHorizontalSpacing
        ? trailing.x - moving.x - moving.width
        : trailing.y - moving.y - moving.height;
    final delta = (trailingGap - leadingGap) / 2;
    if (delta.abs() > threshold) continue;
    if (isHorizontalSpacing && (bestDx == null || delta.abs() < bestDx.abs())) {
      bestDx = delta;
      vertical = moving.x + moving.width / 2 + delta;
      distance = (leadingGap + trailingGap) / 2;
      labelPosition = Offset(moving.x + moving.width / 2, moving.y - 12);
      distanceAxis = Axis.horizontal;
      verticalIdentity = 'spacing:${before.first.id}:${after.first.id}';
    } else if (!isHorizontalSpacing &&
        (bestDy == null || delta.abs() < bestDy.abs())) {
      bestDy = delta;
      horizontal = moving.y + moving.height / 2 + delta;
      distance = (leadingGap + trailingGap) / 2;
      labelPosition = Offset(moving.x - 12, moving.y + moving.height / 2);
      distanceAxis = Axis.vertical;
      horizontalIdentity = 'spacing:${before.first.id}:${after.first.id}';
    }
  }
  if (bestDx == null && bestDy == null) return null;
  return _CanvasSmartGuides(
    vertical: vertical,
    horizontal: horizontal,
    dx: bestDx ?? 0,
    dy: bestDy ?? 0,
    distance: distance,
    labelPosition: labelPosition,
    distanceAxis: distanceAxis,
    verticalIdentity: verticalIdentity,
    horizontalIdentity: horizontalIdentity,
  );
}

typedef CanvasObjectDeleteCallback =
    FutureOr<void> Function(CanvasObject object);
typedef ImageExportCallback =
    FutureOr<void> Function(Uint8List bytes, String fileName);
typedef NodeResizeCallback =
    void Function(MindmapNode node, NodeResizeChange change);
typedef CanvasContextMenuCallback =
    FutureOr<void> Function(Offset globalPosition, Offset scenePosition);
typedef CanvasProductivityNodeCreateCallback =
    FutureOr<void> Function(Offset canvasPosition);
typedef ConnectedNodeCreateCallback =
    FutureOr<MindmapNode?> Function(
      MindmapNode source,
      NodeType type,
      Offset canvasPosition,
    );
typedef ExpandedNodeBuilder = Widget Function(MindmapNode node);
typedef ExpandedSelectionChanging =
    FutureOr<bool> Function(String? currentNodeId, String? nextNodeId);

const int _inlineBodyMaxWords = 1200;
const double inlineNodeWorkspaceHeaderHeight = 64;

@visibleForTesting
final class MindmapExpandedNodeGeometry {
  const MindmapExpandedNodeGeometry({
    required this.node,
    required this.size,
    required this.origin,
    this.position,
  });

  final MindmapNode node;
  final Size size;
  final Offset origin;
  final CanvasPosition? position;

  Rect get hitRect => Rect.fromLTWH(
    origin.dx + (position ?? node.position).dx,
    origin.dy + (position ?? node.position).dy,
    size.width,
    size.height,
  );

  Offset get inputPort => Offset(hitRect.left + 2, hitRect.center.dy);
  Offset get outputPort => Offset(hitRect.right - 2, hitRect.center.dy);

  Rect minimapRect({required Size minimapSize, required Size canvasSize}) {
    final scaleX = minimapSize.width / canvasSize.width;
    final scaleY = minimapSize.height / canvasSize.height;
    return Rect.fromLTWH(
      hitRect.left * scaleX,
      hitRect.top * scaleY,
      hitRect.width * scaleX,
      hitRect.height * scaleY,
    );
  }
}

Size _effectiveNodeSize(MindmapNode node) {
  final Size persisted;
  if (!node.data.containsKey(nodeUiSizePresetKey) &&
      !node.data.containsKey(nodeUiWidthKey) &&
      !node.data.containsKey(nodeUiHeightKey)) {
    persisted = node.type == NodeType.kanban
        ? MindmapCanvas.kanbanNodeSize
        : MindmapCanvas.nodeSize;
  } else {
    final effective = NodeUiStateCodec.read(node);
    persisted = Size(effective.width, effective.height);
  }
  if (node.type != NodeType.note) return persisted;
  final contentHeight = _collapsedNoteContentHeight(node, persisted.width);
  if (contentHeight == 0) return persisted;
  const layoutSafetyMargin = 16.0;
  return Size(
    persisted.width,
    math.max(
      persisted.height + layoutSafetyMargin,
      contentHeight + layoutSafetyMargin,
    ),
  );
}

double _collapsedNoteContentHeight(MindmapNode node, double width) {
  if (node.body.trim().isEmpty) return 0;
  final charactersPerLine = math.max(24, ((width - 48) / 7).floor());
  var visualLines = 0;
  var markdownBlockBreaks = 0;
  for (final line in node.body.split('\n')) {
    final plain = line
        .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
        .replaceFirst(RegExp(r'^[-*+]\s+'), '')
        .replaceFirst(RegExp(r'^\d+\.\s+'), '')
        .replaceAll(RegExp(r'[*_~]'), '');
    if (plain.trim().isEmpty) markdownBlockBreaks += 1;
    visualLines += plain.trim().isEmpty
        ? 1
        : math.max(1, (plain.length / charactersPerLine).ceil());
  }
  final payload = NotePayload.fromNode(node);
  final noteIndicatorRows = <int>[
    if (node.tags.isNotEmpty) 1,
    if (payload.sourceLinks.isNotEmpty) 1,
    if (payload.attachments.isNotEmpty) 1,
  ].length;
  final metadataCharacters = _metadataLabelsFor(
    node,
  ).fold<int>(0, (total, label) => total + label.length + 4);
  final metadataRows = metadataCharacters == 0
      ? 0
      : math.max(1, (metadataCharacters / charactersPerLine).ceil());
  return 220 +
      (visualLines * 20) +
      (markdownBlockBreaks * 12) +
      (metadataRows * 30) +
      (noteIndicatorRows * 24);
}

typedef MindmapTypedPayloadParser = Object? Function(MindmapNode node);

@visibleForTesting
final class MindmapNodePresentationCache {
  MindmapNodePresentationCache({MindmapTypedPayloadParser? typedPayloadParser})
    : _typedPayloadParser = typedPayloadParser ?? _typedPayloadForNode;

  final MindmapTypedPayloadParser _typedPayloadParser;
  final Map<String, _NodePresentationCacheEntry> _entries = {};
  int parseCount = 0;
  int payloadParseCount = 0;

  void sync(Iterable<MindmapNode> nodes) {
    final ids = <String>{};
    for (final node in nodes) {
      ids.add(node.id);
      final existing = _entries[node.id];
      if (existing != null && existing.matches(node)) continue;
      parseCount++;
      final uiState = NodeUiStateCodec.read(node);
      final payload = _typedPayloadParser(node);
      if (payload != null) payloadParseCount++;
      _entries[node.id] = _NodePresentationCacheEntry(
        nodeId: node.id,
        type: node.type,
        presentationDataKey: node.presentationDataKey,
        uiState: uiState,
        typedPayload: payload,
        size: _effectiveNodeSize(node),
      );
    }
    _entries.removeWhere((id, entry) => !ids.contains(id));
  }

  Size sizeFor(MindmapNode node) {
    _ensure(node);
    return _entries[node.id]!.size;
  }

  NodeUiState uiStateFor(MindmapNode node) {
    _ensure(node);
    return _entries[node.id]!.uiState;
  }

  Object? typedPayloadFor(MindmapNode node) {
    _ensure(node);
    return _entries[node.id]!.typedPayload;
  }

  Map<String, Size> sizesFor(Iterable<MindmapNode> nodes) {
    sync(nodes);
    return {for (final node in nodes) node.id: _entries[node.id]!.size};
  }

  void _ensure(MindmapNode node) {
    final existing = _entries[node.id];
    if (existing != null && existing.matches(node)) return;
    parseCount++;
    final uiState = NodeUiStateCodec.read(node);
    final payload = _typedPayloadParser(node);
    if (payload != null) payloadParseCount++;
    _entries[node.id] = _NodePresentationCacheEntry(
      nodeId: node.id,
      type: node.type,
      presentationDataKey: node.presentationDataKey,
      uiState: uiState,
      typedPayload: payload,
      size: _effectiveNodeSize(node),
    );
  }
}

final class _NodePresentationCacheEntry {
  const _NodePresentationCacheEntry({
    required this.nodeId,
    required this.type,
    required this.presentationDataKey,
    required this.uiState,
    required this.typedPayload,
    required this.size,
  });

  final String nodeId;
  final NodeType type;
  final String presentationDataKey;
  final NodeUiState uiState;
  final Object? typedPayload;
  final Size size;

  bool matches(MindmapNode node) =>
      node.id == nodeId &&
      node.type == type &&
      node.presentationDataKey == presentationDataKey;
}

Object? _typedPayloadForNode(MindmapNode node) => switch (node.type) {
  NodeType.task => TaskChecklistPayload.fromNode(node),
  NodeType.note => NotePayload.fromNode(node),
  NodeType.checklist => ChecklistPayload.fromNode(node),
  NodeType.kanban => KanbanPayload.fromNode(node),
  NodeType.plan => PlanPayload.fromNode(node),
  NodeType.goal => GoalPayload.fromNode(node),
  NodeType.habit || NodeType.routine => HabitRoutinePayload.fromNode(node),
  NodeType.journal => JournalPayload.fromNode(node),
  NodeType.idea => IdeaPayload.fromNode(node),
  NodeType.question => QuestionPayload.fromNode(node),
  NodeType.decision => DecisionPayload.fromNode(node),
  NodeType.quote => QuotePayload.fromNode(node),
  NodeType.event => EventCalendarPayload.fromNode(node),
  NodeType.contact => ContactPayload.fromNode(node),
  NodeType.metric => MetricPayload.fromNode(node),
  NodeType.expense => ExpensePayload.fromNode(node),
  NodeType.mood => MoodPayload.fromNode(node),
  NodeType.weather => WeatherPayload.fromNode(node),
  NodeType.fit => FitPayload.fromNode(node),
  NodeType.link || NodeType.bookmark => LinkResourcePayload.fromNode(node),
  NodeType.resource => ResourcePayload.fromNode(node),
  NodeType.timer => TimerPayload.fromNode(node),
  NodeType.audio => AudioPayload.fromNode(node),
  NodeType.canvas => CanvasPayload.fromNode(node),
  NodeType.image => ImagePayload.fromNode(node),
  NodeType.video => VideoPayload.fromNode(node),
  NodeType.itinerary => ItineraryPayload.fromNode(node),
  NodeType.note || NodeType.empty => null,
};

NodeSizePreset _effectiveContentPreset(NodeType type, NodeSizePreset preset) =>
    preset == NodeSizePreset.auto || preset == NodeSizePreset.custom
    ? NodePresentationSpec.forType(type).defaultPreset
    : preset;

final class _NodeResizeOverride {
  const _NodeResizeOverride({
    required this.basePosition,
    required this.baseSize,
    required this.targetPosition,
    required this.targetSize,
  });

  final CanvasPosition basePosition;
  final Size baseSize;
  final CanvasPosition targetPosition;
  final Size targetSize;
}

double _nodePortY(Size size) => size.height / 2;

enum _CanvasLayoutMode { tidy, radial, byType, timeline, matrix, priorityGrid }

enum _CanvasMoreTool { image, linkPreview, eraser, productivityNode }

enum CanvasContextAction {
  createNode,
  quickTask,
  quickNote,
  createLinkedNode,
  paste,
  selectAll,
  clearSelection,
  moveSelectionHere,
  zoomToSelection,
  fitAll,
  resetZoom,
  toggleGrid,
  toggleSnap,
  toggleMinimap,
  tidyLayout,
  radialLayout,
  typeLayout,
  timelineLayout,
  matrixLayout,
  priorityGridLayout,
  groupSelection,
  ungroupSelection,
  cycleBackground,
  toggleCompleted,
  importClipboard,
  exportJson,
  exportPng,
  exportPdf,
  commandPalette,
  togglePresentation,
}

final class MediaExportResult {
  const MediaExportResult._(this.isSuccess, this.message);

  const MediaExportResult.success(String message) : this._(true, message);
  const MediaExportResult.failure(String message) : this._(false, message);

  final bool isSuccess;
  final String message;
}

typedef MediaFileExporter =
    Future<String> Function(Uint8List bytes, String fileName);

String _nodeMediaSource(MindmapNode node) => switch (node.type) {
  NodeType.image =>
    ImagePayload.fromNode(node).attachmentId.isNotEmpty
        ? 'attachment:${ImagePayload.fromNode(node).attachmentId}'
        : 'url:${ImagePayload.fromNode(node).url}',
  NodeType.video =>
    VideoPayload.fromNode(node).attachmentId.isNotEmpty
        ? 'attachment:${VideoPayload.fromNode(node).attachmentId}'
        : 'url:${VideoPayload.fromNode(node).url}',
  _ => '',
};

class MindmapCanvas extends StatefulWidget {
  const MindmapCanvas({
    required this.nodes,
    this.board,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.onCanvasObjectCreated,
    this.onCanvasObjectUpdated,
    this.onCanvasObjectDeleted,
    this.onCanvasObjectsCreated,
    this.onCanvasObjectsUpdated,
    this.onCanvasObjectsDeleted,
    this.onBoardReferenceOpened,
    this.onCanvasVoteChanged,
    this.votingParticipantId = 'local',
    this.workshopSession,
    this.workshopViewerUid = '',
    this.isWorkshopHost = false,
    this.onViewportChanged,
    this.onCanvasAssistantRequested,
    this.assistantPreviewObjects = const <CanvasObject>[],
    this.collaborationBoardComments =
        const <String, List<CanvasObjectComment>>{},
    this.onCollaborationBoardCommentsChanged,
    this.onCanvasImageImport,
    this.loadCanvasAttachmentBytes,
    this.variant = AppThemeVariant.astryxNeutral,
    this.highlightedNodeId,
    this.expandedNodeId,
    this.expandedNodeOverride,
    this.expandedNodeBuilder,
    this.onExpandedSelectionChanging,
    this.onNodeMoved,
    this.onNodeSelected,
    this.onSelectionCleared,
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
    this.onNodesDeleted,
    this.onNodeResize,
    this.onNodeDropped,
    this.onClearNodes,
    this.onCanvasContextMenu,
    this.onProductivityNodeCreateRequested,
    this.onConnectedNodeCreate,
    this.onNodeQuickCreate,
    this.onStatusMessage,
    this.collaborationState,
    this.onLocalCursorChanged,
    this.onLocalSelectionChanged,
    this.onLocalPingRequested,
    this.onInlineEditStateChanged,
    this.onNodeCardBuilt,
    this.onNodeCardBuildProbe,
    this.presentationCache,
    this.pingStream,
    super.key,
  });

  static const Size canvasSize = Size(20000, 14000);
  static const Size nodeSize = Size(340, 320);
  static const Size kanbanNodeSize = Size(500, 320);

  final List<MindmapNode> nodes;
  final CanvasBoard? board;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final CanvasObjectCallback? onCanvasObjectCreated;
  final CanvasObjectCallback? onCanvasObjectUpdated;
  final CanvasObjectDeleteCallback? onCanvasObjectDeleted;
  final CanvasObjectsCallback? onCanvasObjectsCreated;
  final CanvasObjectsCallback? onCanvasObjectsUpdated;
  final CanvasObjectsCallback? onCanvasObjectsDeleted;
  final ValueChanged<CanvasObject>? onBoardReferenceOpened;
  final CanvasVoteChangeCallback? onCanvasVoteChanged;
  final String votingParticipantId;
  final CanvasWorkshopSession? workshopSession;
  final String workshopViewerUid;
  final bool isWorkshopHost;
  final ValueChanged<CanvasViewport>? onViewportChanged;
  final VoidCallback? onCanvasAssistantRequested;
  final List<CanvasObject> assistantPreviewObjects;
  final Map<String, List<CanvasObjectComment>> collaborationBoardComments;
  final CanvasObjectCommentsCallback? onCollaborationBoardCommentsChanged;
  final CanvasImageImportCallback? onCanvasImageImport;
  final CanvasAttachmentBytesLoader? loadCanvasAttachmentBytes;
  final AppThemeVariant variant;
  final String? highlightedNodeId;
  final String? expandedNodeId;
  final MindmapNode? expandedNodeOverride;
  final ExpandedNodeBuilder? expandedNodeBuilder;
  final ExpandedSelectionChanging? onExpandedSelectionChanging;
  final NodeMoveCallback? onNodeMoved;
  final NodeSelectionCallback? onNodeSelected;
  final VoidCallback? onSelectionCleared;
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
  final NodesDeleteCallback? onNodesDeleted;
  final NodeResizeCallback? onNodeResize;
  final void Function(NodeType type, Offset scenePosition)? onNodeDropped;
  final FutureOr<void> Function()? onClearNodes;
  final CanvasContextMenuCallback? onCanvasContextMenu;
  final CanvasProductivityNodeCreateCallback? onProductivityNodeCreateRequested;
  final ConnectedNodeCreateCallback? onConnectedNodeCreate;
  final void Function(
    NodeType type,
    String title, {
    NodePriority? priority,
    List<String>? tags,
  })?
  onNodeQuickCreate;
  final ValueChanged<String>? onStatusMessage;

  final CollaborationState? collaborationState;
  final void Function(Offset position)? onLocalCursorChanged;
  final void Function(String? nodeId)? onLocalSelectionChanged;
  final void Function(Offset scenePosition)? onLocalPingRequested;
  final Stream<PingEvent>? pingStream;
  final void Function(String nodeId, bool isEditing, NodeSaveStatus status)?
  onInlineEditStateChanged;
  final ValueChanged<String>? onNodeCardBuilt;
  final ValueChanged<String>? onNodeCardBuildProbe;
  @visibleForTesting
  final MindmapNodePresentationCache? presentationCache;

  @override
  State<MindmapCanvas> createState() => MindmapCanvasState();
}

class MindmapCanvasState extends State<MindmapCanvas>
    with TickerProviderStateMixin {
  bool get isGridVisible => _showGrid;
  bool get isSnapEnabled => _snapToGrid;
  bool get isMinimapVisible => !_isMinimapCollapsed;
  bool get areCompletedNodesVisible => true;
  bool get isPresentationMode => _isPresentationMode;

  int _presentationFrameIndex = 0;

  void nextPresentationSlide() {
    final groups = _visibleGroups(widget.nodes).values.toList();
    if (groups.isEmpty) return;
    setState(() {
      _presentationFrameIndex = (_presentationFrameIndex + 1) % groups.length;
    });
    _zoomToGroup(groups[_presentationFrameIndex]);
  }

  void previousPresentationSlide() {
    final groups = _visibleGroups(widget.nodes).values.toList();
    if (groups.isEmpty) return;
    setState(() {
      _presentationFrameIndex =
          (_presentationFrameIndex - 1 + groups.length) % groups.length;
    });
    _zoomToGroup(groups[_presentationFrameIndex]);
  }

  void _zoomToGroup(List<MindmapNode> groupNodes) {
    final viewportSize = context.size;
    if (viewportSize == null || groupNodes.isEmpty) return;
    final origin = _sceneOrigin;
    Rect? bounds;
    for (final node in groupNodes) {
      final pos = _positionFor(node);
      final size = _nodeSizeFor(node);
      final rect = (origin + Offset(pos.dx, pos.dy)) & size;
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    if (bounds == null) return;
    final padded = bounds.inflate(60);
    final scaleX = viewportSize.width / padded.width;
    final scaleY = viewportSize.height / padded.height;
    final scale = math.min(scaleX, scaleY).clamp(0.25, 1.8).toDouble();
    final tx = viewportSize.width / 2 - padded.center.dx * scale;
    final ty = viewportSize.height / 2 - padded.center.dy * scale;
    final targetMatrix =
        Matrix4.translationValues(tx, ty, 0) *
                Matrix4.diagonal3Values(scale, scale, 1)
            as Matrix4;
    _transitionViewportTo(targetMatrix);
  }

  void setPresentationMode(bool value) {
    if (_isPresentationMode == value) return;
    setState(() {
      _isPresentationMode = value;
      _presentationFrameIndex = 0;
      _connectionDrag = null;
      _toolPopoverType = null;
      _selectedNodeIds.clear();
      _selectedConnectionKey = null;
    });
    _canvasFocusNode.requestFocus();
    if (value) {
      final groups = _visibleGroups(widget.nodes).values.toList();
      if (groups.isNotEmpty) {
        _zoomToGroup(groups.first);
      } else {
        unawaited(runContextAction(CanvasContextAction.fitAll));
      }
    }
  }

  bool isInlineEditing(String nodeId) => _editingNodeIds.contains(nodeId);

  void beginInlineEdit(String nodeId) {
    _nodeCardKeys[nodeId]?.currentState?.beginInlineEdit();
  }

  Future<bool> finishInlineEdit(String nodeId) async {
    return await _nodeCardKeys[nodeId]?.currentState?.finishInlineEdit() ??
        true;
  }

  Future<MediaExportResult> exportMedia(
    String nodeId, {
    MediaFileExporter? fileExporter,
  }) async {
    final node = widget.nodes.where((item) => item.id == nodeId).firstOrNull;
    if (node == null ||
        (node.type != NodeType.image && node.type != NodeType.video)) {
      return const MediaExportResult.failure('Selected node is not media.');
    }
    final source = _nodeMediaSource(node);
    final attachmentId = switch (node.type) {
      NodeType.image => ImagePayload.fromNode(node).attachmentId,
      NodeType.video => VideoPayload.fromNode(node).attachmentId,
      _ => '',
    };
    final fileName = switch (node.type) {
      NodeType.image => ImagePayload.fromNode(node).fileName,
      NodeType.video => VideoPayload.fromNode(node).fileName,
      _ => '',
    };
    if (attachmentId.isEmpty) {
      return const MediaExportResult.failure(
        'Only local attachments can be exported.',
      );
    }
    try {
      final repository = await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(nodeAttachmentRepositoryProvider.future);
      final bytes = await repository.exportBytes(attachmentId);
      final current = widget.nodes
          .where((item) => item.id == nodeId)
          .firstOrNull;
      if (current == null || _nodeMediaSource(current) != source) {
        return const MediaExportResult.failure(
          'Media source changed before export completed.',
        );
      }
      if (bytes == null) {
        return const MediaExportResult.failure(
          'Media attachment is unavailable.',
        );
      }
      final outputName = fileName.trim().isEmpty
          ? node.type == NodeType.image
                ? 'image.png'
                : 'video.mp4'
          : fileName;
      final path = await (fileExporter ?? saveCanvasPng)(
        _attachmentBytes(bytes),
        outputName,
      );
      return MediaExportResult.success('Exported to $path');
    } on Object catch (error) {
      return MediaExportResult.failure('Export failed: $error');
    }
  }

  final Map<String, CanvasPosition> _dragPositions = {};
  final Map<String, CanvasPosition> _nodeRawDragPositions = {};
  double? _nodeSnapRawX;
  double? _nodeSnapRawY;
  double? _nodeInitialCorrectionX;
  double? _nodeInitialCorrectionY;
  String? _nodeVerticalGuideIdentity;
  String? _nodeHorizontalGuideIdentity;
  _CanvasSmartGuides? _nodeEngagedGuides;
  bool _nodeSnapReleasedX = false;
  bool _nodeSnapReleasedY = false;
  String? _nodeReleasedVerticalIdentity;
  String? _nodeReleasedHorizontalIdentity;
  final Map<String, CanvasGeometry> _canvasObjectGeometryOverrides = {};
  final Map<String, CanvasGeometry> _canvasObjectRawDragGeometries = {};
  double? _canvasObjectSnapRawX;
  double? _canvasObjectSnapRawY;
  double? _canvasObjectInitialCorrectionX;
  double? _canvasObjectInitialCorrectionY;
  String? _canvasObjectVerticalGuideIdentity;
  String? _canvasObjectHorizontalGuideIdentity;
  _CanvasSmartGuides? _canvasObjectEngagedGuides;
  bool _canvasObjectSnapReleasedX = false;
  bool _canvasObjectSnapReleasedY = false;
  String? _canvasObjectReleasedVerticalIdentity;
  String? _canvasObjectReleasedHorizontalIdentity;
  Offset? _canvasObjectDragGlobalPosition;
  Offset? _canvasObjectDropBoardPosition;
  String? _columnDropTargetId;
  int? _columnDropInsertionIndex;
  Offset? _nodeDragGlobalPosition;
  _CanvasSmartGuides? _canvasSmartGuides;
  final Map<String, _NodeResizeOverride> _resizeChanges = {};
  late final MindmapNodePresentationCache _presentationCache;
  late Map<String, Size> _nodeSizes;
  final TransformationController _transformationController =
      TransformationController();
  CanvasSceneBounds _sceneBounds = const CanvasSceneBounds.initial();
  Offset get _sceneOrigin => _sceneBounds.sceneOffset;
  final GlobalKey _canvasExportKey = GlobalKey();
  bool _didSetInitialTransform = false;
  String? _followingCollaboratorId;

  Offset? _mousePos;
  final List<Offset> _cursorTrail = [];
  bool _showGrid = true;
  bool _snapToGrid = false;
  bool _showCompletedNodes = true;
  int _backgroundMode = 0;
  SharedPreferencesAsync? _preferences;
  static const _settingsKey = 'mindmap_canvas_settings_v1';
  bool _isCtrlZoomActive = false;
  bool _isExporting = false;
  bool _isCanvasToolbarCollapsed = true;
  bool _isMinimapCollapsed = true;
  bool _isPresentationMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  CanvasSearchCategory _searchCategory = CanvasSearchCategory.all;
  int _activeSearchResultIndex = 0;
  late CanvasNavigationIndex _navigationIndex;
  NodeType? _searchTypeFilter;
  NodeReviewState? _reviewStateFilter;
  bool _nextActionOnly = false;
  bool _isSearchOverlayCollapsed = true;
  String? _lastSelectedNodeId;
  final Set<String> _selectedNodeIds = <String>{};
  String? _selectedConnectionKey;
  String? _selectedCanvasObjectId;
  final Set<String> _selectedCanvasObjectIds = <String>{};
  CanvasObjectType? _creationObjectType;
  Offset? _connectorStartScene;
  String? _connectorStartObjectId;
  CanvasImageSource? _pendingCanvasImage;
  final _toolDraft = _CanvasToolDraft();
  CanvasPenAppearance _penAppearance = const CanvasPenAppearance();
  CanvasConnectorAppearance _connectorAppearance =
      const CanvasConnectorAppearance();
  CanvasShapeKind _shapeKind = CanvasShapeKind.roundedRectangle;
  CanvasObjectType? _toolPopoverType;
  final Map<CanvasObjectType, LayerLink> _toolLayerLinks =
      <CanvasObjectType, LayerLink>{
        for (final type in <CanvasObjectType>[
          CanvasObjectType.stickyNote,
          CanvasObjectType.text,
          CanvasObjectType.shape,
          CanvasObjectType.connector,
          CanvasObjectType.freehand,
          CanvasObjectType.frame,
          CanvasObjectType.column,
        ])
          type: LayerLink(),
      };
  bool _isCanvasEraserActive = false;
  bool _isCanvasCommentToolActive = false;
  String? _pendingInlineEditCanvasObjectId;
  final Set<String> _erasedCanvasObjectIds = <String>{};
  final Map<String, GlobalKey<_PositionedCanvasObjectState>> _canvasObjectKeys =
      <String, GlobalKey<_PositionedCanvasObjectState>>{};
  late List<CanvasObject> _orderedBoardObjects;
  final spatial.CanvasSpatialIndex<String> _canvasObjectIndex =
      spatial.CanvasSpatialIndex<String>();
  final Set<String> _editingNodeIds = <String>{};
  int _expandedSelectionGeneration = 0;
  final Map<String, GlobalKey<_MindmapNodeCardState>> _nodeCardKeys = {};
  final Map<String, FocusNode> _nodeFocusNodes = <String, FocusNode>{};
  final FocusNode _canvasFocusNode = FocusNode(debugLabel: 'Mindmap canvas');
  String? _focusBeforeExpansionNodeId;
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
  Offset? _touchPanLastLocal;
  _ConnectionDrag? _connectionDrag;

  StreamSubscription<PingEvent>? _pingSub;
  final List<_ActivePing> _activePings = <_ActivePing>[];
  Rect? _visibleSceneRect;
  Timer? _viewportUpdateTimer;
  Timer? _viewportPersistTimer;
  bool _viewportUpdateQueued = false;
  CanvasViewport? _lastEmittedViewport;
  bool get _isHeavyCanvas =>
      widget.nodes.length +
          (widget.board?.objects
                  .where(
                    (object) => object.type != CanvasObjectType.nodeReference,
                  )
                  .length ??
              0) >
      60;

  List<CanvasContextAction> get availableContextActions => const [
    CanvasContextAction.createNode,
    CanvasContextAction.quickTask,
    CanvasContextAction.quickNote,
    CanvasContextAction.createLinkedNode,
    CanvasContextAction.paste,
    CanvasContextAction.selectAll,
    CanvasContextAction.clearSelection,
    CanvasContextAction.moveSelectionHere,
    CanvasContextAction.zoomToSelection,
    CanvasContextAction.fitAll,
    CanvasContextAction.resetZoom,
    CanvasContextAction.toggleGrid,
    CanvasContextAction.toggleSnap,
    CanvasContextAction.toggleMinimap,
    CanvasContextAction.tidyLayout,
    CanvasContextAction.radialLayout,
    CanvasContextAction.typeLayout,
    CanvasContextAction.timelineLayout,
    CanvasContextAction.matrixLayout,
    CanvasContextAction.priorityGridLayout,
    CanvasContextAction.groupSelection,
    CanvasContextAction.ungroupSelection,
    CanvasContextAction.cycleBackground,
    CanvasContextAction.toggleCompleted,
    CanvasContextAction.importClipboard,
    CanvasContextAction.exportJson,
    CanvasContextAction.exportPng,
    CanvasContextAction.commandPalette,
    CanvasContextAction.togglePresentation,
  ];

  Future<void> runContextAction(
    CanvasContextAction action, {
    Offset? scenePosition,
  }) async {
    switch (action) {
      case CanvasContextAction.selectAll:
        _selectAllCanvasObjects();
      case CanvasContextAction.clearSelection:
        await _clearMultiSelection();
      case CanvasContextAction.moveSelectionHere:
        if (scenePosition != null) await _moveSelectionCenterTo(scenePosition);
      case CanvasContextAction.zoomToSelection:
        _zoomToSelected();
      case CanvasContextAction.fitAll:
        _fitBoard();
      case CanvasContextAction.resetZoom:
        _zoomReset();
      case CanvasContextAction.toggleGrid:
        setState(() => _showGrid = !_showGrid);
        await _persistCanvasSettings();
      case CanvasContextAction.toggleSnap:
        setState(() => _snapToGrid = !_snapToGrid);
        await _persistCanvasSettings();
      case CanvasContextAction.toggleMinimap:
        setState(() => _isMinimapCollapsed = !_isMinimapCollapsed);
      case CanvasContextAction.tidyLayout:
        await _applyAutoLayout(_CanvasLayoutMode.tidy);
      case CanvasContextAction.radialLayout:
        await _applyAutoLayout(_CanvasLayoutMode.radial);
      case CanvasContextAction.typeLayout:
        await _applyAutoLayout(_CanvasLayoutMode.byType);
      case CanvasContextAction.timelineLayout:
        await _applyAutoLayout(_CanvasLayoutMode.timeline);
      case CanvasContextAction.matrixLayout:
        await _applyAutoLayout(_CanvasLayoutMode.matrix);
      case CanvasContextAction.priorityGridLayout:
        await _applyAutoLayout(_CanvasLayoutMode.priorityGrid);
      case CanvasContextAction.groupSelection:
        await _setSelectionGroup(
          'group-${DateTime.now().microsecondsSinceEpoch}',
        );
      case CanvasContextAction.ungroupSelection:
        await _setSelectionGroup(null);
      case CanvasContextAction.cycleBackground:
        setState(() => _backgroundMode = (_backgroundMode + 1) % 3);
        await _persistCanvasSettings();
      case CanvasContextAction.toggleCompleted:
        if (!_showCompletedNodes) setState(() => _showCompletedNodes = true);
        await _persistCanvasSettings();
      case CanvasContextAction.paste:
        await _pasteCopiedNodes();
      case CanvasContextAction.importClipboard:
        await _importClipboardText(scenePosition);
      case CanvasContextAction.exportJson:
        await Clipboard.setData(
          ClipboardData(
            text: jsonEncode({
              'version': 1,
              'nodes': [for (final node in widget.nodes) node.toJson()],
              if (widget.board != null) 'board': widget.board!.toJson(),
            }),
          ),
        );
      case CanvasContextAction.exportPng:
        if (_isExporting) return;
        setState(() => _isExporting = true);
        try {
          final result = await _exportCanvasPng();
          widget.onStatusMessage?.call(
            result == null
                ? 'Canvas PNG export failed'
                : 'Canvas PNG exported: $result',
          );
        } catch (error) {
          widget.onStatusMessage?.call('Canvas PNG export failed: $error');
        } finally {
          if (mounted) setState(() => _isExporting = false);
        }
      case CanvasContextAction.exportPdf:
        try {
          final bytes = await generateCanvasPdf(
            nodes: widget.nodes,
            title: 'Mindmap Export',
            board: widget.board,
          );
          final fileName =
              'mindmap-${DateTime.now().millisecondsSinceEpoch}.pdf';
          await saveCanvasPng(bytes, fileName);
          widget.onStatusMessage?.call('Canvas PDF exported');
        } catch (error) {
          widget.onStatusMessage?.call('Canvas PDF export failed: $error');
        }
      case CanvasContextAction.commandPalette:
        _openCommandPalette();
      case CanvasContextAction.togglePresentation:
        setPresentationMode(!_isPresentationMode);
      case CanvasContextAction.createNode:
      case CanvasContextAction.quickTask:
      case CanvasContextAction.quickNote:
      case CanvasContextAction.createLinkedNode:
        break;
    }
  }

  Future<String?> _exportCanvasPng() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _canvasExportKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return saveCanvasPng(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      'var-canvas-$timestamp.png',
    );
  }

  Future<void> groupSelectedEntities() async {
    final nodes = _selectedNodes();
    final objects = _selectedCanvasObjects()
        .where((object) => object.type != CanvasObjectType.nodeReference)
        .toList(growable: false);
    if (nodes.isEmpty ||
        objects.isEmpty ||
        !_canCreateCanvasObjects ||
        widget.onNodeUpdated == null ||
        !_canUpdateCanvasObjects ||
        !_canDeleteCanvasObjects) {
      return;
    }
    Rect? bounds;
    for (final node in nodes) {
      final position = _positionFor(node);
      final rect = Offset(position.dx, position.dy) & _nodeSizeFor(node);
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    for (final object in objects) {
      final geometry = _canvasObjectGeometry(object);
      final rect = Rect.fromLTWH(
        geometry.x,
        geometry.y,
        geometry.width,
        geometry.height,
      );
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    if (bounds == null) return;
    final frameBounds = bounds.inflate(28);
    final now = DateTime.now();
    final frame = CanvasObject(
      id: const Uuid().v4(),
      type: CanvasObjectType.frame,
      geometry: CanvasGeometry(
        x: frameBounds.left,
        y: frameBounds.top,
        width: frameBounds.width,
        height: frameBounds.height,
      ),
      payload: const <String, Object?>{'text': 'Group'},
      createdAt: now,
      updatedAt: now,
    );
    await _createCanvasObjects(<CanvasObject>[frame]);
    try {
      await groupEntitiesInFrame(
        frame.id,
        nodeIds: nodes.map((node) => node.id).toSet(),
        objectIds: objects.map((object) => object.id).toSet(),
      );
    } catch (_) {
      await _deleteCanvasObjects(<CanvasObject>[frame]);
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedNodeIds.clear();
      _selectedCanvasObjectIds
        ..clear()
        ..add(frame.id);
      _selectedCanvasObjectId = frame.id;
    });
  }

  Future<void> groupEntitiesInFrame(
    String frameId, {
    required Set<String> nodeIds,
    required Set<String> objectIds,
  }) async {
    final now = DateTime.now();
    final nodeCallback = widget.onNodeUpdated;
    final originals = widget.nodes
        .where((node) => nodeIds.contains(node.id))
        .toList(growable: false);
    final written = <MindmapNode>[];
    try {
      if (nodeCallback != null) {
        for (final node in originals) {
          written.add(node);
          await nodeCallback(
            node.copyWith(
              data: <String, Object?>{
                ...node.data,
                'groupId': frameId,
                'groupTitle': 'Group',
              },
              updatedAt: now,
            ),
          );
        }
      }
      await _updateCanvasObjects(<CanvasObject>[
        for (final object in widget.board?.objects ?? const <CanvasObject>[])
          if (objectIds.contains(object.id) &&
              object.type != CanvasObjectType.frame &&
              object.type != CanvasObjectType.nodeReference)
            object.copyWith(parentFrameId: frameId, updatedAt: now),
      ]);
    } catch (_) {
      if (nodeCallback != null) {
        for (final node in written.reversed) {
          await nodeCallback(node);
        }
      }
      rethrow;
    }
  }

  Future<void> ungroupFrame(String frameId) async {
    final nodeCallback = widget.onNodeUpdated;
    final nodes = widget.nodes
        .where((node) => node.data['groupId'] == frameId)
        .toList(growable: false);
    final objects = (widget.board?.objects ?? const <CanvasObject>[])
        .where((object) => object.parentFrameId == frameId)
        .toList(growable: false);
    final writtenNodes = <MindmapNode>[];
    try {
      if (nodeCallback != null) {
        for (final node in nodes) {
          final data = Map<String, Object?>.of(node.data)
            ..remove('groupId')
            ..remove('groupTitle')
            ..remove('groupLocked')
            ..remove('swimlaneMode');
          writtenNodes.add(node);
          await nodeCallback(
            node.copyWith(data: data, updatedAt: DateTime.now()),
          );
        }
      }
      await _updateCanvasObjects(<CanvasObject>[
        for (final object in objects)
          object.copyWith(clearParentFrameId: true, updatedAt: DateTime.now()),
      ]);
    } catch (_) {
      if (nodeCallback != null) {
        for (final node in writtenNodes.reversed) {
          await nodeCallback(node);
        }
      }
      await _updateCanvasObjects(objects.reversed.toList());
      rethrow;
    }
  }

  Future<void> deleteFrame(String frameId) async {
    final frame = widget.board?.objectById(frameId);
    if (frame == null ||
        frame.type != CanvasObjectType.frame ||
        !_canDeleteCanvasObjects ||
        widget.onNodeUpdated == null ||
        !_canUpdateCanvasObjects) {
      return;
    }
    try {
      await _deleteCanvasObjects(<CanvasObject>[frame]);
    } catch (_) {
      await _createCanvasObjects(<CanvasObject>[frame]);
      return;
    }
    try {
      await ungroupFrame(frameId);
    } catch (_) {
      await _createCanvasObjects(<CanvasObject>[frame]);
    }
  }

  Future<void> _setSelectionGroup(String? groupId) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    for (final node in _selectedNodes()) {
      final data = Map<String, Object?>.of(node.data);
      if (groupId == null) {
        data
          ..remove('groupId')
          ..remove('groupTitle');
      } else {
        data
          ..['groupId'] = groupId
          ..['groupTitle'] = 'Group';
      }
      await callback(node.copyWith(data: data, updatedAt: DateTime.now()));
    }
  }

  void _selectGroup(List<MindmapNode> nodes) {
    setState(() {
      _selectedNodeIds
        ..clear()
        ..addAll(nodes.map((node) => node.id));
      _lastSelectedNodeId = nodes.firstOrNull?.id;
    });
  }

  Future<void> _renameGroup(List<MindmapNode> nodes) async {
    final callback = widget.onNodeUpdated;
    if (callback == null || nodes.isEmpty) return;
    final currentTitle = nodes.first.data['groupTitle'] as String? ?? 'Group';
    var draftTitle = currentTitle;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextFormField(
          key: const ValueKey('group-title-field'),
          initialValue: currentTitle,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group title'),
          onChanged: (value) => draftTitle = value,
          onFieldSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(draftTitle.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || title == currentTitle) return;
    for (final node in nodes) {
      await callback(
        node.copyWith(
          data: {...node.data, 'groupTitle': title},
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _setGroupLocked(List<MindmapNode> nodes, bool locked) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    for (final node in nodes) {
      await callback(
        node.copyWith(
          data: {...node.data, 'groupLocked': locked},
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _ungroupNodes(List<MindmapNode> nodes) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    for (final node in nodes) {
      final data = Map<String, Object?>.of(node.data)
        ..remove('groupId')
        ..remove('groupTitle')
        ..remove('groupLocked')
        ..remove('swimlaneMode');
      await callback(node.copyWith(data: data, updatedAt: DateTime.now()));
    }
    setState(() => _selectedNodeIds.removeAll(nodes.map((node) => node.id)));
  }

  Future<void> _setGroupSwimlaneMode(
    List<MindmapNode> nodes,
    String mode,
  ) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    for (final node in nodes) {
      final data = Map<String, Object?>.of(node.data);
      if (mode == 'none') {
        data.remove('swimlaneMode');
      } else {
        data['swimlaneMode'] = mode;
      }
      await callback(node.copyWith(data: data, updatedAt: DateTime.now()));
    }
  }

  Future<void> _importClipboardText(Offset? position) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    final isUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final isImageUrl = isUrl && _looksLikeImageUrl(uri);
    final now = DateTime.now();
    final node = MindmapNode.create(
      id: 'clipboard-${now.microsecondsSinceEpoch}',
      type: isImageUrl
          ? NodeType.image
          : isUrl
          ? NodeType.bookmark
          : NodeType.note,
      title: isUrl
          ? (uri.host.isEmpty ? raw : uri.host)
          : raw.split('\n').first,
      body: raw,
      day: widget.nodes.firstOrNull?.day ?? now,
      position: CanvasPosition(position?.dx ?? 0, position?.dy ?? 0),
      data: isImageUrl
          ? ImagePayload(url: raw).toData({'importSource': 'clipboard'})
          : isUrl
          ? {'url': raw, 'importSource': 'clipboard'}
          : {'importSource': 'clipboard'},
      now: now,
    );
    await callback(node);
  }

  // ponytail: local clipboard/file bytes need a cross-platform picker/drop
  // dependency; upgrade this seam when one is added to the app.
  bool _looksLikeImageUrl(Uri uri) {
    final path = uri.path.toLowerCase();
    return const ['.png', '.jpg', '.jpeg', '.gif', '.webp'].any(path.endsWith);
  }

  void _expandSceneToInclude(
    Iterable<Rect> content, {
    bool compensateViewport = true,
  }) {
    var next = _sceneBounds;
    for (final rect in content) {
      next = next.expandToInclude(rect);
    }
    if (next == _sceneBounds) return;
    final sceneShift = next.sceneOffset - _sceneBounds.sceneOffset;
    _sceneBounds = next;
    if (compensateViewport && sceneShift != Offset.zero) {
      _transformationController.value = _transformationController.value.clone()
        ..multiply(
          Matrix4.translationValues(-sceneShift.dx, -sceneShift.dy, 0),
        );
    }
  }

  void _expandSceneForContent({bool compensateViewport = true}) {
    _expandSceneToInclude(<Rect>[
      for (final object in widget.board?.objects ?? const <CanvasObject>[])
        Rect.fromLTWH(
          (_canvasObjectGeometryOverrides[object.id] ?? object.geometry).x,
          (_canvasObjectGeometryOverrides[object.id] ?? object.geometry).y,
          (_canvasObjectGeometryOverrides[object.id] ?? object.geometry).width,
          (_canvasObjectGeometryOverrides[object.id] ?? object.geometry).height,
        ),
      for (final node in widget.nodes)
        Rect.fromLTWH(
          (_dragPositions[node.id] ?? node.position).dx,
          (_dragPositions[node.id] ?? node.position).dy,
          _nodeSizeFor(node).width,
          _nodeSizeFor(node).height,
        ),
    ], compensateViewport: compensateViewport);
  }

  Future<void> _moveSelectionCenterTo(Offset target) async {
    final callback = widget.onNodeMoved;
    final selected = _selectedNodes();
    if (callback == null || selected.isEmpty) return;
    final center = Offset(
      selected.map((node) => _positionFor(node).dx).reduce((a, b) => a + b) /
          selected.length,
      selected.map((node) => _positionFor(node).dy).reduce((a, b) => a + b) /
          selected.length,
    );
    final delta = target - center;
    for (final node in selected) {
      final current = _positionFor(node);
      await callback(
        node,
        CanvasPosition(current.dx + delta.dx, current.dy + delta.dy),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _presentationCache =
        widget.presentationCache ?? MindmapNodePresentationCache();
    _nodeSizes = _effectiveNodeSizes();
    _expandSceneForContent(compensateViewport: false);
    _navigationIndex = CanvasNavigationIndex(
      nodes: widget.nodes,
      board: _workshopVisibleBoard(),
    );
    _orderedBoardObjects = _sortCanvasObjects(_workshopVisibleBoard()?.objects);
    _rebuildCanvasObjectIndex();
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
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
        _activeSearchResultIndex = 0;
      });
    });
    _listenForPings(widget.pingStream);
    unawaited(_loadCanvasSettings());
    if (widget.expandedNodeId != null) _scheduleExpandedNodeFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tokens = AppDesignTokens.of(context);
    _zoomAnimController.duration = tokens.effectiveDuration(
      context,
      tokens.motionFast,
    );
    _cursorAnimController.duration = tokens.effectiveDuration(
      context,
      tokens.motionSlow,
    );
  }

  SharedPreferencesAsync? _canvasPreferences() {
    try {
      return _preferences ??= SharedPreferencesAsync();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCanvasSettings() async {
    try {
      final preferences = _canvasPreferences();
      if (preferences == null) return;
      final raw = await preferences.getString(_settingsKey);
      if (raw == null) return;
      final value = jsonDecode(raw);
      if (value is! Map || !mounted) return;
      final settings = Map<String, Object?>.from(value);
      setState(() {
        _showGrid = settings['showGrid'] as bool? ?? _showGrid;
        _snapToGrid = settings['snapToGrid'] as bool? ?? _snapToGrid;
        _showCompletedNodes = true;
        _backgroundMode =
            ((settings['backgroundMode'] as num?)?.toInt() ?? _backgroundMode)
                .clamp(0, 2);
        final shapeName = settings['shapeKind'];
        _shapeKind = CanvasShapeKind.values.firstWhere(
          (kind) => kind.name == shapeName,
          orElse: () => _shapeKind,
        );
        final pen = settings['penAppearance'];
        if (pen is Map) {
          _penAppearance = CanvasPenAppearance.fromPayload(
            Map<String, Object?>.from(pen),
          );
        }
        final connector = settings['connectorAppearance'];
        if (connector is Map) {
          _connectorAppearance = CanvasConnectorAppearance.fromPayload(
            Map<String, Object?>.from(connector),
          );
        }
      });
    } catch (_) {
      // Preferences are optional on unsupported/test platforms.
    }
  }

  Future<void> _persistCanvasSettings() async {
    try {
      final preferences = _canvasPreferences();
      if (preferences == null) return;
      await preferences.setString(
        _settingsKey,
        jsonEncode({
          'showGrid': _showGrid,
          'snapToGrid': _snapToGrid,
          'showCompleted': true,
          'backgroundMode': _backgroundMode,
          'shapeKind': _shapeKind.name,
          'penAppearance': _penAppearance.toPayload(),
          'connectorAppearance': _connectorAppearance.toPayload(),
        }),
      );
    } catch (_) {
      // Canvas remains usable when preferences are unavailable.
    }
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
    _scheduleViewportPersistence();
  }

  void _scheduleViewportPersistence() {
    if (!_didSetInitialTransform || widget.onViewportChanged == null) return;
    _viewportPersistTimer?.cancel();
    _viewportPersistTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final size = context.size;
      if (size == null || size.isEmpty) return;
      final origin = _sceneOrigin;
      final center = _transformationController.toScene(
        Offset(size.width / 2, size.height / 2),
      );
      final viewport = CanvasViewport(
        x: center.dx - origin.dx,
        y: center.dy - origin.dy,
        scale: _canvasScale(_transformationController.value),
      );
      final previous = _lastEmittedViewport;
      if (previous != null &&
          _nearlyEqual(previous.x, viewport.x, epsilon: 0.5) &&
          _nearlyEqual(previous.y, viewport.y, epsilon: 0.5) &&
          _nearlyEqual(previous.scale, viewport.scale, epsilon: 0.002)) {
        return;
      }
      _lastEmittedViewport = viewport;
      widget.onViewportChanged?.call(viewport);
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
    _toolDraft.dispose();
    _viewportUpdateTimer?.cancel();
    _viewportPersistTimer?.cancel();
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
    _canvasFocusNode.dispose();
    for (final focusNode in _nodeFocusNodes.values) {
      focusNode.dispose();
    }
    _nodeFocusNodes.clear();
    super.dispose();
  }

  /// Calculates the center of the viewport relative to the mindmap's custom origin
  Offset get viewportCenter {
    final viewportSize = context.size;
    if (viewportSize == null) return Offset.zero;

    final centerLocal = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final sceneCenter = _transformationController.toScene(centerLocal);

    final origin = _sceneOrigin;

    return sceneCenter - origin;
  }

  String _connectionLabel(MindmapNode source, String targetId) {
    final labels = source.data['connectionLabels'];
    return labels is Map ? (labels[targetId] as String? ?? '') : '';
  }

  ConnectionStyle _connectionStyle(MindmapNode source, String targetId) {
    final styles = source.data['connection_styles'];
    final styleMap = styles is Map ? styles[targetId] : null;
    var style = styleMap is Map
        ? ConnectionStyle.fromJson((styleMap).cast<String, dynamic>())
        : const ConnectionStyle();
    final label = _connectionLabel(source, targetId);
    if (label.isNotEmpty && (style.label == null || style.label!.isEmpty)) {
      style = style.copyWith(label: label);
    }
    return style;
  }

  Future<void> _updateConnectionStyle(
    MindmapNode source,
    String targetId,
    ConnectionStyle newStyle,
  ) async {
    final styles = <String, Object?>{
      if (source.data['connection_styles'] is Map)
        ...(source.data['connection_styles'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
    };
    styles[targetId] = newStyle.toJson();

    final labels = <String, Object?>{
      if (source.data['connectionLabels'] is Map)
        ...(source.data['connectionLabels'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
    };
    if (newStyle.label != null && newStyle.label!.isNotEmpty) {
      labels[targetId] = newStyle.label!;
    } else {
      labels.remove(targetId);
    }

    await widget.onNodeUpdated?.call(
      source.copyWith(
        data: {
          ...source.data,
          'connection_styles': styles,
          'connectionLabels': labels,
        },
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _editConnectionLabel(MindmapNode source, String targetId) async {
    final controller = TextEditingController(
      text: _connectionLabel(source, targetId),
    );
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection label'),
        content: TextField(
          key: const ValueKey('connection-label-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Depends on'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (label == null) return;
    final labels = <String, Object?>{
      if (source.data['connectionLabels'] is Map)
        ...(source.data['connectionLabels'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
    };
    label.isEmpty ? labels.remove(targetId) : labels[targetId] = label;
    await widget.onNodeUpdated?.call(
      source.copyWith(
        data: {...source.data, 'connectionLabels': labels},
        updatedAt: DateTime.now(),
      ),
    );
  }

  String _connectionKey(MindmapNode source, MindmapNode target) {
    return '${source.id}-${target.id}';
  }

  void _selectConnection(MindmapNode source, MindmapNode target) {
    setState(() {
      _selectedConnectionKey = _connectionKey(source, target);
      _selectedNodeIds.clear();
    });
    widget.onSelectionCleared?.call();
  }

  Future<void> _showConnectionContextMenu(
    MindmapNode source,
    MindmapNode target,
    Offset globalPosition,
  ) async {
    _selectConnection(source, target);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        MediaQuery.sizeOf(context).width - globalPosition.dx,
        MediaQuery.sizeOf(context).height - globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Edit connection label')),
        PopupMenuItem(value: 'source', child: Text('Select source node')),
        PopupMenuItem(value: 'target', child: Text('Select target node')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'detach', child: Text('Delete connection')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _editConnectionLabel(source, target.id);
      case 'source':
        await _selectNode(source);
      case 'target':
        await _selectNode(target);
      case 'detach':
        await widget.onNodeDisconnected?.call(source, target);
        if (mounted) setState(() => _selectedConnectionKey = null);
    }
  }

  /// Selects a node from an external view and pans it into focus.

  void followCollaborator(String? id) {
    setState(() {
      _followingCollaboratorId = id;
      if (id == null) return;
      final peer = widget.collaborationState?.collaborators[id];
      final position = peer?.cursorPosition;
      if (position != null) _followPeerPosition(position);
    });
  }

  String? get followingCollaboratorId => _followingCollaboratorId;

  Set<String> get selectedCanvasObjectIds =>
      Set<String>.unmodifiable(_selectedCanvasObjectIds);

  void selectCanvasObject(String id) {
    final object = widget.board?.objectById(id);
    if (object != null) _selectCanvasObject(object);
  }

  @visibleForTesting
  Rect get sceneWorldBounds => _sceneBounds.worldRect;

  @visibleForTesting
  Rect minimapWorldBoundsForTest() {
    final size = context.size ?? Size.zero;
    final scene = _minimapSceneBounds(size);
    return scene.shift(-_sceneOrigin);
  }

  CanvasViewport get currentViewport {
    final size = context.size;
    if (size == null || size.isEmpty) return const CanvasViewport();
    final origin = _sceneOrigin;
    final center = _transformationController.toScene(
      Offset(size.width / 2, size.height / 2),
    );
    return CanvasViewport(
      x: center.dx - origin.dx,
      y: center.dy - origin.dy,
      scale: _canvasScale(_transformationController.value),
    );
  }

  String? navigateSpatially(LogicalKeyboardKey direction) =>
      _navigateSpatialSelection(direction);

  Future<bool> selectAndFocusNode(MindmapNode node) async {
    final selected = await _selectNode(node);
    if (!selected) return false;
    focusOnPosition(node.position);
    return true;
  }

  void _scheduleExpandedNodeFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final expandedId = widget.expandedNodeId;
      if (expandedId == null) return;
      final expandedNode = widget.nodes
          .where((node) => node.id == expandedId)
          .firstOrNull;
      if (expandedNode == null) return;
      _focusNodeBounds(expandedNode);
    });
  }

  void _focusNodeBounds(MindmapNode node) {
    final viewportSize = context.size;
    if (viewportSize == null || viewportSize.isEmpty) return;
    final nodeSize = _nodeSizeFor(node);
    const viewportPadding = 24.0;
    final availableWidth = math.max(
      1.0,
      viewportSize.width - viewportPadding * 2,
    );
    final availableHeight = math.max(
      1.0,
      viewportSize.height - viewportPadding * 2,
    );
    final scale = math
        .min(
          1.0,
          math.min(
            availableWidth / nodeSize.width,
            availableHeight / nodeSize.height,
          ),
        )
        .clamp(0.04, 1.0)
        .toDouble();
    final origin = _sceneOrigin;
    final position = _positionFor(node);
    final targetScene =
        origin +
        Offset(
          position.dx + nodeSize.width / 2,
          position.dy + nodeSize.height / 2,
        );
    final targetMatrix =
        Matrix4.translationValues(
                  viewportSize.width / 2 - targetScene.dx * scale,
                  viewportSize.height / 2 - targetScene.dy * scale,
                  0,
                ) *
                Matrix4.diagonal3Values(scale, scale, 1)
            as Matrix4;

    _transitionViewportTo(targetMatrix);
  }

  /// Pans the viewport to focus on a specific node position
  void focusOnPosition(CanvasPosition pos, {double scale = 1.0}) {
    final viewportSize = context.size;
    if (viewportSize == null) return;

    final origin = _sceneOrigin;

    final targetScene = origin + Offset(pos.dx, pos.dy);

    final tx = viewportSize.width / 2 - targetScene.dx * scale;
    final ty = viewportSize.height / 2 - targetScene.dy * scale;

    final targetMatrix =
        Matrix4.translationValues(tx, ty, 0) *
                Matrix4.diagonal3Values(scale, scale, 1)
            as Matrix4;

    _transitionViewportTo(targetMatrix);
  }

  void _zoomToSelected() {
    final viewportSize = context.size;
    if (viewportSize == null ||
        (_selectedNodeIds.isEmpty && _selectedCanvasObjectIds.isEmpty)) {
      return;
    }
    final origin = _sceneOrigin;
    Rect? bounds;
    for (final node in widget.nodes) {
      if (!_selectedNodeIds.contains(node.id)) continue;
      final position = _positionFor(node);
      final rect =
          (origin + Offset(position.dx, position.dy)) & _nodeSizeFor(node);
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    for (final object in _orderedCanvasObjects()) {
      if (!_selectedCanvasObjectIds.contains(object.id)) continue;
      final geometry = _canvasObjectGeometry(object);
      final rect = Rect.fromLTWH(
        origin.dx + geometry.x,
        origin.dy + geometry.y,
        geometry.width,
        geometry.height,
      );
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    if (bounds == null) return;
    _focusSceneBounds(bounds, viewportSize);
  }

  void _fitBoard() {
    final viewportSize = context.size;
    if (viewportSize == null) return;
    final origin = _sceneOrigin;
    Rect? bounds;
    for (final entry in _navigationIndex.entries) {
      final rect = entry.bounds.shift(origin);
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    if (bounds == null) {
      _zoomReset();
      return;
    }
    _focusSceneBounds(bounds, viewportSize);
  }

  void _focusSceneBounds(Rect bounds, Size viewportSize) {
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
    _transitionViewportTo(targetMatrix);
  }

  void _zoom(double factor) {
    final viewportSize = context.size;
    if (viewportSize == null) return;
    _zoomAt(Offset(viewportSize.width / 2, viewportSize.height / 2), factor);
  }

  void _zoomAt(Offset localFocalPoint, double factor) {
    final sceneFocalPoint = _transformationController.toScene(localFocalPoint);
    final currentScale = _canvasScale(_transformationController.value);
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

  String? _navigateSpatialSelection(LogicalKeyboardKey key) {
    final direction = switch (key) {
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      _ => Offset.zero,
    };
    if (direction == Offset.zero) return null;
    Offset? source;
    final objectId = _selectedCanvasObjectId;
    if (objectId != null) {
      final geometry = widget.board?.objectById(objectId)?.geometry;
      if (geometry != null) {
        source = Offset(
          geometry.x + geometry.width / 2,
          geometry.y + geometry.height / 2,
        );
      }
    }
    final nodeId = _lastSelectedNodeId;
    if (source == null && nodeId != null) {
      source = _navigationIndex.entries
          .where((entry) => entry.nodeId == nodeId)
          .firstOrNull
          ?.center;
    }
    if (source == null) {
      final size = context.size;
      if (size == null) return null;
      final origin = _sceneOrigin;
      source =
          _transformationController.toScene(
            Offset(size.width / 2, size.height / 2),
          ) -
          origin;
    }
    final target = _navigationIndex.nearest(from: source, direction: direction);
    if (target == null) return null;
    _activateNavigationResult(target);
    return target.id;
  }

  bool get _editableControlHasPrimaryFocus {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
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

    if (_editableControlHasPrimaryFocus) return KeyEventResult.ignored;

    // Delete or Backspace to delete selected nodes
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_selectedCanvasObjectIds.isNotEmpty || _selectedNodeIds.isNotEmpty) {
        unawaited(_deleteSelectedEntities());
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
      if (_isCtrlPressed) {
        _navigateSpatialSelection(key);
        return KeyEventResult.handled;
      }
      if (_selectedCanvasObjectIds.isNotEmpty) {
        _nudgeSelectedCanvasObjects(key, accelerated: isShift);
        return KeyEventResult.handled;
      }
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
      _searchCategory = CanvasSearchCategory.all;
      _activeSearchResultIndex = 0;
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

  void _toggleSearchOverlay() {
    final shouldExpand = _isSearchOverlayCollapsed;
    setState(() => _isSearchOverlayCollapsed = !shouldExpand);
    if (shouldExpand) {
      _searchFocusNode.requestFocus();
    } else {
      _searchFocusNode.unfocus();
    }
  }

  void _focusCanvasSearch() {
    if (_isSearchOverlayCollapsed) {
      setState(() => _isSearchOverlayCollapsed = false);
    }
    _searchFocusNode.requestFocus();
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
      viewportSize.width / 2 - _sceneOrigin.dx,
      viewportSize.height / 2 - _sceneOrigin.dy,
      0,
    );

    _transitionViewportTo(targetMatrix);
  }

  void _zoomActualSize() {
    final viewportSize = context.size;
    if (viewportSize == null) return;
    final currentScale = _canvasScale(_transformationController.value);
    _zoomAt(
      Offset(viewportSize.width / 2, viewportSize.height / 2),
      1 / currentScale,
    );
  }

  void _transitionViewportTo(Matrix4 targetMatrix) {
    _zoomAnimController.stop();
    final media = MediaQuery.maybeOf(context);
    if ((media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false)) {
      _transformationController.value = targetMatrix;
      return;
    }
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
    final origin = _sceneOrigin;
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
      if (_isCanvasEraserActive) {
        _erasedCanvasObjectIds.clear();
        _eraseCanvasObjectAt(scenePosition);
        return;
      }
      if (_creationObjectType == CanvasObjectType.freehand) {
        _toolDraft.beginFreehand(event.pointer, scenePosition);
        return;
      }
      if (_creationObjectType != null) {
        unawaited(_createCanvasObject(scenePosition));
        return;
      }
      if (_nodeAtScene(scenePosition) != null ||
          _connectionAtScene(scenePosition)) {
        return;
      }
      final object = _canvasObjectAtScene(scenePosition);
      if (object != null) {
        _selectCanvasObject(object);
        return;
      }
      if (event.kind == PointerDeviceKind.touch) {
        _touchPanLastLocal = event.localPosition;
        if (_selectedConnectionKey != null) {
          setState(() => _selectedConnectionKey = null);
        }
        return;
      }
      setState(() {
        _lassoStartLocal = event.localPosition;
        _lassoCurrentLocal = event.localPosition;
      });
      return;
    }
    if (event.buttons != kSecondaryMouseButton) return;
    final scenePosition = _transformationController.toScene(
      event.localPosition,
    );
    if (_nodeAtScene(scenePosition) != null ||
        _connectionAtScene(scenePosition)) {
      return;
    }
    final object = _canvasObjectAtScene(scenePosition);
    if (object != null) {
      unawaited(_showCanvasObjectContextMenu(object, event.position));
      return;
    }
    widget.onCanvasContextMenu?.call(
      event.position,
      _alignedCanvasPositionFromLocal(event.localPosition),
    );
  }

  CanvasObject? _canvasObjectAtScene(Offset scenePosition) {
    final origin = _sceneOrigin;
    for (final object in _orderedCanvasObjects().reversed) {
      if (!object.isVisible || object.type == CanvasObjectType.nodeReference) {
        continue;
      }
      final geometry = _canvasObjectGeometry(object);
      final rect = Rect.fromLTWH(
        origin.dx + geometry.x,
        origin.dy + geometry.y,
        geometry.width,
        geometry.height,
      );
      if (rect.contains(scenePosition)) return object;
    }
    return null;
  }

  Future<void> _createCanvasObject(Offset scenePosition) async {
    final type = _creationObjectType;
    final callback = widget.onCanvasObjectCreated;
    if (type == null || callback == null) return;
    final origin = _sceneOrigin;
    if (type == CanvasObjectType.connector && _connectorStartScene == null) {
      setState(() {
        _connectorStartScene = scenePosition;
        _connectorStartObjectId = _canvasObjectAtScene(scenePosition)?.id;
      });
      _toolDraft.beginConnector(scenePosition);
      widget.onStatusMessage?.call('Choose connector end');
      return;
    }
    final link = type == CanvasObjectType.linkPreview
        ? await _promptForCanvasLink()
        : null;
    if (type == CanvasObjectType.linkPreview && link == null) {
      if (mounted) setState(() => _creationObjectType = null);
      return;
    }
    final image = type == CanvasObjectType.image ? _pendingCanvasImage : null;
    if (type == CanvasObjectType.image && image == null) return;
    final size = switch (type) {
      CanvasObjectType.stickyNote => const Size(240, 180),
      CanvasObjectType.shape => const Size(220, 140),
      CanvasObjectType.text => const Size(260, 80),
      CanvasObjectType.frame => const Size(520, 340),
      CanvasObjectType.column => const Size(320, 480),
      CanvasObjectType.image => const Size(360, 240),
      CanvasObjectType.linkPreview => const Size(360, 160),
      _ => const Size(200, 120),
    };
    final now = DateTime.now();
    final connectorStart = _connectorStartScene;
    final startBoard = connectorStart == null ? null : connectorStart - origin;
    final endBoard = scenePosition - origin;
    final connectorLeft = startBoard == null
        ? 0.0
        : math.min(startBoard.dx, endBoard.dx) - 12;
    final connectorTop = startBoard == null
        ? 0.0
        : math.min(startBoard.dy, endBoard.dy) - 12;
    final connectorWidth = startBoard == null
        ? 0.0
        : math.max((startBoard.dx - endBoard.dx).abs() + 24, 24.0);
    final connectorHeight = startBoard == null
        ? 0.0
        : math.max((startBoard.dy - endBoard.dy).abs() + 24, 24.0);
    final geometry = type == CanvasObjectType.connector && startBoard != null
        ? CanvasGeometry(
            x: connectorLeft,
            y: connectorTop,
            width: connectorWidth,
            height: connectorHeight,
          )
        : CanvasGeometry(
            x: scenePosition.dx - origin.dx - size.width / 2,
            y: scenePosition.dy - origin.dy - size.height / 2,
            width: size.width,
            height: size.height,
          );
    final objectId = const Uuid().v4();
    final object = CanvasObject(
      id: objectId,
      type: type,
      geometry: geometry,
      parentFrameId: type == CanvasObjectType.frame
          ? null
          : _frameContainingGeometry(geometry, excludeId: objectId)?.id,
      payload: switch (type) {
        CanvasObjectType.stickyNote => <String, Object?>{
          'text': 'Sticky note',
          'color': 'amber',
          ...const CanvasTextStyle(
            fontSize: 18,
            textColor: '#202124',
            padding: 18,
          ).toPayload(),
        },
        CanvasObjectType.shape => <String, Object?>{
          ...CanvasShapeStyle(kind: _shapeKind).toPayload(),
          ...const CanvasTextStyle(
            horizontalAlign: CanvasTextHorizontalAlign.center,
            verticalAlign: CanvasTextVerticalAlign.center,
          ).toPayload(),
          'text': '',
          'color': 'blue',
        },
        CanvasObjectType.text => <String, Object?>{
          'text': 'Text label',
          'color': 'blue',
          ...const CanvasTextStyle().toPayload(),
        },
        CanvasObjectType.frame => const <String, Object?>{
          'text': 'Section',
          'color': 'blue',
          'opacity': 0.18,
          'borderWidth': 2.0,
        },
        CanvasObjectType.column => const <String, Object?>{
          'title': 'Column',
          'isCollapsed': false,
          'orderedChildIds': <String>[],
        },
        CanvasObjectType.image when image != null => image.toPayload(),
        CanvasObjectType.linkPreview when link != null => <String, Object?>{
          'url': link.toString(),
          'title': link.host,
          'description': link.path == '/' ? '' : link.path,
        },
        CanvasObjectType.connector when startBoard != null => <String, Object?>{
          if (_connectorStartObjectId != null)
            'sourceObjectId': _connectorStartObjectId,
          if (_canvasObjectAtScene(scenePosition) case final target?)
            'targetObjectId': target.id,
          'startX': startBoard.dx - connectorLeft,
          'startY': startBoard.dy - connectorTop,
          'endX': endBoard.dx - connectorLeft,
          'endY': endBoard.dy - connectorTop,
          'routePoints': <Map<String, double>>[
            for (final point in routeOrthogonalConnector(
              start: spatial.CanvasPoint(startBoard.dx, startBoard.dy),
              end: spatial.CanvasPoint(endBoard.dx, endBoard.dy),
              obstacles: (widget.board?.objects ?? const <CanvasObject>[])
                  .where(
                    (object) =>
                        object.isVisible &&
                        object.type != CanvasObjectType.connector &&
                        object.type != CanvasObjectType.freehand,
                  )
                  .map(
                    (object) => spatial.CanvasBounds.fromLTWH(
                      object.geometry.x,
                      object.geometry.y,
                      object.geometry.width,
                      object.geometry.height,
                    ),
                  ),
            ))
              <String, double>{
                'x': point.x - connectorLeft,
                'y': point.y - connectorTop,
              },
          ],
          ..._connectorAppearance.toPayload(),
          'arrowEnd': _connectorAppearance.endArrow != CanvasArrowhead.none,
        },
        _ => const <String, Object?>{},
      },
      createdAt: now,
      updatedAt: now,
    );
    if (type == CanvasObjectType.connector) _toolDraft.clear();
    setState(() {
      _selectedCanvasObjectId = object.id;
      _selectedCanvasObjectIds
        ..clear()
        ..add(object.id);
      if (type == CanvasObjectType.stickyNote ||
          type == CanvasObjectType.text) {
        _pendingInlineEditCanvasObjectId = object.id;
      }
      _toolPopoverType = null;
      _creationObjectType = null;
      _connectorStartScene = null;
      _connectorStartObjectId = null;
      _pendingCanvasImage = null;
    });
    try {
      await callback(object);
    } on Object {
      if (mounted && _pendingInlineEditCanvasObjectId == object.id) {
        setState(() => _pendingInlineEditCanvasObjectId = null);
      }
      rethrow;
    }
  }

  void _activateCanvasSelectTool() {
    _toolDraft.clear();
    setState(() {
      _toolPopoverType = null;
      _creationObjectType = null;
      _connectorStartScene = null;
      _connectorStartObjectId = null;
      _pendingCanvasImage = null;
      _isCanvasEraserActive = false;
      _isCanvasCommentToolActive = false;
    });
    _canvasFocusNode.requestFocus();
  }

  bool get _hasActiveCanvasTool =>
      _creationObjectType != null ||
      _connectorStartScene != null ||
      _toolDraft.hasFreehand ||
      _isCanvasEraserActive ||
      _isCanvasCommentToolActive;

  void _activateCanvasCommentTool() {
    if (!_canUpdateCanvasObjects &&
        widget.onCollaborationBoardCommentsChanged == null) {
      return;
    }
    if (_selectedCanvasObject() != null) {
      _activateCanvasSelectTool();
      unawaited(_showCanvasObjectComments());
      return;
    }
    setState(() {
      _creationObjectType = null;
      _connectorStartScene = null;
      _connectorStartObjectId = null;
      _pendingCanvasImage = null;
      _isCanvasEraserActive = false;
      _isCanvasCommentToolActive = true;
    });
    widget.onStatusMessage?.call('Select a canvas object to comment');
  }

  void _showToolSettings(CanvasObjectType type) {
    setState(() => _toolPopoverType = _toolPopoverType == type ? null : type);
    unawaited(_selectCanvasCreationTool(type));
  }

  void _closeToolSettings() => setState(() => _toolPopoverType = null);

  Widget _buildToolSettings(BuildContext context, CanvasObjectType type) {
    final title = switch (type) {
      CanvasObjectType.stickyNote => 'Sticky note',
      CanvasObjectType.text => 'Text label',
      CanvasObjectType.shape => 'Shape',
      CanvasObjectType.connector => 'Connector',
      CanvasObjectType.freehand => 'Freehand pen',
      CanvasObjectType.frame => 'Frame',
      CanvasObjectType.column => 'Column',
      _ => 'Tool settings',
    };
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _closeToolSettings();
              _canvasFocusNode.requestFocus();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: CanvasToolPopover(
            title: title,
            onClose: _closeToolSettings,
            child: switch (type) {
              CanvasObjectType.shape => _ShapeToolSettings(
                selected: _shapeKind,
                onSelected: (value) {
                  setState(() => _shapeKind = value);
                  unawaited(_persistCanvasSettings());
                },
              ),
              CanvasObjectType.connector => _ConnectorToolSettings(
                appearance: _connectorAppearance,
                onChanged: (value) {
                  setState(() => _connectorAppearance = value);
                  unawaited(_persistCanvasSettings());
                },
              ),
              CanvasObjectType.freehand => _PenToolSettings(
                appearance: _penAppearance,
                onChanged: (value) {
                  setState(() => _penAppearance = value);
                  unawaited(_persistCanvasSettings());
                },
              ),
              CanvasObjectType.stickyNote ||
              CanvasObjectType.text => const Text(
                'Click canvas to create. Double-click object to edit multiline text.',
              ),
              CanvasObjectType.frame => const Text(
                'Click canvas to add a section. Drag and resize after creation.',
              ),
              CanvasObjectType.column => const Text(
                'Click canvas to add an ordered column.',
              ),
              _ => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
  }

  Future<void> _selectCanvasCreationTool(CanvasObjectType type) async {
    if (type == CanvasObjectType.image) {
      final source = await widget.onCanvasImageImport?.call();
      if (!mounted || source == null) return;
      setState(() {
        _pendingCanvasImage = source;
        _creationObjectType = CanvasObjectType.image;
        _connectorStartScene = null;
        _connectorStartObjectId = null;
        _isCanvasEraserActive = false;
        _isCanvasCommentToolActive = false;
      });
      return;
    }
    setState(() {
      _pendingCanvasImage = null;
      _creationObjectType = type;
      _connectorStartScene = null;
      _connectorStartObjectId = null;
      _isCanvasEraserActive = false;
      _isCanvasCommentToolActive = false;
    });
  }

  Future<Uri?> _promptForCanvasLink() async {
    var value = 'https://';
    String? error;
    return showDialog<Uri>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add link preview'),
          content: TextFormField(
            key: const ValueKey('canvas-link-url'),
            initialValue: value,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: 'URL', errorText: error),
            onChanged: (next) => value = next,
            onFieldSubmitted: (_) {
              final uri = Uri.tryParse(value.trim());
              if (uri != null &&
                  (uri.scheme == 'http' || uri.scheme == 'https') &&
                  uri.host.isNotEmpty) {
                Navigator.pop(context, uri);
              } else {
                setDialogState(() => error = 'Enter a valid http(s) URL');
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('canvas-link-add'),
              onPressed: () {
                final uri = Uri.tryParse(value.trim());
                if (uri != null &&
                    (uri.scheme == 'http' || uri.scheme == 'https') &&
                    uri.host.isNotEmpty) {
                  Navigator.pop(context, uri);
                } else {
                  setDialogState(() => error = 'Enter a valid http(s) URL');
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  CanvasGeometry _canvasObjectGeometry(CanvasObject object) =>
      _canvasObjectGeometryOverrides[object.id] ?? object.geometry;

  List<CanvasObject> _orderedCanvasObjects() => _orderedBoardObjects;

  void _rebuildCanvasObjectIndex() {
    _canvasObjectIndex.clear();
    for (final object in _orderedBoardObjects) {
      final geometry = object.geometry;
      _canvasObjectIndex.insert(
        object.id,
        spatial.CanvasBounds.fromLTWH(
          geometry.x,
          geometry.y,
          geometry.width,
          geometry.height,
        ),
      );
    }
  }

  Iterable<CanvasObject> _indexedCanvasObjects(spatial.CanvasBounds area) {
    final ids = _canvasObjectIndex.query(area);
    return _orderedBoardObjects.where((object) {
      if (ids.contains(object.id)) return true;
      final geometry = _canvasObjectGeometryOverrides[object.id];
      return geometry != null &&
          spatial.CanvasBounds.fromLTWH(
            geometry.x,
            geometry.y,
            geometry.width,
            geometry.height,
          ).overlaps(area);
    });
  }

  ({CanvasGeometry geometry, List<Offset> route}) _effectiveConnector(
    CanvasObject connector,
  ) {
    final stored = _canvasObjectGeometry(connector);
    final sourceId = connector.payload['sourceObjectId'] as String?;
    final targetId = connector.payload['targetObjectId'] as String?;
    final source = sourceId == null ? null : widget.board?.objectById(sourceId);
    final target = targetId == null ? null : widget.board?.objectById(targetId);
    Offset fallback(String prefix, Offset defaultPoint) => Offset(
      stored.x +
          ((connector.payload['${prefix}X'] as num?)?.toDouble() ??
              defaultPoint.dx),
      stored.y +
          ((connector.payload['${prefix}Y'] as num?)?.toDouble() ??
              defaultPoint.dy),
    );
    final sourceFallback = fallback('start', const Offset(12, 12));
    final targetFallback = fallback(
      'end',
      Offset(stored.width - 12, stored.height - 12),
    );
    spatial.CanvasBounds? boundsFor(CanvasObject? object) {
      if (object == null || !object.isVisible) return null;
      final geometry = _canvasObjectGeometry(object);
      return spatial.CanvasBounds.fromLTWH(
        geometry.x,
        geometry.y,
        geometry.width,
        geometry.height,
      );
    }

    final sourceBounds = boundsFor(source);
    final targetBounds = boundsFor(target);
    final sourceAttachment = sourceBounds == null
        ? null
        : nearestConnectorAttachment(
            sourceBounds,
            spatial.CanvasPoint(
              targetBounds == null
                  ? targetFallback.dx
                  : (targetBounds.left + targetBounds.right) / 2,
              targetBounds == null
                  ? targetFallback.dy
                  : (targetBounds.top + targetBounds.bottom) / 2,
            ),
          );
    final start = sourceAttachment == null
        ? sourceFallback
        : Offset(sourceAttachment.point.x, sourceAttachment.point.y);
    final targetAttachment = targetBounds == null
        ? null
        : nearestConnectorAttachment(
            targetBounds,
            spatial.CanvasPoint(start.dx, start.dy),
          );
    final end = targetAttachment == null
        ? targetFallback
        : Offset(targetAttachment.point.x, targetAttachment.point.y);
    final appearance = CanvasConnectorAppearance.fromPayload(connector.payload);
    final manualWaypoints = switch (connector.payload['manualWaypoints']) {
      final List<Object?> values =>
        values
            .whereType<Map<Object?, Object?>>()
            .take(32)
            .map(
              (point) => Offset(
                (point['x'] as num?)?.toDouble() ?? 0,
                (point['y'] as num?)?.toDouble() ?? 0,
              ),
            )
            .toList(growable: false),
      _ => const <Offset>[],
    };
    final query = spatial.CanvasBounds(
      math.min(start.dx, end.dx),
      math.min(start.dy, end.dy),
      math.max(start.dx, end.dx),
      math.max(start.dy, end.dy),
    ).inflate(1000);
    final excluded = <String>{connector.id, ?sourceId, ?targetId};
    final route = manualWaypoints.isNotEmpty
        ? <spatial.CanvasPoint>[
            spatial.CanvasPoint(start.dx, start.dy),
            for (final point in manualWaypoints)
              spatial.CanvasPoint(point.dx, point.dy),
            spatial.CanvasPoint(end.dx, end.dy),
          ]
        : switch (appearance.style) {
            CanvasConnectorStyle.straight ||
            CanvasConnectorStyle.curved => <spatial.CanvasPoint>[
              spatial.CanvasPoint(start.dx, start.dy),
              spatial.CanvasPoint(end.dx, end.dy),
            ],
            CanvasConnectorStyle.elbow => routeOrthogonalConnector(
              start: spatial.CanvasPoint(start.dx, start.dy),
              end: spatial.CanvasPoint(end.dx, end.dy),
              obstacles: _indexedCanvasObjects(query)
                  .where(
                    (object) =>
                        object.isVisible &&
                        !excluded.contains(object.id) &&
                        object.type != CanvasObjectType.connector &&
                        object.type != CanvasObjectType.freehand,
                  )
                  .map((object) {
                    final geometry = _canvasObjectGeometry(object);
                    return spatial.CanvasBounds.fromLTWH(
                      geometry.x,
                      geometry.y,
                      geometry.width,
                      geometry.height,
                    );
                  }),
            ),
          };
    final left = route.map((point) => point.x).reduce(math.min) - 12;
    final top = route.map((point) => point.y).reduce(math.min) - 12;
    final right = route.map((point) => point.x).reduce(math.max) + 12;
    final bottom = route.map((point) => point.y).reduce(math.max) + 12;
    return (
      geometry: CanvasGeometry(
        x: left,
        y: top,
        width: math.max(24, right - left),
        height: math.max(24, bottom - top),
      ),
      route: <Offset>[
        for (final point in route) Offset(point.x - left, point.y - top),
      ],
    );
  }

  List<CanvasObject> _sortCanvasObjects(Iterable<CanvasObject>? objects) {
    final sorted = <CanvasObject>[...objects ?? const <CanvasObject>[]]
      ..sort((left, right) {
        int phase(CanvasObject object) => switch (object.type) {
          CanvasObjectType.frame => 0,
          CanvasObjectType.column => 1,
          _ => 2,
        };
        final phaseOrder = phase(left).compareTo(phase(right));
        return phaseOrder != 0
            ? phaseOrder
            : left.zIndex.compareTo(right.zIndex);
      });
    return sorted;
  }

  bool _isCanvasObjectVisible(CanvasObject object, Offset origin) {
    final rect = _visibleSceneRect;
    if (rect == null || object.type == CanvasObjectType.nodeReference) {
      return true;
    }
    if (_selectedCanvasObjectIds.contains(object.id) ||
        _canvasObjectGeometryOverrides.containsKey(object.id)) {
      return true;
    }
    final geometry = _canvasObjectGeometry(object);
    return rect.overlaps(
      Rect.fromLTWH(
        origin.dx + geometry.x,
        origin.dy + geometry.y,
        geometry.width,
        geometry.height,
      ),
    );
  }

  CanvasObject? _frameContainingGeometry(
    CanvasGeometry geometry, {
    String? excludeId,
  }) {
    final center = Offset(
      geometry.x + geometry.width / 2,
      geometry.y + geometry.height / 2,
    );
    final frames =
        (widget.board?.objects ?? const <CanvasObject>[])
            .where(
              (object) =>
                  object.id != excludeId &&
                  object.type == CanvasObjectType.frame &&
                  object.isVisible,
            )
            .where(
              (frame) => Rect.fromLTWH(
                frame.geometry.x,
                frame.geometry.y,
                frame.geometry.width,
                frame.geometry.height,
              ).contains(center),
            )
            .toList()
          ..sort(
            (left, right) => (left.geometry.width * left.geometry.height)
                .compareTo(right.geometry.width * right.geometry.height),
          );
    return frames.firstOrNull;
  }

  CanvasObject? _selectedCanvasObject() {
    final id = _selectedCanvasObjectId;
    return id == null ? null : widget.board?.objectById(id);
  }

  CanvasWorkshopPolicy get _workshopPolicy => canvasWorkshopPolicyFor(
    widget.workshopSession ?? CanvasWorkshopSession(),
    isHost: widget.isWorkshopHost,
  );

  bool _isWorkshopObjectVisible(CanvasObject object) {
    final session = widget.workshopSession;
    return session == null ||
        isWorkshopObjectVisible(
          object.payload,
          session,
          viewerUid: widget.workshopViewerUid,
          isHost: widget.isWorkshopHost,
        );
  }

  CanvasBoard? _workshopVisibleBoard() {
    final board = widget.board;
    if (board == null || widget.workshopSession == null) return board;
    return board.visibleForWorkshop(
      session: widget.workshopSession!,
      viewerUid: widget.workshopViewerUid,
      isHost: widget.isWorkshopHost,
    );
  }

  int _canvasObjectVoteCount(CanvasObject object) {
    final session = widget.board?.votingSession;
    return session == null || session.status == CanvasVotingStatus.inactive
        ? object.voteCount
        : session.resultsConcealed
        ? 0
        : session.votesForObject(object.id);
  }

  bool _hasLocalVote(CanvasObject object) {
    final session = widget.board?.votingSession;
    return session?.isActive == true &&
        session!.hasVote(widget.votingParticipantId, object.id);
  }

  PopupMenuItem<_CanvasObjectAction>? _voteMenuItem(CanvasObject? object) {
    if (object == null ||
        widget.board?.votingSession.isActive != true ||
        !_workshopPolicy.canVote) {
      return null;
    }
    final hasVote = _hasLocalVote(object);
    return PopupMenuItem<_CanvasObjectAction>(
      key: ValueKey(
        hasVote
            ? 'mindmap-canvas-object-remove-vote'
            : 'mindmap-canvas-object-add-vote',
      ),
      value: hasVote
          ? _CanvasObjectAction.removeVote
          : _CanvasObjectAction.addVote,
      child: Text(hasVote ? 'Remove vote' : 'Add vote'),
    );
  }

  int _canvasObjectOpenCommentCount(CanvasObject object) =>
      (widget.collaborationBoardComments[object.id] ?? object.comments)
          .where((comment) => comment.parentId == null && !comment.isResolved)
          .length;

  List<CanvasObject> _selectedCanvasObjects() {
    final board = widget.board;
    if (board == null) return const <CanvasObject>[];
    return board.objects
        .where((object) => _selectedCanvasObjectIds.contains(object.id))
        .toList();
  }

  bool get _canCreateCanvasObjects =>
      _workshopPolicy.canCreate &&
      (widget.onCanvasObjectsCreated != null ||
          widget.onCanvasObjectCreated != null);

  bool get _canUpdateCanvasObjects =>
      (_workshopPolicy.canEditOwn ||
          _workshopPolicy.canEditOthers ||
          _workshopPolicy.canMoveAndGroup) &&
      (widget.onCanvasObjectsUpdated != null ||
          widget.onCanvasObjectUpdated != null);

  bool get _canDeleteCanvasObjects =>
      (_workshopPolicy.canEditOwn || _workshopPolicy.canEditOthers) &&
      (widget.onCanvasObjectsDeleted != null ||
          widget.onCanvasObjectDeleted != null);

  CanvasObject _withWorkshopMetadata(CanvasObject object) {
    final session = widget.workshopSession;
    final stage = session?.activeStage;
    if (session == null || !session.isActive || stage == null) return object;
    return object.copyWith(
      payload: <String, Object?>{
        ...object.payload,
        'workshopSessionId': session.sessionId,
        'workshopStageId': stage.id,
        'workshopAuthorUid': widget.workshopViewerUid,
        'workshopPrivate': stage.contributionsPrivate,
      },
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _createCanvasObjects(List<CanvasObject> objects) async {
    if (objects.isEmpty) return;
    final prepared = objects.map(_withWorkshopMetadata).toList(growable: false);
    final batch = widget.onCanvasObjectsCreated;
    if (batch != null) {
      await batch(prepared);
      return;
    }
    final callback = widget.onCanvasObjectCreated;
    if (callback == null) return;
    for (final object in prepared) {
      await callback(object);
    }
  }

  Future<void> _updateCanvasObjects(List<CanvasObject> objects) async {
    if (objects.isEmpty) return;
    final batch = widget.onCanvasObjectsUpdated;
    if (batch != null) {
      await batch(objects);
      return;
    }
    final callback = widget.onCanvasObjectUpdated;
    if (callback == null) return;
    for (final object in objects) {
      await callback(object);
    }
  }

  Future<void> _deleteCanvasObjects(List<CanvasObject> objects) async {
    if (objects.isEmpty) return;
    final board = widget.board;
    final deletedColumnIds = objects
        .where((object) => object.type == CanvasObjectType.column)
        .map((object) => object.id)
        .toSet();
    final originalChildren = <CanvasObject>[
      if (board != null)
        for (final object in board.objects)
          if (object.parentColumnId != null &&
              deletedColumnIds.contains(object.parentColumnId))
            object,
    ];
    if (originalChildren.isNotEmpty) {
      await _updateCanvasObjects(<CanvasObject>[
        for (final object in originalChildren)
          object.copyWith(clearParentColumnId: true, updatedAt: DateTime.now()),
      ]);
    }
    try {
      final batch = widget.onCanvasObjectsDeleted;
      if (batch != null) {
        await batch(objects);
        return;
      }
      final callback = widget.onCanvasObjectDeleted;
      if (callback == null) return;
      for (final object in objects) {
        await callback(object);
      }
    } on Object {
      await _updateCanvasObjects(originalChildren);
      rethrow;
    }
  }

  Iterable<CanvasObject> _visibleNativeCanvasObjects() =>
      (widget.board?.objects ?? const <CanvasObject>[]).where(
        (object) =>
            object.isVisible &&
            object.type != CanvasObjectType.nodeReference &&
            _isWorkshopObjectVisible(object),
      );

  void _setEntitySelection(
    Set<String> nodeIds,
    Set<String> objectIds, {
    required bool toggle,
  }) {
    setState(() {
      if (toggle) {
        for (final id in nodeIds) {
          if (!_selectedNodeIds.remove(id)) _selectedNodeIds.add(id);
        }
        for (final id in objectIds) {
          if (!_selectedCanvasObjectIds.remove(id)) {
            _selectedCanvasObjectIds.add(id);
          }
        }
      } else {
        _selectedNodeIds
          ..clear()
          ..addAll(nodeIds);
        _selectedCanvasObjectIds
          ..clear()
          ..addAll(objectIds);
      }
      _lastSelectedNodeId = _selectedNodeIds.lastOrNull;
      _selectedCanvasObjectId = _selectedCanvasObjectIds.lastOrNull;
      _selectedConnectionKey = null;
      _connectionDrag = null;
    });
    widget.onLocalSelectionChanged?.call(
      _selectedCanvasObjectId ?? _lastSelectedNodeId,
    );
  }

  List<MindmapNode> _filteredNodesForRendering() {
    final focusNode = widget.nodes
        .where((node) => node.id == _focusedNodeId)
        .firstOrNull;
    final focusIds = focusNode == null
        ? const <String>{}
        : <String>{
            focusNode.id,
            ...focusNode.relatedNodeIds,
            for (final node in widget.nodes)
              if (node.relatedNodeIds.contains(focusNode.id)) node.id,
          };
    final hasCanvasSearch =
        _searchQuery.isNotEmpty || _searchCategory != CanvasSearchCategory.all;
    final matchedNodeIds = hasCanvasSearch
        ? <String>{
            for (final result in _navigationIndex.search(
              _searchQuery,
              category: _searchCategory,
            ))
              if (result.nodeId != null) result.nodeId!,
          }
        : const <String>{};
    final nodes = widget.nodes.where((node) {
      return (!hasCanvasSearch || matchedNodeIds.contains(node.id)) &&
          (_searchTypeFilter == null || node.type == _searchTypeFilter) &&
          (_reviewStateFilter == null ||
              node.reviewState == _reviewStateFilter) &&
          (!_nextActionOnly || node.isNextActionCandidate(DateTime.now())) &&
          (focusNode == null || focusIds.contains(node.id));
    }).toList();
    if (_nextActionOnly) {
      nodes.sort(
        (a, b) => b
            .nextActionScore(DateTime.now())
            .compareTo(a.nextActionScore(DateTime.now())),
      );
    }
    return nodes;
  }

  void _selectAllCanvasObjects() {
    _setEntitySelection(
      _filteredNodesForRendering().map((node) => node.id).toSet(),
      _visibleNativeCanvasObjects().map((object) => object.id).toSet(),
      toggle: false,
    );
  }

  Future<bool> _copySelectedCanvasObjects() async {
    final objects = _selectedCanvasObjects()
        .where((object) => object.type != CanvasObjectType.nodeReference)
        .toList();
    if (objects.isEmpty) return false;
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode(<String, Object?>{
          'varCanvasObjects': 1,
          'objects': <Map<String, Object?>>[
            for (final object in objects) object.toJson(),
          ],
        }),
      ),
    );
    return true;
  }

  Future<bool> _pasteCanvasObjects({String? clipboardText}) async {
    if (!_canCreateCanvasObjects) return false;
    final clipboard = clipboardText == null
        ? await Clipboard.getData(Clipboard.kTextPlain)
        : null;
    final raw = clipboardText ?? clipboard?.text;
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          (decoded['varCanvasObjects'] != 1 &&
              decoded['kind'] != 'var.mindmap.selection')) {
        return false;
      }
      final values = decoded['objects'];
      if (values is! List) return false;
      final source = values
          .whereType<Map<Object?, Object?>>()
          .map(
            (value) => CanvasObject.fromJson(Map<String, Object?>.from(value)),
          )
          .where(
            (object) =>
                object.id.isNotEmpty &&
                object.type != CanvasObjectType.nodeReference,
          )
          .toList();
      if (source.isEmpty) return false;
      final ids = <String, String>{
        for (final object in source) object.id: const Uuid().v4(),
      };
      final now = DateTime.now();
      final copies = <CanvasObject>[
        for (final object in source)
          CanvasObject(
            id: ids[object.id]!,
            type: object.type,
            rawType: object.rawType,
            geometry: object.geometry.copyWith(
              x: object.geometry.x + 24,
              y: object.geometry.y + 24,
            ),
            zIndex: object.zIndex + 1,
            isLocked: object.isLocked,
            isVisible: object.isVisible,
            parentFrameId: ids[object.parentFrameId],
            payload: object.payload,
            createdAt: now,
            updatedAt: now,
          ),
      ];
      await _createCanvasObjects(copies);
      if (mounted) {
        setState(() {
          _selectedCanvasObjectIds
            ..clear()
            ..addAll(copies.map((object) => object.id));
          _selectedCanvasObjectId = copies.last.id;
          _selectedNodeIds.clear();
        });
      }
      return true;
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  Future<void> _cutSelectedCanvasObjects() async {
    if (!await _copySelectedCanvasObjects()) return;
    if (!_canDeleteCanvasObjects) return;
    final objects = _selectedCanvasObjects()
        .where(
          (object) =>
              !object.isLocked && object.type != CanvasObjectType.nodeReference,
        )
        .toList();
    await _deleteCanvasObjects(objects);
    if (mounted) {
      setState(() {
        _selectedCanvasObjectIds.clear();
        _selectedCanvasObjectId = null;
      });
    }
  }

  List<CanvasObject> _canvasObjectsMovingWith(CanvasObject object) {
    final board = widget.board;
    final currentObject = board?.objectById(object.id) ?? object;
    if ((currentObject.type == CanvasObjectType.frame ||
            currentObject.type == CanvasObjectType.column) &&
        board != null) {
      return <CanvasObject>[
        currentObject,
        ...board.objects.where(
          (candidate) => currentObject.type == CanvasObjectType.frame
              ? candidate.parentFrameId == currentObject.id
              : candidate.parentColumnId == currentObject.id,
        ),
      ];
    }
    if (currentObject.parentFrameId != null && board != null) {
      final parent = board.objectById(currentObject.parentFrameId!);
      if (parent?.type == CanvasObjectType.frame) {
        return _selectedCanvasObjectIds.contains(currentObject.id)
            ? _selectedCanvasObjects()
            : <CanvasObject>[currentObject];
      }
      return board.objects
          .where(
            (candidate) =>
                candidate.parentFrameId == currentObject.parentFrameId,
          )
          .toList();
    }
    return _selectedCanvasObjectIds.contains(currentObject.id)
        ? _selectedCanvasObjects()
        : <CanvasObject>[currentObject];
  }

  void _selectCanvasObject(CanvasObject object) {
    final currentObject = widget.board?.objectById(object.id) ?? object;
    if (currentObject.type == CanvasObjectType.nodeReference &&
        widget.nodes.any((node) => node.id == currentObject.mindmapNodeId)) {
      return;
    }
    final openComments = _isCanvasCommentToolActive;
    final parent = currentObject.parentFrameId == null
        ? null
        : widget.board?.objectById(currentObject.parentFrameId!);
    final groupedIds =
        currentObject.parentFrameId == null ||
            parent?.type == CanvasObjectType.frame
        ? <String>{currentObject.id}
        : widget.board?.objects
                  .where(
                    (candidate) =>
                        candidate.parentFrameId == currentObject.parentFrameId,
                  )
                  .map((candidate) => candidate.id)
                  .toSet() ??
              <String>{currentObject.id};
    final isMultiSelect =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    setState(() {
      if (isMultiSelect) {
        if (_selectedCanvasObjectIds.contains(currentObject.id)) {
          _selectedCanvasObjectIds.removeAll(groupedIds);
        } else {
          _selectedCanvasObjectIds.addAll(groupedIds);
        }
      } else {
        _selectedCanvasObjectIds
          ..clear()
          ..addAll(groupedIds);
      }
      _selectedCanvasObjectId =
          _selectedCanvasObjectIds.contains(currentObject.id)
          ? currentObject.id
          : _selectedCanvasObjectIds.firstOrNull;
      if (!isMultiSelect) {
        _selectedNodeIds.clear();
        _lastSelectedNodeId = null;
      }
      _selectedConnectionKey = null;
      if (openComments) _isCanvasCommentToolActive = false;
    });
    _canvasFocusNode.requestFocus();
    if (openComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showCanvasObjectComments());
      });
    }
  }

  void _startCanvasObjectMove(Offset globalPosition) {
    _resetNodeGuideState();
    _canvasObjectDragGlobalPosition = globalPosition;
  }

  void _moveCanvasObjectFromGlobal(CanvasObject object, Offset globalPosition) {
    final previous = _canvasObjectDragGlobalPosition;
    _canvasObjectDragGlobalPosition = globalPosition;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final local = box.globalToLocal(globalPosition);
      final scene = _transformationController.toScene(local);
      _canvasObjectDropBoardPosition = _sceneBounds.sceneToWorld(scene);
    }
    if (previous == null) return;
    final scale = _canvasScale(_transformationController.value);
    _moveCanvasObject(object, (globalPosition - previous) / scale);
  }

  void _moveCanvasObject(CanvasObject object, Offset delta) {
    if (object.isLocked ||
        (!_workshopPolicy.canMoveAndGroup &&
            !_workshopPolicy.canEditOwn &&
            !_workshopPolicy.canEditOthers)) {
      return;
    }
    final scale = _canvasScale(_transformationController.value);
    final sceneDelta = delta;
    final movingObjects = _canvasObjectsMovingWith(object);
    final movingNodes = object.type == CanvasObjectType.frame
        ? widget.nodes
              .where(
                (node) =>
                    node.data['groupId'] == object.id &&
                    node.data['groupLocked'] != true,
              )
              .toList(growable: false)
        : const <MindmapNode>[];
    final movingIds = movingObjects.map((candidate) => candidate.id).toSet();
    for (final movingNode in movingNodes) {
      final current = _dragPositions.putIfAbsent(
        movingNode.id,
        () => _positionFor(movingNode),
      );
      _dragPositions[movingNode.id] = CanvasPosition(
        current.dx + sceneDelta.dx,
        current.dy + sceneDelta.dy,
      );
    }
    for (final movingObject in movingObjects) {
      if (movingObject.isLocked) continue;
      final raw = _canvasObjectRawDragGeometries.putIfAbsent(
        movingObject.id,
        () => _canvasObjectGeometry(movingObject),
      );
      _canvasObjectRawDragGeometries[movingObject.id] = raw.copyWith(
        x: raw.x + sceneDelta.dx,
        y: raw.y + sceneDelta.dy,
      );
    }
    final proposed = _canvasObjectRawDragGeometries[object.id]!;
    final candidates =
        _indexedCanvasObjects(
          spatial.CanvasBounds.fromLTWH(
            proposed.x,
            proposed.y,
            proposed.width,
            proposed.height,
          ).inflate(500 / math.max(scale, 0.01)),
        ).where(
          (candidate) =>
              candidate.isVisible && !movingIds.contains(candidate.id),
        );
    final engageGuides = _findCanvasSmartGuides(proposed, <_SmartGuideGeometry>[
      for (final candidate in candidates)
        _SmartGuideGeometry(
          'native:${candidate.type.name}:${candidate.id}',
          candidate.type == CanvasObjectType.connector
              ? _effectiveConnector(candidate).geometry
              : _canvasObjectGeometry(candidate),
        ),
      ..._liveNodeGuideGeometries(excludedNodeIds: const <String>{}),
    ], screenScale: scale);
    final previous = _canvasObjectEngagedGuides;
    final releaseThreshold = 12 / math.max(scale, 0.01);
    final keepVertical =
        previous?.vertical != null &&
        engageGuides?.verticalIdentity == _canvasObjectVerticalGuideIdentity &&
        _canvasObjectSnapRawX != null &&
        (proposed.x - _canvasObjectSnapRawX!).abs() <= releaseThreshold;
    final keepHorizontal =
        previous?.horizontal != null &&
        engageGuides?.horizontalIdentity ==
            _canvasObjectHorizontalGuideIdentity &&
        _canvasObjectSnapRawY != null &&
        (proposed.y - _canvasObjectSnapRawY!).abs() <= releaseThreshold;
    if (previous?.vertical != null && !keepVertical) {
      _canvasObjectReleasedVerticalIdentity =
          _canvasObjectVerticalGuideIdentity;
    }
    if (previous?.horizontal != null && !keepHorizontal) {
      _canvasObjectReleasedHorizontalIdentity =
          _canvasObjectHorizontalGuideIdentity;
    }
    _canvasObjectSnapReleasedX =
        engageGuides?.vertical != null &&
        engageGuides!.verticalIdentity == _canvasObjectReleasedVerticalIdentity;
    _canvasObjectSnapReleasedY =
        engageGuides?.horizontal != null &&
        engageGuides!.horizontalIdentity ==
            _canvasObjectReleasedHorizontalIdentity;
    if (engageGuides?.verticalIdentity !=
        _canvasObjectReleasedVerticalIdentity) {
      _canvasObjectReleasedVerticalIdentity = null;
    }
    if (engageGuides?.horizontalIdentity !=
        _canvasObjectReleasedHorizontalIdentity) {
      _canvasObjectReleasedHorizontalIdentity = null;
    }
    final nextVertical = _canvasObjectSnapReleasedX
        ? null
        : engageGuides?.vertical;
    final nextHorizontal = _canvasObjectSnapReleasedY
        ? null
        : engageGuides?.horizontal;
    if (!keepVertical) {
      _canvasObjectSnapRawX = nextVertical == null ? null : proposed.x;
      _canvasObjectInitialCorrectionX = nextVertical == null
          ? null
          : engageGuides!.dx;
      _canvasObjectVerticalGuideIdentity = nextVertical == null
          ? null
          : engageGuides!.verticalIdentity;
    }
    if (!keepHorizontal) {
      _canvasObjectSnapRawY = nextHorizontal == null ? null : proposed.y;
      _canvasObjectInitialCorrectionY = nextHorizontal == null
          ? null
          : engageGuides!.dy;
      _canvasObjectHorizontalGuideIdentity = nextHorizontal == null
          ? null
          : engageGuides!.horizontalIdentity;
    }
    final dx = keepVertical
        ? _canvasObjectInitialCorrectionX! -
              (proposed.x - _canvasObjectSnapRawX!)
        : nextVertical == null
        ? 0.0
        : _canvasObjectInitialCorrectionX!;
    final dy = keepHorizontal
        ? _canvasObjectInitialCorrectionY! -
              (proposed.y - _canvasObjectSnapRawY!)
        : nextHorizontal == null
        ? 0.0
        : _canvasObjectInitialCorrectionY!;
    final guides = _CanvasSmartGuides(
      vertical: keepVertical
          ? previous!.vertical
          : _canvasObjectSnapReleasedX
          ? null
          : engageGuides?.vertical,
      horizontal: keepHorizontal
          ? previous!.horizontal
          : _canvasObjectSnapReleasedY
          ? null
          : engageGuides?.horizontal,
      dx: dx,
      dy: dy,
      distance:
          engageGuides?.distanceAxis == Axis.horizontal &&
                  !_canvasObjectSnapReleasedX ||
              engageGuides?.distanceAxis == Axis.vertical &&
                  !_canvasObjectSnapReleasedY
          ? engageGuides?.distance
          : null,
      labelPosition:
          engageGuides?.distanceAxis == Axis.horizontal &&
                  !_canvasObjectSnapReleasedX ||
              engageGuides?.distanceAxis == Axis.vertical &&
                  !_canvasObjectSnapReleasedY
          ? engageGuides?.labelPosition
          : null,
      distanceAxis: engageGuides?.distanceAxis,
    );
    if (guides.vertical != null || guides.horizontal != null) {
      _canvasObjectEngagedGuides = guides;
    } else {
      _canvasObjectSnapRawX = null;
      _canvasObjectSnapRawY = null;
      _canvasObjectInitialCorrectionX = null;
      _canvasObjectInitialCorrectionY = null;
      _canvasObjectVerticalGuideIdentity = null;
      _canvasObjectHorizontalGuideIdentity = null;
      _canvasObjectEngagedGuides = null;
    }
    final hasGuides =
        guides.vertical != null ||
        guides.horizontal != null ||
        guides.dx != 0 ||
        guides.dy != 0;
    final smartDelta = Offset(dx, dy);
    final dropTarget = object.isEligibleColumnChild
        ? widget.board?.objects
              .where(
                (candidate) =>
                    candidate.type == CanvasObjectType.column &&
                    candidate.id != object.id &&
                    !candidate.isColumnCollapsed &&
                    Rect.fromLTWH(
                      candidate.geometry.x,
                      candidate.geometry.y,
                      candidate.geometry.width,
                      candidate.geometry.height,
                    ).contains(
                      Offset(
                        proposed.x + proposed.width / 2,
                        proposed.y + proposed.height / 2,
                      ),
                    ),
              )
              .firstOrNull
        : null;
    _expandSceneToInclude(<Rect>[
      for (final movingObject in movingObjects)
        if (!movingObject.isLocked)
          () {
            final raw = _canvasObjectRawDragGeometries[movingObject.id]!;
            return Rect.fromLTWH(
              raw.x + smartDelta.dx,
              raw.y + smartDelta.dy,
              raw.width,
              raw.height,
            );
          }(),
      for (final movingNode in movingNodes)
        () {
          final position = _dragPositions[movingNode.id]!;
          final size = _nodeSizeFor(movingNode);
          return Rect.fromLTWH(
            position.dx,
            position.dy,
            size.width,
            size.height,
          );
        }(),
    ]);
    setState(() {
      _canvasSmartGuides = hasGuides ? guides : null;
      _columnDropTargetId = dropTarget?.id;
      _columnDropInsertionIndex = dropTarget == null
          ? null
          : const CanvasColumnLayoutEngine()
                .layout(
                  columnGeometry: dropTarget.geometry,
                  orderedChildIds: dropTarget.orderedColumnChildIds
                      .where((id) => id != object.id)
                      .toList(),
                  childGeometries: <String, CanvasGeometry>{
                    for (final id in dropTarget.orderedColumnChildIds)
                      if (widget.board?.objectById(id) case final child?)
                        id: child.geometry,
                  },
                  isCollapsed: false,
                )
                .insertionIndex(
                  Offset(
                    proposed.x + proposed.width / 2,
                    proposed.y + proposed.height / 2,
                  ),
                );
      for (final movingObject in movingObjects) {
        if (movingObject.isLocked) continue;
        final raw = _canvasObjectRawDragGeometries[movingObject.id]!;
        _canvasObjectGeometryOverrides[movingObject.id] = raw.copyWith(
          x: raw.x + smartDelta.dx,
          y: raw.y + smartDelta.dy,
        );
      }
    });
  }

  void _nudgeSelectedCanvasObjects(
    LogicalKeyboardKey key, {
    required bool accelerated,
  }) {
    final selected = _selectedCanvasObjects();
    if (!_canUpdateCanvasObjects ||
        (!_workshopPolicy.canMoveAndGroup &&
            !_workshopPolicy.canEditOwn &&
            !_workshopPolicy.canEditOthers) ||
        selected.isEmpty) {
      return;
    }
    final step = _snapToGrid
        ? (accelerated ? 100.0 : 20.0)
        : (accelerated ? 10.0 : 1.0);
    final delta = switch (key) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => Offset.zero,
    };
    if (delta == Offset.zero) return;
    final moving = <String, CanvasObject>{};
    for (final object in selected) {
      for (final candidate in _canvasObjectsMovingWith(object)) {
        if (!candidate.isLocked) moving[candidate.id] = candidate;
      }
    }
    final now = DateTime.now();
    final updates = <CanvasObject>[
      for (final object in moving.values)
        object.copyWith(
          geometry: _canvasObjectGeometry(object).copyWith(
            x: _canvasObjectGeometry(object).x + delta.dx,
            y: _canvasObjectGeometry(object).y + delta.dy,
          ),
          updatedAt: now,
        ),
    ];
    _expandSceneToInclude(<Rect>[
      for (final update in updates)
        Rect.fromLTWH(
          update.geometry.x,
          update.geometry.y,
          update.geometry.width,
          update.geometry.height,
        ),
    ]);
    setState(() {
      for (final update in updates) {
        _canvasObjectGeometryOverrides[update.id] = update.geometry;
      }
    });
    unawaited(_updateCanvasObjects(updates));
  }

  void _cancelCanvasObjectMove() {
    final movingIds = _canvasObjectRawDragGeometries.keys.toSet();
    _canvasObjectRawDragGeometries.clear();
    _canvasObjectSnapRawX = null;
    _canvasObjectSnapRawY = null;
    _canvasObjectInitialCorrectionX = null;
    _canvasObjectInitialCorrectionY = null;
    _canvasObjectVerticalGuideIdentity = null;
    _canvasObjectHorizontalGuideIdentity = null;
    _canvasObjectEngagedGuides = null;
    _canvasObjectSnapReleasedX = false;
    _canvasObjectSnapReleasedY = false;
    _canvasObjectReleasedVerticalIdentity = null;
    _canvasObjectReleasedHorizontalIdentity = null;
    _canvasObjectDragGlobalPosition = null;
    if (!mounted) return;
    setState(() {
      _canvasObjectGeometryOverrides.removeWhere(
        (id, geometry) => movingIds.contains(id),
      );
      _canvasSmartGuides = null;
    });
  }

  List<CanvasObject>? _columnDropUpdates(
    CanvasObject object,
    CanvasGeometry droppedGeometry,
  ) {
    final board = widget.board;
    if (board == null || !object.isEligibleColumnChild) return null;
    final center =
        _canvasObjectDropBoardPosition ??
        Offset(
          droppedGeometry.x + droppedGeometry.width / 2,
          droppedGeometry.y + droppedGeometry.height / 2,
        );
    final target = board.objects
        .where(
          (candidate) =>
              candidate.type == CanvasObjectType.column &&
              candidate.isVisible &&
              !candidate.isColumnCollapsed &&
              Rect.fromLTWH(
                candidate.geometry.x,
                candidate.geometry.y + CanvasColumnLayoutEngine.headerHeight,
                candidate.geometry.width,
                candidate.geometry.height -
                    CanvasColumnLayoutEngine.headerHeight,
              ).overlaps(
                Rect.fromLTWH(
                  droppedGeometry.x,
                  droppedGeometry.y,
                  droppedGeometry.width,
                  droppedGeometry.height,
                ),
              ),
        )
        .firstOrNull;
    final source = object.parentColumnId == null
        ? null
        : board.objectById(object.parentColumnId!);
    if (target == null && source == null) return null;
    final now = DateTime.now();
    var next = board;
    if (source != null && source.type == CanvasObjectType.column) {
      next = next.reconcileColumnMembership(
        columnId: source.id,
        orderedChildIds: source.orderedColumnChildIds
            .where((id) => id != object.id)
            .toList(),
        now: now,
      );
    }
    if (target == null) {
      final detached = next
          .objectById(object.id)!
          .copyWith(
            geometry: const CanvasColumnLayoutEngine().detachGeometry(
              childGeometry: droppedGeometry,
              dropPosition: center,
            ),
            clearParentColumnId: true,
            updatedAt: now,
          );
      return <CanvasObject>[
        detached,
        if (source != null) next.objectById(source.id)!,
      ];
    }
    final currentIds = target.orderedColumnChildIds
        .where((id) => id != object.id)
        .toList();
    final preliminary = const CanvasColumnLayoutEngine().layout(
      columnGeometry: target.geometry,
      orderedChildIds: currentIds,
      childGeometries: <String, CanvasGeometry>{
        for (final id in currentIds)
          if (next.objectById(id) case final child?) id: child.geometry,
      },
      isCollapsed: false,
    );
    currentIds.insert(preliminary.insertionIndex(center), object.id);
    next = next.reconcileColumnMembership(
      columnId: target.id,
      orderedChildIds: currentIds,
      now: now,
    );
    final nextTarget = next.objectById(target.id)!;
    final layout = const CanvasColumnLayoutEngine().layout(
      columnGeometry: nextTarget.geometry,
      orderedChildIds: currentIds,
      childGeometries: <String, CanvasGeometry>{
        for (final id in currentIds)
          id: id == object.id ? droppedGeometry : next.objectById(id)!.geometry,
      },
      isCollapsed: false,
    );
    return <CanvasObject>[
      nextTarget.copyWith(geometry: layout.columnGeometry, updatedAt: now),
      for (final entry in layout.childBounds.entries)
        next
            .objectById(entry.key)!
            .copyWith(
              geometry: CanvasGeometry(
                x: entry.value.left,
                y: entry.value.top,
                width: entry.value.width,
                height: entry.value.height,
              ),
              updatedAt: now,
            ),
      if (source != null && source.id != target.id) next.objectById(source.id)!,
    ];
  }

  void _finishCanvasObjectMove(CanvasObject object) {
    if (!_canUpdateCanvasObjects) {
      _canvasObjectRawDragGeometries.clear();
      _canvasObjectSnapRawX = null;
      _canvasObjectSnapRawY = null;
      _canvasObjectInitialCorrectionX = null;
      _canvasObjectInitialCorrectionY = null;
      _canvasObjectVerticalGuideIdentity = null;
      _canvasObjectHorizontalGuideIdentity = null;
      _canvasObjectEngagedGuides = null;
      _canvasObjectSnapReleasedX = false;
      _canvasObjectSnapReleasedY = false;
      _canvasObjectReleasedVerticalIdentity = null;
      _canvasObjectReleasedHorizontalIdentity = null;
      _canvasObjectDragGlobalPosition = null;
      if (mounted) setState(() => _canvasSmartGuides = null);
      return;
    }
    final board = widget.board;
    final movingObjects = _canvasObjectsMovingWith(object);
    var snapDelta = Offset.zero;
    final primaryGeometry = _canvasObjectGeometryOverrides[object.id];
    if (_snapToGrid && primaryGeometry != null) {
      const gridSize = 20.0;
      snapDelta = Offset(
        _canvasSmartGuides?.vertical == null
            ? (primaryGeometry.x / gridSize).round() * gridSize -
                  primaryGeometry.x
            : 0,
        _canvasSmartGuides?.horizontal == null
            ? (primaryGeometry.y / gridSize).round() * gridSize -
                  primaryGeometry.y
            : 0,
      );
      setState(() {
        for (final movingObject in movingObjects) {
          final geometry = _canvasObjectGeometryOverrides[movingObject.id];
          if (geometry == null || movingObject.isLocked) continue;
          _canvasObjectGeometryOverrides[movingObject.id] = geometry.copyWith(
            x: geometry.x + snapDelta.dx,
            y: geometry.y + snapDelta.dy,
          );
        }
      });
    }
    final movingNodes = object.type == CanvasObjectType.frame
        ? widget.nodes
              .where(
                (node) =>
                    node.data['groupId'] == object.id &&
                    node.data['groupLocked'] != true,
              )
              .toList(growable: false)
        : const <MindmapNode>[];
    if (movingNodes.isNotEmpty) {
      unawaited(
        _persistMovedNodes(movingNodes, <String, CanvasPosition>{
          for (final node in movingNodes) node.id: _positionFor(node),
        }),
      );
    }
    if (object.type == CanvasObjectType.column && board != null) {
      final columnGeometry =
          _canvasObjectGeometryOverrides[object.id] ?? object.geometry;
      final layout = const CanvasColumnLayoutEngine().layout(
        columnGeometry: columnGeometry,
        orderedChildIds: object.orderedColumnChildIds,
        childGeometries: <String, CanvasGeometry>{
          for (final id in object.orderedColumnChildIds)
            if (board.objectById(id) case final child?) id: child.geometry,
        },
        isCollapsed: object.isColumnCollapsed,
      );
      _canvasObjectGeometryOverrides[object.id] = layout.columnGeometry;
      for (final entry in layout.childBounds.entries) {
        final child = board.objectById(entry.key);
        if (child == null) continue;
        _canvasObjectGeometryOverrides[entry.key] = CanvasGeometry(
          x: entry.value.left,
          y: entry.value.top,
          width: entry.value.width,
          height: entry.value.height,
        );
      }
    }
    final movingIds = <String>{
      ...movingObjects.map((candidate) => candidate.id),
      if (object.type == CanvasObjectType.column)
        ...object.orderedColumnChildIds,
    };
    final columnUpdates =
        primaryGeometry == null || object.type == CanvasObjectType.column
        ? null
        : _columnDropUpdates(object, _canvasObjectGeometry(object));
    _expandSceneForContent();
    final updates =
        columnUpdates ??
        movingIds
            .map((id) {
              final candidate = board?.objectById(id);
              final geometry = _canvasObjectGeometryOverrides[id];
              if (candidate == null ||
                  geometry == null ||
                  (candidate.isLocked &&
                      object.type != CanvasObjectType.column)) {
                return null;
              }
              final moved = candidate.copyWith(
                geometry: geometry,
                updatedAt: DateTime.now(),
              );
              if (candidate.type == CanvasObjectType.frame) return moved;
              final currentParent = candidate.parentFrameId == null
                  ? null
                  : board?.objectById(candidate.parentFrameId!);
              if (currentParent != null &&
                  currentParent.type != CanvasObjectType.frame) {
                return moved;
              }
              final frame = _frameContainingGeometry(
                geometry,
                excludeId: candidate.id,
              );
              return moved.copyWith(
                parentFrameId: frame?.id,
                clearParentFrameId: frame == null,
              );
            })
            .nonNulls
            .toList();
    unawaited(_updateCanvasObjects(updates));
    _canvasObjectRawDragGeometries.removeWhere(
      (id, geometry) => movingIds.contains(id),
    );
    _canvasObjectSnapRawX = null;
    _canvasObjectSnapRawY = null;
    _canvasObjectInitialCorrectionX = null;
    _canvasObjectInitialCorrectionY = null;
    _canvasObjectVerticalGuideIdentity = null;
    _canvasObjectHorizontalGuideIdentity = null;
    _canvasObjectEngagedGuides = null;
    _canvasObjectSnapReleasedX = false;
    _canvasObjectSnapReleasedY = false;
    _canvasObjectReleasedVerticalIdentity = null;
    _canvasObjectReleasedHorizontalIdentity = null;
    _canvasObjectDragGlobalPosition = null;
    _canvasObjectDropBoardPosition = null;
    if (mounted) {
      setState(() {
        _canvasSmartGuides = null;
        _columnDropTargetId = null;
        _columnDropInsertionIndex = null;
      });
    }
  }

  void _resizeCanvasObject(CanvasObject object, Offset delta) {
    if (object.isLocked ||
        (!_workshopPolicy.canEditOwn && !_workshopPolicy.canEditOthers)) {
      return;
    }
    final sceneDelta = delta;
    final current = _canvasObjectGeometry(object);
    final minimumWidth = object.type == CanvasObjectType.column
        ? minimumCanvasColumnWidth
        : 80.0;
    final geometry = current.copyWith(
      width: _snappedCanvasSize(
        math.max(minimumWidth, current.width + sceneDelta.dx),
        minimum: minimumWidth,
      ),
      height: _snappedCanvasSize(
        math.max(60, current.height + sceneDelta.dy),
        minimum: 60,
      ),
    );
    _expandSceneToInclude(<Rect>[
      Rect.fromLTWH(geometry.x, geometry.y, geometry.width, geometry.height),
    ]);
    setState(() => _canvasObjectGeometryOverrides[object.id] = geometry);
  }

  double _snappedCanvasSize(double value, {required double minimum}) {
    if (!_snapToGrid) return value;
    const gridSize = 20.0;
    return math.max(minimum, (value / gridSize).round() * gridSize);
  }

  void _cycleCanvasObjectColor() {
    final object = _selectedCanvasObject();
    if (object == null || object.isLocked || !_canUpdateCanvasObjects) return;
    const colors = <String>['amber', 'blue', 'green', 'rose'];
    final current = object.payload['color'] as String?;
    final next = colors[(colors.indexOf(current ?? '') + 1) % colors.length];
    unawaited(
      _updateCanvasObjects(<CanvasObject>[
        object.copyWith(
          payload: <String, Object?>{...object.payload, 'color': next},
          updatedAt: DateTime.now(),
        ),
      ]),
    );
  }

  void _cycleCanvasShape() {
    final object = _selectedCanvasObject();
    final callback = widget.onCanvasObjectUpdated;
    if (object == null ||
        object.type != CanvasObjectType.shape ||
        object.isLocked ||
        callback == null) {
      return;
    }
    const shapes = <String>['roundedRectangle', 'rectangle', 'ellipse'];
    final current = object.payload['shape'] as String?;
    final next = shapes[(shapes.indexOf(current ?? '') + 1) % shapes.length];
    callback(
      object.copyWith(
        payload: <String, Object?>{...object.payload, 'shape': next},
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _toggleCanvasObjectLock() {
    final objects = _selectedCanvasObjects();
    if (objects.isEmpty || !_canUpdateCanvasObjects) return;
    final shouldLock = objects.any((object) => !object.isLocked);
    unawaited(
      _updateCanvasObjects(<CanvasObject>[
        for (final object in objects)
          object.copyWith(isLocked: shouldLock, updatedAt: DateTime.now()),
      ]),
    );
  }

  void _rotateSelectedCanvasObjects(double delta, {bool reset = false}) {
    final objects = _selectedCanvasObjects().where(
      (object) => !object.isLocked,
    );
    if (!_canUpdateCanvasObjects || objects.isEmpty) return;
    final now = DateTime.now();
    unawaited(
      _updateCanvasObjects(<CanvasObject>[
        for (final object in objects)
          object.copyWith(
            geometry: object.geometry.copyWith(
              rotation: reset
                  ? 0
                  : _normalizeCanvasRotation(object.geometry.rotation + delta),
            ),
            updatedAt: now,
          ),
      ]),
    );
  }

  void _moveCanvasObjectToLayer({required bool front}) {
    final board = widget.board;
    final selected = _selectedCanvasObjects()
        .where((object) => !object.isLocked)
        .toList();
    if (board == null || selected.isEmpty || !_canUpdateCanvasObjects) return;
    final now = DateTime.now();
    final updates = <CanvasObject>[];
    for (final partition in <bool>[true, false]) {
      final peers = board.objects.where(
        (object) => (object.type == CanvasObjectType.frame) == partition,
      );
      final partitionSelected =
          selected
              .where(
                (object) =>
                    (object.type == CanvasObjectType.frame) == partition,
              )
              .toList()
            ..sort((left, right) => left.zIndex.compareTo(right.zIndex));
      if (partitionSelected.isEmpty) continue;
      final edge = peers.fold<int>(
        partitionSelected.first.zIndex,
        (value, object) => front
            ? math.max(value, object.zIndex)
            : math.min(value, object.zIndex),
      );
      for (var index = 0; index < partitionSelected.length; index++) {
        final object = partitionSelected[index];
        final zIndex = front
            ? edge + index + 1
            : edge - partitionSelected.length + index;
        updates.add(object.copyWith(zIndex: zIndex, updatedAt: now));
      }
    }
    unawaited(_updateCanvasObjects(updates));
  }

  void _duplicateCanvasObject() {
    final objects = _selectedCanvasObjects();
    if (objects.isEmpty || !_canCreateCanvasObjects) return;
    final now = DateTime.now();
    final groupId = objects.length > 1 ? const Uuid().v4() : null;
    final duplicates = objects
        .map(
          (object) => CanvasObject(
            id: const Uuid().v4(),
            type: object.type,
            rawType: object.rawType,
            geometry: object.geometry.copyWith(
              x: object.geometry.x + 24,
              y: object.geometry.y + 24,
            ),
            zIndex: object.zIndex + 1,
            isVisible: object.isVisible,
            parentFrameId: groupId ?? object.parentFrameId,
            mindmapNodeId: object.mindmapNodeId,
            payload: object.payload,
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList();
    setState(() {
      _selectedCanvasObjectId = duplicates.last.id;
      _selectedCanvasObjectIds
        ..clear()
        ..addAll(duplicates.map((object) => object.id));
    });
    unawaited(_createCanvasObjects(duplicates));
  }

  void _groupSelectedCanvasObjects() {
    final objects = _selectedCanvasObjects();
    if (objects.length < 2 || !_canUpdateCanvasObjects) return;
    final groupId = const Uuid().v4();
    unawaited(
      _updateCanvasObjects(<CanvasObject>[
        for (final object in objects)
          object.copyWith(parentFrameId: groupId, updatedAt: DateTime.now()),
      ]),
    );
  }

  void _ungroupSelectedCanvasObjects() {
    final objects = _selectedCanvasObjects();
    if (objects.isEmpty || !_canUpdateCanvasObjects) return;
    unawaited(
      _updateCanvasObjects(<CanvasObject>[
        for (final object in objects)
          if (object.parentFrameId != null)
            object.copyWith(
              clearParentFrameId: true,
              updatedAt: DateTime.now(),
            ),
      ]),
    );
  }

  void _changeSelectedCanvasObjectVotes(int delta) {
    final objects = _selectedCanvasObjects();
    if (objects.isEmpty || !_workshopPolicy.canVote || delta == 0) return;
    final callback = widget.onCanvasVoteChanged;
    if (callback != null) {
      unawaited(Future<void>.sync(() => callback(objects, delta)));
      return;
    }
    if (!_canUpdateCanvasObjects) return;
    final now = DateTime.now();
    unawaited(
      _updateCanvasObjects(<CanvasObject>[
        for (final object in objects)
          object.withVoteCount(object.voteCount + delta, updatedAt: now),
      ]),
    );
  }

  Future<void> _showCanvasObjectComments() async {
    final selected = _selectedCanvasObject();
    if (selected == null ||
        (!_canUpdateCanvasObjects &&
            widget.onCollaborationBoardCommentsChanged == null)) {
      return;
    }
    var comments =
        widget.collaborationBoardComments[selected.id] ?? selected.comments;
    String? replyToId;
    var composerText = '';
    var composerRevision = 0;
    var submitting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final roots = comments
              .where((comment) => comment.parentId == null)
              .toList();
          Future<void> persist(List<CanvasObjectComment> next) async {
            setDialogState(() => submitting = true);
            final remoteCallback = widget.onCollaborationBoardCommentsChanged;
            if (remoteCallback != null) {
              await remoteCallback(selected.id, next);
            } else {
              final current = widget.board?.objectById(selected.id) ?? selected;
              await _updateCanvasObjects(<CanvasObject>[
                current.withComments(next, updatedAt: DateTime.now()),
              ]);
            }
            if (!dialogContext.mounted) return;
            setDialogState(() {
              comments = next;
              submitting = false;
            });
          }

          Future<void> submit() async {
            final body = composerText.trim();
            if (body.isEmpty || body.length > 4000 || submitting) return;
            final next = <CanvasObjectComment>[
              ...comments,
              CanvasObjectComment(
                id: const Uuid().v4(),
                body: body,
                authorName:
                    widget.collaborationState?.localName.trim().isNotEmpty ==
                        true
                    ? widget.collaborationState!.localName
                    : 'You',
                createdAt: DateTime.now(),
                parentId: replyToId,
              ),
            ];
            setDialogState(() {
              composerText = '';
              composerRevision++;
              replyToId = null;
            });
            await persist(next);
          }

          Future<void> toggleResolved(CanvasObjectComment root) =>
              persist(<CanvasObjectComment>[
                for (final comment in comments)
                  if (comment.id == root.id)
                    comment.copyWith(isResolved: !root.isResolved)
                  else
                    comment,
              ]);

          return AlertDialog(
            title: const Text('Object comments'),
            content: SizedBox(
              width: 520,
              height: 480,
              child: Column(
                children: [
                  Expanded(
                    child: roots.isEmpty
                        ? const Center(child: Text('No comments yet.'))
                        : ListView.builder(
                            itemCount: roots.length,
                            itemBuilder: (context, index) {
                              final root = roots[index];
                              final replies = comments
                                  .where(
                                    (comment) => comment.parentId == root.id,
                                  )
                                  .toList();
                              return Card(
                                key: ValueKey('canvas-comment-${root.id}'),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              root.authorName,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelLarge,
                                            ),
                                          ),
                                          if (root.isResolved)
                                            const Chip(
                                              label: Text('Resolved'),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(root.body),
                                      for (final reply in replies)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            12,
                                            0,
                                            0,
                                          ),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              border: Border(
                                                left: BorderSide(
                                                  color: Theme.of(
                                                    context,
                                                  ).dividerColor,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                left: 10,
                                              ),
                                              child: Text(
                                                '${reply.authorName}: ${reply.body}',
                                              ),
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          TextButton(
                                            key: ValueKey(
                                              'canvas-comment-reply-${root.id}',
                                            ),
                                            onPressed: root.isResolved
                                                ? null
                                                : () => setDialogState(
                                                    () => replyToId = root.id,
                                                  ),
                                            child: const Text('Reply'),
                                          ),
                                          TextButton(
                                            key: ValueKey(
                                              'canvas-comment-resolve-${root.id}',
                                            ),
                                            onPressed: submitting
                                                ? null
                                                : () => toggleResolved(root),
                                            child: Text(
                                              root.isResolved
                                                  ? 'Reopen'
                                                  : 'Resolve',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (replyToId != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        label: const Text('Replying to thread'),
                        onDeleted: () => setDialogState(() => replyToId = null),
                      ),
                    ),
                  TextField(
                    key: ValueKey('canvas-comment-composer-$composerRevision'),
                    onChanged: (value) => composerText = value,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Comment',
                      hintText: 'Write a comment',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              FilledButton(
                key: const ValueKey('canvas-comment-send'),
                onPressed: submitting ? null : submit,
                child: const Text('Send'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _layoutSelectedCanvasObjects(_CanvasObjectAction action) {
    final objects = _selectedCanvasObjects()
        .where((object) => !object.isLocked)
        .toList();
    final minimumCount = switch (action) {
      _CanvasObjectAction.distributeHorizontal ||
      _CanvasObjectAction.distributeVertical => 3,
      _ => 2,
    };
    if (!_canUpdateCanvasObjects || objects.length < minimumCount) return;
    final geometries = <String, CanvasGeometry>{
      for (final object in objects) object.id: _canvasObjectGeometry(object),
    };
    final left = geometries.values
        .map((geometry) => geometry.x)
        .reduce(math.min);
    final top = geometries.values
        .map((geometry) => geometry.y)
        .reduce(math.min);
    final right = geometries.values
        .map((geometry) => geometry.x + geometry.width)
        .reduce(math.max);
    final bottom = geometries.values
        .map((geometry) => geometry.y + geometry.height)
        .reduce(math.max);
    final updates = <CanvasObject>[];

    if (action == _CanvasObjectAction.distributeHorizontal ||
        action == _CanvasObjectAction.distributeVertical) {
      final horizontal = action == _CanvasObjectAction.distributeHorizontal;
      objects.sort((first, second) {
        final firstGeometry = geometries[first.id]!;
        final secondGeometry = geometries[second.id]!;
        return (horizontal ? firstGeometry.x : firstGeometry.y).compareTo(
          horizontal ? secondGeometry.x : secondGeometry.y,
        );
      });
      final totalSize = objects.fold<double>(0, (sum, object) {
        final geometry = geometries[object.id]!;
        return sum + (horizontal ? geometry.width : geometry.height);
      });
      final gap =
          ((horizontal ? right - left : bottom - top) - totalSize) /
          (objects.length - 1);
      var cursor = horizontal ? left : top;
      for (final object in objects) {
        final geometry = geometries[object.id]!;
        updates.add(
          object.copyWith(
            geometry: geometry.copyWith(
              x: horizontal ? cursor : geometry.x,
              y: horizontal ? geometry.y : cursor,
            ),
            updatedAt: DateTime.now(),
          ),
        );
        cursor += (horizontal ? geometry.width : geometry.height) + gap;
      }
    } else {
      for (final object in objects) {
        final geometry = geometries[object.id]!;
        final next = switch (action) {
          _CanvasObjectAction.alignLeft => geometry.copyWith(x: left),
          _CanvasObjectAction.alignCenter => geometry.copyWith(
            x: (left + right - geometry.width) / 2,
          ),
          _CanvasObjectAction.alignRight => geometry.copyWith(
            x: right - geometry.width,
          ),
          _CanvasObjectAction.alignTop => geometry.copyWith(y: top),
          _CanvasObjectAction.alignMiddle => geometry.copyWith(
            y: (top + bottom - geometry.height) / 2,
          ),
          _CanvasObjectAction.alignBottom => geometry.copyWith(
            y: bottom - geometry.height,
          ),
          _ => geometry,
        };
        updates.add(object.copyWith(geometry: next, updatedAt: DateTime.now()));
      }
    }
    unawaited(_updateCanvasObjects(updates));
  }

  Future<void> _showCanvasObjectContextMenu(
    CanvasObject object,
    Offset globalPosition,
  ) async {
    _selectCanvasObject(object);
    final action = await showMenu<_CanvasObjectAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        MediaQuery.sizeOf(context).width - globalPosition.dx,
        MediaQuery.sizeOf(context).height - globalPosition.dy,
      ),
      items: <PopupMenuEntry<_CanvasObjectAction>>[
        const PopupMenuItem(
          key: ValueKey('mindmap-canvas-object-context-properties'),
          value: _CanvasObjectAction.properties,
          child: Text('Edit properties'),
        ),
        const PopupMenuItem(
          value: _CanvasObjectAction.duplicate,
          child: Text('Duplicate'),
        ),
        PopupMenuItem(
          value: _CanvasObjectAction.toggleLock,
          child: Text(object.isLocked ? 'Unlock' : 'Lock'),
        ),
        const PopupMenuItem(
          value: _CanvasObjectAction.rotateLeft,
          child: Text('Rotate -15°'),
        ),
        const PopupMenuItem(
          value: _CanvasObjectAction.rotateRight,
          child: Text('Rotate +15°'),
        ),
        const PopupMenuItem(
          value: _CanvasObjectAction.resetRotation,
          child: Text('Reset rotation'),
        ),
        const PopupMenuItem(
          value: _CanvasObjectAction.sendBack,
          child: Text('Send to back'),
        ),
        const PopupMenuItem(
          value: _CanvasObjectAction.bringFront,
          child: Text('Bring to front'),
        ),
        ?_voteMenuItem(object),
        const PopupMenuItem(
          value: _CanvasObjectAction.comments,
          child: Text('Comments'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          key: ValueKey('mindmap-canvas-object-context-delete'),
          value: _CanvasObjectAction.delete,
          child: Text('Delete'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    _runCanvasObjectAction(action);
  }

  void _runCanvasObjectAction(_CanvasObjectAction action) {
    switch (action) {
      case _CanvasObjectAction.properties:
        unawaited(_showCanvasObjectProperties());
      case _CanvasObjectAction.duplicate:
        _duplicateCanvasObject();
      case _CanvasObjectAction.toggleLock:
        _toggleCanvasObjectLock();
      case _CanvasObjectAction.rotateLeft:
        _rotateSelectedCanvasObjects(-math.pi / 12);
      case _CanvasObjectAction.rotateRight:
        _rotateSelectedCanvasObjects(math.pi / 12);
      case _CanvasObjectAction.resetRotation:
        _rotateSelectedCanvasObjects(0, reset: true);
      case _CanvasObjectAction.sendBack:
        _moveCanvasObjectToLayer(front: false);
      case _CanvasObjectAction.bringFront:
        _moveCanvasObjectToLayer(front: true);
      case _CanvasObjectAction.group:
        _groupSelectedCanvasObjects();
      case _CanvasObjectAction.ungroup:
        _ungroupSelectedCanvasObjects();
      case _CanvasObjectAction.addVote:
        _changeSelectedCanvasObjectVotes(1);
      case _CanvasObjectAction.removeVote:
        _changeSelectedCanvasObjectVotes(-1);
      case _CanvasObjectAction.comments:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_showCanvasObjectComments());
        });
      case _CanvasObjectAction.alignLeft:
      case _CanvasObjectAction.alignCenter:
      case _CanvasObjectAction.alignRight:
      case _CanvasObjectAction.alignTop:
      case _CanvasObjectAction.alignMiddle:
      case _CanvasObjectAction.alignBottom:
      case _CanvasObjectAction.distributeHorizontal:
      case _CanvasObjectAction.distributeVertical:
        _layoutSelectedCanvasObjects(action);
      case _CanvasObjectAction.delete:
        _deleteSelectedCanvasObject();
    }
  }

  Future<void> _showCanvasObjectProperties() async {
    final object = _selectedCanvasObject();
    if (object == null || !_canUpdateCanvasObjects) return;
    var fillColor = object.payload['fillColor'] as String? ?? '#4F7CFF';
    var borderColor = object.payload['borderColor'] as String? ?? '#FFFFFF';
    var borderWidth = (object.payload['borderWidth'] as num?)?.toDouble() ?? 1;
    var opacity = (object.payload['opacity'] as num?)?.toDouble() ?? 1;
    var shape = object.payload['shape'] as String? ?? 'roundedRectangle';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            _selectedCanvasObjectIds.length > 1
                ? 'Object properties (${_selectedCanvasObjectIds.length})'
                : 'Object properties',
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('canvas-property-fill-color'),
                  initialValue: fillColor,
                  onChanged: (value) => fillColor = value,
                  decoration: const InputDecoration(
                    labelText: 'Fill color',
                    hintText: '#RRGGBB',
                  ),
                ),
                TextFormField(
                  key: const ValueKey('canvas-property-border-color'),
                  initialValue: borderColor,
                  onChanged: (value) => borderColor = value,
                  decoration: const InputDecoration(
                    labelText: 'Border color',
                    hintText: '#RRGGBB',
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: 96, child: Text('Border')),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('canvas-property-border-width'),
                        value: borderWidth,
                        min: 0,
                        max: 12,
                        divisions: 12,
                        label: borderWidth.round().toString(),
                        onChanged: (value) =>
                            setDialogState(() => borderWidth = value),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 96, child: Text('Opacity')),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('canvas-property-opacity'),
                        value: opacity,
                        min: 0.1,
                        max: 1,
                        divisions: 9,
                        label: '${(opacity * 100).round()}%',
                        onChanged: (value) =>
                            setDialogState(() => opacity = value),
                      ),
                    ),
                  ],
                ),
                if (object.type == CanvasObjectType.shape)
                  DropdownButtonFormField<String>(
                    key: const ValueKey('canvas-property-shape'),
                    initialValue: shape,
                    decoration: const InputDecoration(labelText: 'Shape'),
                    items: <DropdownMenuItem<String>>[
                      for (final kind in CanvasShapeKind.values)
                        DropdownMenuItem(
                          value: kind.name,
                          child: Text(kind.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) shape = value;
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('canvas-property-apply'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (result == true && mounted) {
      await _updateCanvasObjects(<CanvasObject>[
        for (final selected in _selectedCanvasObjects())
          if (!selected.isLocked)
            selected.copyWith(
              payload: <String, Object?>{
                ...selected.payload,
                'fillColor': _normalizedCanvasHex(fillColor),
                'borderColor': _normalizedCanvasHex(borderColor),
                'borderWidth': borderWidth,
                'opacity': opacity,
                if (selected.type == CanvasObjectType.shape) 'shape': shape,
              },
              updatedAt: DateTime.now(),
            ),
      ]);
    }
  }

  Future<void> setColumnChildren(
    String columnId,
    List<String> orderedChildIds,
  ) async {
    final board = widget.board;
    if (board == null || !_canUpdateCanvasObjects) return;
    final reconciled = board.reconcileColumnMembership(
      columnId: columnId,
      orderedChildIds: orderedChildIds,
      now: DateTime.now(),
    );
    final column = reconciled.objectById(columnId)!;
    final layout = const CanvasColumnLayoutEngine().layout(
      columnGeometry: column.geometry,
      orderedChildIds: column.orderedColumnChildIds,
      childGeometries: <String, CanvasGeometry>{
        for (final id in column.orderedColumnChildIds)
          if (reconciled.objectById(id) case final child?) id: child.geometry,
      },
      isCollapsed: column.isColumnCollapsed,
    );
    await _updateCanvasObjects(<CanvasObject>[
      column.copyWith(geometry: layout.columnGeometry),
      for (final entry in layout.childBounds.entries)
        reconciled
            .objectById(entry.key)!
            .copyWith(
              geometry: CanvasGeometry(
                x: entry.value.left,
                y: entry.value.top,
                width: entry.value.width,
                height: entry.value.height,
              ),
            ),
      for (final object in reconciled.objects)
        if (object.parentColumnId == null &&
            board.objectById(object.id)?.parentColumnId == columnId)
          object,
    ]);
  }

  Future<void> _toggleColumn(CanvasObject column) async {
    final collapsed = !column.isColumnCollapsed;
    final layout = const CanvasColumnLayoutEngine().layout(
      columnGeometry: column.geometry,
      orderedChildIds: column.orderedColumnChildIds,
      childGeometries: <String, CanvasGeometry>{
        for (final id in column.orderedColumnChildIds)
          if (widget.board?.objectById(id) case final child?)
            id: child.geometry,
      },
      isCollapsed: collapsed,
    );
    await _updateCanvasObjects(<CanvasObject>[
      column.copyWith(
        geometry: layout.columnGeometry,
        payload: <String, Object?>{...column.payload, 'isCollapsed': collapsed},
        updatedAt: DateTime.now(),
      ),
    ]);
  }

  void _updateCanvasObjectText(CanvasObject object, String text) {
    if (!_canUpdateCanvasObjects) return;
    final updated = object.copyWith(
      payload: <String, Object?>{...object.payload, 'text': text},
      updatedAt: DateTime.now(),
    );
    unawaited(_updateCanvasObjects(<CanvasObject>[updated]));
  }

  void _deleteSelectedCanvasObject() {
    final objects = _selectedCanvasObjects();
    if (objects.isEmpty || !_canDeleteCanvasObjects) return;
    final deletable = objects.where((object) => !object.isLocked).toList();
    if (deletable.isEmpty) return;
    setState(() {
      _selectedCanvasObjectId = null;
      _selectedCanvasObjectIds.clear();
      for (final object in deletable) {
        _canvasObjectGeometryOverrides.remove(object.id);
      }
    });
    unawaited(_deleteCanvasObjects(deletable));
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

  void _updateConnectorDraft(Offset scenePosition) {
    final start = _connectorStartScene;
    if (start == null) return;
    final origin = _sceneOrigin;
    final startBoard = start - origin;
    final endBoard = scenePosition - origin;
    final route = switch (_connectorAppearance.style) {
      CanvasConnectorStyle.straight ||
      CanvasConnectorStyle.curved => <Offset>[start, scenePosition],
      CanvasConnectorStyle.elbow => <Offset>[
        for (final point in routeOrthogonalConnector(
          start: spatial.CanvasPoint(startBoard.dx, startBoard.dy),
          end: spatial.CanvasPoint(endBoard.dx, endBoard.dy),
          obstacles: (widget.board?.objects ?? const <CanvasObject>[])
              .where(
                (object) =>
                    object.isVisible &&
                    object.id != _connectorStartObjectId &&
                    object.type != CanvasObjectType.connector &&
                    object.type != CanvasObjectType.freehand,
              )
              .map(
                (object) => spatial.CanvasBounds.fromLTWH(
                  object.geometry.x,
                  object.geometry.y,
                  object.geometry.width,
                  object.geometry.height,
                ),
              ),
        ))
          origin + Offset(point.x, point.y),
      ],
    };
    _toolDraft.updateConnector(scenePosition, route);
  }

  void _handleCanvasPointerMove(PointerMoveEvent event) {
    if (_toolDraft.hasFreehand) {
      _toolDraft.appendFreehand(
        event.pointer,
        _transformationController.toScene(event.localPosition),
      );
      return;
    }
    if (_isCanvasEraserActive && event.buttons == kPrimaryMouseButton) {
      _eraseCanvasObjectAt(
        _transformationController.toScene(event.localPosition),
      );
      return;
    }
    final touchPanLastLocal = _touchPanLastLocal;
    if (touchPanLastLocal != null && event.kind == PointerDeviceKind.touch) {
      final delta = event.localPosition - touchPanLastLocal;
      _touchPanLastLocal = event.localPosition;
      _transformationController.value = Matrix4.translationValues(
        delta.dx,
        delta.dy,
        0,
      )..multiply(_transformationController.value);
      return;
    }
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

  void _eraseCanvasObjectAt(Offset scenePosition) {
    final object = _canvasObjectAtScene(scenePosition);
    if (object == null ||
        object.isLocked ||
        !_canDeleteCanvasObjects ||
        !_erasedCanvasObjectIds.add(object.id)) {
      return;
    }
  }

  void _finishCanvasEraser() {
    if (_erasedCanvasObjectIds.isEmpty) return;
    final objects = _erasedCanvasObjectIds
        .map((id) => widget.board?.objectById(id))
        .nonNulls
        .where((object) => !object.isLocked)
        .toList(growable: false);
    _erasedCanvasObjectIds.clear();
    unawaited(_deleteCanvasObjects(objects));
  }

  void _finishFreehandStroke(int pointer) {
    final points = _toolDraft.takeFreehand(pointer);
    final callback = widget.onCanvasObjectCreated;
    if (points.length < 2 || callback == null) return;
    final origin = _sceneOrigin;
    final boardPoints = points.map((point) => point - origin).toList();
    final minX = boardPoints.map((point) => point.dx).reduce(math.min);
    final minY = boardPoints.map((point) => point.dy).reduce(math.min);
    final maxX = boardPoints.map((point) => point.dx).reduce(math.max);
    final maxY = boardPoints.map((point) => point.dy).reduce(math.max);
    const padding = 8.0;
    final now = DateTime.now();
    final object = CanvasObject(
      id: const Uuid().v4(),
      type: CanvasObjectType.freehand,
      geometry: CanvasGeometry(
        x: minX - padding,
        y: minY - padding,
        width: math.max(maxX - minX + padding * 2, padding * 2),
        height: math.max(maxY - minY + padding * 2, padding * 2),
      ),
      payload: <String, Object?>{
        'points': <Map<String, Object?>>[
          for (final point in boardPoints)
            <String, Object?>{
              'x': point.dx - minX + padding,
              'y': point.dy - minY + padding,
            },
        ],
        ..._penAppearance.toPayload(),
      },
      createdAt: now,
      updatedAt: now,
    );
    setState(() {
      _selectedCanvasObjectId = object.id;
      _selectedCanvasObjectIds
        ..clear()
        ..add(object.id);
    });
    unawaited(Future<void>.sync(() => callback(object)));
  }

  void _finishLasso(PointerUpEvent event, Offset origin) {
    final start = _lassoStartLocal;
    final current = _lassoCurrentLocal;
    if (start == null || current == null) return;
    final localRect = Rect.fromPoints(start, current);
    final sceneA = _transformationController.toScene(localRect.topLeft);
    final sceneB = _transformationController.toScene(localRect.bottomRight);
    final sceneRect = Rect.fromPoints(sceneA, sceneB);
    final selectedNodes = <String>{};
    for (final node in _filteredNodesForRendering()) {
      final position = _positionFor(node);
      final nodeRect = Rect.fromLTWH(
        position.dx + origin.dx,
        position.dy + origin.dy,
        _nodeSizeFor(node).width,
        _nodeSizeFor(node).height,
      );
      if (sceneRect.overlaps(nodeRect)) selectedNodes.add(node.id);
    }
    final selectedObjects = <String>{};
    for (final object in _visibleNativeCanvasObjects()) {
      final geometry = object.type == CanvasObjectType.connector
          ? _effectiveConnector(object).geometry
          : _canvasObjectGeometry(object);
      final objectRect = Rect.fromLTWH(
        origin.dx + geometry.x,
        origin.dy + geometry.y,
        geometry.width,
        geometry.height,
      );
      if (sceneRect.overlaps(objectRect)) selectedObjects.add(object.id);
    }
    setState(() {
      _lassoStartLocal = null;
      _lassoCurrentLocal = null;
    });
    _setEntitySelection(
      selectedNodes,
      selectedObjects,
      toggle:
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed,
    );
  }

  Rect _minimapSceneBounds(Size viewportSize) {
    final origin = _sceneOrigin;
    var bounds = _viewportRectInSceneOf(viewportSize);
    for (final entry in _navigationIndex.entries) {
      bounds = bounds.expandToInclude(entry.bounds.shift(origin));
    }
    for (final geometry in _canvasObjectGeometryOverrides.values) {
      bounds = bounds.expandToInclude(
        Rect.fromLTWH(
          geometry.x + origin.dx,
          geometry.y + origin.dy,
          geometry.width,
          geometry.height,
        ),
      );
    }
    final optimisticNodeIds = <String>{
      ..._dragPositions.keys,
      ..._resizeChanges.keys,
    };
    for (final id in optimisticNodeIds) {
      final node = widget.nodes
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      if (node == null) continue;
      final position = _positionFor(node);
      final size = _nodeSizeFor(node);
      bounds = bounds.expandToInclude(
        Rect.fromLTWH(
          position.dx + origin.dx,
          position.dy + origin.dy,
          size.width,
          size.height,
        ),
      );
    }
    if (bounds.width < 1200 || bounds.height < 800) {
      bounds = Rect.fromCenter(
        center: bounds.center,
        width: math.max(1200, bounds.width),
        height: math.max(800, bounds.height),
      );
    }
    return bounds.inflate(120);
  }

  void _onMinimapPan(Offset localPos, Size minimapSize, Rect contentBounds) {
    final pctX = (localPos.dx / minimapSize.width).clamp(0.0, 1.0);
    final pctY = (localPos.dy / minimapSize.height).clamp(0.0, 1.0);

    final targetX = contentBounds.left + pctX * contentBounds.width;
    final targetY = contentBounds.top + pctY * contentBounds.height;

    final pos = CanvasPosition(
      targetX - _sceneOrigin.dx,
      targetY - _sceneOrigin.dy,
    );

    final currentScale = _canvasScale(_transformationController.value);
    focusOnPosition(pos, scale: currentScale);
  }

  KeyEventResult _handleMinimapKey(
    KeyEvent event,
    Size viewportSize,
    Size minimapSize,
    Rect contentBounds,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => const Offset(-12, 0),
      LogicalKeyboardKey.arrowRight => const Offset(12, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -12),
      LogicalKeyboardKey.arrowDown => const Offset(0, 12),
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    final viewportCenter = _viewportRectInSceneOf(viewportSize).center;
    final minimapCenter = Offset(
      (viewportCenter.dx - contentBounds.left) *
          minimapSize.width /
          contentBounds.width,
      (viewportCenter.dy - contentBounds.top) *
          minimapSize.height /
          contentBounds.height,
    );
    _onMinimapPan(minimapCenter + delta, minimapSize, contentBounds);
    return KeyEventResult.handled;
  }

  void _followPeerPosition(Offset peerPos) {
    final size = context.size;
    if (size == null) return;

    final currentMatrix = _transformationController.value;
    final currentScale = _canvasScale(currentMatrix);

    final origin = _sceneOrigin;

    final sceneX = origin.dx + peerPos.dx;
    final sceneY = origin.dy + peerPos.dy;

    final targetX = -sceneX * currentScale + size.width / 2;
    final targetY = -sceneY * currentScale + size.height / 2;

    final targetMatrix = Matrix4.identity()
      ..translateByDouble(targetX, targetY, 0, 1)
      ..scaleByDouble(currentScale, currentScale, 1, 1);

    _transitionViewportTo(targetMatrix);
  }

  @override
  void didUpdateWidget(covariant MindmapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.board != widget.board) {
      _canvasObjectGeometryOverrides.clear();
    }
    if (oldWidget.nodes != widget.nodes ||
        oldWidget.board != widget.board ||
        oldWidget.workshopSession != widget.workshopSession ||
        oldWidget.workshopViewerUid != widget.workshopViewerUid ||
        oldWidget.isWorkshopHost != widget.isWorkshopHost) {
      _navigationIndex = CanvasNavigationIndex(
        nodes: widget.nodes,
        board: _workshopVisibleBoard(),
      );
      _activeSearchResultIndex = 0;
    }
    if (oldWidget.board != widget.board ||
        oldWidget.workshopSession != widget.workshopSession ||
        oldWidget.workshopViewerUid != widget.workshopViewerUid ||
        oldWidget.isWorkshopHost != widget.isWorkshopHost) {
      _orderedBoardObjects = _sortCanvasObjects(
        _workshopVisibleBoard()?.objects,
      );
      _rebuildCanvasObjectIndex();
    }
    if (oldWidget.nodes != widget.nodes ||
        oldWidget.board != widget.board ||
        oldWidget.expandedNodeId != widget.expandedNodeId ||
        oldWidget.expandedNodeOverride != widget.expandedNodeOverride) {
      _nodeSizes = _effectiveNodeSizes();
    }
    if (oldWidget.nodes != widget.nodes || oldWidget.board != widget.board) {
      _expandSceneForContent();
    }
    _handleExpandedFocusTransition(oldWidget.expandedNodeId);
    final collapsedNodeId = oldWidget.expandedNodeId;
    if (collapsedNodeId != null && collapsedNodeId != widget.expandedNodeId) {
      _editingNodeIds.remove(collapsedNodeId);
    }
    if (oldWidget.pingStream != widget.pingStream) {
      _listenForPings(widget.pingStream);
    }
    final nodeIds = widget.nodes.map((node) => node.id).toSet();
    final removedFocusIds = _nodeFocusNodes.keys
        .where((id) => !nodeIds.contains(id))
        .toList();
    for (final id in removedFocusIds) {
      _nodeFocusNodes.remove(id)?.dispose();
    }
    _dragPositions.removeWhere((id, position) => !nodeIds.contains(id));
    _resizeChanges.removeWhere((id, change) => !nodeIds.contains(id));
    final canvasObjectIds =
        widget.board?.objects.map((object) => object.id).toSet() ??
        const <String>{};
    _selectedNodeIds.removeWhere((id) => !nodeIds.contains(id));
    _selectedCanvasObjectIds.removeWhere((id) => !canvasObjectIds.contains(id));
    if (!nodeIds.contains(_lastSelectedNodeId)) _lastSelectedNodeId = null;
    if (!canvasObjectIds.contains(_selectedCanvasObjectId)) {
      _selectedCanvasObjectId = _selectedCanvasObjectIds.firstOrNull;
    }
    _canvasObjectKeys.removeWhere((id, key) => !canvasObjectIds.contains(id));
    final pendingObjectId = _pendingInlineEditCanvasObjectId;
    if (pendingObjectId != null && canvasObjectIds.contains(pendingObjectId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pendingInlineEditCanvasObjectId != pendingObjectId) {
          return;
        }
        final state = _canvasObjectKeys[pendingObjectId]?.currentState;
        if (state == null) return;
        _pendingInlineEditCanvasObjectId = null;
        state.beginInlineEdit();
      });
    }

    for (final node in widget.nodes) {
      final resize = _resizeChanges[node.id];
      if (resize == null) continue;
      final persistedSize = _presentationCache.sizeFor(node);
      final targetPositionMatches =
          _nearlyEqual(node.position.dx, resize.targetPosition.dx) &&
          _nearlyEqual(node.position.dy, resize.targetPosition.dy);
      final targetSizeMatches =
          _nearlyEqual(persistedSize.width, resize.targetSize.width) &&
          _nearlyEqual(persistedSize.height, resize.targetSize.height);
      if (targetPositionMatches && targetSizeMatches) {
        _resizeChanges.remove(node.id);
        continue;
      }
      final basePositionMatches =
          _nearlyEqual(node.position.dx, resize.basePosition.dx) &&
          _nearlyEqual(node.position.dy, resize.basePosition.dy);
      final baseSizeMatches =
          _nearlyEqual(persistedSize.width, resize.baseSize.width) &&
          _nearlyEqual(persistedSize.height, resize.baseSize.height);
      if (!basePositionMatches || !baseSizeMatches) {
        _resizeChanges.remove(node.id);
      }
    }

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
    final nodeColors = AppSemanticColors.of(context).nodeColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        _setInitialTransform(constraints.biggest);
        final showMiroToolRail =
            constraints.maxWidth >= 840 && constraints.maxHeight >= 520;
        final leftOverlayInset = showMiroToolRail ? 80.0 : 16.0;

        final origin = _sceneOrigin;
        return RepaintBoundary(
          key: _canvasExportKey,
          child: ClipRect(
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
                final searchResults = _navigationIndex.search(
                  _searchQuery,
                  category: _searchCategory,
                );
                final matchedObjectIds = <String>{
                  for (final result in searchResults)
                    if (result.objectId != null) result.objectId!,
                };
                final hasCanvasSearch =
                    _searchQuery.isNotEmpty ||
                    _searchCategory != CanvasSearchCategory.all;
                final filteredNodes = _filteredNodesForRendering();
                final isSearchActive =
                    hasCanvasSearch ||
                    _searchTypeFilter != null ||
                    _reviewStateFilter != null ||
                    _nextActionOnly;
                final isFocusActive = focusNode != null;
                final hiddenColumnNodeIds = <String>{
                  for (final reference
                      in widget.board?.objects ?? const <CanvasObject>[])
                    if (reference.type == CanvasObjectType.nodeReference &&
                        reference.mindmapNodeId != null &&
                        reference.parentColumnId != null &&
                        widget.board
                                ?.objectById(reference.parentColumnId!)
                                ?.isColumnCollapsed ==
                            true)
                      reference.mindmapNodeId!,
                };
                final visibleNodes = filteredNodes
                    .where((node) => !hiddenColumnNodeIds.contains(node.id))
                    .where((node) => _isNodeVisible(node, origin))
                    .toList(growable: false);
                final visibleArea = _visibleSceneRect;
                final canvasObjectCandidates = visibleArea == null
                    ? _orderedCanvasObjects()
                    : _indexedCanvasObjects(
                        spatial.CanvasBounds(
                          visibleArea.left - origin.dx,
                          visibleArea.top - origin.dy,
                          visibleArea.right - origin.dx,
                          visibleArea.bottom - origin.dy,
                        ),
                      );
                final visibleCanvasObjects = _sortCanvasObjects(
                  canvasObjectCandidates
                      .where(_isWorkshopObjectVisible)
                      .where(
                        (object) => _isCanvasObjectVisible(object, origin),
                      ),
                );
                final scale = _canvasScale(_transformationController.value);
                final useCompactCards = _isHeavyCanvas || scale < 0.45;
                final highlightedNodeIds = {
                  if (isSearchActive)
                    for (final node in filteredNodes) node.id,
                  ..._selectedNodeIds,
                  if (widget.highlightedNodeId != null)
                    widget.highlightedNodeId!,
                  if (widget.expandedNodeId != null) widget.expandedNodeId!,
                };
                final compactNodeIds = {
                  if (useCompactCards)
                    for (final node in visibleNodes)
                      if (!_editingNodeIds.contains(node.id)) node.id,
                };

                return CallbackShortcuts(
                  bindings: {
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyK, control: true),
                    ): _openCommandPalette,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.slash),
                    ): _openCommandPalette,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.space, shift: true),
                    ): _broadcastCanvasPing,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyF, control: true),
                    ): _focusCanvasSearch,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.equal, control: true),
                    ): _zoomIn,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.minus, control: true),
                    ): _zoomOut,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.digit0, control: true),
                    ): _zoomReset,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyC, control: true),
                    ): () =>
                        unawaited(_copySelectedEntities()),
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyV, control: true),
                    ): () =>
                        unawaited(_pasteSelectedEntities()),
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyD, control: true),
                    ): () =>
                        unawaited(_duplicateSelectedEntities()),
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyX, control: true),
                    ): () {
                      if (_selectedCanvasObjectIds.isNotEmpty) {
                        unawaited(_cutSelectedCanvasObjects());
                      }
                    },
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyA, control: true),
                    ): _selectAllCanvasObjects,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyA, meta: true),
                    ): _selectAllCanvasObjects,
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(
                        LogicalKeyboardKey.arrowUp,
                        control: true,
                      ),
                    ): () =>
                        _navigateSpatialSelection(LogicalKeyboardKey.arrowUp),
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(
                        LogicalKeyboardKey.arrowDown,
                        control: true,
                      ),
                    ): () =>
                        _navigateSpatialSelection(LogicalKeyboardKey.arrowDown),
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(
                        LogicalKeyboardKey.arrowLeft,
                        control: true,
                      ),
                    ): () =>
                        _navigateSpatialSelection(LogicalKeyboardKey.arrowLeft),
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(
                        LogicalKeyboardKey.arrowRight,
                        control: true,
                      ),
                    ): () => _navigateSpatialSelection(
                      LogicalKeyboardKey.arrowRight,
                    ),
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.arrowRight),
                    ): () {
                      if (_isPresentationMode) nextPresentationSlide();
                    },
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.arrowLeft),
                    ): () {
                      if (_isPresentationMode) previousPresentationSlide();
                    },
                    const SingleActivator(LogicalKeyboardKey.escape): () {
                      if (_isPresentationMode) {
                        setPresentationMode(false);
                      } else if (_hasActiveCanvasTool) {
                        _activateCanvasSelectTool();
                      } else if (_selectedCanvasObjectIds.isNotEmpty ||
                          _selectedNodeIds.isNotEmpty ||
                          _selectedConnectionKey != null ||
                          _lassoStartLocal != null) {
                        unawaited(_clearMultiSelection());
                      } else if (_focusedNodeId != null) {
                        setState(() => _focusedNodeId = null);
                      } else {
                        _clearSearch();
                      }
                    },
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyG, control: true),
                    ): () =>
                        setState(() => _showGrid = !_showGrid),
                    const _CanvasNonTextEditingActivator(
                      SingleActivator(LogicalKeyboardKey.keyS, control: true),
                    ): () =>
                        setState(() => _snapToGrid = !_snapToGrid),
                  },
                  child: Focus(
                    focusNode: _canvasFocusNode,
                    autofocus: true,
                    onKeyEvent: _handleCanvasKeyEvent,
                    child: Stack(
                      children: [
                        if (widget.nodes.isEmpty &&
                            (widget.board?.objects.every(
                                  (object) =>
                                      object.type ==
                                      CanvasObjectType.nodeReference,
                                ) ??
                                true))
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
                            if (_toolDraft.hasFreehand) {
                              _finishFreehandStroke(event.pointer);
                              return;
                            }
                            if (_isCanvasEraserActive) {
                              _finishCanvasEraser();
                              return;
                            }
                            if (_middlePanLastLocal != null) {
                              _middlePanLastLocal = null;
                              return;
                            }
                            if (_touchPanLastLocal != null) {
                              _touchPanLastLocal = null;
                              _scheduleViewportUpdate();
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
                            final worldPosition = _sceneBounds.sceneToWorld(
                              scenePosition,
                            );
                            focusOnPosition(
                              CanvasPosition(
                                worldPosition.dx,
                                worldPosition.dy,
                              ),
                              scale: 1.5,
                            );
                          },
                          onPointerCancel: (event) {
                            if (_toolDraft.pointer == event.pointer) {
                              _toolDraft.clear();
                            }
                            _erasedCanvasObjectIds.clear();
                            _middlePanLastLocal = null;
                            _touchPanLastLocal = null;
                            if (_lassoStartLocal != null && mounted) {
                              setState(() {
                                _lassoStartLocal = null;
                                _lassoCurrentLocal = null;
                              });
                            }
                          },
                          child: InteractiveViewer(
                            key: const ValueKey('mindmap-canvas'),
                            transformationController: _transformationController,
                            constrained: false,
                            boundaryMargin: EdgeInsets.all(
                              math.max(
                                    _sceneBounds.sceneSize.width,
                                    _sceneBounds.sceneSize.height,
                                  ) *
                                  0.2,
                            ),
                            minScale: 0.04,
                            maxScale: 2.4,
                            panEnabled: false,
                            scaleEnabled: _isCtrlPressed,
                            trackpadScrollCausesScale: _isCtrlPressed,
                            child: Listener(
                              key: const ValueKey('mindmap-scene-listener'),
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (_) {
                                if (_followingCollaboratorId != null) {
                                  setState(
                                    () => _followingCollaboratorId = null,
                                  );
                                }
                              },
                              child: SizedBox(
                                width: _sceneBounds.sceneSize.width,
                                height: _sceneBounds.sceneSize.height,
                                child: MouseRegion(
                                  onHover: (event) {
                                    widget.onLocalCursorChanged?.call(
                                      event.localPosition,
                                    );
                                    if (_connectorStartScene != null) {
                                      _updateConnectorDraft(
                                        event.localPosition,
                                      );
                                    }
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
                                          key: ValueKey(
                                            'mindmap-background-mode-$_backgroundMode',
                                          ),
                                          painter:
                                              _InteractiveBackgroundPainter(
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
                                                    : _cursorAnimController
                                                          .value,
                                                showGrid:
                                                    _showGrid &&
                                                    !_isHeavyCanvas,
                                                backgroundMode: _backgroundMode,
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
                                            nodeSizes: _nodeSizes,
                                            origin: origin,
                                            compactNodeIds: compactNodeIds,
                                            nodeColors: nodeColors,
                                          ),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: RepaintBoundary(
                                            child: ListenableBuilder(
                                              listenable: _toolDraft,
                                              builder: (context, child) =>
                                                  CustomPaint(
                                                    key: const ValueKey(
                                                      'mindmap-canvas-tool-draft',
                                                    ),
                                                    painter:
                                                        _CanvasToolDraftPainter(
                                                          draft: _toolDraft,
                                                          pen: _penAppearance,
                                                          connector:
                                                              _connectorAppearance,
                                                        ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (!_isPresentationMode &&
                                          _connectionDrag != null)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _ConnectionDragPainter(
                                                drag: _connectionDrag!,
                                                nodeColors: nodeColors,
                                              ),
                                            ),
                                          ),
                                        ),
                                      for (final entry in _visibleGroups(
                                        visibleNodes,
                                      ).entries)
                                        _PositionedNodeGroup(
                                          groupId: entry.key,
                                          nodes: entry.value,
                                          positions: {
                                            for (final node in entry.value)
                                              node.id: _positionFor(node),
                                          },
                                          sizes: {
                                            for (final node in entry.value)
                                              node.id: _nodeSizeFor(node),
                                          },
                                          origin: origin,
                                          isLocked: entry.value.any(
                                            (node) =>
                                                node.data['groupLocked'] ==
                                                true,
                                          ),
                                          isPresentationMode:
                                              _isPresentationMode,
                                          onPanUpdate: (delta) =>
                                              _moveGroup(entry.value, delta),
                                          onPanEnd: () =>
                                              _finishGroupMove(entry.value),
                                          onSelect: () =>
                                              _selectGroup(entry.value),
                                          onRename: () =>
                                              _renameGroup(entry.value),
                                          onToggleLock: (locked) =>
                                              _setGroupLocked(
                                                entry.value,
                                                locked,
                                              ),
                                          onSetSwimlaneMode: (mode) =>
                                              _setGroupSwimlaneMode(
                                                entry.value,
                                                mode,
                                              ),
                                          onUngroup: () =>
                                              _ungroupNodes(entry.value),
                                        ),
                                      for (final source in visibleNodes)
                                        for (final targetId
                                            in source.relatedNodeIds)
                                          if (visibleNodes.any(
                                            (node) => node.id == targetId,
                                          ))
                                            _ConnectionOverlay(
                                              source: source,
                                              target: visibleNodes.firstWhere(
                                                (node) => node.id == targetId,
                                              ),
                                              sourcePosition: _positionFor(
                                                source,
                                              ),
                                              targetPosition: _positionFor(
                                                visibleNodes.firstWhere(
                                                  (node) => node.id == targetId,
                                                ),
                                              ),
                                              sourceSize: _nodeSizeFor(source),
                                              targetSize: _nodeSizeFor(
                                                visibleNodes.firstWhere(
                                                  (node) => node.id == targetId,
                                                ),
                                              ),
                                              origin: origin,
                                              label: _connectionLabel(
                                                source,
                                                targetId,
                                              ),
                                              isSelected:
                                                  _selectedConnectionKey ==
                                                  _connectionKey(
                                                    source,
                                                    visibleNodes.firstWhere(
                                                      (node) =>
                                                          node.id == targetId,
                                                    ),
                                                  ),
                                              onSelect: () => _selectConnection(
                                                source,
                                                visibleNodes.firstWhere(
                                                  (node) => node.id == targetId,
                                                ),
                                              ),
                                              onContextMenu: (position) =>
                                                  _showConnectionContextMenu(
                                                    source,
                                                    visibleNodes.firstWhere(
                                                      (node) =>
                                                          node.id == targetId,
                                                    ),
                                                    position,
                                                  ),
                                              onEditLabel: () =>
                                                  _editConnectionLabel(
                                                    source,
                                                    targetId,
                                                  ),
                                              onDetach: () => widget
                                                  .onNodeDisconnected
                                                  ?.call(
                                                    source,
                                                    visibleNodes.firstWhere(
                                                      (node) =>
                                                          node.id == targetId,
                                                    ),
                                                  ),
                                            ),
                                      if (!_isPresentationMode)
                                        for (final source in visibleNodes)
                                          for (final targetId
                                              in source.relatedNodeIds)
                                            if (visibleNodes.any(
                                              (node) => node.id == targetId,
                                            ))
                                              _ConnectionEndpointHandle(
                                                source: source,
                                                target: visibleNodes.firstWhere(
                                                  (node) => node.id == targetId,
                                                ),
                                                targetPosition: _positionFor(
                                                  visibleNodes.firstWhere(
                                                    (node) =>
                                                        node.id == targetId,
                                                  ),
                                                ),
                                                targetSize: _nodeSizeFor(
                                                  visibleNodes.firstWhere(
                                                    (node) =>
                                                        node.id == targetId,
                                                  ),
                                                ),
                                                origin: origin,
                                                onPanStart: (position) =>
                                                    _startConnectionRelink(
                                                      source,
                                                      visibleNodes.firstWhere(
                                                        (node) =>
                                                            node.id == targetId,
                                                      ),
                                                      position,
                                                    ),
                                                onPanUpdate:
                                                    _updateConnectionDrag,
                                                onPanEnd: (_) =>
                                                    _finishConnectionRelink(
                                                      source,
                                                      visibleNodes.firstWhere(
                                                        (node) =>
                                                            node.id == targetId,
                                                      ),
                                                    ),
                                              ),
                                      if (_selectedConnectionKey != null)
                                        for (final source in visibleNodes)
                                          for (final targetId
                                              in source.relatedNodeIds)
                                            if (visibleNodes.any(
                                                  (node) =>
                                                      node.id == targetId,
                                                ) &&
                                                _selectedConnectionKey ==
                                                    _connectionKey(
                                                      source,
                                                      visibleNodes.firstWhere(
                                                        (node) =>
                                                            node.id == targetId,
                                                      ),
                                                    ))
                                              Builder(
                                                builder: (context) {
                                                  final target =
                                                      visibleNodes.firstWhere(
                                                    (node) =>
                                                        node.id == targetId,
                                                  );
                                                  final srcPos =
                                                      _positionFor(source);
                                                  final tgtPos =
                                                      _positionFor(target);
                                                  final srcSize =
                                                      _nodeSizeFor(source);
                                                  final tgtSize =
                                                      _nodeSizeFor(target);
                                                  final startPt = origin +
                                                      Offset(
                                                        srcPos.dx +
                                                            srcSize.width -
                                                            2,
                                                        srcPos.dy +
                                                            _nodePortY(
                                                              srcSize,
                                                            ),
                                                      );
                                                  final endPt = origin +
                                                      Offset(
                                                        tgtPos.dx + 2,
                                                        tgtPos.dy +
                                                            _nodePortY(
                                                              tgtSize,
                                                            ),
                                                      );
                                                  final mid = Offset(
                                                    (startPt.dx + endPt.dx) / 2,
                                                    (startPt.dy + endPt.dy) / 2,
                                                  );
                                                  final style =
                                                      _connectionStyle(
                                                    source,
                                                    targetId,
                                                  );
                                                  return Positioned(
                                                    left: mid.dx - 120,
                                                    top: mid.dy + 24,
                                                    child: ConnectionStyleBar(
                                                      style: style,
                                                      onStyleChanged:
                                                          (newStyle) {
                                                        unawaited(
                                                          _updateConnectionStyle(
                                                            source,
                                                            targetId,
                                                            newStyle,
                                                          ),
                                                        );
                                                      },
                                                      onDelete: () {
                                                        widget
                                                            .onNodeDisconnected
                                                            ?.call(
                                                          source,
                                                          target,
                                                        );
                                                        setState(
                                                          () =>
                                                              _selectedConnectionKey =
                                                                  null,
                                                        );
                                                      },
                                                    ),
                                                  );
                                                },
                                              ),
                                      for (final object in visibleCanvasObjects)
                                        if (object.isVisible &&
                                            (!hasCanvasSearch ||
                                                matchedObjectIds.contains(
                                                  object.id,
                                                )) &&
                                            (object.type ==
                                                    CanvasObjectType
                                                        .stickyNote ||
                                                object.type ==
                                                    CanvasObjectType.shape ||
                                                object.type ==
                                                    CanvasObjectType.text ||
                                                object.type ==
                                                    CanvasObjectType
                                                        .connector ||
                                                object.type ==
                                                    CanvasObjectType.freehand ||
                                                object.type ==
                                                    CanvasObjectType.frame ||
                                                object.type ==
                                                    CanvasObjectType.column ||
                                                object.type ==
                                                    CanvasObjectType
                                                        .boardReference ||
                                                object.type ==
                                                    CanvasObjectType.image ||
                                                object.type ==
                                                    CanvasObjectType
                                                        .linkPreview))
                                          if (object.parentColumnId != null &&
                                              widget.board
                                                      ?.objectById(
                                                        object.parentColumnId!,
                                                      )
                                                      ?.isColumnCollapsed ==
                                                  true)
                                            const SizedBox.shrink()
                                          else if (object.type ==
                                              CanvasObjectType.connector)
                                            _PositionedCanvasConnector(
                                              object: object,
                                              geometry: _effectiveConnector(
                                                object,
                                              ).geometry,
                                              route: _effectiveConnector(
                                                object,
                                              ).route,
                                              origin: origin,
                                              isSelected:
                                                  _selectedCanvasObjectIds
                                                      .contains(object.id),
                                              onSelect: () =>
                                                  _selectCanvasObject(object),
                                              onPanUpdate: (delta) =>
                                                  _moveCanvasObject(
                                                    object,
                                                    delta,
                                                  ),
                                              onPanEnd: () =>
                                                  _finishCanvasObjectMove(
                                                    object,
                                                  ),
                                              onPanCancel:
                                                  _cancelCanvasObjectMove,
                                            )
                                          else if (object.type ==
                                              CanvasObjectType.freehand)
                                            _PositionedCanvasFreehand(
                                              object: object,
                                              geometry: _canvasObjectGeometry(
                                                object,
                                              ),
                                              origin: origin,
                                              isSelected:
                                                  _selectedCanvasObjectIds
                                                      .contains(object.id),
                                              onSelect: () =>
                                                  _selectCanvasObject(object),
                                              onPanUpdate: (delta) =>
                                                  _moveCanvasObject(
                                                    object,
                                                    delta,
                                                  ),
                                              onPanEnd: () =>
                                                  _finishCanvasObjectMove(
                                                    object,
                                                  ),
                                              onPanCancel:
                                                  _cancelCanvasObjectMove,
                                            )
                                          else if (object.type ==
                                              CanvasObjectType.column)
                                            _PositionedCanvasColumn(
                                              object: object,
                                              geometry: _canvasObjectGeometry(
                                                object,
                                              ),
                                              origin: origin,
                                              isSelected:
                                                  _selectedCanvasObjectIds
                                                      .contains(object.id),
                                              onSelect: () =>
                                                  _selectCanvasObject(object),
                                              onPanDown: _startCanvasObjectMove,
                                              onPanUpdate: (position) =>
                                                  _moveCanvasObjectFromGlobal(
                                                    object,
                                                    position,
                                                  ),
                                              onPanEnd: () =>
                                                  _finishCanvasObjectMove(
                                                    object,
                                                  ),
                                              onToggle: () =>
                                                  _toggleColumn(object),
                                              onResizeUpdate: (delta) =>
                                                  _resizeCanvasObject(
                                                    object,
                                                    delta,
                                                  ),
                                              onResizeEnd: () =>
                                                  _finishCanvasObjectMove(
                                                    object,
                                                  ),
                                            )
                                          else if (object.type ==
                                                  CanvasObjectType.image ||
                                              object.type ==
                                                  CanvasObjectType.linkPreview)
                                            _PositionedCanvasMediaObject(
                                              object: object,
                                              geometry: _canvasObjectGeometry(
                                                object,
                                              ),
                                              origin: origin,
                                              isSelected:
                                                  _selectedCanvasObjectIds
                                                      .contains(object.id),
                                              loadAttachmentBytes: widget
                                                  .loadCanvasAttachmentBytes,
                                              onSelect: () =>
                                                  _selectCanvasObject(object),
                                              onPanUpdate: (delta) =>
                                                  _moveCanvasObject(
                                                    object,
                                                    delta,
                                                  ),
                                              onPanEnd: () =>
                                                  _finishCanvasObjectMove(
                                                    object,
                                                  ),
                                              onPanCancel:
                                                  _cancelCanvasObjectMove,
                                              onResizeUpdate: (delta) =>
                                                  _resizeCanvasObject(
                                                    object,
                                                    delta,
                                                  ),
                                              onResizeEnd: () =>
                                                  _finishCanvasObjectMove(
                                                    object,
                                                  ),
                                            )
                                          else
                                            _PositionedCanvasObject(
                                              key: _canvasObjectKeys.putIfAbsent(
                                                object.id,
                                                () =>
                                                    GlobalKey<
                                                      _PositionedCanvasObjectState
                                                    >(),
                                              ),
                                              object: object,
                                              geometry: _canvasObjectGeometry(
                                                object,
                                              ),
                                              origin: origin,
                                              isSelected:
                                                  _selectedCanvasObjectIds
                                                      .contains(object.id),
                                              onSelect: () =>
                                                  _selectCanvasObject(object),
                                              onOpen:
                                                  object.type ==
                                                      CanvasObjectType
                                                          .boardReference
                                                  ? () => widget
                                                        .onBoardReferenceOpened
                                                        ?.call(object)
                                                  : null,
                                              onPanDown: _startCanvasObjectMove,
                                              onPanStart: (position) =>
                                                  _selectCanvasObject(object),
                                              onPanUpdate: (position) =>
                                                  _moveCanvasObjectFromGlobal(
                                                    object,
                                                    position,
                                                  ),
                                              onPanEnd: () =>
                                                  _finishCanvasObjectMove(
                                                    object,
                                                  ),
                                              onPanCancel:
                                                  _cancelCanvasObjectMove,
                                              onResizeUpdate: (delta) =>
                                                  _resizeCanvasObject(
                                                    object,
                                                    delta,
                                                  ),
                                              onResizeEnd: () =>
                                                  _finishCanvasObjectMove(
                                                    object,
                                                  ),
                                              onTextChanged: (text) =>
                                                  _updateCanvasObjectText(
                                                    object,
                                                    text,
                                                  ),
                                              onEditingFinished: () =>
                                                  _canvasFocusNode
                                                      .requestFocus(),
                                            ),
                                      if (_columnDropTargetId != null &&
                                          widget.board?.objectById(
                                                _columnDropTargetId!,
                                              ) !=
                                              null)
                                        Positioned(
                                          key: const ValueKey(
                                            'canvas-column-insertion-indicator',
                                          ),
                                          left:
                                              origin.dx +
                                              widget.board!
                                                  .objectById(
                                                    _columnDropTargetId!,
                                                  )!
                                                  .geometry
                                                  .x +
                                              CanvasColumnLayoutEngine.padding,
                                          top:
                                              origin.dy +
                                              widget.board!
                                                  .objectById(
                                                    _columnDropTargetId!,
                                                  )!
                                                  .geometry
                                                  .y +
                                              CanvasColumnLayoutEngine
                                                  .headerHeight +
                                              CanvasColumnLayoutEngine.padding +
                                              (_columnDropInsertionIndex ?? 0) *
                                                  (CanvasColumnLayoutEngine
                                                          .minimumChildHeight +
                                                      CanvasColumnLayoutEngine
                                                          .childGap),
                                          width:
                                              widget.board!
                                                  .objectById(
                                                    _columnDropTargetId!,
                                                  )!
                                                  .geometry
                                                  .width -
                                              CanvasColumnLayoutEngine.padding *
                                                  2,
                                          height: 3,
                                          child: ColoredBox(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      if (_canvasSmartGuides != null)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: Semantics(
                                              label:
                                                  _canvasSmartGuides!
                                                          .distance ==
                                                      null
                                                  ? null
                                                  : 'Equal spacing ${_canvasSmartGuides!.distance!.round()} px',
                                              child: CustomPaint(
                                                key: const ValueKey(
                                                  'mindmap-canvas-smart-guides',
                                                ),
                                                painter:
                                                    _CanvasSmartGuidesPainter(
                                                      guides:
                                                          _canvasSmartGuides!,
                                                      origin: origin,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.primary,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      for (final object
                                          in widget.assistantPreviewObjects)
                                        _CanvasAssistantPreviewOutline(
                                          object: object,
                                          origin: origin,
                                        ),
                                      for (final object in visibleCanvasObjects)
                                        if (object.isVisible &&
                                            object.type !=
                                                CanvasObjectType
                                                    .nodeReference &&
                                            (!hasCanvasSearch ||
                                                matchedObjectIds.contains(
                                                  object.id,
                                                )) &&
                                            (_canvasObjectVoteCount(object) >
                                                    0 ||
                                                _hasLocalVote(object) ||
                                                _canvasObjectOpenCommentCount(
                                                      object,
                                                    ) >
                                                    0))
                                          _CanvasObjectSignalsBadge(
                                            object: object,
                                            voteCount: _canvasObjectVoteCount(
                                              object,
                                            ),
                                            hasLocalVote: _hasLocalVote(object),
                                            openCommentCount:
                                                _canvasObjectOpenCommentCount(
                                                  object,
                                                ),
                                            geometry: _canvasObjectGeometry(
                                              object,
                                            ),
                                            origin: origin,
                                          ),
                                      for (final node in visibleNodes) ...[
                                        _PositionedNode(
                                          cardKey: _nodeCardKeys.putIfAbsent(
                                            node.id,
                                            () =>
                                                GlobalKey<
                                                  _MindmapNodeCardState
                                                >(),
                                          ),
                                          node: node,
                                          focusNode: _nodeFocusNodes
                                              .putIfAbsent(
                                                node.id,
                                                () => FocusNode(
                                                  debugLabel: 'Mindmap node',
                                                ),
                                              ),
                                          preset: _presentationCache
                                              .uiStateFor(node)
                                              .sizePreset,
                                          typedPayload: _presentationCache
                                              .typedPayloadFor(node),
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
                                            widget.onInlineEditStateChanged
                                                ?.call(
                                                  node.id,
                                                  isEditing,
                                                  isEditing
                                                      ? NodeSaveStatus.idle
                                                      : NodeSaveStatus.idle,
                                                );
                                          },
                                          onInlineSaveStatusChanged: (status) =>
                                              widget.onInlineEditStateChanged
                                                  ?.call(
                                                    node.id,
                                                    _editingNodeIds.contains(
                                                      node.id,
                                                    ),
                                                    status,
                                                  ),
                                          isHighlighted: highlightedNodeIds
                                              .contains(node.id),
                                          isCompact:
                                              compactNodeIds.contains(
                                                node.id,
                                              ) &&
                                              widget.expandedNodeId != node.id,
                                          expandedChild:
                                              widget.expandedNodeId == node.id
                                              ? widget.expandedNodeBuilder
                                                    ?.call(node)
                                              : null,
                                          onBuilt: widget.onNodeCardBuilt,
                                          onBuildProbe:
                                              widget.onNodeCardBuildProbe,
                                          onPointerDown: (globalPosition) =>
                                              _nodeDragGlobalPosition =
                                                  globalPosition,
                                          onPointerUp: () =>
                                              _nodeDragGlobalPosition = null,
                                          onPanUpdate: (globalPosition) {
                                            final previous =
                                                _nodeDragGlobalPosition;
                                            _nodeDragGlobalPosition =
                                                globalPosition;
                                            if (previous == null) return;
                                            final scale = _canvasScale(
                                              _transformationController.value,
                                            );
                                            _moveNode(
                                              node,
                                              (globalPosition - previous) /
                                                  scale,
                                            );
                                          },
                                          onPanEnd: () => _finishMove(node),
                                          onPanCancel: () {
                                            _nodeDragGlobalPosition = null;
                                            _resetNodeGuideState();
                                          },

                                          onConnectionStart: (globalPosition) =>
                                              _startConnectionDrag(
                                                node,
                                                globalPosition,
                                              ),
                                          onConnectionUpdate:
                                              _updateConnectionDrag,
                                          onConnectionEnd:
                                              _finishConnectionDrag,
                                          onNodeUpdated: widget.onNodeUpdated,
                                          onResizeChanged:
                                              widget.onNodeResize == null ||
                                                  widget.expandedNodeId ==
                                                      node.id
                                              ? null
                                              : (change) => _applyNodeResize(
                                                  node,
                                                  change,
                                                ),
                                          onSelect: () =>
                                              unawaited(_selectNode(node)),
                                          onOpen: () => unawaited(
                                            selectAndFocusNode(node),
                                          ),
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
                                              widget.onKanbanCardAdvanced ==
                                                  null
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
                                        if (!_isPresentationMode)
                                          _KeyboardConnectionPort(
                                            key: ValueKey(
                                              'mindmap-output-port-${node.id}',
                                            ),
                                            node: node,
                                            position: _positionFor(node),
                                            size: _nodeSizeFor(node),
                                            origin: origin,
                                            isInput: false,
                                            onPressed: () =>
                                                _startKeyboardConnection(node),
                                          ),
                                        if (!_isPresentationMode)
                                          _KeyboardConnectionPort(
                                            key: ValueKey(
                                              'mindmap-input-port-${node.id}',
                                            ),
                                            node: node,
                                            position: _positionFor(node),
                                            size: _nodeSizeFor(node),
                                            origin: origin,
                                            isInput: true,
                                            onPressed: () => unawaited(
                                              _finishKeyboardConnection(node),
                                            ),
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
                                            position:
                                                entry.value.cursorPosition!,
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
                        if (!_isPresentationMode && !_isSearchOverlayCollapsed)
                          Positioned.fill(
                            child: _CanvasSearchOverlay(
                              searchController: _searchController,
                              searchFocusNode: _searchFocusNode,
                              isSearchActive: isSearchActive,
                              results: searchResults,
                              activeResultIndex: _activeSearchResultIndex,
                              selectedCategory: _searchCategory,
                              selectedType: _searchTypeFilter,
                              selectedReviewState: _reviewStateFilter,
                              nextActionOnly: _nextActionOnly,
                              isCollapsed: false,
                              onClearSearch: _clearSearch,
                              onCategorySelected: (category) => setState(() {
                                _searchCategory = category;
                                _activeSearchResultIndex = 0;
                              }),
                              onTypeSelected: _setSearchTypeFilter,
                              onReviewStateSelected: _setReviewStateFilter,
                              onNextActionOnlyChanged: _setNextActionOnly,
                              onCollapsedChanged: _setSearchOverlayCollapsed,
                              onPrevious: () => _cycleSearchResult(
                                searchResults,
                                backwards: true,
                              ),
                              onNext: () => _cycleSearchResult(searchResults),
                              onResultSelected: (index) =>
                                  _activateSearchResult(searchResults, index),
                              leftInset: leftOverlayInset,
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
                                  accent: AppSemanticColors.of(context).accent,
                                  fill: AppSemanticColors.of(
                                    context,
                                  ).accentMuted,
                                ),
                              ),
                            ),
                          ),
                        if (_selectedNodeIds.length +
                                _selectedCanvasObjectIds.length >
                            1)
                          Positioned(
                            top: 86,
                            right: 16,
                            child: _MultiSelectToolbar(
                              nodeCount: _selectedNodeIds.length,
                              objectCount: _selectedCanvasObjectIds.length,
                              canEditNodes: widget.onNodeUpdated != null,
                              canArrange:
                                  (_selectedNodeIds.isEmpty ||
                                      widget.onNodeMoved != null) &&
                                  (!_selectedCanvasObjects().any(
                                        (object) => !object.isLocked,
                                      ) ||
                                      _canUpdateCanvasObjects) &&
                                  ((_selectedNodeIds.isNotEmpty &&
                                          widget.onNodeMoved != null) ||
                                      (_selectedCanvasObjects().any(
                                            (object) => !object.isLocked,
                                          ) &&
                                          _canUpdateCanvasObjects)),
                              canUpdateObjects: _canUpdateCanvasObjects,
                              canCreateObjects: _canCreateCanvasObjects,
                              canGroupInFrame:
                                  _canCreateCanvasObjects &&
                                  widget.onNodeUpdated != null &&
                                  _canUpdateCanvasObjects,
                              canDelete:
                                  (_selectedNodeIds.isNotEmpty &&
                                      widget.onNodesDeleted != null) ||
                                  (_selectedCanvasObjects().any(
                                        (object) => !object.isLocked,
                                      ) &&
                                      _canDeleteCanvasObjects),
                              onComplete: () =>
                                  unawaited(_completeSelectedNodes()),
                              onGroupInFrame: () =>
                                  unawaited(groupSelectedEntities()),
                              onObjectProperties: () =>
                                  unawaited(_showCanvasObjectProperties()),
                              onObjectLock: () => _runCanvasObjectAction(
                                _CanvasObjectAction.toggleLock,
                              ),
                              onObjectRotate: () =>
                                  _rotateSelectedCanvasObjects(math.pi / 12),
                              onObjectLayer: () =>
                                  _moveCanvasObjectToLayer(front: true),
                              onObjectGroup: _groupSelectedCanvasObjects,

                              onStatusChanged: (status) =>
                                  unawaited(_setSelectedStatus(status)),
                              onPriorityChanged: (priority) =>
                                  unawaited(_setSelectedPriority(priority)),
                              onTag: () => unawaited(_tagSelectedNodes()),
                              onProject: () => unawaited(_setSelectedProject()),
                              onClearProject: () =>
                                  unawaited(_clearSelectedProject()),
                              onArea: () => unawaited(_setSelectedArea()),
                              onClearArea: () =>
                                  unawaited(_clearSelectedArea()),
                              onClearTags: () =>
                                  unawaited(_clearSelectedTags()),
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
                              onCopy: () => unawaited(_copySelectedEntities()),
                              onPaste: () =>
                                  unawaited(_pasteSelectedEntities()),
                              onDuplicate: () =>
                                  unawaited(_duplicateSelectedEntities()),
                              onArchive: () =>
                                  unawaited(_archiveSelectedNodes()),
                              onDelete: () =>
                                  unawaited(_deleteSelectedEntities()),
                              onClear: _clearMultiSelection,
                            ),
                          ),
                        if (_isPresentationMode)
                          Positioned(
                            bottom: 24,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Material(
                                elevation: 6,
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(24),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Previous slide',
                                        icon: const Icon(Icons.arrow_back),
                                        onPressed: previousPresentationSlide,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Slide ${_presentationFrameIndex + 1} / ${math.max(1, _visibleGroups(widget.nodes).length)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: 'Next slide',
                                        icon: const Icon(Icons.arrow_forward),
                                        onPressed: nextPresentationSlide,
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        tooltip: 'Exit presentation',
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            setPresentationMode(false),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (isFocusActive)
                          Positioned(
                            top: 86,
                            left: leftOverlayInset,
                            child: _FocusModeBanner(
                              title: focusNode.title,
                              visibleCount: filteredNodes.length,
                              onClear: () =>
                                  setState(() => _focusedNodeId = null),
                            ),
                          ),
                        if (isSearchActive && searchResults.isEmpty)
                          Center(
                            child: _CanvasSearchEmptyState(
                              query: _searchQuery.isEmpty
                                  ? _searchTypeFilter?.label ?? 'filter'
                                  : _searchQuery,
                              onClearSearch: _clearSearch,
                            ),
                          ),

                        if (!_isPresentationMode && showMiroToolRail)
                          Positioned(
                            left: 16,
                            top: 16,
                            child: _buildMiroToolRail(context),
                          ),
                        if (!_isPresentationMode &&
                            showMiroToolRail &&
                            _toolPopoverType != null)
                          Positioned.fill(
                            key: const ValueKey(
                              'mindmap-canvas-tool-popover-position',
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: GestureDetector(
                                    key: const ValueKey(
                                      'mindmap-canvas-tool-popover-barrier',
                                    ),
                                    behavior: HitTestBehavior.translucent,
                                    onTap: _closeToolSettings,
                                  ),
                                ),
                                CompositedTransformFollower(
                                  link: _toolLayerLinks[_toolPopoverType]!,
                                  showWhenUnlinked: false,
                                  targetAnchor: Alignment.centerRight,
                                  followerAnchor: Alignment.centerLeft,
                                  offset: const Offset(12, 0),
                                  child: _buildToolSettings(
                                    context,
                                    _toolPopoverType!,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Zoom & Grid Toolbar Overlay
                        if (!_isPresentationMode)
                          ValueListenableBuilder<Matrix4>(
                            valueListenable: _transformationController,
                            builder: (context, value, child) {
                              return Positioned(
                                bottom: 16,
                                left: leftOverlayInset,
                                child: _buildCanvasToolbar(
                                  context,
                                  isSearchActive: isSearchActive,
                                  filteredCount: filteredNodes.length,
                                  showCreationTools: !showMiroToolRail,
                                ),
                              );
                            },
                          ),

                        // Mini-map Overlay
                        if (!_isPresentationMode)
                          ValueListenableBuilder<Matrix4>(
                            valueListenable: _transformationController,
                            builder: (context, value, child) {
                              return Positioned(
                                key: const ValueKey('mindmap-minimap-anchor'),
                                bottom: 16,
                                right: 16,
                                child: AnimatedSize(
                                  alignment: Alignment.bottomRight,
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOut,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 140),
                                    layoutBuilder: (current, previous) => Stack(
                                      alignment: Alignment.bottomRight,
                                      children: <Widget>[...previous, ?current],
                                    ),
                                    child: KeyedSubtree(
                                      key: ValueKey<bool>(_isMinimapCollapsed),
                                      child: _buildMinimap(
                                        context,
                                        constraints.biggest,
                                      ),
                                    ),
                                  ),
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
          ),
        );
      },
    );
  }

  void _cycleSearchResult(
    List<CanvasSearchResult> results, {
    bool backwards = false,
  }) {
    if (results.isEmpty) return;
    final delta = backwards ? -1 : 1;
    final next = (_activeSearchResultIndex + delta) % results.length;
    _activateSearchResult(results, next);
  }

  void _activateSearchResult(List<CanvasSearchResult> results, int index) {
    if (results.isEmpty) return;
    final safeIndex = index.clamp(0, results.length - 1);
    final result = results[safeIndex];
    setState(() => _activeSearchResultIndex = safeIndex);
    _activateNavigationResult(result);
  }

  void _activateNavigationResult(CanvasSearchResult result) {
    focusOnPosition(
      CanvasPosition(result.center.dx, result.center.dy),
      scale: 1.25,
    );
    final nodeId = result.nodeId;
    if (nodeId != null) {
      final node = widget.nodes.where((item) => item.id == nodeId).firstOrNull;
      if (node != null) unawaited(_selectNode(node));
      return;
    }
    final objectId = result.objectId;
    final object = objectId == null ? null : widget.board?.objectById(objectId);
    if (object != null) {
      setState(() {
        _selectedCanvasObjectIds
          ..clear()
          ..add(object.id);
        _selectedCanvasObjectId = object.id;
        _selectedNodeIds.clear();
        _selectedConnectionKey = null;
      });
      _canvasFocusNode.requestFocus();
    }
  }

  void _handleExpandedFocusTransition(String? previousExpandedId) {
    final expandedId = widget.expandedNodeId;
    if (previousExpandedId == expandedId) return;
    if (expandedId != null) _scheduleExpandedNodeFocus();
    if (previousExpandedId == null && expandedId != null) {
      _focusBeforeExpansionNodeId = _nodeFocusNodes.entries
          .where((entry) => entry.value.hasFocus)
          .map((entry) => entry.key)
          .firstOrNull;
      return;
    }
    if (previousExpandedId != null && expandedId == null) {
      final restoreNodeId =
          widget.nodes.any((node) => node.id == previousExpandedId)
          ? previousExpandedId
          : _focusBeforeExpansionNodeId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nodeFocus = restoreNodeId == null
            ? null
            : _nodeFocusNodes[restoreNodeId];
        if (nodeFocus != null && nodeFocus.canRequestFocus) {
          nodeFocus.requestFocus();
        } else {
          _canvasFocusNode.requestFocus();
        }
      });
      _focusBeforeExpansionNodeId = null;
    }
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

  Future<bool> _selectNode(MindmapNode node) async {
    final generation = ++_expandedSelectionGeneration;
    final guard = widget.onExpandedSelectionChanging;
    if (guard != null && !await guard(widget.expandedNodeId, node.id)) {
      return false;
    }
    if (!mounted || generation != _expandedSelectionGeneration) return false;
    widget.onLocalSelectionChanged?.call(node.id);
    final isMultiSelect =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    setState(() {
      _lastSelectedNodeId = node.id;
      if (!isMultiSelect) {
        _selectedCanvasObjectIds.clear();
        _selectedCanvasObjectId = null;
      }
      _selectedConnectionKey = null;
      if (isMultiSelect) {
        if (!_selectedNodeIds.remove(node.id)) _selectedNodeIds.add(node.id);
      } else {
        _selectedNodeIds
          ..clear()
          ..add(node.id);
      }
    });
    await widget.onNodeSelected?.call(node);
    return mounted && generation == _expandedSelectionGeneration;
  }

  Map<String, Size> _effectiveNodeSizes() {
    final sizes = _presentationCache.sizesFor(widget.nodes);
    for (final node in widget.nodes) {
      final object = widget.board?.objectById('node:${node.id}');
      if (object != null) {
        sizes[node.id] = Size(object.geometry.width, object.geometry.height);
      }
    }
    final expandedId = widget.expandedNodeId;
    if (expandedId == null) return sizes;
    final expanded = widget.nodes
        .where((node) => node.id == expandedId)
        .firstOrNull;
    if (expanded == null) return sizes;
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(expanded);
    return <String, Size>{
      ...sizes,
      expanded.id: Size(policy.width, policy.height),
    };
  }

  Future<void> _clearMultiSelection() async {
    final generation = ++_expandedSelectionGeneration;
    final guard = widget.onExpandedSelectionChanging;
    if (guard != null && !await guard(widget.expandedNodeId, null)) return;
    if (!mounted || generation != _expandedSelectionGeneration) return;
    widget.onLocalSelectionChanged?.call(null);
    setState(() {
      _lassoStartLocal = null;
      _lassoCurrentLocal = null;
      _selectedNodeIds.clear();
      _lastSelectedNodeId = null;
      _selectedCanvasObjectIds.clear();
      _selectedCanvasObjectId = null;
      _selectedConnectionKey = null;
      _connectionDrag = null;
    });
    widget.onSelectionCleared?.call();
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
    await _layoutSelectedEntities(horizontal: horizontal, distribute: false);
  }

  Future<void> _distributeSelectedNodes({required bool horizontal}) async {
    await _layoutSelectedEntities(horizontal: horizontal, distribute: true);
  }

  Future<void> _layoutSelectedEntities({
    required bool horizontal,
    required bool distribute,
  }) async {
    final nodes = _selectedNodes();
    final objects = _selectedCanvasObjects()
        .where((object) => object.type != CanvasObjectType.nodeReference)
        .toList(growable: false);
    final items =
        <({MindmapNode? node, CanvasObject? object, CanvasGeometry geometry})>[
          for (final node in nodes)
            (
              node: node,
              object: null,
              geometry: CanvasGeometry(
                x: node.position.dx,
                y: node.position.dy,
                width: _nodeSizeFor(node).width,
                height: _nodeSizeFor(node).height,
              ),
            ),
          for (final object in objects)
            (
              node: null,
              object: object,
              geometry: object.type == CanvasObjectType.connector
                  ? _effectiveConnector(object).geometry
                  : _canvasObjectGeometry(object),
            ),
        ];
    final minimumCount = distribute ? 3 : 2;
    if (items.length < minimumCount) return;
    final left = items.map((item) => item.geometry.x).reduce(math.min);
    final top = items.map((item) => item.geometry.y).reduce(math.min);
    final right = items
        .map((item) => item.geometry.x + item.geometry.width)
        .reduce(math.max);
    final bottom = items
        .map((item) => item.geometry.y + item.geometry.height)
        .reduce(math.max);
    final positions = <int, CanvasPosition>{};
    if (distribute) {
      items.sort((first, second) {
        final firstValue = horizontal ? first.geometry.x : first.geometry.y;
        final secondValue = horizontal ? second.geometry.x : second.geometry.y;
        return firstValue.compareTo(secondValue);
      });
      final totalSize = items.fold<double>(0, (sum, item) {
        return sum + (horizontal ? item.geometry.width : item.geometry.height);
      });
      final gap =
          ((horizontal ? right - left : bottom - top) - totalSize) /
          (items.length - 1);
      var cursor = horizontal ? left : top;
      for (var index = 0; index < items.length; index++) {
        final geometry = items[index].geometry;
        positions[index] = CanvasPosition(
          horizontal ? cursor : geometry.x,
          horizontal ? geometry.y : cursor,
        );
        cursor += (horizontal ? geometry.width : geometry.height) + gap;
      }
    } else {
      for (var index = 0; index < items.length; index++) {
        final geometry = items[index].geometry;
        positions[index] = CanvasPosition(
          horizontal ? geometry.x : (left + right - geometry.width) / 2,
          horizontal ? (top + bottom - geometry.height) / 2 : geometry.y,
        );
      }
    }
    final objectUpdates = <CanvasObject>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final position = positions[index]!;
      final node = item.node;
      if (node != null) {
        final callback = widget.onNodeMoved;
        if (callback != null &&
            (position.dx != node.position.dx ||
                position.dy != node.position.dy)) {
          await callback(node, position);
        }
        continue;
      }
      final object = item.object!;
      if (object.isLocked || !_canUpdateCanvasObjects) continue;
      final geometry = item.geometry;
      if (position.dx == geometry.x && position.dy == geometry.y) continue;
      objectUpdates.add(
        object.copyWith(
          geometry: object.geometry.copyWith(
            x: object.geometry.x + position.dx - geometry.x,
            y: object.geometry.y + position.dy - geometry.y,
          ),
          updatedAt: DateTime.now(),
        ),
      );
    }
    if (objectUpdates.isNotEmpty) await _updateCanvasObjects(objectUpdates);
  }

  List<MindmapNode> _selectedNodes() {
    return widget.nodes
        .where((node) => _selectedNodeIds.contains(node.id))
        .toList(growable: false);
  }

  Future<void> _copySelectedEntities() async {
    final nodes = _selectedNodes();
    final objects = _selectedCanvasObjects()
        .where((object) => object.type != CanvasObjectType.nodeReference)
        .toList(growable: false);
    if (nodes.isEmpty && objects.isEmpty) return;
    _copiedNodes = nodes;
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode(<String, Object?>{
          'kind': 'var.mindmap.selection',
          'nodes': <Map<String, Object?>>[
            for (final node in nodes) node.toJson(),
          ],
          'objects': <Map<String, Object?>>[
            for (final object in objects) object.toJson(),
          ],
        }),
      ),
    );
  }

  Future<void> _pasteSelectedEntities() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clipboard?.text;
    final nodes = _decodeCopiedNodes(raw);
    await _pasteCanvasObjects(clipboardText: raw);
    if (nodes.isNotEmpty) {
      await _insertNodeCopies(nodes, offset: const Offset(36, 36));
    } else if (raw == null && _copiedNodes.isNotEmpty) {
      await _insertNodeCopies(_copiedNodes, offset: const Offset(36, 36));
    }
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

  Future<void> _duplicateSelectedEntities() async {
    final nodes = _selectedNodes();
    final objects = _selectedCanvasObjects()
        .where((object) => object.type != CanvasObjectType.nodeReference)
        .toList(growable: false);
    if ((nodes.isNotEmpty && widget.onNodeUpdated == null) ||
        (objects.isNotEmpty && !_canCreateCanvasObjects) ||
        (nodes.isNotEmpty &&
            objects.isNotEmpty &&
            (widget.onNodesDeleted == null || !_canDeleteCanvasObjects))) {
      return;
    }
    if (objects.isEmpty) {
      await _insertNodeCopies(nodes, offset: const Offset(42, 42));
      return;
    }
    final now = DateTime.now();
    final ids = <String, String>{
      for (final object in objects) object.id: const Uuid().v4(),
    };
    final copies = <CanvasObject>[
      for (final object in objects)
        CanvasObject(
          id: ids[object.id]!,
          type: object.type,
          rawType: object.rawType,
          geometry: object.geometry.copyWith(
            x: object.geometry.x + 42,
            y: object.geometry.y + 42,
          ),
          zIndex: object.zIndex + 1,
          isLocked: object.isLocked,
          isVisible: object.isVisible,
          parentFrameId: ids[object.parentFrameId] ?? object.parentFrameId,
          payload: object.payload,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final createdNodes = <MindmapNode>[];
    try {
      await _createCanvasObjects(copies);
      if (nodes.isNotEmpty) {
        await _insertNodeCopies(
          nodes,
          offset: const Offset(42, 42),
          created: createdNodes,
        );
      }
    } catch (_) {
      if (createdNodes.isNotEmpty) {
        await widget.onNodesDeleted!(createdNodes.reversed.toList());
      }
      await _deleteCanvasObjects(copies.reversed.toList());
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedCanvasObjectIds
        ..clear()
        ..addAll(copies.map((object) => object.id));
      _selectedCanvasObjectId = copies.last.id;
    });
  }

  Future<void> _insertNodeCopies(
    List<MindmapNode> nodes, {
    required Offset offset,
    List<MindmapNode>? created,
  }) async {
    final callback = widget.onNodeUpdated;
    if (callback == null) return;
    final now = DateTime.now();
    final ids = <String, String>{
      for (var index = 0; index < nodes.length; index++)
        nodes[index].id: 'copy-${now.microsecondsSinceEpoch}-$index',
    };
    final createdIds = <String>{};
    for (final node in nodes) {
      final copy = node.copyWith(
        id: ids[node.id]!,
        title: node.title.endsWith(' copy') ? node.title : '${node.title} copy',
        position: CanvasPosition(
          node.position.dx + offset.dx,
          node.position.dy + offset.dy,
        ),
        relatedNodeIds: <String>[
          for (final relatedId in node.relatedNodeIds)
            if (ids.containsKey(relatedId)) ids[relatedId]!,
        ],
        data: <String, Object?>{
          ...node.data,
          if (node.data['relations'] case final List<Object?> relations)
            'relations': <Map<String, Object?>>[
              for (final relation in relations)
                if (relation case final Map<Object?, Object?> value)
                  if (value['targetId'] case final String targetId)
                    if (ids[targetId] case final String copyTargetId)
                      <String, Object?>{
                        ...value.cast<String, Object?>(),
                        'targetId': copyTargetId,
                      },
            ],
        },
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );
      created?.add(copy);
      createdIds.add(copy.id);
      await callback(copy);
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
      if ((decoded['kind'] != 'var.mindmap.nodes' &&
              decoded['kind'] != 'var.mindmap.selection') ||
          nodes is! List<Object?>) {
        return const [];
      }
      return nodes
          .whereType<Map<Object?, Object?>>()
          .map((node) => MindmapNode.fromJson(node.cast<String, Object?>()))
          .toList(growable: false);
    } on FormatException catch (_) {
      return const [];
    } on TypeError catch (_) {
      return const [];
    }
  }

  Future<void> _deleteSelectedEntities() async {
    final selectedNodes = _selectedNodes();
    final selectedObjects = _selectedCanvasObjects()
        .where((object) => object.type != CanvasObjectType.nodeReference)
        .toList(growable: false);
    final selectedFrameIds = selectedObjects
        .where((object) => object.type == CanvasObjectType.frame)
        .map((object) => object.id)
        .toSet();
    final deletableObjects = selectedObjects
        .where(
          (object) =>
              !object.isLocked &&
              (object.type == CanvasObjectType.frame ||
                  !selectedFrameIds.contains(object.parentFrameId)),
        )
        .toList(growable: false);
    final lockedCount = selectedObjects
        .where((object) => object.isLocked)
        .length;
    final protectedNodeIds = selectedNodes
        .where((node) => selectedFrameIds.contains(node.data['groupId']))
        .map((node) => node.id)
        .toSet();
    final nodesToDelete = selectedNodes
        .where((node) => !protectedNodeIds.contains(node.id))
        .toList(growable: false);
    if (!await _deleteNodes(nodesToDelete)) return;
    final deletableFrames = deletableObjects
        .where((object) => object.type == CanvasObjectType.frame)
        .toList(growable: false);
    final frameIds = deletableFrames.map((frame) => frame.id).toSet();
    final memberNodes = widget.nodes
        .where((node) => frameIds.contains(node.data['groupId']))
        .toList(growable: false);
    final memberObjects = (widget.board?.objects ?? const <CanvasObject>[])
        .where((object) => frameIds.contains(object.parentFrameId))
        .toList(growable: false);
    if (deletableFrames.isNotEmpty &&
        (!_canCreateCanvasObjects ||
            widget.onNodeUpdated == null ||
            !_canUpdateCanvasObjects)) {
      return;
    }
    if (deletableObjects.isNotEmpty && _canDeleteCanvasObjects) {
      try {
        await _deleteCanvasObjects(deletableObjects);
        for (final frame in deletableFrames) {
          await ungroupFrame(frame.id);
        }
      } catch (_) {
        await _createCanvasObjects(deletableObjects);
        final nodeCallback = widget.onNodeUpdated;
        if (nodeCallback != null) {
          for (final node in memberNodes.reversed) {
            await nodeCallback(node);
          }
        }
        await _updateCanvasObjects(memberObjects.reversed.toList());
        return;
      }
      if (!mounted) return;
      if (protectedNodeIds.isNotEmpty) {
        setState(() => _selectedNodeIds.removeAll(protectedNodeIds));
      }
      setState(() {
        _selectedCanvasObjectIds.removeAll(
          deletableObjects.map((object) => object.id),
        );
        _selectedCanvasObjectId = _selectedCanvasObjectIds.lastOrNull;
      });
    }
    if (lockedCount > 0) {
      widget.onStatusMessage?.call(
        'Skipped $lockedCount locked object${lockedCount == 1 ? '' : 's'}',
      );
    }
  }

  Future<bool> _deleteNodes(List<MindmapNode> selected) async {
    final callback = widget.onNodesDeleted;
    if (selected.isEmpty) return true;
    if (callback == null || !mounted) return false;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              selected.length == 1
                  ? 'Delete selected node?'
                  : 'Delete ${selected.length} selected nodes?',
            ),
            content: const Text(
              'Selected nodes will be removed from this canvas. You can undo this action.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return false;
    await callback(List<MindmapNode>.unmodifiable(selected));
    if (!mounted) return false;
    setState(() {
      _selectedNodeIds.removeAll(selected.map((node) => node.id));
      _lastSelectedNodeId = _selectedNodeIds.lastOrNull;
      if (selected.any((node) => node.id == _focusedNodeId)) {
        _focusedNodeId = null;
      }
    });
    if (_selectedNodeIds.isEmpty) widget.onSelectionCleared?.call();
    return true;
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

  Widget _buildMiroToolRail(BuildContext context) {
    final theme = Theme.of(context);
    Widget tool({
      required Key key,
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback? onPressed,
      CanvasObjectType? type,
    }) {
      final button = Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Tooltip(
          message: label,
          child: SizedBox.square(
            dimension: 48,
            child: IconButton(
              key: key,
              onPressed: onPressed,
              style: IconButton.styleFrom(
                backgroundColor: selected
                    ? theme.colorScheme.primaryContainer
                    : Colors.transparent,
                foregroundColor: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              icon: Icon(icon, size: 22),
            ),
          ),
        ),
      );
      final link = type == null ? null : _toolLayerLinks[type];
      return link == null
          ? button
          : CompositedTransformTarget(link: link, child: button);
    }

    final selectActive = !_hasActiveCanvasTool;
    return Material(
      key: const ValueKey('mindmap-canvas-tool-rail'),
      elevation: 6,
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      shadowColor: Colors.black.withValues(alpha: 0.24),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tool(
                key: const ValueKey('mindmap-canvas-tool-select'),
                label: 'Select',
                icon: Icons.near_me_outlined,
                selected: selectActive,
                onPressed: _activateCanvasSelectTool,
              ),
              tool(
                key: const ValueKey('mindmap-canvas-create-sticky'),
                label: 'Sticky note',
                icon: Icons.note_add_outlined,
                selected: _creationObjectType == CanvasObjectType.stickyNote,
                type: CanvasObjectType.stickyNote,
                onPressed: _canCreateCanvasObjects
                    ? () => _showToolSettings(CanvasObjectType.stickyNote)
                    : null,
              ),
              tool(
                key: const ValueKey('mindmap-canvas-create-text'),
                label: 'Text label',
                icon: Icons.title_rounded,
                selected: _creationObjectType == CanvasObjectType.text,
                type: CanvasObjectType.text,
                onPressed: _canCreateCanvasObjects
                    ? () => _showToolSettings(CanvasObjectType.text)
                    : null,
              ),
              tool(
                key: const ValueKey('mindmap-canvas-create-shape'),
                label: 'Shape',
                icon: Icons.category_outlined,
                selected: _creationObjectType == CanvasObjectType.shape,
                type: CanvasObjectType.shape,
                onPressed: _canCreateCanvasObjects
                    ? () => _showToolSettings(CanvasObjectType.shape)
                    : null,
              ),
              tool(
                key: const ValueKey('mindmap-canvas-create-connector'),
                label: 'Connector',
                icon: Icons.polyline_outlined,
                selected: _creationObjectType == CanvasObjectType.connector,
                type: CanvasObjectType.connector,
                onPressed: _canCreateCanvasObjects
                    ? () => _showToolSettings(CanvasObjectType.connector)
                    : null,
              ),
              tool(
                key: const ValueKey('mindmap-canvas-create-freehand'),
                label: 'Freehand pen',
                icon: Icons.draw_outlined,
                selected: _creationObjectType == CanvasObjectType.freehand,
                type: CanvasObjectType.freehand,
                onPressed: _canCreateCanvasObjects
                    ? () => _showToolSettings(CanvasObjectType.freehand)
                    : null,
              ),
              tool(
                key: const ValueKey('mindmap-canvas-create-frame'),
                label: 'Frame / section',
                icon: Icons.crop_free_rounded,
                selected: _creationObjectType == CanvasObjectType.frame,
                type: CanvasObjectType.frame,
                onPressed: _canCreateCanvasObjects
                    ? () => _showToolSettings(CanvasObjectType.frame)
                    : null,
              ),
              tool(
                key: const ValueKey('mindmap-canvas-create-column'),
                label: 'Column',
                icon: Icons.view_column_outlined,
                selected: _creationObjectType == CanvasObjectType.column,
                type: CanvasObjectType.column,
                onPressed: _canCreateCanvasObjects
                    ? () => _showToolSettings(CanvasObjectType.column)
                    : null,
              ),
              tool(
                key: const ValueKey('mindmap-canvas-tool-comment'),
                label: 'Comment',
                icon: Icons.mode_comment_outlined,
                selected: _isCanvasCommentToolActive,
                onPressed:
                    _canUpdateCanvasObjects ||
                        widget.onCollaborationBoardCommentsChanged != null
                    ? _activateCanvasCommentTool
                    : null,
              ),
              const SizedBox(
                width: 32,
                child: Divider(height: 8, thickness: 1),
              ),
              Semantics(
                button: true,
                label: 'More canvas tools',
                child: PopupMenuButton<_CanvasMoreTool>(
                  key: const ValueKey('mindmap-canvas-create-menu'),
                  tooltip: 'More brainstorming tools',
                  padding: EdgeInsets.zero,
                  onSelected: (tool) {
                    switch (tool) {
                      case _CanvasMoreTool.image:
                        unawaited(
                          _selectCanvasCreationTool(CanvasObjectType.image),
                        );
                      case _CanvasMoreTool.linkPreview:
                        unawaited(
                          _selectCanvasCreationTool(
                            CanvasObjectType.linkPreview,
                          ),
                        );
                      case _CanvasMoreTool.eraser:
                        setState(() {
                          _creationObjectType = null;
                          _connectorStartScene = null;
                          _connectorStartObjectId = null;
                          _isCanvasCommentToolActive = false;
                          _isCanvasEraserActive = !_isCanvasEraserActive;
                        });
                      case _CanvasMoreTool.productivityNode:
                        _activateCanvasSelectTool();
                        final callback =
                            widget.onProductivityNodeCreateRequested;
                        if (callback != null) {
                          unawaited(
                            Future<void>.sync(() => callback(viewportCenter)),
                          );
                        }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<_CanvasMoreTool>(
                      key: const ValueKey('mindmap-canvas-create-image'),
                      value: _CanvasMoreTool.image,
                      enabled: _canCreateCanvasObjects,
                      child: const ListTile(
                        leading: Icon(Icons.image_outlined),
                        title: Text('Image'),
                      ),
                    ),
                    PopupMenuItem<_CanvasMoreTool>(
                      key: const ValueKey('mindmap-canvas-create-link-preview'),
                      value: _CanvasMoreTool.linkPreview,
                      enabled: _canCreateCanvasObjects,
                      child: const ListTile(
                        leading: Icon(Icons.link_rounded),
                        title: Text('Link preview'),
                      ),
                    ),
                    PopupMenuItem<_CanvasMoreTool>(
                      key: const ValueKey('mindmap-canvas-eraser'),
                      value: _CanvasMoreTool.eraser,
                      enabled: _canDeleteCanvasObjects,
                      child: ListTile(
                        leading: const Icon(Icons.auto_fix_off_rounded),
                        title: Text(
                          _isCanvasEraserActive ? 'Disable eraser' : 'Eraser',
                        ),
                      ),
                    ),
                    PopupMenuItem<_CanvasMoreTool>(
                      key: const ValueKey(
                        'mindmap-canvas-create-productivity-node',
                      ),
                      value: _CanvasMoreTool.productivityNode,
                      enabled: widget.onProductivityNodeCreateRequested != null,
                      child: const ListTile(
                        leading: Icon(Icons.account_tree_outlined),
                        title: Text('Productivity node'),
                      ),
                    ),
                  ],
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      Icons.add_rounded,
                      size: 24,
                      color:
                          _isCanvasEraserActive ||
                              _creationObjectType == CanvasObjectType.image ||
                              _creationObjectType ==
                                  CanvasObjectType.linkPreview
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
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

  Widget _buildCanvasToolbar(
    BuildContext context, {
    required bool isSearchActive,
    required int filteredCount,
    required bool showCreationTools,
  }) {
    final theme = Theme.of(context);
    final currentScale = _canvasScale(_transformationController.value);

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
      child: _OverlayPanel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Zoom Out',
              icon: const Icon(Icons.zoom_out, size: 20),
              onPressed: _zoomOut,
            ),
            _ToolbarPill(
              label: '${(currentScale * 100).round()}%',
              tooltip: 'Minimize canvas controls',
              onTap: () => setState(() => _isCanvasToolbarCollapsed = true),
            ),
            IconButton(
              tooltip: 'Zoom In',
              icon: const Icon(Icons.zoom_in, size: 20),
              onPressed: _zoomIn,
            ),
            IconButton(
              key: const ValueKey('mindmap-canvas-actual-size'),
              tooltip: 'Actual size (100%)',
              icon: const Icon(Icons.one_x_mobiledata_rounded, size: 20),
              onPressed: _zoomActualSize,
            ),
            IconButton(
              key: const ValueKey('mindmap-canvas-fit-board'),
              tooltip: 'Fit board',
              icon: const Icon(Icons.fit_screen_rounded, size: 20),
              onPressed: _fitBoard,
            ),
            IconButton(
              key: const ValueKey('mindmap-canvas-reset-center'),
              tooltip: 'Reset zoom and center',
              icon: const Icon(Icons.center_focus_strong, size: 20),
              onPressed: _zoomReset,
            ),
            const SizedBox(
              height: 24,
              child: VerticalDivider(width: 16, thickness: 1),
            ),
            IconButton(
              key: const ValueKey('mindmap-canvas-undo'),
              tooltip: 'Undo (Ctrl+Z)',
              icon: const Icon(Icons.undo_rounded, size: 20),
              onPressed: widget.canUndo ? widget.onUndo : null,
            ),
            IconButton(
              key: const ValueKey('mindmap-canvas-redo'),
              tooltip: 'Redo (Ctrl+Shift+Z)',
              icon: const Icon(Icons.redo_rounded, size: 20),
              onPressed: widget.canRedo ? widget.onRedo : null,
            ),
            if (widget.onCanvasAssistantRequested != null)
              IconButton(
                key: const ValueKey('mindmap-canvas-assistant'),
                tooltip: 'Canvas assistant',
                icon: const Icon(Icons.auto_awesome_outlined, size: 20),
                onPressed: widget.onCanvasAssistantRequested,
              ),
            if (showCreationTools)
              PopupMenuButton<CanvasObjectType>(
                key: const ValueKey('mindmap-canvas-create-menu'),
                tooltip: _connectorStartScene == null
                    ? 'Create canvas object'
                    : 'Choose connector end',
                enabled: widget.onCanvasObjectCreated != null,
                icon: Icon(
                  Icons.add_box_outlined,
                  size: 20,
                  color: _creationObjectType == null
                      ? null
                      : theme.colorScheme.primary,
                ),
                onSelected: (type) =>
                    unawaited(_selectCanvasCreationTool(type)),
                itemBuilder: (context) =>
                    const <PopupMenuEntry<CanvasObjectType>>[
                      PopupMenuItem<CanvasObjectType>(
                        key: ValueKey('mindmap-canvas-create-sticky'),
                        value: CanvasObjectType.stickyNote,
                        child: Text('Sticky note'),
                      ),
                      PopupMenuItem<CanvasObjectType>(
                        key: ValueKey('mindmap-canvas-create-shape'),
                        value: CanvasObjectType.shape,
                        child: Text('Shape'),
                      ),
                      PopupMenuItem<CanvasObjectType>(
                        key: ValueKey('mindmap-canvas-create-text'),
                        value: CanvasObjectType.text,
                        child: Text('Text label'),
                      ),
                      PopupMenuItem<CanvasObjectType>(
                        key: ValueKey('mindmap-canvas-create-connector'),
                        value: CanvasObjectType.connector,
                        child: Text('Connector'),
                      ),
                      PopupMenuItem<CanvasObjectType>(
                        key: ValueKey('mindmap-canvas-create-freehand'),
                        value: CanvasObjectType.freehand,
                        child: Text('Freehand pen'),
                      ),
                      PopupMenuItem<CanvasObjectType>(
                        key: ValueKey('mindmap-canvas-create-frame'),
                        value: CanvasObjectType.frame,
                        child: Text('Frame / section'),
                      ),
                      PopupMenuItem<CanvasObjectType>(
                        key: ValueKey('mindmap-canvas-create-image'),
                        value: CanvasObjectType.image,
                        child: Text('Image'),
                      ),
                      PopupMenuItem<CanvasObjectType>(
                        key: ValueKey('mindmap-canvas-create-link-preview'),
                        value: CanvasObjectType.linkPreview,
                        child: Text('Link preview'),
                      ),
                    ],
              ),
            if (showCreationTools)
              IconButton(
                key: const ValueKey('mindmap-canvas-eraser'),
                tooltip: _isCanvasEraserActive
                    ? 'Disable eraser'
                    : 'Erase canvas objects',
                icon: Icon(
                  Icons.auto_fix_off_rounded,
                  size: 20,
                  color: _isCanvasEraserActive
                      ? theme.colorScheme.primary
                      : null,
                ),
                onPressed: widget.onCanvasObjectDeleted == null
                    ? null
                    : () => setState(() {
                        _isCanvasEraserActive = !_isCanvasEraserActive;
                        _creationObjectType = null;
                        _connectorStartScene = null;
                      }),
              ),
            IconButton(
              key: const ValueKey('mindmap-canvas-object-color'),
              tooltip: 'Cycle object color',
              icon: const Icon(Icons.palette_outlined, size: 20),
              onPressed: _selectedCanvasObject() == null
                  ? null
                  : _cycleCanvasObjectColor,
            ),
            IconButton(
              key: const ValueKey('mindmap-canvas-shape-style'),
              tooltip: 'Cycle shape style',
              icon: const Icon(Icons.category_outlined, size: 20),
              onPressed: _selectedCanvasObject()?.type == CanvasObjectType.shape
                  ? _cycleCanvasShape
                  : null,
            ),
            IconButton(
              key: const ValueKey('mindmap-canvas-object-properties'),
              tooltip: 'Object properties',
              icon: const Icon(Icons.tune_rounded, size: 20),
              onPressed: _selectedCanvasObject() == null
                  ? null
                  : () => unawaited(_showCanvasObjectProperties()),
            ),
            PopupMenuButton<_CanvasObjectAction>(
              key: const ValueKey('mindmap-canvas-object-rotation'),
              tooltip: 'Object rotation',
              enabled: _selectedCanvasObject() != null,
              icon: const Icon(Icons.rotate_right_rounded, size: 20),
              onSelected: (action) {
                switch (action) {
                  case _CanvasObjectAction.rotateLeft:
                    _rotateSelectedCanvasObjects(-math.pi / 12);
                  case _CanvasObjectAction.rotateRight:
                    _rotateSelectedCanvasObjects(math.pi / 12);
                  case _CanvasObjectAction.resetRotation:
                    _rotateSelectedCanvasObjects(0, reset: true);
                  default:
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<_CanvasObjectAction>(
                  key: ValueKey('mindmap-canvas-object-rotate-left'),
                  value: _CanvasObjectAction.rotateLeft,
                  child: Text('Rotate -15°'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: ValueKey('mindmap-canvas-object-rotate-right'),
                  value: _CanvasObjectAction.rotateRight,
                  child: Text('Rotate +15°'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: ValueKey('mindmap-canvas-object-rotate-reset'),
                  value: _CanvasObjectAction.resetRotation,
                  child: Text('Reset rotation'),
                ),
              ],
            ),
            PopupMenuButton<_CanvasObjectAction>(
              key: const ValueKey('mindmap-canvas-object-layer'),
              tooltip: 'Object layer',
              enabled: _selectedCanvasObject() != null,
              icon: const Icon(Icons.layers_outlined, size: 20),
              onSelected: (action) => _moveCanvasObjectToLayer(
                front: action == _CanvasObjectAction.bringFront,
              ),
              itemBuilder: (context) => const [
                PopupMenuItem<_CanvasObjectAction>(
                  key: ValueKey('mindmap-canvas-object-send-back'),
                  value: _CanvasObjectAction.sendBack,
                  child: Text('Send to back'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: ValueKey('mindmap-canvas-object-bring-front'),
                  value: _CanvasObjectAction.bringFront,
                  child: Text('Bring to front'),
                ),
              ],
            ),
            PopupMenuButton<_CanvasObjectAction>(
              key: const ValueKey('mindmap-canvas-object-actions'),
              tooltip: 'Object actions',
              enabled: _selectedCanvasObject() != null,
              icon: const Icon(Icons.more_horiz_rounded, size: 20),
              onSelected: _runCanvasObjectAction,
              itemBuilder: (context) => <PopupMenuEntry<_CanvasObjectAction>>[
                const PopupMenuItem<_CanvasObjectAction>(
                  key: ValueKey('mindmap-canvas-object-duplicate'),
                  value: _CanvasObjectAction.duplicate,
                  child: Text('Duplicate'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-lock'),
                  value: _CanvasObjectAction.toggleLock,
                  child: Text(
                    _selectedCanvasObject()?.isLocked == true
                        ? 'Unlock'
                        : 'Lock',
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-group'),
                  value: _CanvasObjectAction.group,
                  enabled: _selectedCanvasObjectIds.length > 1,
                  child: const Text('Group selection'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-ungroup'),
                  value: _CanvasObjectAction.ungroup,
                  enabled: _selectedCanvasObjects().any(
                    (object) => object.parentFrameId != null,
                  ),
                  child: const Text('Ungroup'),
                ),
                const PopupMenuDivider(),
                ?_voteMenuItem(_selectedCanvasObject()),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-comments'),
                  value: _CanvasObjectAction.comments,
                  child: Text(
                    (_selectedCanvasObject()?.openCommentCount ?? 0) > 0
                        ? 'Comments (${_selectedCanvasObject()!.openCommentCount} open)'
                        : 'Comments',
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-align-left'),
                  value: _CanvasObjectAction.alignLeft,
                  enabled: _selectedCanvasObjectIds.length > 1,
                  child: const Text('Align left'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-align-center'),
                  value: _CanvasObjectAction.alignCenter,
                  enabled: _selectedCanvasObjectIds.length > 1,
                  child: const Text('Align horizontal center'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-align-right'),
                  value: _CanvasObjectAction.alignRight,
                  enabled: _selectedCanvasObjectIds.length > 1,
                  child: const Text('Align right'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-align-top'),
                  value: _CanvasObjectAction.alignTop,
                  enabled: _selectedCanvasObjectIds.length > 1,
                  child: const Text('Align top'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-align-middle'),
                  value: _CanvasObjectAction.alignMiddle,
                  enabled: _selectedCanvasObjectIds.length > 1,
                  child: const Text('Align vertical center'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey('mindmap-canvas-object-align-bottom'),
                  value: _CanvasObjectAction.alignBottom,
                  enabled: _selectedCanvasObjectIds.length > 1,
                  child: const Text('Align bottom'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey(
                    'mindmap-canvas-object-distribute-horizontal',
                  ),
                  value: _CanvasObjectAction.distributeHorizontal,
                  enabled: _selectedCanvasObjectIds.length > 2,
                  child: const Text('Distribute horizontally'),
                ),
                PopupMenuItem<_CanvasObjectAction>(
                  key: const ValueKey(
                    'mindmap-canvas-object-distribute-vertical',
                  ),
                  value: _CanvasObjectAction.distributeVertical,
                  enabled: _selectedCanvasObjectIds.length > 2,
                  child: const Text('Distribute vertically'),
                ),
              ],
            ),
            const SizedBox(
              height: 24,
              child: VerticalDivider(width: 16, thickness: 1),
            ),
            IconButton(
              key: const ValueKey('mindmap-canvas-search-toggle'),
              tooltip: 'Search canvas (Ctrl+F)',
              icon: Badge(
                isLabelVisible: isSearchActive,
                label: Text('$filteredCount'),
                child: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: isSearchActive || !_isSearchOverlayCollapsed
                      ? theme.colorScheme.primary
                      : null,
                ),
              ),
              onPressed: _toggleSearchOverlay,
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
              key: const ValueKey('mindmap-presentation-mode'),
              tooltip: 'Enter presentation mode',
              icon: const Icon(Icons.slideshow_outlined, size: 20),
              onPressed: () => setPresentationMode(true),
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
                PopupMenuItem(
                  value: _CanvasLayoutMode.matrix,
                  child: Text('Eisenhower matrix'),
                ),
                PopupMenuItem(
                  value: _CanvasLayoutMode.priorityGrid,
                  child: Text('Priority grid'),
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

    final nodeColors = AppSemanticColors.of(context).nodeColors;
    final minimapSize = viewportSize.width < 600
        ? const Size(136, 96)
        : const Size(180, 120);
    final contentBounds = _minimapSceneBounds(viewportSize);
    return Material(
      color: Colors.transparent,
      child: _OverlayPanel(
        width: minimapSize.width,
        height: minimapSize.height,
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaleX = constraints.maxWidth / contentBounds.width;
            final scaleY = constraints.maxHeight / contentBounds.height;
            final origin = _sceneOrigin;
            return Focus(
              key: const ValueKey('mindmap-minimap-focus'),
              onKeyEvent: (_, event) => _handleMinimapKey(
                event,
                viewportSize,
                minimapSize,
                contentBounds,
              ),
              child: Semantics(
                container: true,
                focusable: true,
                label:
                    'Minimap with ${widget.nodes.length} nodes and ${widget.board?.objects.where((object) => object.type != CanvasObjectType.nodeReference).length ?? 0} canvas objects',
                hint: 'Use arrow keys to move around the canvas',
                child: KeyedSubtree(
                  key: const ValueKey('mindmap-minimap-semantics'),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: GestureDetector(
                            onPanUpdate: (details) => _onMinimapPan(
                              details.localPosition,
                              minimapSize,
                              contentBounds,
                            ),
                            onTapDown: (details) => _onMinimapPan(
                              details.localPosition,
                              minimapSize,
                              contentBounds,
                            ),
                            child: CustomPaint(
                              painter: _MinimapPainter(
                                nodes: widget.nodes,
                                objects: _orderedCanvasObjects(),
                                dragPositions: _dragPositions,
                                objectGeometryOverrides:
                                    _canvasObjectGeometryOverrides,
                                nodeSizes: _nodeSizes,
                                viewportRect: _viewportRectInSceneOf(
                                  viewportSize,
                                ),
                                contentBounds: contentBounds,
                                origin: origin,
                                nodeColors: nodeColors,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!_isHeavyCanvas)
                        for (final node in widget.nodes)
                          Positioned(
                            key: ValueKey('mindmap-minimap-node-${node.id}'),
                            left:
                                (origin.dx +
                                    _positionFor(node).dx -
                                    contentBounds.left) *
                                scaleX,
                            top:
                                (origin.dy +
                                    _positionFor(node).dy -
                                    contentBounds.top) *
                                scaleY,
                            width: _nodeSizeFor(node).width * scaleX,
                            height: _nodeSizeFor(node).height * scaleY,
                            child: const IgnorePointer(
                              child: ExcludeSemantics(child: SizedBox.expand()),
                            ),
                          ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _TinyOverlayButton(
                          tooltip: 'Minimize minimap',
                          icon: Icons.remove_rounded,
                          onPressed: () =>
                              setState(() => _isMinimapCollapsed = true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _setInitialTransform(Size viewport) {
    if (_didSetInitialTransform || !viewport.width.isFinite) return;
    final saved = widget.board?.viewport ?? const CanvasViewport();
    final scale = saved.scale.clamp(0.04, 2.4).toDouble();
    final origin = _sceneOrigin;
    final target = origin + Offset(saved.x, saved.y);
    _didSetInitialTransform = true;
    _transformationController.value =
        Matrix4.translationValues(
                  viewport.width / 2 - target.dx * scale,
                  viewport.height / 2 - target.dy * scale,
                  0,
                ) *
                Matrix4.diagonal3Values(scale, scale, 1)
            as Matrix4;
  }

  CanvasPosition _positionFor(MindmapNode node) {
    final resize = _resizeChanges[node.id];
    if (resize != null) return resize.targetPosition;
    final boardObject = widget.board?.objectById('node:${node.id}');
    final override = _canvasObjectGeometryOverrides['node:${node.id}'];
    return _dragPositions[node.id] ??
        (override != null
            ? CanvasPosition(override.x, override.y)
            : boardObject == null
            ? node.position
            : CanvasPosition(boardObject.geometry.x, boardObject.geometry.y));
  }

  void _applyNodeResize(MindmapNode node, NodeResizeChange change) {
    if (change.phase == NodeResizePhase.cancel) {
      setState(() => _resizeChanges.remove(node.id));
      return;
    }
    final existing = _resizeChanges[node.id];
    final basePosition =
        existing?.basePosition ?? _dragPositions[node.id] ?? node.position;
    final baseSize = existing?.baseSize ?? _nodeSizeFor(node);
    final targetPosition = CanvasPosition(
      basePosition.dx + change.positionDelta.dx,
      basePosition.dy + change.positionDelta.dy,
    );
    _expandSceneToInclude(<Rect>[
      Rect.fromLTWH(
        targetPosition.dx,
        targetPosition.dy,
        change.size.width,
        change.size.height,
      ),
    ]);
    setState(() {
      _resizeChanges[node.id] = _NodeResizeOverride(
        basePosition: basePosition,
        baseSize: baseSize,
        targetPosition: targetPosition,
        targetSize: change.size,
      );
    });
    if (change.phase == NodeResizePhase.commit) {
      widget.onNodeResize?.call(node, change);
    }
  }

  Future<void> _applyAutoLayout(_CanvasLayoutMode mode) async {
    final callback = widget.onNodeMoved;
    if (callback == null || widget.nodes.isEmpty) return;

    final positions = switch (mode) {
      _CanvasLayoutMode.tidy => _tidyGridPositions(widget.nodes),
      _CanvasLayoutMode.radial => _radialPositions(widget.nodes),
      _CanvasLayoutMode.byType => _typeGroupedPositions(widget.nodes),
      _CanvasLayoutMode.timeline => _timelinePositions(widget.nodes),
      _CanvasLayoutMode.matrix => _matrixPositions(widget.nodes),
      _CanvasLayoutMode.priorityGrid => _priorityGridPositions(widget.nodes),
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
    const gap = 48.0;
    final columnWidths = List<double>.filled(columns, 0);
    final rowCount = (sorted.length / columns).ceil();
    final rowHeights = List<double>.filled(rowCount, 0);
    for (var index = 0; index < sorted.length; index++) {
      final size = _nodeSizeFor(sorted[index]);
      final column = index % columns;
      final row = index ~/ columns;
      columnWidths[column] = math.max(columnWidths[column], size.width);
      rowHeights[row] = math.max(rowHeights[row], size.height);
    }
    final totalWidth =
        columnWidths.fold<double>(0, (sum, width) => sum + width) +
        gap * (columns - 1);
    final columnX = <double>[];
    var x = -totalWidth / 2;
    for (final width in columnWidths) {
      columnX.add(x);
      x += width + gap;
    }
    final rowY = <double>[];
    var y = -220.0;
    for (final height in rowHeights) {
      rowY.add(y);
      y += height + gap;
    }
    return <String, CanvasPosition>{
      for (var index = 0; index < sorted.length; index++)
        sorted[index].id: CanvasPosition(
          columnX[index % columns],
          rowY[index ~/ columns],
        ),
    };
  }

  Map<String, CanvasPosition> _radialPositions(List<MindmapNode> nodes) {
    final sorted = [...nodes]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (sorted.isEmpty) return const <String, CanvasPosition>{};
    if (sorted.length == 1) {
      final node = sorted.single;
      final size = _nodeSizeFor(node);
      return <String, CanvasPosition>{
        node.id: CanvasPosition(-size.width / 2, -size.height / 2),
      };
    }
    const gap = 48.0;
    final maxDiagonal = sorted
        .map(_nodeSizeFor)
        .map(
          (size) =>
              math.sqrt(size.width * size.width + size.height * size.height),
        )
        .fold<double>(0, math.max);
    final halfAngle = math.pi / sorted.length;
    final radiusForChord = (maxDiagonal + gap) / (2 * math.sin(halfAngle));
    final radius = math.max(260.0, radiusForChord);
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
    const horizontalGap = 64.0;
    const verticalGap = 48.0;
    var x = -520.0;
    for (final type in NodeType.values) {
      final group = groups[type];
      if (group == null || group.isEmpty) continue;
      group.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      var y = -260.0;
      var columnWidth = 0.0;
      for (final node in group) {
        final size = _nodeSizeFor(node);
        positions[node.id] = CanvasPosition(x, y);
        y += size.height + verticalGap;
        columnWidth = math.max(columnWidth, size.width);
      }
      x += columnWidth + horizontalGap;
    }
    return positions;
  }

  Map<String, CanvasPosition> _timelinePositions(List<MindmapNode> nodes) {
    final sorted = [...nodes]
      ..sort((a, b) {
        final aDate = a.dueDate ?? a.createdAt;
        final bDate = b.dueDate ?? b.createdAt;
        final dateOrder = aDate.compareTo(bDate);
        return dateOrder != 0 ? dateOrder : a.id.compareTo(b.id);
      });
    const gap = 64.0;
    final totalWidth =
        sorted.fold<double>(0, (sum, node) {
          return sum + _nodeSizeFor(node).width;
        }) +
        gap * (sorted.length - 1);
    var x = -totalWidth / 2;
    final positions = <String, CanvasPosition>{};
    for (var index = 0; index < sorted.length; index++) {
      final node = sorted[index];
      positions[node.id] = CanvasPosition(x, index.isEven ? -90 : 90);
      x += _nodeSizeFor(node).width + gap;
    }
    return positions;
  }

  Map<String, CanvasPosition> _matrixPositions(List<MindmapNode> nodes) {
    final quadrants = <int, List<MindmapNode>>{0: [], 1: [], 2: [], 3: []};
    for (final node in nodes) {
      final q = switch (node.priority) {
        NodePriority.urgent => 0,
        NodePriority.high => 1,
        NodePriority.medium => 2,
        NodePriority.low || NodePriority.none => 3,
      };
      quadrants[q]!.add(node);
    }

    final positions = <String, CanvasPosition>{};
    const cellWidth = 380.0;
    const cellHeight = 340.0;
    const padding = 60.0;

    final quadrantOffsets = [
      const Offset(-cellWidth - padding, -cellHeight - padding),
      const Offset(padding, -cellHeight - padding),
      const Offset(-cellWidth - padding, padding),
      const Offset(padding, padding),
    ];

    for (var q = 0; q < 4; q++) {
      final list = quadrants[q]!
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final base = quadrantOffsets[q];
      final cols = math.max(1, math.sqrt(list.length).ceil());
      for (var i = 0; i < list.length; i++) {
        final col = i % cols;
        final row = i ~/ cols;
        positions[list[i].id] = CanvasPosition(
          base.dx + col * (cellWidth + 20),
          base.dy + row * (cellHeight + 20),
        );
      }
    }
    return positions;
  }

  Map<String, CanvasPosition> _priorityGridPositions(List<MindmapNode> nodes) {
    final groups = <NodePriority, List<MindmapNode>>{};
    for (final node in nodes) {
      groups.putIfAbsent(node.priority, () => []).add(node);
    }

    final positions = <String, CanvasPosition>{};
    const cellWidth = 380.0;
    const cellHeight = 340.0;
    const colGap = 80.0;
    const rowGap = 30.0;

    final priorities = [
      NodePriority.urgent,
      NodePriority.high,
      NodePriority.medium,
      NodePriority.low,
      NodePriority.none,
    ];

    var x = -800.0;
    for (final p in priorities) {
      final list = groups[p];
      if (list == null || list.isEmpty) continue;
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      var y = -400.0;
      for (final node in list) {
        positions[node.id] = CanvasPosition(x, y);
        y += cellHeight + rowGap;
      }
      x += cellWidth + colGap;
    }
    return positions;
  }

  Map<String, List<MindmapNode>> _visibleGroups(List<MindmapNode> nodes) {
    final groups = <String, List<MindmapNode>>{};
    for (final node in nodes) {
      final groupId = node.data['groupId'];
      if (groupId is! String || groupId.isEmpty) continue;
      groups.putIfAbsent(groupId, () => []).add(node);
    }
    groups.removeWhere((groupId, members) => members.length < 2);
    return groups;
  }

  void _moveGroup(List<MindmapNode> nodes, Offset delta) {
    final sceneDelta = delta;
    setState(() {
      for (final node in nodes) {
        final current = _positionFor(node);
        _dragPositions[node.id] = CanvasPosition(
          current.dx + sceneDelta.dx,
          current.dy + sceneDelta.dy,
        );
      }
    });
  }

  void _finishGroupMove(List<MindmapNode> nodes) {
    final callback = widget.onNodeMoved;
    if (callback == null) return;
    final finalPositions = <String, CanvasPosition>{
      for (final node in nodes) node.id: _snappedPosition(_positionFor(node)),
    };
    if (_snapToGrid) {
      setState(() {
        for (final entry in finalPositions.entries) {
          _dragPositions[entry.key] = entry.value;
        }
      });
    }
    unawaited(_persistMovedNodes(nodes, finalPositions));
  }

  List<_SmartGuideGeometry> _liveNodeGuideGeometries({
    required Set<String> excludedNodeIds,
  }) => <_SmartGuideGeometry>[
    for (final node in widget.nodes)
      if (!excludedNodeIds.contains(node.id) &&
          _nodeCardKeys[node.id]?.currentContext != null)
        _SmartGuideGeometry(
          'live-node:${node.id}',
          CanvasGeometry(
            x: _positionFor(node).dx,
            y: _positionFor(node).dy,
            width: _nodeSizeFor(node).width,
            height: _nodeSizeFor(node).height,
          ),
        ),
  ];

  List<_SmartGuideGeometry> _nativeGuideGeometries({
    required Set<String> excludedObjectIds,
  }) {
    final liveNodeIds = widget.nodes.map((node) => node.id).toSet();
    return <_SmartGuideGeometry>[
      for (final object in _orderedCanvasObjects())
        if (_isWorkshopObjectVisible(object) &&
            _isCanvasObjectVisible(object, _sceneOrigin) &&
            !excludedObjectIds.contains(object.id) &&
            !(object.type == CanvasObjectType.nodeReference &&
                liveNodeIds.contains(object.mindmapNodeId)))
          _SmartGuideGeometry(
            'native:${object.type.name}:${object.id}',
            object.type == CanvasObjectType.connector
                ? _effectiveConnector(object).geometry
                : _canvasObjectGeometry(object),
          ),
    ];
  }

  void _resetNodeGuideState() {
    final movingIds = _nodeRawDragPositions.keys.toSet();
    _nodeRawDragPositions.clear();
    _dragPositions.removeWhere((id, position) => movingIds.contains(id));
    _nodeSnapRawX = null;
    _nodeSnapRawY = null;
    _nodeInitialCorrectionX = null;
    _nodeInitialCorrectionY = null;
    _nodeVerticalGuideIdentity = null;
    _nodeHorizontalGuideIdentity = null;
    _nodeEngagedGuides = null;
    _nodeSnapReleasedX = false;
    _nodeSnapReleasedY = false;
    _nodeReleasedVerticalIdentity = null;
    _nodeReleasedHorizontalIdentity = null;
    if (mounted && (movingIds.isNotEmpty || _canvasSmartGuides != null)) {
      setState(() => _canvasSmartGuides = null);
    }
  }

  void _moveNode(MindmapNode node, Offset delta) {
    if (_canvasObjectDragGlobalPosition != null ||
        _canvasObjectRawDragGeometries.isNotEmpty) {
      _canvasObjectDragGlobalPosition = null;
      _canvasObjectRawDragGeometries.clear();
      _canvasObjectSnapRawX = null;
      _canvasObjectSnapRawY = null;
      _canvasObjectInitialCorrectionX = null;
      _canvasObjectInitialCorrectionY = null;
      _canvasObjectVerticalGuideIdentity = null;
      _canvasObjectHorizontalGuideIdentity = null;
      _canvasObjectEngagedGuides = null;
      _canvasObjectSnapReleasedX = false;
      _canvasObjectSnapReleasedY = false;
    }
    final movingNodes = _movingSelectionFor(node);
    final movingIds = movingNodes.map((candidate) => candidate.id).toSet();
    for (final movingNode in movingNodes) {
      final raw = _nodeRawDragPositions.putIfAbsent(
        movingNode.id,
        () => _positionFor(movingNode),
      );
      _nodeRawDragPositions[movingNode.id] = CanvasPosition(
        raw.dx + delta.dx,
        raw.dy + delta.dy,
      );
    }
    final raw = _nodeRawDragPositions[node.id]!;
    final size = _nodeSizeFor(node);
    final proposed = CanvasGeometry(
      x: raw.dx,
      y: raw.dy,
      width: size.width,
      height: size.height,
    );
    final scale = _canvasScale(_transformationController.value);
    final engageGuides = _findCanvasSmartGuides(proposed, <_SmartGuideGeometry>[
      ..._liveNodeGuideGeometries(excludedNodeIds: movingIds),
      ..._nativeGuideGeometries(excludedObjectIds: const <String>{}),
    ], screenScale: scale);
    final previous = _nodeEngagedGuides;
    final releaseThreshold = 12 / math.max(scale, 0.01);
    final keepVertical =
        previous?.vertical != null &&
        engageGuides?.verticalIdentity == _nodeVerticalGuideIdentity &&
        _nodeSnapRawX != null &&
        (raw.dx - _nodeSnapRawX!).abs() <= releaseThreshold;
    final keepHorizontal =
        previous?.horizontal != null &&
        engageGuides?.horizontalIdentity == _nodeHorizontalGuideIdentity &&
        _nodeSnapRawY != null &&
        (raw.dy - _nodeSnapRawY!).abs() <= releaseThreshold;
    if (previous?.vertical != null && !keepVertical) {
      _nodeReleasedVerticalIdentity = _nodeVerticalGuideIdentity;
    }
    if (previous?.horizontal != null && !keepHorizontal) {
      _nodeReleasedHorizontalIdentity = _nodeHorizontalGuideIdentity;
    }
    _nodeSnapReleasedX =
        engageGuides?.vertical != null &&
        engageGuides!.verticalIdentity == _nodeReleasedVerticalIdentity;
    _nodeSnapReleasedY =
        engageGuides?.horizontal != null &&
        engageGuides!.horizontalIdentity == _nodeReleasedHorizontalIdentity;
    if (engageGuides?.verticalIdentity != _nodeReleasedVerticalIdentity) {
      _nodeReleasedVerticalIdentity = null;
    }
    if (engageGuides?.horizontalIdentity != _nodeReleasedHorizontalIdentity) {
      _nodeReleasedHorizontalIdentity = null;
    }
    final nextVertical = _nodeSnapReleasedX ? null : engageGuides?.vertical;
    final nextHorizontal = _nodeSnapReleasedY ? null : engageGuides?.horizontal;
    if (!keepVertical) {
      _nodeSnapRawX = nextVertical == null ? null : raw.dx;
      _nodeInitialCorrectionX = nextVertical == null ? null : engageGuides!.dx;
      _nodeVerticalGuideIdentity = nextVertical == null
          ? null
          : engageGuides!.verticalIdentity;
    }
    if (!keepHorizontal) {
      _nodeSnapRawY = nextHorizontal == null ? null : raw.dy;
      _nodeInitialCorrectionY = nextHorizontal == null
          ? null
          : engageGuides!.dy;
      _nodeHorizontalGuideIdentity = nextHorizontal == null
          ? null
          : engageGuides!.horizontalIdentity;
    }
    final dx = keepVertical
        ? _nodeInitialCorrectionX! - (raw.dx - _nodeSnapRawX!)
        : nextVertical == null
        ? 0.0
        : _nodeInitialCorrectionX!;
    final dy = keepHorizontal
        ? _nodeInitialCorrectionY! - (raw.dy - _nodeSnapRawY!)
        : nextHorizontal == null
        ? 0.0
        : _nodeInitialCorrectionY!;
    final guides = _CanvasSmartGuides(
      vertical: keepVertical
          ? previous!.vertical
          : _nodeSnapReleasedX
          ? null
          : engageGuides?.vertical,
      horizontal: keepHorizontal
          ? previous!.horizontal
          : _nodeSnapReleasedY
          ? null
          : engageGuides?.horizontal,
      dx: dx,
      dy: dy,
      distance:
          engageGuides?.distanceAxis == Axis.horizontal &&
                  !_nodeSnapReleasedX ||
              engageGuides?.distanceAxis == Axis.vertical && !_nodeSnapReleasedY
          ? engageGuides?.distance
          : null,
      labelPosition:
          engageGuides?.distanceAxis == Axis.horizontal &&
                  !_nodeSnapReleasedX ||
              engageGuides?.distanceAxis == Axis.vertical && !_nodeSnapReleasedY
          ? engageGuides?.labelPosition
          : null,
      distanceAxis: engageGuides?.distanceAxis,
    );
    if (guides.vertical != null || guides.horizontal != null) {
      _nodeEngagedGuides = guides;
    } else {
      _nodeSnapRawX = null;
      _nodeSnapRawY = null;
      _nodeInitialCorrectionX = null;
      _nodeInitialCorrectionY = null;
      _nodeVerticalGuideIdentity = null;
      _nodeHorizontalGuideIdentity = null;
      _nodeEngagedGuides = null;
    }
    final translation = Offset(dx, dy);
    for (final movingNode in movingNodes) {
      final position = _nodeRawDragPositions[movingNode.id]!;
      _dragPositions[movingNode.id] = CanvasPosition(
        position.dx + translation.dx,
        position.dy + translation.dy,
      );
    }
    _expandSceneToInclude(<Rect>[
      for (final movingNode in movingNodes)
        () {
          final position = _dragPositions[movingNode.id]!;
          final nodeSize = _nodeSizeFor(movingNode);
          return Rect.fromLTWH(
            position.dx,
            position.dy,
            nodeSize.width,
            nodeSize.height,
          );
        }(),
    ]);
    setState(() {
      _canvasSmartGuides = guides.vertical != null || guides.horizontal != null
          ? guides
          : null;
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
    if (callback == null) {
      _resetNodeGuideState();
      _nodeDragGlobalPosition = null;
      return;
    }
    final movingNodes = _movingSelectionFor(node);
    final finalPositions = <String, CanvasPosition>{};
    for (final movingNode in movingNodes) {
      finalPositions[movingNode.id] = _positionFor(movingNode);
    }
    if (_snapToGrid) {
      final guideX = _canvasSmartGuides?.vertical != null;
      final guideY = _canvasSmartGuides?.horizontal != null;
      final primary = finalPositions[node.id]!;
      final correction = Offset(
        guideX ? 0 : (primary.dx / 20).round() * 20 - primary.dx,
        guideY ? 0 : (primary.dy / 20).round() * 20 - primary.dy,
      );
      for (final entry in finalPositions.entries) {
        final position = entry.value;
        finalPositions[entry.key] = CanvasPosition(
          position.dx + correction.dx,
          position.dy + correction.dy,
        );
      }
      setState(() {
        for (final entry in finalPositions.entries) {
          _dragPositions[entry.key] = entry.value;
        }
      });
    }
    _resetNodeGuideState();
    _nodeDragGlobalPosition = null;
    unawaited(_persistMovedNodesWithColumns(movingNodes, finalPositions));
  }

  Future<void> _persistMovedNodesWithColumns(
    List<MindmapNode> nodes,
    Map<String, CanvasPosition> positions,
  ) async {
    final board = widget.board;
    final updates = <String, CanvasObject>{};
    final resolvedPositions = <String, CanvasPosition>{...positions};
    if (board != null && nodes.length == 1) {
      final node = nodes.single;
      final reference = board.objects
          .where(
            (object) =>
                object.type == CanvasObjectType.nodeReference &&
                object.mindmapNodeId == node.id,
          )
          .firstOrNull;
      final position = positions[node.id];
      if (reference != null && position != null) {
        final size = _nodeSizeFor(node);
        final dropped = reference.copyWith(
          geometry: CanvasGeometry(
            x: position.dx,
            y: position.dy,
            width: size.width,
            height: size.height,
          ),
          updatedAt: DateTime.now(),
        );
        final columnUpdates = _columnDropUpdates(dropped, dropped.geometry);
        for (final update in columnUpdates ?? <CanvasObject>[dropped]) {
          updates[update.id] = update;
        }
        final updatedReference = updates[reference.id];
        if (updatedReference != null) {
          resolvedPositions[node.id] = CanvasPosition(
            updatedReference.geometry.x,
            updatedReference.geometry.y,
          );
          if (mounted) {
            setState(() {
              _dragPositions[node.id] = resolvedPositions[node.id]!;
              for (final update in updates.values) {
                _canvasObjectGeometryOverrides[update.id] = update.geometry;
              }
            });
          }
        }
      }
    }
    if (updates.isNotEmpty) await _updateCanvasObjects(updates.values.toList());
    await _persistMovedNodes(nodes, resolvedPositions);
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

  void _startKeyboardConnection(MindmapNode source) {
    final start = _nodeOutputScenePoint(source);
    setState(() {
      _connectionDrag = _ConnectionDrag(
        source: source,
        startScene: start,
        currentScene: start,
        target: null,
      );
    });
  }

  Future<void> _finishKeyboardConnection(MindmapNode target) async {
    final drag = _connectionDrag;
    if (drag == null || drag.source.id == target.id) return;
    setState(() => _connectionDrag = null);
    await widget.onNodeConnected?.call(drag.source, target);
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

  void _startConnectionRelink(
    MindmapNode source,
    MindmapNode oldTarget,
    Offset globalPosition,
  ) {
    final scene = _globalToScene(globalPosition);
    setState(() {
      _connectionDrag = _ConnectionDrag(
        source: source,
        startScene: _nodeOutputScenePoint(source),
        currentScene: scene,
        target: _nodeAtScene(scene, source.id),
      );
    });
  }

  Future<void> _finishConnectionRelink(
    MindmapNode source,
    MindmapNode oldTarget,
  ) async {
    final scene = _connectionDrag?.currentScene;
    if (scene == null) return;
    final newTarget = _nodeAtScene(scene, source.id) ?? _connectionDrag?.target;
    setState(() => _connectionDrag = null);
    if (newTarget?.id == oldTarget.id) return;
    await widget.onNodeDisconnected?.call(source, oldTarget);
    if (newTarget != null) {
      await widget.onNodeConnected?.call(source, newTarget);
    }
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
    final origin = _sceneOrigin;
    return origin +
        Offset(position.dx + size.width, position.dy + _nodePortY(size));
  }

  MindmapNode? _nodeAtScene(Offset scenePosition, [String? sourceId]) {
    final origin = _sceneOrigin;
    for (final node in widget.nodes.reversed) {
      if (sourceId != null && node.id == sourceId) continue;
      final pos = _positionFor(node);
      final size = _nodeSizeFor(node);
      final rect = MindmapExpandedNodeGeometry(
        node: node,
        size: size,
        origin: origin,
        position: pos,
      ).hitRect.inflate(18);
      if (rect.contains(scenePosition)) return node;
    }
    return null;
  }

  bool _connectionAtScene(Offset scenePosition) {
    final origin = _sceneOrigin;
    final nodesById = {for (final node in widget.nodes) node.id: node};
    for (final source in widget.nodes) {
      final sourcePosition = _positionFor(source);
      final sourceSize = _nodeSizeFor(source);
      final start = MindmapExpandedNodeGeometry(
        node: source,
        size: sourceSize,
        origin: origin,
        position: sourcePosition,
      ).outputPort;
      for (final targetId in source.relatedNodeIds) {
        final target = nodesById[targetId];
        if (target == null) continue;
        final targetPosition = _positionFor(target);
        final targetSize = _nodeSizeFor(target);
        final end = MindmapExpandedNodeGeometry(
          node: target,
          size: targetSize,
          origin: origin,
          position: targetPosition,
        ).inputPort;
        if (_distanceToSegment(scenePosition, start, end) <= 12) return true;
      }
    }
    return false;
  }

  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    if (lengthSquared == 0) return (point - start).distance;
    final projection =
        ((point.dx - start.dx) * segment.dx +
            (point.dy - start.dy) * segment.dy) /
        lengthSquared;
    final clampedProjection = projection.clamp(0.0, 1.0);
    final nearest = start + segment * clampedProjection;
    return (point - nearest).distance;
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
    final resize = _resizeChanges[node.id];
    final size =
        resize?.targetSize ?? _nodeSizes[node.id] ?? _effectiveNodeSize(node);
    if (widget.expandedNodeId != node.id) return size;
    final sizingNode = widget.expandedNodeOverride?.id == node.id
        ? widget.expandedNodeOverride!
        : node;
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(sizingNode);
    return Size(policy.width, policy.height);
  }
}

bool _nearlyEqual(double left, double right, {double epsilon = 0.01}) =>
    (left - right).abs() < epsilon;

double _canvasScale(Matrix4 matrix) {
  final storage = matrix.storage;
  return math.sqrt(storage[0] * storage[0] + storage[1] * storage[1]);
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
    final tokens = AppDesignTokens.of(context);
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

    final borderRadius = BorderRadius.circular(tokens.radiusContainer);
    return DecoratedBox(
      key: const ValueKey('connection-target-menu-panel'),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: tokens.shadowHigh,
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.62),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 320,
          constraints: const BoxConstraints(maxHeight: 430),
          padding: const EdgeInsets.all(10),
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
                      icon: NodeVisuals.icon(node.type),
                      color: NodeVisuals.color(context, node.type),
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
                      icon: NodeVisuals.icon(type),
                      color: NodeVisuals.color(context, type),
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
                'Focus: $title ┬╖$visibleCount nodes',
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
  const _LassoSelectionPainter({
    required this.rect,
    required this.accent,
    required this.fill,
  });

  final Rect rect;
  final Color accent;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = fill.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      fillPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LassoSelectionPainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.accent != accent ||
        oldDelegate.fill != fill;
  }
}

class _MultiSelectToolbar extends StatelessWidget {
  const _MultiSelectToolbar({
    required this.nodeCount,
    required this.objectCount,
    required this.canEditNodes,
    required this.canArrange,
    required this.canUpdateObjects,
    required this.canCreateObjects,
    required this.canGroupInFrame,
    required this.canDelete,
    required this.onComplete,
    required this.onGroupInFrame,
    required this.onObjectProperties,
    required this.onObjectLock,
    required this.onObjectRotate,
    required this.onObjectLayer,
    required this.onObjectGroup,
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
    required this.onDelete,
    required this.onClear,
  });

  final int nodeCount;
  final int objectCount;
  final bool canEditNodes;
  final bool canArrange;
  final bool canUpdateObjects;
  final bool canCreateObjects;
  final bool canGroupInFrame;
  final bool canDelete;
  final VoidCallback onComplete;
  final VoidCallback onGroupInFrame;
  final VoidCallback onObjectProperties;
  final VoidCallback onObjectLock;
  final VoidCallback onObjectRotate;
  final VoidCallback onObjectLayer;
  final VoidCallback onObjectGroup;
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
  final VoidCallback onDelete;
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
            Text(
              nodeCount > 0 && objectCount > 0
                  ? '$nodeCount ${nodeCount == 1 ? 'node' : 'nodes'} + $objectCount ${objectCount == 1 ? 'object' : 'objects'} selected'
                  : nodeCount > 0
                  ? '$nodeCount ${nodeCount == 1 ? 'node' : 'nodes'} selected'
                  : '$objectCount ${objectCount == 1 ? 'object' : 'objects'} selected',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(width: 8),
            if (nodeCount > 0 && canEditNodes) ...[
              IconButton.filledTonal(
                tooltip: 'Complete selected tasks/habits',
                visualDensity: VisualDensity.compact,
                onPressed: onComplete,
                icon: const Icon(Icons.check_circle_outline, size: 18),
              ),
              PopupMenuButton<NodeStatus>(
                tooltip: objectCount > 0
                    ? 'Set status for $nodeCount ${nodeCount == 1 ? 'node' : 'nodes'}'
                    : 'Set selected status',
                icon: const Icon(Icons.tune_outlined, size: 18),
                onSelected: onStatusChanged,
                itemBuilder: (context) => [
                  for (final status in NodeStatus.values)
                    PopupMenuItem(value: status, child: Text(status.label)),
                ],
              ),
              PopupMenuButton<NodePriority>(
                tooltip: objectCount > 0
                    ? 'Set priority for $nodeCount ${nodeCount == 1 ? 'node' : 'nodes'}'
                    : 'Set selected priority',
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
                    value: onZoomToSelected,
                    child: const Text('Zoom to selected'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: onCopy, child: const Text('Copy')),
                  PopupMenuItem(value: onPaste, child: const Text('Paste')),
                  if (objectCount == 0 || canCreateObjects)
                    PopupMenuItem(
                      value: onDuplicate,
                      child: const Text('Duplicate'),
                    ),
                ],
              ),
            ],
            if (objectCount > 0 && canUpdateObjects)
              IconButton.filledTonal(
                tooltip: nodeCount > 0
                    ? 'Object properties for $objectCount ${objectCount == 1 ? 'object' : 'objects'}'
                    : 'Object properties',
                visualDensity: VisualDensity.compact,
                onPressed: onObjectProperties,
                icon: const Icon(Icons.tune_rounded, size: 18),
              ),
            if (objectCount > 0 && (canUpdateObjects || canCreateObjects))
              PopupMenuButton<VoidCallback>(
                tooltip: nodeCount > 0
                    ? 'Object actions for $objectCount ${objectCount == 1 ? 'object' : 'objects'}'
                    : 'Object actions',
                icon: const Icon(Icons.layers_outlined, size: 18),
                onSelected: (callback) => callback(),
                itemBuilder: (context) => <PopupMenuEntry<VoidCallback>>[
                  if (canCreateObjects)
                    PopupMenuItem(
                      value: onDuplicate,
                      child: const Text('Duplicate'),
                    ),
                  if (canUpdateObjects) ...[
                    PopupMenuItem(
                      value: onObjectLock,
                      child: const Text('Lock'),
                    ),
                    if (nodeCount == 0 && objectCount > 1)
                      PopupMenuItem(
                        value: onObjectGroup,
                        child: const Text('Group selection'),
                      ),
                    PopupMenuItem(
                      value: onObjectRotate,
                      child: const Text('Rotate +15°'),
                    ),
                    PopupMenuItem(
                      value: onObjectLayer,
                      child: const Text('Bring to front'),
                    ),
                  ],
                ],
              ),
            if (nodeCount > 0 && objectCount > 0 && canGroupInFrame)
              TextButton(
                onPressed: onGroupInFrame,
                child: const Text('Group in frame'),
              ),
            if (nodeCount + objectCount >= 2 && canArrange)
              PopupMenuButton<VoidCallback>(
                tooltip: 'Arrange selected',
                icon: const Icon(Icons.align_horizontal_center, size: 18),
                onSelected: (callback) => callback(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: onAlignHorizontal,
                    child: const Text('Align horizontal'),
                  ),
                  PopupMenuItem(
                    value: onAlignVertical,
                    child: const Text('Align vertical'),
                  ),
                  if (nodeCount + objectCount >= 3) ...[
                    PopupMenuItem(
                      value: onDistributeHorizontal,
                      child: const Text('Distribute horizontal'),
                    ),
                    PopupMenuItem(
                      value: onDistributeVertical,
                      child: const Text('Distribute vertical'),
                    ),
                  ],
                ],
              ),
            IconButton.filledTonal(
              tooltip: 'Copy selected',
              visualDensity: VisualDensity.compact,
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
            const SizedBox(width: 6),
            Container(
              width: 1,
              height: 24,
              color: theme.colorScheme.outlineVariant,
            ),
            if (nodeCount > 0 && canEditNodes) ...[
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Archive selected',
                visualDensity: VisualDensity.compact,
                onPressed: onArchive,
                icon: const Icon(Icons.archive_outlined, size: 18),
              ),
            ],
            if (canDelete) ...[
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Delete selected',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
            const SizedBox(width: 4),
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

class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final radius = borderRadius ?? tokens.radiusContainer;
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: semantic.popover,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: semantic.border),
        boxShadow: tokens.shadowMedium,
      ),
      child: child,
    );
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
          child: _OverlayPanel(
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
  const _ToolbarPill({required this.label, this.tooltip, this.onTap});

  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colorScheme.surface,
        shape: StadiumBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
    final onPressed = onTap;
    if (onPressed == null) return pill;
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: pill,
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
    required this.results,
    required this.activeResultIndex,
    required this.selectedCategory,
    required this.selectedType,
    required this.selectedReviewState,
    required this.nextActionOnly,
    required this.isCollapsed,
    required this.onClearSearch,
    required this.onCategorySelected,
    required this.onTypeSelected,
    required this.onReviewStateSelected,
    required this.onNextActionOnlyChanged,
    required this.onCollapsedChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onResultSelected,
    this.leftInset = 16,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearchActive;
  final List<CanvasSearchResult> results;
  final int activeResultIndex;
  final CanvasSearchCategory selectedCategory;
  final NodeType? selectedType;
  final NodeReviewState? selectedReviewState;
  final bool nextActionOnly;
  final bool isCollapsed;
  final VoidCallback onClearSearch;
  final ValueChanged<CanvasSearchCategory> onCategorySelected;
  final ValueChanged<NodeType?> onTypeSelected;
  final ValueChanged<NodeReviewState?> onReviewStateSelected;
  final ValueChanged<bool> onNextActionOnlyChanged;
  final ValueChanged<bool> onCollapsedChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onResultSelected;
  final double leftInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    const bottom = 76.0;
    final overlayWidth = math
        .min(380.0, width - leftInset - 24)
        .clamp(260.0, 380.0);
    if (isCollapsed) return const SizedBox.shrink();

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            bottom: bottom,
            left: leftInset,
            width: overlayWidth,
            child: MouseRegion(
              onExit: (_) {
                if (!searchFocusNode.hasFocus) {
                  onCollapsedChanged(true);
                }
              },
              child: Material(
                color: Colors.transparent,
                child: _OverlayPanel(
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 38,
                          child: Focus(
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter &&
                                  HardwareKeyboard.instance.isShiftPressed) {
                                onPrevious();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: searchController,
                              focusNode: searchFocusNode,
                              onSubmitted: (_) => onNext(),
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
                                        padding: const EdgeInsets.only(
                                          right: 2,
                                        ),
                                        child: Text(
                                          '${results.length}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color:
                                                    theme.colorScheme.primary,
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
                        ),
                        const SizedBox(height: 8),
                        _CanvasSearchCategoryFilters(
                          selectedCategory: selectedCategory,
                          onSelected: onCategorySelected,
                        ),
                        if (isSearchActive && results.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            label:
                                '${results.length} canvas search results. Result ${activeResultIndex + 1} selected.',
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${activeResultIndex + 1} of ${results.length}',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey(
                                    'mindmap-search-previous',
                                  ),
                                  tooltip: 'Previous result (Shift+Enter)',
                                  onPressed: onPrevious,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('mindmap-search-next'),
                                  tooltip: 'Next result (Enter)',
                                  onPressed: onNext,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 176),
                            child: ListView.builder(
                              key: const ValueKey('mindmap-search-results'),
                              shrinkWrap: true,
                              itemCount: math.min(results.length, 50),
                              itemBuilder: (context, index) {
                                final result = results[index];
                                return Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    key: ValueKey(
                                      'mindmap-search-result-${result.id}',
                                    ),
                                    selected: index == activeResultIndex,
                                    dense: true,
                                    minTileHeight: 48,
                                    leading: Icon(
                                      result.kind == CanvasSearchResultKind.node
                                          ? Icons.account_tree_outlined
                                          : Icons.dashboard_outlined,
                                      size: 18,
                                    ),
                                    title: Text(
                                      result.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(result.secondaryLabel),
                                    onTap: () => onResultSelected(index),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
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

class _CanvasSearchCategoryFilters extends StatelessWidget {
  const _CanvasSearchCategoryFilters({
    required this.selectedCategory,
    required this.onSelected,
  });

  final CanvasSearchCategory selectedCategory;
  final ValueChanged<CanvasSearchCategory> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: CanvasSearchCategory.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final category = CanvasSearchCategory.values[index];
        return ChoiceChip(
          key: ValueKey('mindmap-search-category-${category.name}'),
          label: Text(switch (category) {
            CanvasSearchCategory.all => 'All',
            CanvasSearchCategory.nodes => 'Nodes',
            CanvasSearchCategory.notesAndText => 'Notes/Text',
            CanvasSearchCategory.frames => 'Frames',
            CanvasSearchCategory.media => 'Media',
            CanvasSearchCategory.links => 'Links',
          }),
          selected: selectedCategory == category,
          onSelected: (_) => onSelected(category),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        );
      },
    ),
  );
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
            icon: NodeVisuals.icon(type),
            label: _filterLabel(type),
            color: NodeVisuals.color(context, type),
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
    return FilterChip(
      selected: isSelected,
      onSelected: (_) => onTap(),
      avatar: Icon(icon, size: 15, color: color),
      label: Text(label),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        letterSpacing: 0.05,
      ),
      selectedColor: color.withValues(alpha: 0.24),
      side: BorderSide(
        color: isSelected ? color : theme.colorScheme.outlineVariant,
      ),
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
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
            Flexible(
              child: Text(
                'No canvas items match $query',
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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

class _PositionedNodeGroup extends StatelessWidget {
  const _PositionedNodeGroup({
    required this.groupId,
    required this.nodes,
    required this.positions,
    required this.sizes,
    required this.origin,
    required this.isLocked,
    required this.isPresentationMode,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onSelect,
    required this.onRename,
    required this.onToggleLock,
    required this.onSetSwimlaneMode,
    required this.onUngroup,
  });

  final String groupId;
  final List<MindmapNode> nodes;
  final Map<String, CanvasPosition> positions;
  final Map<String, Size> sizes;
  final Offset origin;
  final bool isLocked;
  final bool isPresentationMode;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onSelect;
  final Future<void> Function() onRename;
  final Future<void> Function(bool locked) onToggleLock;
  final Future<void> Function(String mode) onSetSwimlaneMode;
  final Future<void> Function() onUngroup;

  @override
  Widget build(BuildContext context) {
    Rect? bounds;
    for (final node in nodes) {
      final position = positions[node.id]!;
      final rect = Offset(position.dx, position.dy) & sizes[node.id]!;
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    final frame = bounds!.inflate(28).translate(origin.dx, origin.dy);
    final title = nodes.first.data['groupTitle'] as String? ?? 'Group';
    final swimlaneMode = nodes.first.data['swimlaneMode'] as String? ?? 'none';
    return Positioned.fromRect(
      rect: frame,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              key: ValueKey('mindmap-group-$groupId'),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.24),
                  width: 2,
                ),
              ),
            ),
          ),
          if (swimlaneMode == 'horizontal')
            Center(
              child: Divider(
                color: Colors.white.withValues(alpha: 0.2),
                thickness: 1.5,
              ),
            )
          else if (swimlaneMode == 'vertical')
            Center(
              child: VerticalDivider(
                color: Colors.white.withValues(alpha: 0.2),
                thickness: 1.5,
              ),
            ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.topLeft,
              child: Semantics(
                label: '$title group',
                value: isLocked ? 'Locked' : 'Unlocked',
                child: GestureDetector(
                  key: ValueKey('mindmap-group-handle-$groupId'),
                  behavior: HitTestBehavior.opaque,
                  onTap: isPresentationMode ? null : onSelect,
                  onSecondaryTapDown: isPresentationMode
                      ? null
                      : (details) async {
                          final action = await showMenu<String>(
                            context: context,
                            position: RelativeRect.fromLTRB(
                              details.globalPosition.dx,
                              details.globalPosition.dy,
                              details.globalPosition.dx,
                              details.globalPosition.dy,
                            ),
                            items: [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename group'),
                              ),
                              PopupMenuItem(
                                value: 'lock',
                                child: Text(
                                  isLocked ? 'Unlock group' : 'Lock group',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'swimlane_h',
                                child: Text('Swimlane (Horizontal)'),
                              ),
                              const PopupMenuItem(
                                value: 'swimlane_v',
                                child: Text('Swimlane (Vertical)'),
                              ),
                              const PopupMenuItem(
                                value: 'swimlane_none',
                                child: Text('Clear Swimlane'),
                              ),
                              const PopupMenuItem(
                                value: 'ungroup',
                                child: Text('Ungroup'),
                              ),
                            ],
                          );
                          if (action == 'rename') await onRename();
                          if (action == 'lock') await onToggleLock(!isLocked);
                          if (action == 'swimlane_h') {
                            await onSetSwimlaneMode('horizontal');
                          }
                          if (action == 'swimlane_v') {
                            await onSetSwimlaneMode('vertical');
                          }
                          if (action == 'swimlane_none') {
                            await onSetSwimlaneMode('none');
                          }
                          if (action == 'ungroup') await onUngroup();
                        },
                  onPanUpdate: isLocked || isPresentationMode
                      ? null
                      : (details) => onPanUpdate(details.delta),
                  onPanEnd: isLocked || isPresentationMode
                      ? null
                      : (_) => onPanEnd(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 24, 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLocked) ...[
                          const Icon(
                            Icons.lock,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          title,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
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

class _PositionedCanvasMediaObject extends StatefulWidget {
  const _PositionedCanvasMediaObject({
    required this.object,
    required this.geometry,
    required this.origin,
    required this.isSelected,
    required this.loadAttachmentBytes,
    required this.onSelect,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final CanvasObject object;
  final CanvasGeometry geometry;
  final Offset origin;
  final bool isSelected;
  final CanvasAttachmentBytesLoader? loadAttachmentBytes;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onPanCancel;
  final ValueChanged<Offset> onResizeUpdate;
  final VoidCallback onResizeEnd;

  @override
  State<_PositionedCanvasMediaObject> createState() =>
      _PositionedCanvasMediaObjectState();
}

class _PositionedCanvasMediaObjectState
    extends State<_PositionedCanvasMediaObject> {
  Future<List<int>?>? _bytesFuture;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _PositionedCanvasMediaObject oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.payload['attachmentId'] !=
            widget.object.payload['attachmentId'] ||
        oldWidget.loadAttachmentBytes != widget.loadAttachmentBytes) {
      _loadImage();
    }
  }

  void _loadImage() {
    final attachmentId = widget.object.payload['attachmentId'] as String?;
    final loader = widget.loadAttachmentBytes;
    _bytesFuture =
        attachmentId == null || attachmentId.isEmpty || loader == null
        ? null
        : loader(attachmentId);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final object = widget.object;
    final geometry = widget.geometry;
    final isImage = object.type == CanvasObjectType.image;
    final url = object.payload['url'] as String? ?? '';
    return Positioned(
      key: ValueKey('canvas-object-${object.id}'),
      left: widget.origin.dx + geometry.x,
      top: widget.origin.dy + geometry.y,
      width: geometry.width,
      height: geometry.height,
      child: Transform.rotate(
        angle: geometry.rotation,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelect,
          onDoubleTap: isImage || url.isEmpty
              ? null
              : () => unawaited(launchUrl(Uri.parse(url))),
          onPanStart: object.isLocked ? null : (_) => widget.onSelect(),
          onPanUpdate: object.isLocked
              ? null
              : (details) => widget.onPanUpdate(details.delta),
          onPanEnd: object.isLocked ? null : (_) => widget.onPanEnd(),
          onPanCancel: object.isLocked ? null : widget.onPanCancel,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: widget.isSelected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      width: widget.isSelected ? 3 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: isImage
                        ? FutureBuilder<List<int>?>(
                            future: _bytesFuture,
                            builder: (context, snapshot) {
                              final bytes = snapshot.data;
                              if (bytes != null && bytes.isNotEmpty) {
                                return Image.memory(
                                  _attachmentBytes(bytes),
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                );
                              }
                              return _CanvasMediaPlaceholder(
                                icon: Icons.image_outlined,
                                title:
                                    object.payload['fileName'] as String? ??
                                    'Image',
                              );
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.link_rounded,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  object.payload['title'] as String? ?? url,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              if (widget.isSelected && !object.isLocked)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: GestureDetector(
                    key: ValueKey('canvas-object-resize-${object.id}'),
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) =>
                        widget.onResizeUpdate(details.delta),
                    onPanEnd: (_) => widget.onResizeEnd(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const SizedBox.square(dimension: 18),
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

class _CanvasMediaPlaceholder extends StatelessWidget {
  const _CanvasMediaPlaceholder({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 38),
        const SizedBox(height: 8),
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

class _ShapeToolSettings extends StatelessWidget {
  const _ShapeToolSettings({required this.selected, required this.onSelected});

  final CanvasShapeKind selected;
  final ValueChanged<CanvasShapeKind> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final shape in CanvasShapeKind.values)
        Semantics(
          button: true,
          selected: selected == shape,
          label: shape.name,
          child: InkWell(
            key: ValueKey('canvas-shape-${shape.name}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelected(shape),
            child: Container(
              width: 46,
              height: 42,
              decoration: BoxDecoration(
                color: selected == shape
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: selected == shape
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(_shapeKindIcon(shape), size: 22),
            ),
          ),
        ),
    ],
  );
}

IconData _shapeKindIcon(CanvasShapeKind shape) => switch (shape) {
  CanvasShapeKind.ellipse => Icons.circle_outlined,
  CanvasShapeKind.triangle => Icons.change_history_rounded,
  CanvasShapeKind.diamond => Icons.diamond_outlined,
  CanvasShapeKind.star => Icons.star_border_rounded,
  CanvasShapeKind.arrow => Icons.arrow_forward_rounded,
  CanvasShapeKind.callout => Icons.chat_bubble_outline_rounded,
  CanvasShapeKind.cloud => Icons.cloud_outlined,
  CanvasShapeKind.hexagon || CanvasShapeKind.pentagon => Icons.hexagon_outlined,
  _ => Icons.crop_square_rounded,
};

class _ConnectorToolSettings extends StatelessWidget {
  const _ConnectorToolSettings({
    required this.appearance,
    required this.onChanged,
  });

  final CanvasConnectorAppearance appearance;
  final ValueChanged<CanvasConnectorAppearance> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SegmentedButton<CanvasConnectorStyle>(
        segments: const [
          ButtonSegment(
            value: CanvasConnectorStyle.straight,
            label: Text('Straight'),
          ),
          ButtonSegment(
            value: CanvasConnectorStyle.curved,
            label: Text('Curve'),
          ),
          ButtonSegment(
            value: CanvasConnectorStyle.elbow,
            label: Text('Elbow'),
          ),
        ],
        selected: <CanvasConnectorStyle>{appearance.style},
        onSelectionChanged: (values) =>
            onChanged(appearance.copyWith(style: values.first)),
      ),
      const SizedBox(height: 8),
      SegmentedButton<CanvasLinePattern>(
        segments: const [
          ButtonSegment(value: CanvasLinePattern.solid, label: Text('Solid')),
          ButtonSegment(value: CanvasLinePattern.dashed, label: Text('Dash')),
          ButtonSegment(value: CanvasLinePattern.dotted, label: Text('Dot')),
        ],
        selected: <CanvasLinePattern>{appearance.pattern},
        onSelectionChanged: (values) =>
            onChanged(appearance.copyWith(pattern: values.first)),
      ),
      const SizedBox(height: 12),
      CanvasColorChoices(
        selected: appearance.strokeColor,
        onSelected: (color) =>
            onChanged(appearance.copyWith(strokeColor: color)),
      ),
      const SizedBox(height: 8),
      Text('Width ${appearance.strokeWidth.round()}'),
      Slider(
        key: const ValueKey('canvas-connector-width'),
        value: appearance.strokeWidth,
        min: 1,
        max: 12,
        divisions: 11,
        onChanged: (width) =>
            onChanged(appearance.copyWith(strokeWidth: width)),
      ),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<CanvasArrowhead>(
              key: const ValueKey('canvas-connector-start-arrow'),
              initialValue: appearance.startArrow,
              decoration: const InputDecoration(labelText: 'Start'),
              items: [
                for (final value in CanvasArrowhead.values)
                  DropdownMenuItem(value: value, child: Text(value.name)),
              ],
              onChanged: (value) {
                if (value != null) {
                  onChanged(appearance.copyWith(startArrow: value));
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<CanvasArrowhead>(
              key: const ValueKey('canvas-connector-end-arrow'),
              initialValue: appearance.endArrow,
              decoration: const InputDecoration(labelText: 'End'),
              items: [
                for (final value in CanvasArrowhead.values)
                  DropdownMenuItem(value: value, child: Text(value.name)),
              ],
              onChanged: (value) {
                if (value != null) {
                  onChanged(appearance.copyWith(endArrow: value));
                }
              },
            ),
          ),
        ],
      ),
    ],
  );
}

class _PenToolSettings extends StatelessWidget {
  const _PenToolSettings({required this.appearance, required this.onChanged});

  final CanvasPenAppearance appearance;
  final ValueChanged<CanvasPenAppearance> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SegmentedButton<CanvasPenStyle>(
        segments: const [
          ButtonSegment(value: CanvasPenStyle.pen, label: Text('Pen')),
          ButtonSegment(
            value: CanvasPenStyle.highlighter,
            label: Text('Highlighter'),
          ),
        ],
        selected: <CanvasPenStyle>{appearance.style},
        onSelectionChanged: (values) => onChanged(
          CanvasPenAppearance(
            style: values.first,
            strokeColor: appearance.strokeColor,
            strokeWidth: appearance.strokeWidth,
            opacity: appearance.opacity,
            smoothing: appearance.smoothing,
          ),
        ),
      ),
      const SizedBox(height: 12),
      CanvasColorChoices(
        selected: appearance.strokeColor,
        onSelected: (color) => onChanged(
          CanvasPenAppearance(
            style: appearance.style,
            strokeColor: color,
            strokeWidth: appearance.strokeWidth,
            opacity: appearance.opacity,
            smoothing: appearance.smoothing,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('Width ${appearance.strokeWidth.round()}'),
      Slider(
        key: const ValueKey('canvas-pen-width'),
        value: appearance.strokeWidth,
        min: 1,
        max: 24,
        divisions: 23,
        onChanged: (width) =>
            onChanged(appearance.copyWith(strokeWidth: width)),
      ),
      Text('Opacity ${(appearance.opacity * 100).round()}%'),
      Slider(
        key: const ValueKey('canvas-pen-opacity'),
        value: appearance.opacity,
        min: 0.05,
        max: 1,
        divisions: 19,
        onChanged: (opacity) =>
            onChanged(appearance.copyWith(opacity: opacity)),
      ),
      Text('Smoothing ${(appearance.smoothing * 100).round()}%'),
      Slider(
        key: const ValueKey('canvas-pen-smoothing'),
        value: appearance.smoothing,
        min: 0,
        max: 1,
        divisions: 10,
        onChanged: (smoothing) =>
            onChanged(appearance.copyWith(smoothing: smoothing)),
      ),
    ],
  );
}

class _CanvasToolDraftPainter extends CustomPainter {
  const _CanvasToolDraftPainter({
    required this.draft,
    required this.pen,
    required this.connector,
  }) : super(repaint: draft);

  final _CanvasToolDraft draft;
  final CanvasPenAppearance pen;
  final CanvasConnectorAppearance connector;

  @override
  void paint(Canvas canvas, Size size) {
    if (draft.freehandPoints.length >= 2) {
      _CanvasFreehandPainter(
        points: draft.freehandPoints,
        color: (_canvasColorFromHex(pen.strokeColor) ?? Colors.blue).withValues(
          alpha: pen.style == CanvasPenStyle.highlighter
              ? math.min(pen.opacity, 0.35)
              : pen.opacity,
        ),
        strokeWidth: pen.style == CanvasPenStyle.highlighter
            ? pen.strokeWidth * 2
            : pen.strokeWidth,
      ).paint(canvas, size);
    }
    if (draft.connectorRoute.length >= 2) {
      final color = (_canvasColorFromHex(connector.strokeColor) ?? Colors.blue)
          .withValues(alpha: connector.opacity);
      _CanvasConnectorPainter(
        start: draft.connectorRoute.first,
        end: draft.connectorRoute.last,
        points: draft.connectorRoute,
        color: color,
        strokeWidth: connector.strokeWidth,
        style: connector.style,
        pattern: connector.pattern,
        startArrow: connector.startArrow,
        endArrow: connector.endArrow,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasToolDraftPainter oldDelegate) =>
      oldDelegate.pen != pen || oldDelegate.connector != connector;
}

class _PositionedCanvasFreehand extends StatelessWidget {
  const _PositionedCanvasFreehand({
    required this.object,
    required this.geometry,
    required this.origin,
    required this.isSelected,
    required this.onSelect,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });

  final CanvasObject object;
  final CanvasGeometry geometry;
  final Offset origin;
  final bool isSelected;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onPanCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rawPoints = object.payload['points'];
    final points = rawPoints is List
        ? rawPoints
              .whereType<Map<Object?, Object?>>()
              .map(
                (point) => Offset(
                  (point['x'] as num?)?.toDouble() ?? 0,
                  (point['y'] as num?)?.toDouble() ?? 0,
                ),
              )
              .toList()
        : const <Offset>[];
    final appearance = CanvasPenAppearance.fromPayload(object.payload);
    final baseColor =
        _canvasColorFromHex(appearance.strokeColor) ?? colorScheme.primary;
    final color = baseColor.withValues(
      alpha: appearance.style == CanvasPenStyle.highlighter
          ? math.min(appearance.opacity, 0.35)
          : appearance.opacity,
    );
    return Positioned(
      key: ValueKey('canvas-object-${object.id}'),
      left: origin.dx + geometry.x,
      top: origin.dy + geometry.y,
      width: geometry.width,
      height: geometry.height,
      child: Transform.rotate(
        angle: geometry.rotation,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onSelect,
          onPanStart: object.isLocked ? null : (_) => onSelect(),
          onPanUpdate: object.isLocked
              ? null
              : (details) => onPanUpdate(details.delta),
          onPanEnd: object.isLocked ? null : (_) => onPanEnd(),
          onPanCancel: object.isLocked ? null : onPanCancel,
          child: CustomPaint(
            key: ValueKey('canvas-freehand-paint-${object.id}'),
            painter: _CanvasFreehandPainter(
              points: points,
              color: isSelected ? colorScheme.primary : color,
              strokeWidth: appearance.style == CanvasPenStyle.highlighter
                  ? appearance.strokeWidth * 2
                  : appearance.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasFreehandPainter extends CustomPainter {
  const _CanvasFreehandPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length - 1; index++) {
      final point = points[index];
      final midpoint = (point + points[index + 1]) / 2;
      path.quadraticBezierTo(point.dx, point.dy, midpoint.dx, midpoint.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CanvasFreehandPainter oldDelegate) => true;
}

class _PositionedCanvasConnector extends StatelessWidget {
  const _PositionedCanvasConnector({
    required this.object,
    required this.geometry,
    required this.route,
    required this.origin,
    required this.isSelected,
    required this.onSelect,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
  });

  final CanvasObject object;
  final CanvasGeometry geometry;
  final List<Offset> route;
  final Offset origin;
  final bool isSelected;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onPanCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appearance = CanvasConnectorAppearance.fromPayload(object.payload);
    final color =
        _canvasColorFromHex(appearance.strokeColor) ?? colorScheme.primary;
    return Positioned(
      key: ValueKey('canvas-object-${object.id}'),
      left: origin.dx + geometry.x,
      top: origin.dy + geometry.y,
      width: geometry.width,
      height: geometry.height,
      child: Transform.rotate(
        angle: geometry.rotation,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onSelect,
          onPanStart: object.isLocked ? null : (_) => onSelect(),
          onPanUpdate: object.isLocked
              ? null
              : (details) => onPanUpdate(details.delta),
          onPanEnd: object.isLocked ? null : (_) => onPanEnd(),
          onPanCancel: object.isLocked ? null : onPanCancel,
          child: CustomPaint(
            key: ValueKey('canvas-connector-paint-${object.id}'),
            painter: _CanvasConnectorPainter(
              start: Offset(
                (object.payload['startX'] as num?)?.toDouble() ?? 12,
                (object.payload['startY'] as num?)?.toDouble() ?? 12,
              ),
              end: Offset(
                (object.payload['endX'] as num?)?.toDouble() ??
                    geometry.width - 12,
                (object.payload['endY'] as num?)?.toDouble() ??
                    geometry.height - 12,
              ),
              points: route,
              color: isSelected
                  ? colorScheme.primary
                  : color.withValues(alpha: appearance.opacity),
              strokeWidth: appearance.strokeWidth,
              style: appearance.style,
              pattern: appearance.pattern,
              startArrow: appearance.startArrow,
              endArrow: appearance.endArrow,
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasConnectorPainter extends CustomPainter {
  const _CanvasConnectorPainter({
    required this.start,
    required this.end,
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.style = CanvasConnectorStyle.elbow,
    this.pattern = CanvasLinePattern.solid,
    this.startArrow = CanvasArrowhead.none,
    this.endArrow = CanvasArrowhead.open,
  });

  final Offset start;
  final Offset end;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final CanvasConnectorStyle style;
  final CanvasLinePattern pattern;
  final CanvasArrowhead startArrow;
  final CanvasArrowhead endArrow;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final route = points.length >= 2 ? points : <Offset>[start, end];
    final path = Path()..moveTo(route.first.dx, route.first.dy);
    if (style == CanvasConnectorStyle.curved && route.length == 2) {
      final control = Offset(
        (route.first.dx + route.last.dx) / 2,
        math.min(route.first.dy, route.last.dy) -
            (route.last - route.first).distance * 0.2,
      );
      path.quadraticBezierTo(
        control.dx,
        control.dy,
        route.last.dx,
        route.last.dy,
      );
    } else {
      for (final point in route.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
    }
    _drawPatternedPath(canvas, path, paint);
    _drawArrowhead(canvas, route.first, route[1], startArrow, paint);
    _drawArrowhead(
      canvas,
      route.last,
      route[route.length - 2],
      endArrow,
      paint,
    );
  }

  void _drawPatternedPath(Canvas canvas, Path path, Paint paint) {
    if (pattern == CanvasLinePattern.solid) {
      canvas.drawPath(path, paint);
      return;
    }
    final lengths = pattern == CanvasLinePattern.dashed
        ? const (10.0, 7.0)
        : const (2.0, 6.0);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + lengths.$1, metric.length),
          ),
          paint,
        );
        distance += lengths.$1 + lengths.$2;
      }
    }
  }

  void _drawArrowhead(
    Canvas canvas,
    Offset tip,
    Offset toward,
    CanvasArrowhead arrow,
    Paint paint,
  ) {
    if (arrow == CanvasArrowhead.none || (tip - toward).distance < 1) return;
    final direction = (tip - toward) / (tip - toward).distance;
    final normal = Offset(-direction.dy, direction.dx);
    final length = math.max(12.0, strokeWidth * 4).toDouble();
    final base = tip - direction * length;
    switch (arrow) {
      case CanvasArrowhead.none:
        return;
      case CanvasArrowhead.open:
        canvas
          ..drawLine(tip, base + normal * length * 0.45, paint)
          ..drawLine(tip, base - normal * length * 0.45, paint);
      case CanvasArrowhead.filled:
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(
              base.dx + normal.dx * length * 0.5,
              base.dy + normal.dy * length * 0.5,
            )
            ..lineTo(
              base.dx - normal.dx * length * 0.5,
              base.dy - normal.dy * length * 0.5,
            )
            ..close(),
          Paint()..color = paint.color,
        );
      case CanvasArrowhead.diamond:
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(
              base.dx + normal.dx * length * 0.42,
              base.dy + normal.dy * length * 0.42,
            )
            ..lineTo(
              (tip - direction * length * 1.8).dx,
              (tip - direction * length * 1.8).dy,
            )
            ..lineTo(
              base.dx - normal.dx * length * 0.42,
              base.dy - normal.dy * length * 0.42,
            )
            ..close(),
          Paint()
            ..color = paint.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = paint.strokeWidth,
        );
      case CanvasArrowhead.circle:
        canvas.drawCircle(
          tip - direction * length * 0.45,
          length * 0.42,
          Paint()
            ..color = paint.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = paint.strokeWidth,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasConnectorPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.points.length != points.length ||
      oldDelegate.points.indexed.any((entry) => entry.$2 != points[entry.$1]) ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.style != style ||
      oldDelegate.pattern != pattern ||
      oldDelegate.startArrow != startArrow ||
      oldDelegate.endArrow != endArrow;
}

enum _CanvasObjectAction {
  properties,
  duplicate,
  toggleLock,
  rotateLeft,
  rotateRight,
  resetRotation,
  sendBack,
  bringFront,
  group,
  ungroup,
  addVote,
  removeVote,
  comments,
  alignLeft,
  alignCenter,
  alignRight,
  alignTop,
  alignMiddle,
  alignBottom,
  distributeHorizontal,
  distributeVertical,
  delete,
}

class _CanvasAssistantPreviewOutline extends StatelessWidget {
  const _CanvasAssistantPreviewOutline({
    required this.object,
    required this.origin,
  });

  final CanvasObject object;
  final Offset origin;

  @override
  Widget build(BuildContext context) => Positioned(
    key: ValueKey('canvas-assistant-preview-${object.id}'),
    left: origin.dx + object.geometry.x - 5,
    top: origin.dy + object.geometry.y - 5,
    width: object.geometry.width + 10,
    height: object.geometry.height + 10,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.auto_awesome, size: 16),
          ),
        ),
      ),
    ),
  );
}

class _CanvasObjectSignalsBadge extends StatelessWidget {
  const _CanvasObjectSignalsBadge({
    required this.object,
    required this.voteCount,
    required this.hasLocalVote,
    required this.openCommentCount,
    required this.geometry,
    required this.origin,
  });

  final CanvasObject object;
  final int voteCount;
  final bool hasLocalVote;
  final int openCommentCount;
  final CanvasGeometry geometry;
  final Offset origin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      left: origin.dx + geometry.x,
      top: origin.dy + geometry.y,
      width: geometry.width,
      height: geometry.height,
      child: IgnorePointer(
        child: FittedBox(
          alignment: Alignment.topRight,
          fit: BoxFit.scaleDown,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: [
              if (hasLocalVote)
                Container(
                  key: ValueKey('canvas-object-your-vote-${object.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: ShapeDecoration(
                    color: colorScheme.secondaryContainer,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'Your vote',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (openCommentCount > 0)
                Container(
                  key: ValueKey('canvas-object-comments-${object.id}'),
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: ShapeDecoration(
                    color: colorScheme.tertiaryContainer,
                    shape: const StadiumBorder(),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mode_comment_outlined,
                        size: 14,
                        color: colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$openCommentCount',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              if (voteCount > 0)
                Container(
                  key: ValueKey('canvas-object-votes-${object.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: ShapeDecoration(
                    color: colorScheme.primaryContainer,
                    shape: const StadiumBorder(),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.how_to_vote_outlined,
                        size: 14,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$voteCount',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
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
}

class _PositionedCanvasObject extends StatefulWidget {
  const _PositionedCanvasObject({
    required this.object,
    required this.geometry,
    required this.origin,
    required this.isSelected,
    required this.onSelect,
    this.onOpen,
    required this.onPanDown,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    required this.onTextChanged,
    required this.onEditingFinished,
    super.key,
  });

  final CanvasObject object;
  final CanvasGeometry geometry;
  final Offset origin;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback? onOpen;
  final ValueChanged<Offset> onPanDown;
  final ValueChanged<Offset> onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onPanCancel;
  final ValueChanged<Offset> onResizeUpdate;
  final VoidCallback onResizeEnd;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onEditingFinished;

  @override
  State<_PositionedCanvasObject> createState() =>
      _PositionedCanvasObjectState();
}

TextAlign _canvasTextAlign(CanvasTextHorizontalAlign alignment) =>
    switch (alignment) {
      CanvasTextHorizontalAlign.left => TextAlign.left,
      CanvasTextHorizontalAlign.center => TextAlign.center,
      CanvasTextHorizontalAlign.right => TextAlign.right,
    };

Alignment _canvasTextAlignment(CanvasTextStyle style) =>
    switch ((style.horizontalAlign, style.verticalAlign)) {
      (CanvasTextHorizontalAlign.left, CanvasTextVerticalAlign.top) =>
        Alignment.topLeft,
      (CanvasTextHorizontalAlign.center, CanvasTextVerticalAlign.top) =>
        Alignment.topCenter,
      (CanvasTextHorizontalAlign.right, CanvasTextVerticalAlign.top) =>
        Alignment.topRight,
      (CanvasTextHorizontalAlign.left, CanvasTextVerticalAlign.center) =>
        Alignment.centerLeft,
      (CanvasTextHorizontalAlign.center, CanvasTextVerticalAlign.center) =>
        Alignment.center,
      (CanvasTextHorizontalAlign.right, CanvasTextVerticalAlign.center) =>
        Alignment.centerRight,
      (CanvasTextHorizontalAlign.left, CanvasTextVerticalAlign.bottom) =>
        Alignment.bottomLeft,
      (CanvasTextHorizontalAlign.center, CanvasTextVerticalAlign.bottom) =>
        Alignment.bottomCenter,
      (CanvasTextHorizontalAlign.right, CanvasTextVerticalAlign.bottom) =>
        Alignment.bottomRight,
    };

TextStyle _canvasObjectTextStyle(
  BuildContext context,
  CanvasTextStyle style, {
  required Color fallbackColor,
  bool forceBold = false,
}) => Theme.of(context).textTheme.titleMedium!.copyWith(
  color: _canvasColorFromHex(style.textColor) ?? fallbackColor,
  fontSize: style.fontSize,
  fontWeight: forceBold || style.isBold ? FontWeight.w700 : FontWeight.normal,
  fontStyle: style.isItalic ? FontStyle.italic : FontStyle.normal,
);

class _CanvasShapePainter extends CustomPainter {
  const _CanvasShapePainter({
    required this.kind,
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
  });

  final CanvasShapeKind kind;
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;

  Path _path(Size size) {
    final rect = Offset.zero & size;
    final path = Path();
    switch (kind) {
      case CanvasShapeKind.rectangle:
        path.addRect(rect);
      case CanvasShapeKind.roundedRectangle:
        path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)));
      case CanvasShapeKind.ellipse:
        path.addOval(rect);
      case CanvasShapeKind.triangle:
        path
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
      case CanvasShapeKind.diamond:
        path
          ..moveTo(size.width / 2, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(0, size.height / 2)
          ..close();
      case CanvasShapeKind.parallelogram:
        path
          ..moveTo(size.width * 0.2, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width * 0.8, size.height)
          ..lineTo(0, size.height)
          ..close();
      case CanvasShapeKind.trapezoid:
        path
          ..moveTo(size.width * 0.2, 0)
          ..lineTo(size.width * 0.8, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
      case CanvasShapeKind.pentagon:
        _addRegularPolygon(path, size, 5);
      case CanvasShapeKind.hexagon:
        _addRegularPolygon(path, size, 6);
      case CanvasShapeKind.star:
        _addStar(path, size);
      case CanvasShapeKind.arrow:
        path
          ..moveTo(0, size.height * 0.3)
          ..lineTo(size.width * 0.6, size.height * 0.3)
          ..lineTo(size.width * 0.6, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(size.width * 0.6, size.height)
          ..lineTo(size.width * 0.6, size.height * 0.7)
          ..lineTo(0, size.height * 0.7)
          ..close();
      case CanvasShapeKind.callout:
        path
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, size.width, size.height * 0.82),
              const Radius.circular(18),
            ),
          )
          ..moveTo(size.width * 0.62, size.height * 0.8)
          ..lineTo(size.width * 0.78, size.height)
          ..lineTo(size.width * 0.76, size.height * 0.76)
          ..close();
      case CanvasShapeKind.cloud:
        path
          ..moveTo(size.width * 0.2, size.height * 0.8)
          ..cubicTo(
            0,
            size.height * 0.76,
            0,
            size.height * 0.45,
            size.width * 0.2,
            size.height * 0.42,
          )
          ..cubicTo(
            size.width * 0.2,
            size.height * 0.12,
            size.width * 0.52,
            size.height * 0.02,
            size.width * 0.66,
            size.height * 0.28,
          )
          ..cubicTo(
            size.width * 0.94,
            size.height * 0.18,
            size.width,
            size.height * 0.52,
            size.width * 0.84,
            size.height * 0.66,
          )
          ..cubicTo(
            size.width * 0.8,
            size.height * 0.88,
            size.width * 0.42,
            size.height * 0.9,
            size.width * 0.2,
            size.height * 0.8,
          )
          ..close();
    }
    return path;
  }

  void _addRegularPolygon(Path path, Size size, int sides) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var index = 0; index < sides; index++) {
      final angle = -math.pi / 2 + index * math.pi * 2 / sides;
      final point =
          center +
          Offset(
            math.cos(angle) * size.width / 2,
            math.sin(angle) * size.height / 2,
          );
      index == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();
  }

  void _addStar(Path path, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var index = 0; index < 10; index++) {
      final radius = index.isEven ? 1.0 : 0.45;
      final angle = -math.pi / 2 + index * math.pi / 5;
      final point =
          center +
          Offset(
            math.cos(angle) * size.width / 2 * radius,
            math.sin(angle) * size.height / 2 * radius,
          );
      index == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    path.close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.drawPath(path, Paint()..color = fillColor);
    if (borderWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = borderColor
          ..strokeWidth = borderWidth
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasShapePainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth;
}

class _PositionedCanvasColumn extends StatelessWidget {
  const _PositionedCanvasColumn({
    required this.object,
    required this.geometry,
    required this.origin,
    required this.isSelected,
    required this.onSelect,
    required this.onPanDown,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onToggle,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final CanvasObject object;
  final CanvasGeometry geometry;
  final Offset origin;
  final bool isSelected;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onPanDown;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onToggle;
  final ValueChanged<Offset> onResizeUpdate;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned(
      key: ValueKey('canvas-column-${object.id}'),
      left: origin.dx + geometry.x,
      top: origin.dy + geometry.y,
      width: geometry.width,
      height: geometry.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border.all(
                  color: isSelected ? colors.primary : colors.outlineVariant,
                  width: isSelected ? 3 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: object.isLocked
                        ? null
                        : (details) {
                            onSelect();
                            onPanDown(details.globalPosition);
                          },
                    onLongPressMoveUpdate: object.isLocked
                        ? null
                        : (details) => onPanUpdate(details.globalPosition),
                    onLongPressEnd: object.isLocked ? null : (_) => onPanEnd(),
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: object.isLocked
                          ? null
                          : (event) {
                              if (event.kind == PointerDeviceKind.touch) return;
                              onSelect();
                              onPanDown(event.position);
                            },
                      onPointerMove: object.isLocked
                          ? null
                          : (event) {
                              if (event.kind != PointerDeviceKind.touch) {
                                onPanUpdate(event.position);
                              }
                            },
                      onPointerUp: object.isLocked
                          ? null
                          : (event) {
                              if (event.kind != PointerDeviceKind.touch) {
                                onPanEnd();
                              }
                            },
                      child: SizedBox(
                        height: CanvasColumnLayoutEngine.headerHeight,
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                object.columnTitle,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              key: ValueKey(
                                'canvas-column-collapse-${object.id}',
                              ),
                              tooltip: object.isColumnCollapsed
                                  ? 'Expand column'
                                  : 'Collapse column',
                              onPressed: onToggle,
                              icon: Icon(
                                object.isColumnCollapsed
                                    ? Icons.expand_more
                                    : Icons.expand_less,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!object.isColumnCollapsed)
                    Expanded(
                      child: Container(
                        key: ValueKey('canvas-column-body-${object.id}'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isSelected && !object.isLocked)
            Positioned(
              right: -6,
              bottom: -6,
              child: GestureDetector(
                key: ValueKey('canvas-column-resize-${object.id}'),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => onResizeUpdate(details.delta),
                onPanEnd: (_) => onResizeEnd(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const SizedBox.square(dimension: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PositionedCanvasObjectState extends State<_PositionedCanvasObject> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _autosaveTimer;
  bool _isEditing = false;
  bool _selectAllOnFocus = false;
  String _lastSavedText = '';

  String get _objectText =>
      widget.object.payload['text'] as String? ??
      (widget.object.type == CanvasObjectType.frame
          ? 'Section'
          : widget.object.type == CanvasObjectType.text
          ? 'Text label'
          : widget.object.type == CanvasObjectType.shape
          ? ''
          : 'Sticky note');

  @override
  void initState() {
    super.initState();
    _lastSavedText = _objectText;
    _controller = TextEditingController(text: _lastSavedText);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _PositionedCanvasObject oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.object.payload != widget.object.payload) {
      _lastSavedText = _objectText;
      _controller.text = _lastSavedText;
    }
  }

  @override
  void dispose() {
    _flushText();
    _autosaveTimer?.cancel();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_isEditing && !_focusNode.hasFocus) _finishEditing();
  }

  void beginInlineEdit() => _startEditing(selectAll: true);

  void _startEditing({bool selectAll = false}) {
    if ((widget.object.type != CanvasObjectType.stickyNote &&
            widget.object.type != CanvasObjectType.text &&
            widget.object.type != CanvasObjectType.shape &&
            widget.object.type != CanvasObjectType.frame) ||
        widget.object.isLocked) {
      return;
    }
    _selectAllOnFocus = selectAll;
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = _selectAllOnFocus
          ? TextSelection(baseOffset: 0, extentOffset: _controller.text.length)
          : TextSelection.collapsed(offset: _controller.text.length);
      _selectAllOnFocus = false;
    });
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 400), _flushText);
  }

  void _flushText() {
    _autosaveTimer?.cancel();
    final text = _controller.text;
    if (text == _lastSavedText) return;
    _lastSavedText = text;
    widget.onTextChanged(text);
  }

  void _finishEditing() {
    if (!_isEditing) return;
    _flushText();
    if (mounted) setState(() => _isEditing = false);
    _focusNode.unfocus();
    widget.onEditingFinished();
  }

  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _finishEditing();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _finishEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final object = widget.object;
    final geometry = widget.geometry;
    final isSticky = object.type == CanvasObjectType.stickyNote;
    final isText = object.type == CanvasObjectType.text;
    final isShape = object.type == CanvasObjectType.shape;
    final isFrame = object.type == CanvasObjectType.frame;
    final isBoardReference = object.type == CanvasObjectType.boardReference;
    final textStyle = CanvasTextStyle.fromPayload(object.payload);
    final color = object.payload['color'] as String?;
    final themedFill = switch (color) {
      'blue' => colorScheme.primaryContainer,
      'green' => Color.alphaBlend(
        Colors.green.withValues(alpha: 0.28),
        colorScheme.surface,
      ),
      'rose' => colorScheme.errorContainer,
      _ => colorScheme.tertiaryContainer,
    };
    final opacity = ((object.payload['opacity'] as num?)?.toDouble() ?? 1)
        .clamp(0.1, 1.0);
    final fill = isText
        ? Colors.transparent
        : (_canvasColorFromHex(object.payload['fillColor']) ?? themedFill)
              .withValues(alpha: opacity);
    final borderColor =
        _canvasColorFromHex(object.payload['borderColor']) ??
        (widget.isSelected ? colorScheme.primary : colorScheme.outlineVariant);
    final borderWidth =
        ((object.payload['borderWidth'] as num?)?.toDouble() ??
                (widget.isSelected ? 3 : 1))
            .clamp(0.0, 12.0);
    final foreground = switch (color) {
      'blue' => colorScheme.onPrimaryContainer,
      'rose' => colorScheme.onErrorContainer,
      _ => colorScheme.onTertiaryContainer,
    };
    final shape = object.payload['shape'] as String? ?? 'roundedRectangle';
    final borderRadius = isSticky
        ? BorderRadius.circular(8)
        : isFrame
        ? BorderRadius.circular(12)
        : switch (shape) {
            'rectangle' => BorderRadius.zero,
            'ellipse' => BorderRadius.circular(999),
            _ => BorderRadius.circular(18),
          };
    final objectLabel =
        object.payload['text'] as String? ??
        object.payload['title'] as String? ??
        (isFrame
            ? 'Section'
            : isText
            ? 'Text label'
            : isBoardReference
            ? 'Nested board'
            : 'Canvas object');
    return Positioned(
      key: ValueKey('canvas-object-${object.id}'),
      left: widget.origin.dx + geometry.x,
      top: widget.origin.dy + geometry.y,
      width: geometry.width,
      height: geometry.height,
      child: Transform.rotate(
        angle: geometry.rotation,
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (isBoardReference) {
                widget.onOpen?.call();
              } else if (isSticky || isText || isShape || isFrame) {
                _startEditing();
              } else {
                widget.onSelect();
              }

              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.space) {
              widget.onSelect();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Semantics(
            key: ValueKey('canvas-object-semantics-${object.id}'),
            container: true,
            focusable: true,
            selected: widget.isSelected,
            button: true,
            label: '${object.type.name}: $objectLabel',
            value: object.isLocked ? 'Locked' : 'Unlocked',
            hint: isBoardReference
                ? 'Press Enter to open or Space to select'
                : isSticky || isText || isShape || isFrame
                ? 'Press Enter to edit or Space to select'
                : 'Press Enter or Space to select',
            onTap: isBoardReference ? widget.onOpen : widget.onSelect,

            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => widget.onSelect(),
              onTap: widget.onSelect,
              onDoubleTap: isBoardReference
                  ? widget.onOpen
                  : isSticky || isText || isShape || isFrame
                  ? () => _startEditing()
                  : null,

              onLongPressStart: object.isLocked || _isEditing
                  ? null
                  : (details) {
                      widget.onPanDown(details.globalPosition);
                      widget.onPanStart(details.globalPosition);
                    },
              onLongPressMoveUpdate: object.isLocked || _isEditing
                  ? null
                  : (details) => widget.onPanUpdate(details.globalPosition),
              onLongPressEnd: object.isLocked || _isEditing
                  ? null
                  : (_) => widget.onPanEnd(),
              onPanDown: _isEditing
                  ? null
                  : (details) => widget.onPanDown(details.globalPosition),
              onPanStart: _isEditing
                  ? null
                  : (details) => widget.onPanStart(details.globalPosition),
              onPanUpdate: object.isLocked || _isEditing
                  ? null
                  : (details) => widget.onPanUpdate(details.globalPosition),
              onPanEnd: object.isLocked || _isEditing
                  ? null
                  : (_) => widget.onPanEnd(),
              onPanCancel: object.isLocked || _isEditing
                  ? null
                  : widget.onPanCancel,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: isShape
                        ? CustomPaint(
                            key: ValueKey('canvas-shape-paint-${object.id}'),
                            painter: _CanvasShapePainter(
                              kind: CanvasShapeStyle.fromPayload(
                                object.payload,
                              ).kind,
                              fillColor: fill,
                              borderColor: widget.isSelected
                                  ? colorScheme.primary
                                  : borderColor,
                              borderWidth: widget.isSelected
                                  ? math.max(3, borderWidth)
                                  : borderWidth,
                            ),
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: fill,
                              borderRadius: borderRadius,
                              border: Border.all(
                                color: widget.isSelected
                                    ? colorScheme.primary
                                    : borderColor,
                                width: widget.isSelected
                                    ? math.max(3, borderWidth)
                                    : borderWidth,
                              ),
                              boxShadow: <BoxShadow>[
                                if (!isText && !isFrame)
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  if (isBoardReference)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.dashboard_customize_outlined,
                              color: colorScheme.primary,
                              size: 32,
                            ),
                            const Spacer(),
                            Text(
                              'Nested board',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Open board',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (isSticky || isText || isShape || isFrame)
                    Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.all(
                          isFrame ? 12 : textStyle.padding,
                        ),
                        child: _isEditing
                            ? Focus(
                                onKeyEvent: _handleEditorKey,
                                child: TextField(
                                  key: ValueKey(
                                    'canvas-object-editor-${object.id}',
                                  ),
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  maxLines: null,
                                  expands: false,
                                  onChanged: (_) => _scheduleAutosave(),
                                  textAlign: _canvasTextAlign(
                                    textStyle.horizontalAlign,
                                  ),
                                  style: _canvasObjectTextStyle(
                                    context,
                                    textStyle,
                                    fallbackColor: isSticky
                                        ? foreground
                                        : colorScheme.onSurface,
                                    forceBold: isFrame,
                                  ),
                                  decoration: const InputDecoration.collapsed(
                                    hintText: 'Write something',
                                  ),
                                ),
                              )
                            : IgnorePointer(
                                child: Align(
                                  alignment: _canvasTextAlignment(textStyle),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      _objectText,
                                      textAlign: _canvasTextAlign(
                                        textStyle.horizontalAlign,
                                      ),
                                      style: _canvasObjectTextStyle(
                                        context,
                                        textStyle,
                                        fallbackColor: isSticky
                                            ? foreground
                                            : colorScheme.onSurface,
                                        forceBold: isFrame,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  if (isFrame && !object.isLocked && !_isEditing)
                    Positioned(
                      left: 0,
                      top: 0,
                      right: 0,
                      height: 44,
                      child: Listener(
                        key: ValueKey('canvas-frame-handle-${object.id}'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) {
                          widget.onSelect();
                          widget.onPanDown(event.position);
                        },
                        onPointerMove: (event) =>
                            widget.onPanUpdate(event.position),
                        onPointerUp: (_) => widget.onPanEnd(),
                      ),
                    ),
                  if (widget.isSelected && !object.isLocked && !_isEditing)
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: GestureDetector(
                        key: ValueKey('canvas-object-resize-${object.id}'),
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) =>
                            widget.onResizeUpdate(details.delta),
                        onPanEnd: (_) => widget.onResizeEnd(),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const SizedBox.square(dimension: 18),
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
  }
}

class _PositionedNode extends StatelessWidget {
  const _PositionedNode({
    required this.cardKey,
    required this.node,
    required this.focusNode,
    required this.preset,
    required this.typedPayload,
    required this.position,
    required this.size,
    required this.origin,
    required this.isHighlighted,
    required this.isMovementLocked,
    required this.enableHoverEffects,
    required this.isCompact,
    required this.expandedChild,
    required this.onBuilt,
    required this.onBuildProbe,
    required this.onInlineEditingChanged,
    required this.onInlineSaveStatusChanged,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required this.onSelect,
    required this.onOpen,
    required this.onContextMenu,
    required this.onConnectionStart,
    required this.onConnectionUpdate,
    required this.onConnectionEnd,
    required this.onNodeUpdated,
    required this.onResizeChanged,
    required this.onTaskDoneChanged,
    required this.onTaskChecklistItemCompleted,
    required this.onKanbanCardAdvanced,
    required this.onHabitCompleted,
    required this.onGoalMilestoneAdvanced,
    required this.onPlanStepAdvanced,
  });

  final GlobalKey<_MindmapNodeCardState> cardKey;
  final MindmapNode node;
  final FocusNode focusNode;
  final NodeSizePreset preset;
  final Object? typedPayload;
  final CanvasPosition position;
  final Size size;
  final Offset origin;
  final bool isHighlighted;
  final bool isMovementLocked;
  final bool enableHoverEffects;
  final bool isCompact;
  final Widget? expandedChild;
  final ValueChanged<String>? onBuilt;
  final ValueChanged<String>? onBuildProbe;
  final ValueChanged<bool> onInlineEditingChanged;
  final ValueChanged<NodeSaveStatus> onInlineSaveStatusChanged;
  final ValueChanged<Offset> onPointerDown;
  final VoidCallback onPointerUp;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onPanCancel;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onContextMenu;
  final ValueChanged<Offset> onConnectionStart;
  final ValueChanged<Offset> onConnectionUpdate;
  final ValueChanged<Offset> onConnectionEnd;
  final NodeUpdateCallback? onNodeUpdated;
  final ValueChanged<NodeResizeChange>? onResizeChanged;
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
        focusNode: focusNode,
        isHighlighted: isHighlighted,
        onPointerDown: onPointerDown,
        onPointerUp: onPointerUp,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        onPanCancel: onPanCancel,
        onSelect: onSelect,
        onContextMenu: onContextMenu,
        onConnectionStart: onConnectionStart,
        onConnectionUpdate: onConnectionUpdate,
        onConnectionEnd: onConnectionEnd,
        canToggleDone: node.type == NodeType.task,
        showTaskToggle: expandedChild == null,
        isDone: node.isDone,
        onTaskDoneChanged: onTaskDoneChanged,
        isMovementLocked: isMovementLocked,
        enableHoverEffects: enableHoverEffects,
        shouldIgnoreDrag: expandedChild != null
            ? (position) =>
                  position.dy > inlineNodeWorkspaceHeaderHeight ||
                  position.dx >= size.width - 72 ||
                  _isInsideResizeHandle(position)
            : onResizeChanged == null
            ? null
            : _isInsideResizeHandle,
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
            key: cardKey,
            node: node,
            preset: preset,
            typedPayload: typedPayload,
            size: size,
            isHighlighted: isHighlighted,
            onTaskChecklistItemCompleted: onTaskChecklistItemCompleted,
            onKanbanCardAdvanced: onKanbanCardAdvanced,
            onHabitCompleted: onHabitCompleted,
            onGoalMilestoneAdvanced: onGoalMilestoneAdvanced,
            onPlanStepAdvanced: onPlanStepAdvanced,
            onNodeUpdated: onNodeUpdated,
            onOpen: onOpen,
            onResizeChanged: onResizeChanged,
            onInlineEditingChanged: onInlineEditingChanged,
            onInlineSaveStatusChanged: onInlineSaveStatusChanged,
            isCompact: isCompact,
            expandedChild: expandedChild,
            onBuilt: onBuilt,
            onBuildProbe: onBuildProbe,
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

  bool _isInsideResizeHandle(Offset position) {
    const hitSize = 14.0;
    final nearLeft = position.dx <= hitSize;
    final nearRight = position.dx >= size.width - hitSize;
    final nearTop = position.dy <= hitSize;
    final nearBottom = position.dy >= size.height - hitSize;
    return (nearLeft || nearRight) && (nearTop || nearBottom);
  }
}

class _NodePointerSurface extends StatefulWidget {
  const _NodePointerSurface({
    required this.nodeId,
    required this.focusNode,
    required this.isHighlighted,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required this.onSelect,
    required this.onContextMenu,
    required this.onConnectionStart,
    required this.onConnectionUpdate,
    required this.onConnectionEnd,
    required this.canToggleDone,
    required this.showTaskToggle,
    required this.isDone,
    required this.onTaskDoneChanged,
    required this.isMovementLocked,
    required this.enableHoverEffects,
    required this.shouldIgnoreDrag,
    required this.shouldIgnoreTap,
    required this.child,
  });

  final String nodeId;
  final FocusNode focusNode;
  final bool isHighlighted;
  final ValueChanged<Offset> onPointerDown;
  final VoidCallback onPointerUp;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onPanCancel;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onContextMenu;
  final ValueChanged<Offset> onConnectionStart;
  final ValueChanged<Offset> onConnectionUpdate;
  final ValueChanged<Offset> onConnectionEnd;
  final bool canToggleDone;
  final bool showTaskToggle;
  final bool isDone;
  final ValueChanged<bool> onTaskDoneChanged;
  final bool isMovementLocked;
  final bool enableHoverEffects;
  final bool Function(Offset position)? shouldIgnoreDrag;
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
  void didUpdateWidget(covariant _NodePointerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showTaskToggle && !widget.showTaskToggle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Tooltip.dismissAllToolTips();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (details) {
        _lastLocalPosition = details.localPosition;
        if (widget.shouldIgnoreDrag?.call(details.localPosition) ?? false) {
          _isDragging = false;
          return;
        }
        _isConnecting =
            !widget.isMovementLocked &&
            _isConnectionPortHit(details.localPosition);
        _isDragging = !widget.isMovementLocked;
        if (!_isDragging) return;
        widget.onPointerDown(details.position);
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
            widget.onPanUpdate(details.position);
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
          widget.onPanCancel();
        }
      },
      child: Focus(
        key: ValueKey('mindmap-node-focus-${widget.nodeId}'),
        focusNode: widget.focusNode,
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
                        top: 16,
                        left: 16,
                        child: IgnorePointer(
                          ignoring: !widget.showTaskToggle,
                          child: ExcludeSemantics(
                            excluding: !widget.showTaskToggle,
                            child: AnimatedOpacity(
                              key: ValueKey(
                                'mindmap-task-toggle-visibility-${widget.nodeId}',
                              ),
                              opacity: widget.showTaskToggle ? 1 : 0,
                              duration: const Duration(milliseconds: 120),
                              child: _TaskDoneToggle(
                                nodeId: widget.nodeId,
                                isDone: widget.isDone,
                                onChanged: widget.onTaskDoneChanged,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isConnectionPortHit(Offset position) {
    final size = context.size ?? Size.zero;
    return position.dx >= size.width - 36 &&
        (position.dy - size.height / 2).abs() <= 28;
  }

  bool _isToggleHit(Offset position) {
    return widget.canToggleDone &&
        widget.showTaskToggle &&
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
    NodeType.itinerary => [
      NodeType.event,
      NodeType.plan,
      NodeType.task,
      NodeType.expense,
      NodeType.contact,
    ],
    NodeType.image || NodeType.video => [
      NodeType.note,
      NodeType.resource,
      NodeType.bookmark,
      NodeType.canvas,
    ],
    NodeType.empty =>
      NodeType.values.where((t) => t != NodeType.empty).toList(),
    _ => informational,
  };
}

String compatibleNodeTypeLabel(NodeType type) {
  return compatibleNodeTypes(type).take(4).map((t) => t.label).join(', ');
}

class _CompactMindmapNodeCard extends StatelessWidget {
  const _CompactMindmapNodeCard({
    required this.node,
    required this.preset,
    required this.typedPayload,
    required this.size,
    required this.color,
    required this.isHighlighted,
    required this.onResizeChanged,
  });

  final MindmapNode node;
  final NodeSizePreset preset;
  final Object? typedPayload;
  final Size size;
  final Color color;
  final bool isHighlighted;
  final ValueChanged<NodeResizeChange>? onResizeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: NodeShell(
        type: node.type,
        size: size,
        color: color,
        isSelected: isHighlighted,
        preset: preset,
        isCompact: true,
        onResizeChanged: onResizeChanged,
        child:
            {
              NodeType.image,
              NodeType.itinerary,
              NodeType.video,
            }.contains(node.type)
            ? _ProductionNodeTypeContent(
                node: node,
                typedPayload: typedPayload,
                effectivePreset: _effectiveContentPreset(node.type, preset),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          NodeVisuals.icon(node.type),
                          color: color,
                          size: 18,
                        ),
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
                          if (node.type == NodeType.habit)
                            _CollapsedHabitTracker(
                              node: node,
                              color: color,
                              compact: true,
                            )
                          else if (node.type == NodeType.goal)
                            Text(
                              '${completedGoalMilestones(node).length}/${goalMilestones(node).length} milestones',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else if (node.type == NodeType.event)
                            Text(
                              _eventCollapsedSummary(node),
                              key: ValueKey<String>(
                                'event-collapsed-summary-${node.id}',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else if (node.type == NodeType.metric)
                            Text(
                              _metricCollapsedLabel(node),
                              key: ValueKey<String>(
                                'metric-collapsed-summary-${node.id}',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else if (node.type == NodeType.expense)
                            Text(
                              _expenseCollapsedLabel(node),
                              key: ValueKey<String>(
                                'expense-collapsed-summary-${node.id}',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else
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
                    if (node.isDone)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.check_circle,
                          key: ValueKey('mindmap-node-done-${node.id}'),
                          color: color,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _MindmapNodeCard extends StatefulWidget {
  const _MindmapNodeCard({
    required this.node,
    required this.preset,
    required this.typedPayload,
    required this.size,
    required this.isHighlighted,
    required this.onTaskChecklistItemCompleted,
    required this.onKanbanCardAdvanced,
    required this.onHabitCompleted,
    required this.onGoalMilestoneAdvanced,
    required this.onPlanStepAdvanced,
    required this.onNodeUpdated,
    required this.onOpen,
    required this.onResizeChanged,
    required this.onInlineEditingChanged,
    required this.onInlineSaveStatusChanged,
    required this.isCompact,
    required this.expandedChild,
    required this.onBuilt,
    required this.onBuildProbe,
    super.key,
  });

  final MindmapNode node;
  final NodeSizePreset preset;
  final Object? typedPayload;
  final Size size;
  final bool isHighlighted;
  final VoidCallback? onTaskChecklistItemCompleted;
  final ValueChanged<String>? onKanbanCardAdvanced;
  final VoidCallback? onHabitCompleted;
  final VoidCallback? onGoalMilestoneAdvanced;
  final VoidCallback? onPlanStepAdvanced;
  final NodeUpdateCallback? onNodeUpdated;
  final VoidCallback onOpen;
  final ValueChanged<NodeResizeChange>? onResizeChanged;
  final ValueChanged<bool> onInlineEditingChanged;
  final ValueChanged<NodeSaveStatus> onInlineSaveStatusChanged;
  final bool isCompact;
  final Widget? expandedChild;
  final ValueChanged<String>? onBuilt;
  final ValueChanged<String>? onBuildProbe;

  @override
  State<_MindmapNodeCard> createState() => _MindmapNodeCardState();
}

class _MindmapNodeCardState extends State<_MindmapNodeCard> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _isEditing = false;
  int _buildCallbackGeneration = 0;
  String? _lastNotifiedBuildSignature;
  String? _pendingBuildSignature;

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
    _buildCallbackGeneration++;
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _setInlineEditing(bool value) {
    if (_isEditing == value) return;
    setState(() => _isEditing = value);
    widget.onInlineEditingChanged(value);
  }

  void beginInlineEdit() => _setInlineEditing(true);

  Future<bool> finishInlineEdit() => _saveInlineEdit();

  Future<bool> _saveInlineEdit() async {
    final title = _titleController.text.trim();
    final body = _trimToWordLimit(_bodyController.text.trim());
    if (title.isEmpty) {
      widget.onInlineSaveStatusChanged(NodeSaveStatus.error);
      return false;
    }
    if (title == widget.node.title && body == widget.node.body) {
      _setInlineEditing(false);
      widget.onInlineSaveStatusChanged(NodeSaveStatus.saved);
      return true;
    }
    widget.onInlineSaveStatusChanged(NodeSaveStatus.saving);
    try {
      await widget.onNodeUpdated?.call(
        widget.node.copyWith(
          title: title,
          body: body,
          updatedAt: DateTime.now(),
        ),
      );
      _setInlineEditing(false);
      widget.onInlineSaveStatusChanged(NodeSaveStatus.saved);
      return true;
    } on Object {
      widget.onInlineSaveStatusChanged(NodeSaveStatus.error);
      return false;
    }
  }

  void _markTextDraftStatus() {
    final isDirty =
        _titleController.text.trim() != widget.node.title ||
        _trimToWordLimit(_bodyController.text.trim()) != widget.node.body;
    widget.onInlineSaveStatusChanged(
      isDirty ? NodeSaveStatus.dirty : NodeSaveStatus.idle,
    );
    _scheduleBuiltCallback();
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
    widget.onInlineSaveStatusChanged(NodeSaveStatus.idle);
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuildProbe?.call(widget.node.id);
    _scheduleBuiltCallback();
    final node = widget.node;
    final theme = Theme.of(context);
    final color = NodeVisuals.color(context, node.type);
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

    if (widget.expandedChild case final expandedChild?) {
      return NodeShell(
        type: node.type,
        size: widget.size,
        color: color,
        isSelected: true,
        preset: widget.preset,
        onResizeChanged:
            node.type == NodeType.task ||
                node.type == NodeType.canvas ||
                node.type == NodeType.resource ||
                node.type == NodeType.bookmark ||
                node.type == NodeType.image ||
                node.type == NodeType.video ||
                node.type == NodeType.weather ||
                node.type == NodeType.fit ||
                node.type == NodeType.itinerary ||
                node.type == NodeType.idea ||
                node.type == NodeType.question ||
                node.type == NodeType.decision
            ? null
            : widget.onResizeChanged,
        showPresetControl: false,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: -6,
              top: _nodePortY(widget.size) - 9,
              child: _NodePort(color: color, alignment: Alignment.centerLeft),
            ),
            Positioned(
              right: -6,
              top: _nodePortY(widget.size) - 9,
              child: _NodePort(color: color, alignment: Alignment.centerRight),
            ),
            Positioned.fill(child: expandedChild),
          ],
        ),
      );
    }

    final h = node.body.trim().isNotEmpty || node.isDone ? 240 : 200;
    final useNarrowHeader = widget.size.width < 240;
    final compact =
        widget.isCompact ||
        useNarrowHeader ||
        widget.preset == NodeSizePreset.compact ||
        widget.size.height < h ||
        (node.type == NodeType.goal && widget.size.height < 300) ||
        (node.type == NodeType.event && widget.size.height < 320) ||
        (node.type == NodeType.mood && widget.size.height < 280) ||
        (node.type == NodeType.contact && widget.size.height < 300) ||
        (node.type == NodeType.metric && widget.size.height < 280) ||
        (node.type == NodeType.expense && widget.size.height < 300);
    if (compact) {
      if (_isEditing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isEditing) unawaited(_saveInlineEdit());
        });
      }
      return _CompactMindmapNodeCard(
        node: node,
        preset: widget.preset,
        typedPayload: widget.typedPayload,
        size: widget.size,
        color: color,
        isHighlighted: widget.isHighlighted,
        onResizeChanged: widget.onResizeChanged,
      );
    }

    return NodeShell(
      type: node.type,
      size: widget.size,
      color: color,
      isSelected: widget.isHighlighted,
      preset: widget.preset,
      onResizeChanged: _isEditing ? null : widget.onResizeChanged,
      child: Stack(
        children: [
          Positioned(
            left: -6,
            top: _nodePortY(widget.size) - 9,
            child: _NodePort(color: color, alignment: Alignment.centerLeft),
          ),
          Positioned(
            right: -6,
            top: _nodePortY(widget.size) - 9,
            child: _NodePort(color: color, alignment: Alignment.centerRight),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              useNarrowHeader ? 16 : 24,
              8,
              useNarrowHeader ? 16 : 24,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (node.type == NodeType.task)
                      SizedBox(width: useNarrowHeader ? 24 : 32),
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
                          NodeVisuals.icon(node.type),
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
                      tooltip: 'Open ${node.type.label} inline',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: widget.onOpen,
                      icon: const Icon(Icons.open_in_full_rounded),
                    ),
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
                          key: ValueKey('node-inline-title-field-${node.id}'),
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
                          onChanged: (_) => _markTextDraftStatus(),
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
                  _NodeMetadataChips(
                    node: node,
                    maxItems:
                        node.type == NodeType.bookmark &&
                            widget.size.height < 380
                        ? 2
                        : null,
                  ),
                ],
                if (node.type == NodeType.habit) ...[
                  const SizedBox(height: 4),
                  Flexible(
                    fit: FlexFit.loose,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: math.max(120, widget.size.width - 48),
                        child: _CollapsedHabitTracker(node: node, color: color),
                      ),
                    ),
                  ),
                ],
                if (calendarNodePayloadFromData(node.data) != null) ...[
                  const SizedBox(height: 8),
                  _CalendarPayloadSummary(node: node),
                ],
                if (node.data.containsKey('kanban')) ...[
                  const SizedBox(height: 10),
                  Expanded(child: _KanbanNodeBoard(node: node)),
                ],
                if (_isEditing ||
                    (node.type != NodeType.mood &&
                        node.type != NodeType.contact &&
                        node.body.isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  _isEditing
                      ? (node.type == NodeType.image ||
                                node.type == NodeType.itinerary
                            ? Expanded(
                                child: _ProductionNodeInlineEditor(
                                  node: node,
                                  initialPayload: widget.typedPayload,
                                  effectivePreset: _effectiveContentPreset(
                                    node.type,
                                    widget.preset,
                                  ),
                                  onNodeUpdated: widget.onNodeUpdated,
                                  onSaveStatusChanged:
                                      widget.onInlineSaveStatusChanged,
                                ),
                              )
                            : TextField(
                                key: ValueKey(
                                  'node-inline-body-field-${node.id}',
                                ),
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
                                onChanged: (_) => _markTextDraftStatus(),
                              ))
                      : node.type == NodeType.note
                      ? Flexible(
                          fit: FlexFit.loose,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: widget.onNodeUpdated == null
                                ? null
                                : () => _setInlineEditing(true),
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: _CollapsedNoteMarkdownPreview(
                                markdown: node.body,
                              ),
                            ),
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
                if (node.type != NodeType.habit &&
                    !node.data.containsKey('kanban') &&
                    !(_isEditing &&
                        (node.type == NodeType.image ||
                            node.type == NodeType.itinerary))) ...[
                  const SizedBox(height: 8),
                  Flexible(
                    child: _NodeTypeSpecificContent(
                      node: node,
                      typedPayload: widget.typedPayload,
                      effectivePreset: _effectiveContentPreset(
                        node.type,
                        widget.preset,
                      ),
                      onNodeUpdated: widget.onNodeUpdated,
                      maxBookmarkItems:
                          node.type == NodeType.bookmark &&
                              widget.size.height < 380
                          ? 2
                          : null,
                    ),
                  ),
                ],
                if (_hasTypeQuickAction(node) &&
                    !_hasProgressAction(node) &&
                    !node.isDone &&
                    (node.type != NodeType.bookmark ||
                        widget.size.height >= 380)) ...[
                  const SizedBox(height: 8),
                  _NodeQuickAction(node: node),
                ],
                if (node.type == NodeType.task &&
                    node.checklist.isNotEmpty &&
                    !node.isDone &&
                    widget.onTaskChecklistItemCompleted != null) ...[
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
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

  void _scheduleBuiltCallback() {
    final callback = widget.onBuilt;
    if (callback == null) return;
    final signature = [
      widget.node.id,
      _titleController.text,
      _bodyController.text,
      widget.node.presentationDataKey,
      _isEditing,
      widget.preset.name,
      widget.size.width,
      widget.size.height,
    ].join('|');
    if (signature == _lastNotifiedBuildSignature ||
        signature == _pendingBuildSignature) {
      return;
    }
    _pendingBuildSignature = signature;
    final generation = ++_buildCallbackGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _buildCallbackGeneration ||
          signature != _pendingBuildSignature) {
        return;
      }
      _pendingBuildSignature = null;
      _lastNotifiedBuildSignature = signature;
      callback(widget.node.id);
    });
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
          color: AppSemanticColors.of(context).surfaceSunken,
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
    final color = NodeVisuals.color(context, type);
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
            children: [Icon(NodeVisuals.icon(type), color: color, size: 12)],
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
      NodeType.contact => null,
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
    final color = NodeVisuals.color(context, node.type);
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
  const _NodeMetadataChips({required this.node, this.maxItems});

  final MindmapNode node;
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    final labels = _metadataLabelsFor(node);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in labels.take(maxItems ?? labels.length))
          _MetadataPill(label: label),
      ],
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
  const _KanbanNodeBoard({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final board = KanbanBoard.fromNodeData(node.data);
    final columns = [...board.columns]
      ..sort((left, right) => left.order.compareTo(right.order));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < columns.length; index++) ...[
          Expanded(
            child: _KanbanColumnView(
              nodeId: node.id,
              column: columns[index],
              cards: board.cardsFor(columns[index].id),
            ),
          ),
          if (index < columns.length - 1) const SizedBox(width: 8),
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
  });

  final String nodeId;
  final KanbanColumnDefinition column;
  final List<KanbanCard> cards;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    column.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text('${cards.length}', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final card in cards) ...[
                      _KanbanCardPreview(nodeId: nodeId, card: card),
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

class _KanbanCardPreview extends StatelessWidget {
  const _KanbanCardPreview({required this.nodeId, required this.card});

  final String nodeId;
  final KanbanCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      key: ValueKey('kanban-card-preview-$nodeId-${card.id}'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.7)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showMetadata = constraints.maxWidth >= 112;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: showMetadata ? 8 : 5,
              vertical: 7,
            ),
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
                if (showMetadata && card.checklist.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Icon(
                    Icons.checklist_rounded,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${card.completedChecklistCount}/${card.checklist.length}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
                if (showMetadata && card.attachments.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Icon(
                    Icons.attach_file_rounded,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  Text(
                    '${card.attachments.length}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TaskDoneToggle extends StatelessWidget {
  const _TaskDoneToggle({
    required this.nodeId,
    required this.isDone,
    required this.onChanged,
  });

  final String nodeId;
  final bool isDone;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('mindmap-task-toggle-$nodeId'),
      button: true,
      checked: isDone,
      label: isDone ? 'Mark task incomplete' : 'Mark task complete',
      child: SizedBox.square(
        dimension: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: isDone ? 'Mark task incomplete' : 'Mark task complete',
          onPressed: () => onChanged(!isDone),
          icon: Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isDone
                ? NodeVisuals.color(context, NodeType.task)
                : Theme.of(context).textTheme.bodySmall?.color,
            size: 20,
          ),
        ),
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
    required this.backgroundMode,
    required this.variant,
    required this.isDark,
  });

  final Offset? mousePos;
  final List<Offset> cursorTrail;
  final double animationValue;
  final bool showGrid;
  final int backgroundMode;
  final AppThemeVariant variant;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final guideOffset = mousePos != null
        ? (mousePos! - center) * 0.004
        : Offset.zero;
    final rect = Offset.zero & size;

    final palette = AppThemeVariantColors.of(variant);
    canvas.drawRect(
      rect,
      Paint()..color = isDark ? palette.darkBg : palette.lightBg,
    );

    if (showGrid) {
      _drawCanvasGuides(canvas, size, guideOffset);
    }
  }

  void _drawCanvasGuides(Canvas canvas, Size size, Offset guideOffset) {
    final borderColor = isDark
        ? AppThemeVariantColors.of(variant).darkBorder
        : AppThemeVariantColors.of(variant).lightBorder;
    final guideColor = borderColor.withValues(alpha: isDark ? 0.045 : 0.1);
    final guidePaint = Paint()
      ..color = guideColor
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    switch (backgroundMode) {
      case 1:
        _drawDotGrid(canvas, size, guideOffset, guideColor);
        break;
      case 2:
        _drawSquareGrid(canvas, size, guideOffset, guidePaint);
        break;
      default:
        _drawRuledGuides(canvas, size, guideOffset, guidePaint);
    }
  }

  void _drawDotGrid(
    Canvas canvas,
    Size size,
    Offset guideOffset,
    Color guideColor,
  ) {
    final dotPaint = Paint()
      ..color = guideColor.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const step = 48.0;
    final startX = (guideOffset.dx % step) - step;
    final startY = (guideOffset.dy % step) - step;
    for (var x = startX; x <= size.width + step; x += step) {
      for (var y = startY; y <= size.height + step; y += step) {
        canvas.drawPoints(ui.PointMode.points, [Offset(x, y)], dotPaint);
      }
    }
  }

  void _drawSquareGrid(
    Canvas canvas,
    Size size,
    Offset guideOffset,
    Paint guidePaint,
  ) {
    const step = 64.0;
    final startX = (guideOffset.dx % step) - step;
    final startY = (guideOffset.dy % step) - step;
    for (var x = startX; x <= size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), guidePaint);
    }
    for (var y = startY; y <= size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
    }
  }

  void _drawRuledGuides(
    Canvas canvas,
    Size size,
    Offset guideOffset,
    Paint guidePaint,
  ) {
    const step = 96.0;
    final startY = (guideOffset.dy % step) - step;
    for (var y = startY; y <= size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _InteractiveBackgroundPainter oldDelegate) {
    return oldDelegate.mousePos != mousePos ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.backgroundMode != backgroundMode ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.variant != variant ||
        oldDelegate.isDark != isDark ||
        oldDelegate.cursorTrail.length != cursorTrail.length ||
        (oldDelegate.cursorTrail.isNotEmpty &&
            cursorTrail.isNotEmpty &&
            oldDelegate.cursorTrail.last != cursorTrail.last);
  }
}

class _CanvasSmartGuidesPainter extends CustomPainter {
  const _CanvasSmartGuidesPainter({
    required this.guides,
    required this.origin,
    required this.color,
  });

  final _CanvasSmartGuides guides;
  final Offset origin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1.5;
    if (guides.vertical case final x?) {
      canvas.drawLine(
        Offset(origin.dx + x, 0),
        Offset(origin.dx + x, size.height),
        paint,
      );
    }
    if (guides.horizontal case final y?) {
      canvas.drawLine(
        Offset(0, origin.dy + y),
        Offset(size.width, origin.dy + y),
        paint,
      );
    }
    if (guides.distance case final distance?) {
      final position = guides.labelPosition;
      if (position == null) return;
      final painter = TextPainter(
        text: TextSpan(
          text: '${distance.round()} px',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, origin + position - Offset(painter.width / 2, 18));
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasSmartGuidesPainter oldDelegate) =>
      oldDelegate.guides != guides ||
      oldDelegate.origin != origin ||
      oldDelegate.color != color;
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
  const _ConnectionDragPainter({required this.drag, required this.nodeColors});

  final _ConnectionDrag drag;
  final Map<NodeType, Color> nodeColors;

  @override
  void paint(Canvas canvas, Size size) {
    final colorA = nodeColors[drag.source.type]!;
    final colorB = drag.target == null
        ? colorA
        : nodeColors[drag.target!.type]!;
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
    return oldDelegate.drag != drag || oldDelegate.nodeColors != nodeColors;
  }
}

class _KeyboardConnectionPort extends StatelessWidget {
  const _KeyboardConnectionPort({
    required this.node,
    required this.position,
    required this.size,
    required this.origin,
    required this.isInput,
    required this.onPressed,
    super.key,
  });

  final MindmapNode node;
  final CanvasPosition position;
  final Size size;
  final Offset origin;
  final bool isInput;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Positioned(
    left: origin.dx + position.dx + (isInput ? -14 : size.width - 14),
    top: origin.dy + position.dy + size.height / 2 - 14,
    width: 28,
    height: 28,
    child: Focus(
      key: ValueKey(
        'mindmap-${isInput ? 'input' : 'output'}-port-focus-${node.id}',
      ),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: true,
        label: isInput
            ? 'Connect to ${node.title}'
            : 'Start connection from ${node.title}',
        child: IgnorePointer(
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: isInput
                ? 'Connect to ${node.title}'
                : 'Start connection from ${node.title}',
            onPressed: onPressed,
            icon: Icon(
              isInput ? Icons.radio_button_unchecked : Icons.add_circle_outline,
              size: 14,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ConnectionEndpointHandle extends StatelessWidget {
  const _ConnectionEndpointHandle({
    required this.source,
    required this.target,
    required this.targetPosition,
    required this.targetSize,
    required this.origin,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final MindmapNode source;
  final MindmapNode target;
  final CanvasPosition targetPosition;
  final Size targetSize;
  final Offset origin;
  final ValueChanged<Offset> onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final ValueChanged<Offset> onPanEnd;

  @override
  Widget build(BuildContext context) {
    final endpoint =
        origin +
        Offset(
          targetPosition.dx + 2,
          targetPosition.dy + _nodePortY(targetSize),
        );
    return Positioned(
      left: endpoint.dx - 12,
      top: endpoint.dy - 12,
      width: 24,
      height: 24,
      child: GestureDetector(
        key: ValueKey('mindmap-connection-end-${source.id}-${target.id}'),
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) => onPanStart(details.globalPosition),
        onPanUpdate: (details) => onPanUpdate(details.globalPosition),
        onPanEnd: (details) => onPanEnd(details.globalPosition),
        child: const MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ConnectionOverlay extends StatelessWidget {
  const _ConnectionOverlay({
    required this.source,
    required this.target,
    required this.sourcePosition,
    required this.targetPosition,
    required this.sourceSize,
    required this.targetSize,
    required this.origin,
    required this.label,
    required this.isSelected,
    required this.onSelect,
    required this.onContextMenu,
    required this.onEditLabel,
    required this.onDetach,
  });

  final MindmapNode source;
  final MindmapNode target;
  final CanvasPosition sourcePosition;
  final CanvasPosition targetPosition;
  final Size sourceSize;
  final Size targetSize;
  final Offset origin;
  final String label;
  final bool isSelected;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onContextMenu;
  final VoidCallback onEditLabel;
  final VoidCallback onDetach;

  @override
  Widget build(BuildContext context) {
    final start =
        origin +
        Offset(
          sourcePosition.dx + sourceSize.width - 2,
          sourcePosition.dy + _nodePortY(sourceSize),
        );
    final end =
        origin +
        Offset(
          targetPosition.dx + 2,
          targetPosition.dy + _nodePortY(targetSize),
        );
    final delta = end - start;
    final length = delta.distance;
    final angle = math.atan2(delta.dy, delta.dx);
    final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final selectedColor = Theme.of(context).colorScheme.primary;

    Widget hitTarget({required Widget child, Key? key}) {
      return GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onSelect,
        onDoubleTap: onEditLabel,
        onSecondaryTapUp: (details) => onContextMenu(details.globalPosition),
        onLongPressStart: (details) => onContextMenu(details.globalPosition),
        child: child,
      );
    }

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: start.dx,
            top: start.dy - 10,
            child: Transform.rotate(
              angle: angle,
              alignment: Alignment.centerLeft,
              child: hitTarget(
                key: ValueKey(
                  'mindmap-connection-line-${source.id}-${target.id}',
                ),
                child: SizedBox(
                  width: length,
                  height: 20,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: isSelected ? 6 : 2,
                      color: isSelected
                          ? selectedColor.withValues(alpha: 0.72)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: midpoint.dx - 70,
            top: midpoint.dy - 22,
            width: 140,
            height: 44,
            child: hitTarget(
              key: ValueKey('mindmap-connection-${source.id}-${target.id}'),
              child: Center(
                child: label.isEmpty
                    ? const Icon(Icons.edit_outlined, size: 16)
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
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

class _ConnectionLinesPainter extends CustomPainter {
  _ConnectionLinesPainter({
    required this.nodes,
    required this.dragPositions,
    required this.nodeSizes,
    required this.origin,
    required this.compactNodeIds,
    required this.nodeColors,
  });

  final List<MindmapNode> nodes;
  final Map<String, CanvasPosition> dragPositions;
  final Map<String, Size> nodeSizes;
  final Offset origin;
  final Set<String> compactNodeIds;
  final Map<NodeType, Color> nodeColors;

  CanvasPosition _positionFor(MindmapNode node) {
    return dragPositions[node.id] ?? node.position;
  }

  Size _nodeSizeFor(MindmapNode node) {
    return nodeSizes[node.id] ?? _effectiveNodeSize(node);
  }

  Offset _getOutputPort(MindmapNode node) {
    final pos = _positionFor(node);
    final size = _nodeSizeFor(node);
    return MindmapExpandedNodeGeometry(
      node: node,
      size: size,
      origin: origin,
      position: pos,
    ).outputPort;
  }

  Offset _getInputPort(MindmapNode node) {
    final pos = _positionFor(node);
    final size = _nodeSizeFor(node);
    return MindmapExpandedNodeGeometry(
      node: node,
      size: size,
      origin: origin,
      position: pos,
    ).inputPort;
  }

  ConnectionStyle _styleFor(MindmapNode source, String targetId) {
    final styles = source.data['connection_styles'];
    final styleMap = styles is Map ? styles[targetId] : null;
    return styleMap is Map
        ? ConnectionStyle.fromJson((styleMap).cast<String, dynamic>())
        : const ConnectionStyle();
  }

  Path _buildPath(Offset pA, Offset pB, ConnectionLineType lineType) {
    final dx = (pB.dx - pA.dx).abs();
    final dy = (pB.dy - pA.dy).abs();
    switch (lineType) {
      case ConnectionLineType.straight:
        return Path()
          ..moveTo(pA.dx, pA.dy)
          ..lineTo(pB.dx, pB.dy);
      case ConnectionLineType.orthogonal:
        final midX = (pA.dx + pB.dx) / 2;
        return Path()
          ..moveTo(pA.dx, pA.dy)
          ..lineTo(midX, pA.dy)
          ..lineTo(midX, pB.dy)
          ..lineTo(pB.dx, pB.dy);
      case ConnectionLineType.bezier:
        Offset cp1;
        Offset cp2;
        if (dx > dy) {
          cp1 = Offset(pA.dx + (pB.dx - pA.dx) * 0.5, pA.dy);
          cp2 = Offset(pB.dx - (pB.dx - pA.dx) * 0.5, pB.dy);
        } else {
          cp1 = Offset(pA.dx, pA.dy + (pB.dy - pA.dy) * 0.5);
          cp2 = Offset(pB.dx, pB.dy - (pB.dy - pA.dy) * 0.5);
        }
        return Path()
          ..moveTo(pA.dx, pA.dy)
          ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pB.dx, pB.dy);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      ConnectionLinePattern pattern) {
    if (pattern == ConnectionLinePattern.solid) {
      canvas.drawPath(path, paint);
      return;
    }
    final metrics = path.computeMetrics();
    final double dashLen = pattern == ConnectionLinePattern.dashed ? 8.0 : 2.0;
    const double gapLen = 4.0;
    for (final metric in metrics) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final segLen = draw ? dashLen : gapLen;
        final end = (distance + segLen).clamp(0.0, metric.length);
        if (draw) {
          final seg = metric.extractPath(distance, end);
          canvas.drawPath(seg, paint);
        }
        distance = end;
        draw = !draw;
      }
    }
  }

  void _drawArrowhead(Canvas canvas, Offset tip, Offset from, Paint paint) {
    final dir = tip - from;
    final len = dir.distance;
    if (len == 0) return;
    final unitDir = dir / len;
    final normal = Offset(-unitDir.dy, unitDir.dx);
    final arrowBase = tip - unitDir * 7;
    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((arrowBase + normal * 4.5).dx, (arrowBase + normal * 4.5).dy)
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((arrowBase - normal * 4.5).dx, (arrowBase - normal * 4.5).dy);
    canvas.drawPath(arrowPath, paint);
  }

  void _drawLabel(Canvas canvas, Path path, String label, Color color) {
    final metrics = path.computeMetrics();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(metric.length / 2);
    if (tangent == null) return;
    final mid = tangent.position;
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
    );
    final tp = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    final pillW = tp.width + 10;
    final pillH = tp.height + 6;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: mid, width: pillW, height: pillH),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      pillRect,
      Paint()..color = const Color(0xFF1E1E1E),
    );
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, MindmapNode> nodeMap = {for (final n in nodes) n.id: n};

    final Set<String> drawnConnections = {};

    for (final node in nodes) {
      final pA = _getOutputPort(node);
      final colorA = nodeColors[node.type]!;

      for (final relatedId in node.relatedNodeIds) {
        if (!nodeMap.containsKey(relatedId)) continue;

        final connKey = node.id.compareTo(relatedId) < 0
            ? '${node.id}-$relatedId'
            : '$relatedId-${node.id}';
        if (drawnConnections.contains(connKey)) continue;
        drawnConnections.add(connKey);

        final targetNode = nodeMap[relatedId]!;
        final pB = _getInputPort(targetNode);
        final colorB = nodeColors[targetNode.type]!;
        final style = _styleFor(node, relatedId);

        final lineColor = style.colorHex != null
            ? Color(int.parse('FF${style.colorHex!.replaceFirst('#', '')}',
                radix: 16))
            : Color.lerp(colorA, colorB, 0.5)!;

        final paint = Paint()
          ..strokeWidth = style.strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = lineColor.withValues(alpha: 0.82);

        final path = _buildPath(pA, pB, style.lineType);
        _drawDashedPath(canvas, path, paint, style.linePattern);

        final sketchPaint = Paint()
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = lineColor.withValues(alpha: 0.36);

        final dx = (pB.dx - pA.dx).abs();
        final dy = (pB.dy - pA.dy).abs();
        if (style.lineType == ConnectionLineType.bezier) {
          final sketchPath = Path()..moveTo(pA.dx + 1.2, pA.dy - 0.8);
          Offset scp1;
          Offset scp2;
          if (dx > dy) {
            final cp1 = Offset(pA.dx + (pB.dx - pA.dx) * 0.5, pA.dy);
            final cp2 = Offset(pB.dx - (pB.dx - pA.dx) * 0.5, pB.dy);
            scp1 = Offset(cp1.dx + 2.0, cp1.dy - 1.2);
            scp2 = Offset(cp2.dx - 1.2, cp2.dy + 1.8);
          } else {
            final cp1 = Offset(pA.dx, pA.dy + (pB.dy - pA.dy) * 0.5);
            final cp2 = Offset(pB.dx, pB.dy - (pB.dy - pA.dy) * 0.5);
            scp1 = Offset(cp1.dx - 1.2, cp1.dy + 2.0);
            scp2 = Offset(cp2.dx + 1.8, cp2.dy - 1.2);
          }
          sketchPath.cubicTo(
            scp1.dx, scp1.dy,
            scp2.dx, scp2.dy,
            pB.dx + 0.8, pB.dy - 0.8,
          );
          canvas.drawPath(sketchPath, sketchPaint);
        }

        final arrowPaint = Paint()
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = lineColor.withValues(alpha: 0.72);

        if (style.arrowhead == ConnectionArrowhead.target ||
            style.arrowhead == ConnectionArrowhead.both) {
          final metrics = path.computeMetrics();
          if (metrics.isNotEmpty) {
            final metric = metrics.first;
            final tangent = metric.getTangentForOffset(metric.length);
            if (tangent != null) {
              final from = metric
                  .getTangentForOffset(
                      (metric.length - 1).clamp(0, metric.length))
                  ?.position;
              if (from != null) {
                _drawArrowhead(canvas, pB, from, arrowPaint);
              }
            }
          }
        }
        if (style.arrowhead == ConnectionArrowhead.both) {
          final metrics = path.computeMetrics();
          if (metrics.isNotEmpty) {
            final metric = metrics.first;
            final tangent = metric.getTangentForOffset(0);
            if (tangent != null) {
              final to =
                  metric.getTangentForOffset(1.0.clamp(0, metric.length))
                      ?.position;
              if (to != null) {
                _drawArrowhead(canvas, pA, to, arrowPaint);
              }
            }
          }
        }

        if (style.label != null && style.label!.isNotEmpty) {
          _drawLabel(canvas, path, style.label!, lineColor);
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
        oldDelegate.nodeSizes != nodeSizes ||
        oldDelegate.origin != origin ||
        oldDelegate.compactNodeIds != compactNodeIds ||
        oldDelegate.nodeColors != nodeColors;
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.nodes,
    required this.objects,
    required this.dragPositions,
    required this.objectGeometryOverrides,
    required this.nodeSizes,
    required this.viewportRect,
    required this.contentBounds,
    required this.origin,
    required this.nodeColors,
  });

  final List<MindmapNode> nodes;
  final List<CanvasObject> objects;
  final Map<String, CanvasPosition> dragPositions;
  final Map<String, CanvasGeometry> objectGeometryOverrides;
  final Map<String, Size> nodeSizes;
  final Rect viewportRect;
  final Rect contentBounds;
  final Offset origin;
  final Map<NodeType, Color> nodeColors;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / contentBounds.width;
    final scaleY = size.height / contentBounds.height;

    Offset mapPoint(Offset point) => Offset(
      (point.dx - contentBounds.left) * scaleX,
      (point.dy - contentBounds.top) * scaleY,
    );

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    final Map<String, MindmapNode> nodeMap = {for (final n in nodes) n.id: n};

    CanvasPosition positionFor(MindmapNode node) {
      return dragPositions[node.id] ?? node.position;
    }

    Size nodeSizeFor(MindmapNode node) {
      return nodeSizes[node.id] ?? _effectiveNodeSize(node);
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
        canvas.drawLine(mapPoint(pA), mapPoint(pB), linePaint);
      }
    }

    // Draw nodes as tiny colored rectangles
    for (final node in nodes) {
      final pos = positionFor(node);
      final nodeSize = nodeSizeFor(node);
      final sceneRect = MindmapExpandedNodeGeometry(
        node: node,
        size: nodeSize,
        origin: origin,
        position: pos,
      ).hitRect;
      final rect = Rect.fromPoints(
        mapPoint(sceneRect.topLeft),
        mapPoint(sceneRect.bottomRight),
      );

      final color = nodeColors[node.type]!;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }

    for (final object in objects) {
      if (!object.isVisible || object.type == CanvasObjectType.nodeReference) {
        continue;
      }
      final geometry = objectGeometryOverrides[object.id] ?? object.geometry;
      final rect = Rect.fromLTWH(
        (origin.dx + geometry.x - contentBounds.left) * scaleX,
        (origin.dy + geometry.y - contentBounds.top) * scaleY,
        math.max(2, geometry.width * scaleX),
        math.max(2, geometry.height * scaleY),
      );
      final color = switch (object.type) {
        CanvasObjectType.frame => Colors.blueGrey,
        CanvasObjectType.connector => Colors.white54,
        CanvasObjectType.image => Colors.purpleAccent,
        CanvasObjectType.linkPreview => Colors.lightBlueAccent,
        _ => Colors.amberAccent,
      };
      final paint = Paint()
        ..color = color.withValues(alpha: 0.75)
        ..style = object.type == CanvasObjectType.frame
            ? PaintingStyle.stroke
            : PaintingStyle.fill;
      canvas.drawRect(rect, paint);
    }

    // Draw viewport rectangle (the indicator box)
    final viewportRectScaled = Rect.fromLTRB(
      (viewportRect.left - contentBounds.left) * scaleX,
      (viewportRect.top - contentBounds.top) * scaleY,
      (viewportRect.right - contentBounds.left) * scaleX,
      (viewportRect.bottom - contentBounds.top) * scaleY,
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
        oldDelegate.objects != objects ||
        oldDelegate.dragPositions != dragPositions ||
        oldDelegate.objectGeometryOverrides != objectGeometryOverrides ||
        oldDelegate.nodeSizes != nodeSizes ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.contentBounds != contentBounds ||
        oldDelegate.nodeColors != nodeColors;
  }
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
      final payload = ResourcePayload.fromNode(node);
      final assetCount =
          (payload.primaryAsset == null ? 0 : 1) + payload.relatedAssets.length;
      if (payload.folderPath.isNotEmpty) labels.add(payload.folderPath.last);
      if (assetCount > 0) {
        labels.add('$assetCount asset${assetCount == 1 ? '' : 's'}');
      }
      for (final tag
          in payload.tags.where((tag) => !node.tags.contains(tag)).take(2)) {
        labels.add('#$tag');
      }
    case NodeType.bookmark:
      final payload = LinkResourcePayload.fromNode(node);
      labels.addAll(_sourceLabel(payload.url));
      if (payload.collection.trim().isNotEmpty) {
        labels.add(payload.collection.trim());
      }
      labels.add(switch (payload.bookmarkStatus) {
        'reading' => 'Reading',
        'read' => 'Read',
        _ => 'Inbox',
      });
      if (payload.isFavorite) labels.add('Favorite');
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

class _CollapsedHabitTracker extends StatelessWidget {
  const _CollapsedHabitTracker({
    required this.node,
    required this.color,
    this.compact = false,
  });

  final MindmapNode node;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completions = habitCompletionKeys(node).toSet();
    final days = List<DateTime>.generate(
      7,
      (index) => node.day.dateOnly.subtract(Duration(days: 6 - index)),
    );
    final completedCount = days
        .where((day) => completions.contains(dayKey(day)))
        .length;

    if (compact) {
      return Row(
        key: ValueKey<String>('habit-collapsed-tracker-${node.id}'),
        children: [
          for (final day in days)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(
                completions.contains(dayKey(day))
                    ? Icons.circle
                    : Icons.circle_outlined,
                size: 9,
                color: color,
              ),
            ),
        ],
      );
    }

    final heatmapStart = node.day.dateOnly.subtract(const Duration(days: 83));
    return Column(
      key: ValueKey<String>('habit-collapsed-tracker-${node.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday -
                          1],
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Icon(
                      completions.contains(dayKey(day))
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 16,
                      color: completions.contains(dayKey(day))
                          ? color
                          : theme.colorScheme.outlineVariant,
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            Text(
              '$completedCount/7',
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          key: ValueKey<String>('habit-collapsed-heatmap-${node.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var week = 0; week < 12; week++)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Column(
                  children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Builder(
                        builder: (context) {
                          final day = heatmapStart.add(
                            Duration(days: week * 7 + weekday),
                          );
                          final completed = completions.contains(dayKey(day));
                          return Container(
                            key: ValueKey<String>(
                              'habit-collapsed-heatmap-day-${node.id}-${dayKey(day)}',
                            ),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: completed
                                  ? color
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: completed
                                    ? color
                                    : theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.45),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
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

class _CollapsedNoteMarkdownPreview extends StatelessWidget {
  const _CollapsedNoteMarkdownPreview({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.25,
    );
    return KeyedSubtree(
      key: const ValueKey<String>('note-collapsed-markdown-preview'),
      child: MarkdownBody(
        data: markdown,
        shrinkWrap: true,
        softLineBreak: true,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: bodyStyle,
          h1: bodyStyle?.copyWith(fontWeight: FontWeight.w800),
          h2: bodyStyle?.copyWith(fontWeight: FontWeight.w800),
          h3: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
          h4: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
          h5: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
          h6: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
          blockSpacing: 4,
          listIndent: 18,
          blockquotePadding: const EdgeInsets.only(left: 8),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
          ),
          code: bodyStyle?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.primary,
          ),
        ),
        imageBuilder: (uri, title, alt) =>
            const Icon(Icons.image_outlined, size: 16),
      ),
    );
  }
}

class _NodeTypeSpecificContent extends StatelessWidget {
  const _NodeTypeSpecificContent({
    required this.node,
    required this.typedPayload,
    required this.effectivePreset,
    this.onNodeUpdated,
    this.maxBookmarkItems,
  });

  final MindmapNode node;
  final Object? typedPayload;
  final NodeSizePreset effectivePreset;
  final NodeUpdateCallback? onNodeUpdated;
  final int? maxBookmarkItems;

  @override
  Widget build(BuildContext context) {
    if (node.type == NodeType.image ||
        node.type == NodeType.itinerary ||
        node.type == NodeType.video) {
      return _ProductionNodeTypeContent(
        node: node,
        typedPayload: typedPayload,
        effectivePreset: node.type == NodeType.video
            ? NodeSizePreset.compact
            : effectivePreset,
      );
    }
    if (node.type == NodeType.resource) {
      return _ResourceNodeDetails(node: node);
    }
    if (node.type == NodeType.goal) {
      return LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: constraints.maxWidth,
            child: _GoalNodeMilestones(node: node),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: switch (node.type) {
        NodeType.task => _TaskNodeChecklist(node: node),
        NodeType.plan => _PlanNodeSteps(node: node),
        NodeType.goal => const SizedBox.shrink(),
        NodeType.habit => _HabitNodeInfo(node: node),
        NodeType.journal => _JournalNodeDetails(node: node),
        NodeType.note || NodeType.link => _NoteNodeSource(node: node),
        NodeType.event => _EventNodeDetails(node: node),
        NodeType.decision => _DecisionNodeDetails(node: node),
        NodeType.idea => _IdeaNodeDetails(node: node),
        NodeType.question => _QuestionNodeDetails(node: node),
        NodeType.contact => _ContactNodeDetails(node: node),
        NodeType.metric => _MetricNodeDetails(node: node),
        NodeType.expense => _ExpenseNodeDetails(node: node),
        NodeType.bookmark => _BookmarkNodeDetails(
          node: node,
          maxItems: maxBookmarkItems,
        ),
        NodeType.routine => _RoutineNodeDetails(node: node),
        NodeType.mood => _MoodNodeInfo(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.timer => _TimerNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.quote => _QuoteNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.audio => _AudioNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.checklist => _ChecklistNodeDetails(
          node: node,
          onNodeUpdated: onNodeUpdated,
        ),
        NodeType.canvas => _CanvasNodeDetails(node: node),
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

class _ProductionNodeTypeContent extends ConsumerStatefulWidget {
  const _ProductionNodeTypeContent({
    required this.node,
    this.typedPayload,
    this.effectivePreset,
  });
  final MindmapNode node;
  final Object? typedPayload;
  final NodeSizePreset? effectivePreset;

  @override
  ConsumerState<_ProductionNodeTypeContent> createState() =>
      _ProductionNodeTypeContentState();
}

@visibleForTesting
Widget buildProductionNodeTypeContentForTest(MindmapNode node) =>
    _ProductionNodeTypeContent(
      node: node,
      typedPayload: _typedPayloadForNode(node),
    );

class _ProductionNodeTypeContentState
    extends ConsumerState<_ProductionNodeTypeContent> {
  Uint8List? _bytes;
  Object? _error;
  bool _loading = false;
  int _revision = 0;
  late String _mediaSource = _mediaSourceFor(widget.node);
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _ProductionNodeTypeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSource = _mediaSourceFor(widget.node);
    if (oldWidget.node.id != widget.node.id || nextSource != _mediaSource) {
      _mediaSource = nextSource;
      unawaited(_load());
    }
  }

  static String _mediaSourceFor(MindmapNode node) {
    return switch (node.type) {
      NodeType.image => () {
        final payload = ImagePayload.fromNode(node);
        return payload.hasLocalAttachment
            ? 'attachment:${payload.attachmentId}'
            : 'url:${payload.url}';
      }(),
      NodeType.video => () {
        final payload = VideoPayload.fromNode(node);
        return payload.hasLocalAttachment
            ? 'attachment:${payload.attachmentId}'
            : 'url:${payload.url}';
      }(),
      NodeType.resource => () {
        final primary = ResourcePayload.fromNode(node).primaryAsset;
        if (primary == null) return '';
        if (primary.attachmentId.isNotEmpty) {
          return 'attachment:${primary.attachmentId}';
        }
        return '${primary.kind}:${primary.location}';
      }(),
      NodeType.audio => () {
        final payload = AudioPayload.fromNode(node);
        return payload.attachmentId.isNotEmpty
            ? 'attachment:${payload.attachmentId}'
            : 'url:${payload.remoteUrl}';
      }(),
      _ => '',
    };
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final source = _mediaSourceFor(widget.node);
    final attachmentId = switch (widget.node.type) {
      NodeType.image => ImagePayload.fromNode(widget.node).attachmentId,
      NodeType.video => VideoPayload.fromNode(widget.node).attachmentId,
      NodeType.resource =>
        ResourcePayload.fromNode(widget.node).primaryAsset?.attachmentId ?? '',
      _ => '',
    };
    if (attachmentId.isEmpty) {
      if (mounted && generation == _loadGeneration && source == _mediaSource) {
        setState(() {
          _bytes = null;
          _error = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      final bytes = await repository.readBytes(attachmentId);
      if (!mounted || generation != _loadGeneration || source != _mediaSource) {
        return;
      }
      setState(() {
        _bytes = bytes == null ? null : _attachmentBytes(bytes);
        _error = bytes == null ? 'Media thumbnail is missing.' : null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration || source != _mediaSource) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectivePreset =
        widget.effectivePreset ??
        (() {
          final uiState = NodeUiStateCodec.read(widget.node);
          final spec = NodePresentationSpec.forType(widget.node.type);
          return uiState.sizePreset == NodeSizePreset.auto ||
                  uiState.sizePreset == NodeSizePreset.custom
              ? spec.defaultPreset
              : uiState.sizePreset;
        })();
    return KeyedSubtree(
      key: ValueKey('production-node-content-${widget.node.id}-$_revision'),
      child: buildNodeTypeContent(
        NodeRenderContext(
          node: widget.node,
          typedPayload: widget.typedPayload,
          effectivePreset: effectivePreset,
          attachmentBytes: _bytes,
          attachmentLoading: _loading,
          attachmentError: _error?.toString(),
          onMediaAction: (action) async {
            if (action is RetryImageAction) {
              setState(() => _revision++);
              unawaited(_load());
            }
            if (action is OpenImageExternallyAction) {
              if (!isValidExternalImageUrl(action.target)) {
                setState(() => _error = 'Image URL is not safe to open.');
                return;
              }
              final uri = Uri.tryParse(action.target);
              if (uri != null) {
                unawaited(() async {
                  try {
                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (mounted && !opened) {
                      setState(() => _error = 'Image URL could not be opened.');
                    }
                  } on Object catch (error) {
                    if (mounted) setState(() => _error = error);
                  }
                }());
              }
            }
            if (action is OpenVideoExternallyAction) {
              if (!isValidExternalVideoUrl(action.target)) {
                setState(() => _error = 'Video URL is not safe to open.');
                return;
              }
              final uri = Uri.tryParse(action.target);
              if (uri != null) {
                unawaited(() async {
                  try {
                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (mounted && !opened) {
                      setState(() => _error = 'Video URL could not be opened.');
                    }
                  } on Object catch (error) {
                    if (mounted) setState(() => _error = error);
                  }
                }());
              }
            }
          },
        ),
      ),
    );
  }
}

class _ProductionNodeInlineEditor extends ConsumerStatefulWidget {
  const _ProductionNodeInlineEditor({
    required this.node,
    required this.onNodeUpdated,
    this.initialPayload,
    this.effectivePreset,
    this.onSaveStatusChanged,
    this.onImageExport,
  });
  final MindmapNode node;
  final Object? initialPayload;
  final NodeSizePreset? effectivePreset;
  final NodeUpdateCallback? onNodeUpdated;
  final ValueChanged<NodeSaveStatus>? onSaveStatusChanged;
  final ImageExportCallback? onImageExport;

  @override
  ConsumerState<_ProductionNodeInlineEditor> createState() =>
      _ProductionNodeInlineEditorState();
}

@visibleForTesting
Widget buildProductionNodeInlineEditorForTest({
  required MindmapNode node,
  required NodeUpdateCallback? onNodeUpdated,
  Object? initialPayload,
  ImageExportCallback? onImageExport,
  ValueChanged<NodeSaveStatus>? onSaveStatusChanged,
}) => _ProductionNodeInlineEditor(
  node: node,
  initialPayload: initialPayload ?? _typedPayloadForNode(node),
  onNodeUpdated: onNodeUpdated,
  onImageExport: onImageExport,
  onSaveStatusChanged: onSaveStatusChanged,
);

class _ProductionNodeInlineEditorState
    extends ConsumerState<_ProductionNodeInlineEditor> {
  late Object _draft;
  Uint8List? _bytes;
  Object? _error;
  bool _loading = false;
  late String _persistedRevision;
  String? _lastLocalRevision;
  late String _mediaSource;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialPayload ?? _payloadFor(widget.node);
    _persistedRevision = _dataRevision(widget.node);
    _mediaSource = _mediaSourceForDraft(_draft);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _ProductionNodeInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _draft = widget.initialPayload ?? _payloadFor(widget.node);
      _persistedRevision = _dataRevision(widget.node);
      _lastLocalRevision = null;
      _mediaSource = _mediaSourceForDraft(_draft);
      unawaited(_load());
      return;
    }
    final nextRevision = _dataRevision(widget.node);
    if (nextRevision != _persistedRevision) {
      if (nextRevision == _lastLocalRevision) {
        _persistedRevision = nextRevision;
        _lastLocalRevision = null;
      } else {
        setState(
          () => _draft = widget.initialPayload ?? _payloadFor(widget.node),
        );
        _persistedRevision = nextRevision;
        _lastLocalRevision = null;
      }
    }
    final nextSource = _mediaSourceForDraft(_draft);
    if (nextSource != _mediaSource) {
      _mediaSource = nextSource;
      unawaited(_load());
    }
  }

  static String _dataRevision(MindmapNode node) => jsonEncode(node.data);

  static String _mediaSourceForDraft(Object draft) {
    return switch (draft) {
      final ImagePayload payload =>
        payload.hasLocalAttachment
            ? 'attachment:${payload.attachmentId}'
            : 'url:${payload.url}',
      final VideoPayload payload =>
        payload.thumbnailAttachmentId.isNotEmpty
            ? 'attachment:${payload.thumbnailAttachmentId}'
            : 'url:${payload.thumbnailUrl}',
      final ResourcePayload payload => () {
        final primary = payload.primaryAsset;
        if (primary == null) return '';
        if (primary.attachmentId.isNotEmpty) {
          return 'attachment:${primary.attachmentId}';
        }
        return '${primary.kind}:${primary.location}';
      }(),
      final AudioPayload payload => switch (payload.sourceType) {
        AudioSourceType.attachment => 'attachment:${payload.attachmentId}',
        AudioSourceType.url => 'url:${payload.remoteUrl}',
        _ => '',
      },
      _ => '',
    };
  }

  static Object _payloadFor(MindmapNode node) => switch (node.type) {
    NodeType.image => ImagePayload.fromNode(node),
    NodeType.itinerary => ItineraryPayload.fromNode(node),
    NodeType.video => VideoPayload.fromNode(node),
    NodeType.resource => ResourcePayload.fromNode(node),
    NodeType.audio => AudioPayload.fromNode(node),
    _ => const ImagePayload(),
  };

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final source = _mediaSourceForDraft(_draft);
    final attachmentId = switch (_draft) {
      final ImagePayload payload => payload.attachmentId,
      final VideoPayload payload => payload.thumbnailAttachmentId,
      final ResourcePayload payload => payload.primaryAsset?.attachmentId ?? '',
      final AudioPayload payload => payload.attachmentId,
      _ => '',
    };
    if (attachmentId.isEmpty) {
      if (mounted && generation == _loadGeneration && source == _mediaSource) {
        setState(() {
          _bytes = null;
          _error = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      final bytes = await repository.readBytes(attachmentId);
      if (!mounted || generation != _loadGeneration || source != _mediaSource) {
        return;
      }
      setState(() {
        _bytes = bytes == null ? null : _attachmentBytes(bytes);
        _error = bytes == null ? 'Media thumbnail is missing.' : null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration || source != _mediaSource) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  Future<void> _saveDraft(MindmapNode baseNode, Object value) async {
    final nextSource = _mediaSourceForDraft(value);
    final sourceChanged = nextSource != _mediaSource;
    setState(() => _draft = value);
    if (sourceChanged) {
      _mediaSource = nextSource;
      unawaited(_load());
    }
    widget.onSaveStatusChanged?.call(NodeSaveStatus.dirty);
    final Map<String, Object?> data = switch (value) {
      final ImagePayload payload => payload.toData(baseNode.data),
      final ItineraryPayload payload => payload.toData(baseNode.data),
      final VideoPayload payload => payload.toData(baseNode.data),
      final TaskChecklistPayload payload => payload.toData(baseNode.data),
      final ChecklistPayload payload => payload.toData(baseNode.data),
      final NotePayload payload => payload.toData(baseNode.data),
      final KanbanPayload payload => payload.toData(baseNode.data),
      final ResourcePayload payload => payload.toData(baseNode.data),
      final LinkResourcePayload payload => payload.toData(baseNode.data),
      final AudioPayload payload => payload.toData(baseNode.data),
      _ => baseNode.data,
    };
    final updatedNode = switch (value) {
      final TaskChecklistPayload payload =>
        payload.toNode(baseNode).copyWith(updatedAt: DateTime.now()),
      final ChecklistPayload payload =>
        payload.toNode(baseNode).copyWith(updatedAt: DateTime.now()),
      final ResourcePayload payload =>
        payload.toNode(baseNode).copyWith(updatedAt: DateTime.now()),
      final LinkResourcePayload payload =>
        payload.toNode(baseNode).copyWith(updatedAt: DateTime.now()),
      _ => baseNode.copyWith(data: data, updatedAt: DateTime.now()),
    };
    if (baseNode.id == widget.node.id) {
      _lastLocalRevision = jsonEncode(data);
    }
    widget.onSaveStatusChanged?.call(NodeSaveStatus.saving);
    try {
      await widget.onNodeUpdated?.call(updatedNode);
      widget.onSaveStatusChanged?.call(NodeSaveStatus.saved);
    } on Object {
      widget.onSaveStatusChanged?.call(NodeSaveStatus.error);
    }
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
      if (file.size <= 0) {
        throw const FormatException('Selected attachment is empty.');
      }
      if (file.size > maxNodeAttachmentBytes) {
        throw const FormatException('Attachment exceeds 100 MB.');
      }
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.readStream != null) {
        final builder = BytesBuilder(copy: false);
        var length = 0;
        await for (final chunk in file.readStream!) {
          length += chunk.length;
          if (length > maxNodeAttachmentBytes) {
            throw const FormatException('Attachment exceeds 100 MB.');
          }
          builder.add(chunk);
        }
        bytes = builder.takeBytes();
      }
      if (bytes == null || bytes.isEmpty || bytes.length != file.size) {
        throw const FormatException('Attachment data is unavailable.');
      }
      final repository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      final mimeType = _taskAttachmentMimeType(file.extension);
      final attachment = await repository.importBytes(
        bytes: bytes,
        fileName: file.name,
        mimeType: mimeType,
      );
      return TaskAttachmentReference(
        id: attachment.id,
        fileName: attachment.fileName,
        mimeType: attachment.mimeType,
        byteLength: attachment.byteLength,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
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
          uri.host.isEmpty) {
        if (mounted) {
          setState(() => _error = 'Resource URL is not safe to open.');
        }
        return;
      }
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (mounted && !opened) {
          setState(() => _error = 'Resource URL could not be opened.');
        }
      } on Object catch (error) {
        if (mounted) setState(() => _error = error);
      }
      return;
    }
    if (!asset.isFile || asset.attachmentId.isEmpty) {
      if (mounted) setState(() => _error = 'Resource file is unavailable.');
      return;
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
    try {
      final repository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      final bytes = await repository.readBytes(attachment.id);
      if (bytes == null || !mounted) {
        throw const FormatException('Attachment is unavailable.');
      }
      final data = _attachmentBytes(bytes);
      if (attachment.mimeType.startsWith('image/')) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
              child: Stack(
                children: [
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
      if (attachment.mimeType.startsWith('text/') ||
          _isTextAttachmentName(attachment.fileName)) {
        final preview = utf8.decode(data, allowMalformed: true);
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(attachment.fileName),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: SelectableText(
                  preview.length > 20000
                      ? preview.substring(0, 20000)
                      : preview,
                ),
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
        return;
      }
      final callback = widget.onImageExport;
      if (callback != null) {
        await callback(data, attachment.fileName);
      } else {
        await saveCanvasPng(data, attachment.fileName);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _removeTaskAttachment(TaskAttachmentReference attachment) async {
    try {
      final repository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      await repository.delete(attachment.id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      rethrow;
    }
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
        'aac' => 'audio/aac',
        'm4a' => 'audio/m4a',
        'mp3' => 'audio/mpeg',
        'ogg' => 'audio/ogg',
        'wav' => 'audio/wav',
        _ => 'application/octet-stream',
      };

  static bool _isTextAttachmentName(String fileName) {
    final lower = fileName.toLowerCase();
    return const [
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

  static List<List<String>> _resourceFolderSuggestions(
    List<MindmapNode> nodes,
  ) {
    final seen = <String>{};
    final suggestions = <List<String>>[];
    for (final node in nodes) {
      if (node.type != NodeType.resource) continue;
      final path = ResourcePayload.fromNode(node).folderPath;
      if (path.isEmpty) continue;
      final key = path.map((item) => item.trim().toLowerCase()).join('\u0000');
      if (seen.add(key)) suggestions.add(List<String>.unmodifiable(path));
    }
    return List<List<String>>.unmodifiable(suggestions);
  }

  @override
  Widget build(BuildContext context) {
    final NodeSizePreset preset =
        widget.effectivePreset ??
        (() {
          final uiState = NodeUiStateCodec.read(widget.node);
          final spec = NodePresentationSpec.forType(widget.node.type);
          return uiState.sizePreset == NodeSizePreset.auto ||
                  uiState.sizePreset == NodeSizePreset.custom
              ? spec.defaultPreset
              : uiState.sizePreset;
        })();
    final List<String> errors = switch (_draft) {
      final ImagePayload payload => payload.validate(title: widget.node.title),
      final ItineraryPayload payload => payload.validate(
        title: widget.node.title,
      ),
      final VideoPayload payload => payload.validate(title: widget.node.title),
      final TaskChecklistPayload payload => payload.validate(
        title: widget.node.title,
      ),
      final ChecklistPayload payload => payload.validate(
        title: widget.node.title,
      ),
      final NotePayload payload => payload.validate(title: widget.node.title),
      final ResourcePayload payload => payload.validate(
        title: widget.node.title,
      ),
      final LinkResourcePayload payload => payload.validate(
        title: widget.node.title,
      ),
      final AudioPayload payload => payload.validate(title: widget.node.title),
      _ => const <String>[],
    };
    final List<List<String>> resourceFolderSuggestions =
        widget.node.type == NodeType.resource
        ? ref
              .watch(nodesForDayProvider(widget.node.day))
              .when(
                data: _resourceFolderSuggestions,
                error: (_, _) => const <List<String>>[],
                loading: () => const <List<String>>[],
              )
        : const <List<String>>[];
    final nodeSnapshot = widget.node;
    return buildNodeTypeInlineEditor(
      NodeEditContext(
        node: widget.node,
        typedDraft: _draft,
        cachedPayload: widget.initialPayload,
        effectivePreset: preset,
        validationErrors: errors,
        onTitleChanged: (value) => widget.onNodeUpdated?.call(
          widget.node.copyWith(title: value, updatedAt: DateTime.now()),
        ),
        onBodyChanged: (value) => widget.onNodeUpdated?.call(
          widget.node.copyWith(body: value, updatedAt: DateTime.now()),
        ),
        onDraftChanged: (value) => unawaited(_saveDraft(nodeSnapshot, value)),
        onNodeDraftChanged: (value) => widget.onNodeUpdated?.call(value),
        attachmentBytes: _bytes,
        attachmentLoading: _loading,
        attachmentError: _error?.toString(),
        onTaskAttachmentAdd: widget.node.type == NodeType.task
            ? _addTaskAttachment
            : null,
        onTaskAttachmentOpen: widget.node.type == NodeType.task
            ? _openTaskAttachment
            : null,
        onTaskAttachmentRemove: widget.node.type == NodeType.task
            ? _removeTaskAttachment
            : null,
        onResourceAssetAdd:
            widget.node.type == NodeType.resource ||
                widget.node.type == NodeType.expense
            ? _addResourceAsset
            : null,
        onResourceAssetOpen:
            widget.node.type == NodeType.resource ||
                widget.node.type == NodeType.expense
            ? _openResourceAsset
            : null,
        resourceFolderSuggestions: resourceFolderSuggestions,
        onKanbanAttachmentAdd: widget.node.type == NodeType.kanban
            ? _addKanbanAttachment
            : null,
        onKanbanAttachmentOpen: widget.node.type == NodeType.kanban
            ? _openKanbanAttachment
            : null,
        onKanbanAttachmentRemove: widget.node.type == NodeType.kanban
            ? _removeKanbanAttachment
            : null,
        onPlanAttachmentAdd: widget.node.type == NodeType.plan
            ? _addPlanAttachment
            : null,
        onPlanAttachmentOpen: widget.node.type == NodeType.plan
            ? _openPlanAttachment
            : null,
        onPlanAttachmentRemove: widget.node.type == NodeType.plan
            ? _removePlanAttachment
            : null,
        onKanbanAction: widget.node.type == NodeType.kanban
            ? (value) => _saveDraft(nodeSnapshot, value)
            : null,
        onMediaAction: (action) async {
          if (action is SaveEditedImageAction) {
            try {
              final repository = await ref.read(
                nodeAttachmentRepositoryProvider.future,
              );
              final attachment = await repository.importBytes(
                bytes: action.bytes,
                fileName:
                    'edited-image-${DateTime.now().millisecondsSinceEpoch}.png',
                mimeType: 'image/png',
              );
              action.result.complete(
                action.existing.copyWith(
                  attachmentId: attachment.id,
                  originalAttachmentId:
                      action.existing.originalAttachmentId.isEmpty
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
            } on Object catch (error) {
              action.result.complete(null);
              if (mounted) setState(() => _error = error);
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
            } on Object catch (error) {
              action.result.complete(null);
              if (mounted) setState(() => _error = error);
            }
            return;
          }
          if (action is RetryImageAction) unawaited(_load());
          if (action is ReplaceImageAction) {
            try {
              final existing = _draft as ImagePayload;
              final service = await ref.read(
                mediaFileImportServiceProvider.future,
              );
              final replacement = await service.pickImage(existing: existing);
              if (replacement == null || !mounted) return;
              setState(() => _error = null);
              await _saveDraft(widget.node, replacement);
            } on FormatException catch (error) {
              if (mounted) setState(() => _error = error.message);
            } on Object catch (error) {
              if (mounted) setState(() => _error = error);
            }
            return;
          }
          if (action is ExportImageAction) {
            final payload = _draft as ImagePayload;
            final source = _mediaSourceForDraft(payload);
            final attachmentId = payload.attachmentId;
            final fileName = payload.fileName.isEmpty
                ? 'image.png'
                : payload.fileName;
            if (attachmentId.isEmpty || action.attachmentId != attachmentId) {
              return;
            }
            unawaited(() async {
              try {
                final repository = await ref.read(
                  nodeAttachmentRepositoryProvider.future,
                );
                if (!mounted || _mediaSource != source) return;
                final bytes = await repository.exportBytes(attachmentId);
                if (!mounted || _mediaSource != source) return;
                if (bytes == null) {
                  setState(() => _error = 'Image attachment is unavailable.');
                  return;
                }
                final exportBytes = _attachmentBytes(bytes);
                final callback = widget.onImageExport;
                if (callback != null) {
                  await callback(exportBytes, fileName);
                  return;
                }
                await saveCanvasPng(exportBytes, fileName);
              } on Object catch (error) {
                if (mounted) setState(() => _error = error);
              }
            }());
          }
          if (action is OpenImageExternallyAction) {
            if (!isValidExternalImageUrl(action.target)) {
              setState(() => _error = 'Image URL is not safe to open.');
              return;
            }
            final uri = Uri.tryParse(action.target);
            if (uri != null) {
              unawaited(() async {
                try {
                  final opened = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (mounted && !opened) {
                    setState(() => _error = 'Image URL could not be opened.');
                  }
                } on Object catch (error) {
                  if (mounted) setState(() => _error = error);
                }
              }());
            }
          }
          if (action is ReplaceVideoAction) {
            setState(() {
              _error =
                  'Local file picker is unavailable. Replace using a video URL.';
            });
          }
          if (action is ExportVideoAction) {
            final payload = VideoPayload.fromNode(widget.node);
            final attachmentId = payload.attachmentId;
            if (attachmentId.isEmpty || action.attachmentId != attachmentId) {
              return;
            }
            unawaited(() async {
              try {
                final repository = await ref.read(
                  nodeAttachmentRepositoryProvider.future,
                );
                final bytes = await repository.exportBytes(attachmentId);
                if (!mounted || bytes == null) {
                  if (mounted) {
                    setState(() => _error = 'Video attachment is unavailable.');
                  }
                  return;
                }
                final callback = widget.onImageExport;
                if (callback != null) {
                  await callback(
                    _attachmentBytes(bytes),
                    payload.fileName.isEmpty ? 'video.mp4' : payload.fileName,
                  );
                }
              } on Object catch (error) {
                if (mounted) setState(() => _error = error);
              }
            }());
          }
          if (action is OpenVideoExternallyAction) {
            if (!isValidExternalVideoUrl(action.target)) {
              setState(() => _error = 'Video URL is not safe to open.');
              return;
            }
            final uri = Uri.tryParse(action.target);
            if (uri != null) {
              unawaited(() async {
                try {
                  final opened = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (mounted && !opened) {
                    setState(() => _error = 'Video URL could not be opened.');
                  }
                } on Object catch (error) {
                  if (mounted) setState(() => _error = error);
                }
              }());
            }
          }
        },
      ),
    );
  }
}

class _MoodNodeInfo extends StatelessWidget {
  const _MoodNodeInfo({required this.node, required this.onNodeUpdated});
  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final energy = (node.data['energy'] as num?)?.toDouble() ?? 3.0;
    const moodList = ['😞', '☹️', '😐', '🙂', '🤩'];
    final storedMood = node.data['mood'] as String?;
    final mood = moodList.contains(storedMood)
        ? storedMood!
        : moodList[energy.round().clamp(1, 5) - 1];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Mood:', style: Theme.of(context).textTheme.bodySmall),
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
                child: Opacity(
                  opacity: m == mood ? 1.0 : 0.4,
                  child: Text(m, style: const TextStyle(fontSize: 18)),
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
                activeColor: NodeVisuals.color(context, node.type),
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

  HybridTimerState get _state => TimerPayload.fromNode(widget.node).timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(_TimerNodeDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.data != widget.node.data) _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!_state.isRunning) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggleRunning() async {
    final now = DateTime.now();
    final state = _state;
    final updatedState = state.isRunning ? state.pause(now) : state.start(now);
    await widget.onNodeUpdated?.call(
      widget.node.copyWith(
        data: TimerPayload(timer: updatedState).toData(widget.node.data),
        updatedAt: now,
      ),
    );
  }

  String _formatTime(int totalSecs) {
    final safe = totalSecs.clamp(0, 359999);
    final hours = safe ~/ 3600;
    final mins = (safe % 3600) ~/ 60;
    final secs = safe % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${mins.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = NodeVisuals.color(context, widget.node.type);
    final now = DateTime.now();
    final state = _state;
    final seconds = state.mode == TimerMode.stopwatch
        ? state.elapsedSecondsAt(now)
        : state.remainingSecondsAt(now) ?? 0;
    final status = state.effectiveStatusAt(now);

    return Column(
      key: const ValueKey<String>('timer-collapsed-preview'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(_timerModeIcon(state.mode), size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _timerModeLabel(state.mode),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              _timerStatusLabel(status),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              key: const ValueKey<String>('timer-collapsed-primary-action'),
              tooltip: state.isRunning ? 'Pause timer' : 'Start timer',
              visualDensity: VisualDensity.compact,
              onPressed: widget.onNodeUpdated == null ? null : _toggleRunning,
              icon: Icon(
                state.isRunning
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            _formatTime(seconds),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        if (state.isBounded) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: state.progressAt(now)),
        ],
        if (state.mode == TimerMode.focus) ...[
          const SizedBox(height: 6),
          Text(
            '${state.segment == FocusSegment.focus ? 'Focus' : 'Break'} ΓÇó'
            '${state.completedCycles}/${state.cycleTarget} cycles',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}

String _timerModeLabel(TimerMode mode) => switch (mode) {
  TimerMode.focus => 'Focus',
  TimerMode.countdown => 'Countdown',
  TimerMode.stopwatch => 'Stopwatch',
};

IconData _timerModeIcon(TimerMode mode) => switch (mode) {
  TimerMode.focus => Icons.center_focus_strong_outlined,
  TimerMode.countdown => Icons.hourglass_bottom_rounded,
  TimerMode.stopwatch => Icons.timer_outlined,
};

String _timerStatusLabel(TimerRunStatus status) => switch (status) {
  TimerRunStatus.idle => 'Idle',
  TimerRunStatus.running => 'Running',
  TimerRunStatus.paused => 'Paused',
  TimerRunStatus.expired => 'Expired',
  TimerRunStatus.completed => 'Completed',
};

class _QuoteNodeDetails extends StatelessWidget {
  const _QuoteNodeDetails({required this.node, required this.onNodeUpdated});

  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  Future<void> _copyQuote(BuildContext context, QuotePayload payload) async {
    final quote = node.body.trim();
    if (quote.isEmpty) return;
    final text = payload.author.trim().isEmpty
        ? quote
        : '?$quote? ? ${payload.author.trim()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Quote copied')));
  }

  @override
  Widget build(BuildContext context) {
    final payload = QuotePayload.fromNode(node);
    final color = NodeVisuals.color(context, node.type);
    final quote = node.body.trim().isEmpty ? 'No quote text yet.' : node.body;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 240 || constraints.maxHeight < 190;
        final showMetadata = constraints.maxHeight >= 150;
        final showTags =
            payload.tags.isNotEmpty && constraints.maxHeight >= 220;
        final showActions = constraints.maxHeight >= 180;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  size: compact ? 18 : 24,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    quote,
                    key: const ValueKey<String>('quote-collapsed-text'),
                    maxLines: compact ? 3 : 6,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                ),
                if (payload.isFavorite)
                  Icon(Icons.star_rounded, size: 20, color: color),
              ],
            ),
            if (payload.author.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '? ${payload.author.trim()}',
                  key: const ValueKey<String>('quote-collapsed-author'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
            if (showMetadata &&
                (payload.source.trim().isNotEmpty ||
                    payload.collection.trim().isNotEmpty)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (payload.source.trim().isNotEmpty)
                    _QuoteMetadataChip(
                      icon: Icons.menu_book_outlined,
                      label: payload.source.trim(),
                    ),
                  if (payload.collection.trim().isNotEmpty)
                    _QuoteMetadataChip(
                      icon: Icons.folder_outlined,
                      label: payload.collection.trim(),
                    ),
                ],
              ),
            ],
            if (showTags) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 4,
                children: [
                  for (final tag in payload.tags.take(compact ? 2 : 5))
                    Text(
                      '#$tag',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: color),
                    ),
                ],
              ),
            ],
            if (showActions) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    key: const ValueKey<String>('quote-collapsed-favorite'),
                    visualDensity: VisualDensity.compact,
                    tooltip: payload.isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    onPressed: onNodeUpdated == null
                        ? null
                        : () => onNodeUpdated!(
                            node.copyWith(
                              data: payload
                                  .copyWith(isFavorite: !payload.isFavorite)
                                  .toData(node.data),
                            ),
                          ),
                    icon: Icon(
                      payload.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: payload.isFavorite ? color : null,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('quote-collapsed-copy'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy quote',
                    onPressed: node.body.trim().isEmpty
                        ? null
                        : () => _copyQuote(context, payload),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _QuoteMetadataChip extends StatelessWidget {
  const _QuoteMetadataChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 180),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    ),
  );
}

class _AudioNodeDetails extends ConsumerStatefulWidget {
  const _AudioNodeDetails({required this.node, required this.onNodeUpdated});
  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  ConsumerState<_AudioNodeDetails> createState() => _AudioNodeDetailsState();
}

@visibleForTesting
Widget buildCollapsedAudioDetailsForTest(MindmapNode node) =>
    _AudioNodeDetails(node: node, onNodeUpdated: null);

class _AudioNodeDetailsState extends ConsumerState<_AudioNodeDetails> {
  final AudioPlayer _player = AudioPlayer();
  String? _loadedSourceKey;
  String? _playbackSourcePath;
  bool _loading = false;
  String? _error;

  AudioPayload get _payload => AudioPayload.fromNode(widget.node);

  String get _sourceKey => switch (_payload.sourceType) {
    AudioSourceType.url => 'url:${_payload.remoteUrl}',
    AudioSourceType.attachment => 'attachment:${_payload.attachmentId}',
    AudioSourceType.legacy => 'legacy:${_payload.fileName}',
    AudioSourceType.none => '',
  };

  @override
  void didUpdateWidget(covariant _AudioNodeDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPayload = AudioPayload.fromNode(oldWidget.node);
    final oldSourceKey = switch (oldPayload.sourceType) {
      AudioSourceType.url => 'url:${oldPayload.remoteUrl}',
      AudioSourceType.attachment => 'attachment:${oldPayload.attachmentId}',
      AudioSourceType.legacy => 'legacy:${oldPayload.fileName}',
      AudioSourceType.none => '',
    };
    if (oldWidget.node.id != widget.node.id || oldSourceKey != _sourceKey) {
      unawaited(_resetSource());
    }
  }

  Future<void> _resetSource() async {
    await _player.stop();
    _loadedSourceKey = null;
    final playbackSourcePath = _playbackSourcePath;
    _playbackSourcePath = null;
    if (playbackSourcePath != null) {
      await deleteAudioPlaybackSource(playbackSourcePath);
    }
    if (mounted) setState(() => _error = null);
  }

  Future<bool> _ensureLoaded() async {
    if (_sourceKey.isEmpty) return false;
    if (_loadedSourceKey == _sourceKey) return true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _resetSource();
      if (_payload.sourceType == AudioSourceType.url) {
        await _player.setUrl(_payload.remoteUrl);
      } else {
        final repository = await ref.read(
          nodeAttachmentRepositoryProvider.future,
        );
        final bytes = await repository.readBytes(_payload.attachmentId);
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Stored voice note could not be loaded.');
        }
        final path = await createAudioPlaybackSource(
          _attachmentBytes(bytes),
          _payload.mimeType.isEmpty ? 'audio/mpeg' : _payload.mimeType,
        );
        _playbackSourcePath = path;
        await _player.setFilePath(path);
      }
      _loadedSourceKey = _sourceKey;
      return true;
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (!await _ensureLoaded()) return;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    unawaited(_player.play());
  }

  @override
  void dispose() {
    final playbackSourcePath = _playbackSourcePath;
    unawaited(_player.dispose());
    if (playbackSourcePath != null) {
      unawaited(deleteAudioPlaybackSource(playbackSourcePath));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final path = payload.fileName.isNotEmpty
        ? payload.fileName
        : payload.remoteUrl;
    final transcript = payload.transcriptText;
    final color = NodeVisuals.color(context, widget.node.type);

    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      initialData: _player.playerState,
      builder: (context, playerSnapshot) => StreamBuilder<Duration>(
        stream: _player.positionStream,
        initialData: _player.position,
        builder: (context, positionSnapshot) {
          final playing = playerSnapshot.data?.playing ?? false;
          final position = positionSnapshot.data ?? Duration.zero;
          final duration = _player.duration ?? Duration.zero;
          final progress = duration.inMilliseconds == 0
              ? 0.0
              : (position.inMilliseconds / duration.inMilliseconds).clamp(
                  0.0,
                  1.0,
                );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey<String>('audio-collapsed-play-toggle'),
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                          ),
                    iconSize: 40,
                    color: color,
                    onPressed: path.isEmpty || _loading
                        ? null
                        : () => unawaited(_togglePlayback()),
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                ),
                                child: Slider(
                                  value: progress,
                                  onChanged: duration == Duration.zero
                                      ? null
                                      : (value) => unawaited(
                                          _player.seek(duration * value),
                                        ),
                                  activeColor: color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatAudioDuration(duration),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
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
        },
      ),
    );
  }
}

String _formatAudioDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
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
  final TextEditingController _todoInputController = TextEditingController();
  bool _isAdding = false;

  ChecklistPayload get _payload => ChecklistPayload.fromNode(widget.node);

  @override
  void dispose() {
    _todoInputController.dispose();
    super.dispose();
  }

  void _persist(ChecklistPayload payload) {
    widget.onNodeUpdated?.call(
      payload.toNode(widget.node).copyWith(updatedAt: DateTime.now()),
    );
  }

  void _addTodo() {
    final text = _todoInputController.text.trim();
    if (text.isEmpty || widget.onNodeUpdated == null) return;
    _persist(
      _payload.copyWith(
        items: <ChecklistEntry>[
          ..._payload.items,
          ChecklistEntry(id: 'check-${const Uuid().v4()}', title: text),
        ],
      ),
    );
    _todoInputController.clear();
    setState(() => _isAdding = false);
  }

  void _toggle(ChecklistEntry item, bool isDone) {
    _persist(
      _payload.copyWith(
        items: <ChecklistEntry>[
          for (final entry in _payload.items)
            if (entry.id == item.id) entry.copyWith(isDone: isDone) else entry,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = NodeVisuals.color(context, widget.node.type);
    final semantic = AppSemanticColors.of(context);
    final payload = _payload;
    final previewItems = <ChecklistEntry>[
      ...payload.items.where((item) => !item.isDone),
      ...payload.items.where((item) => item.isDone),
    ].take(4).toList(growable: false);

    return Column(
      key: const ValueKey<String>('checklist-collapsed-preview'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${payload.completedCount}/${payload.items.length} completed',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Text('${(payload.progress * 100).round()}%'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: payload.progress, color: color),
        const SizedBox(height: 6),
        if (previewItems.isEmpty && !_isAdding)
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
          for (final item in previewItems)
            Row(
              children: <Widget>[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    key: ValueKey<String>(
                      'checklist-collapsed-toggle-${item.id}',
                    ),
                    value: item.isDone,
                    activeColor: color,
                    onChanged: widget.onNodeUpdated == null
                        ? null
                        : (value) => _toggle(item, value ?? false),
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
                if (item.priority != ChecklistPriority.none)
                  Icon(
                    Icons.flag_outlined,
                    size: 14,
                    color: switch (item.priority) {
                      ChecklistPriority.none => null,
                      ChecklistPriority.low => semantic.info,
                      ChecklistPriority.medium => semantic.warning,
                      ChecklistPriority.high => semantic.danger,
                    },
                  ),
              ],
            ),
        if (payload.items.length > 4)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              '+ ${payload.items.length - 4} more items',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: semantic.textSecondary),
            ),
          ),
        const SizedBox(height: 4),
        if (_isAdding)
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    key: const ValueKey<String>(
                      'checklist-collapsed-add-field',
                    ),
                    controller: _todoInputController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'New item...',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addTodo(),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey<String>('checklist-collapsed-add-submit'),
                tooltip: 'Add item',
                visualDensity: VisualDensity.compact,
                onPressed: _addTodo,
                icon: const Icon(Icons.check, size: 16),
              ),
              IconButton(
                tooltip: 'Cancel',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _isAdding = false),
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          )
        else
          TextButton.icon(
            key: const ValueKey<String>('checklist-collapsed-add-action'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 24),
              alignment: Alignment.centerLeft,
            ),
            onPressed: widget.onNodeUpdated == null
                ? null
                : () => setState(() => _isAdding = true),
            icon: Icon(Icons.add, size: 14, color: color),
            label: Text(
              'Add item',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
      ],
    );
  }
}

class _CanvasNodeDetails extends StatelessWidget {
  const _CanvasNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = CanvasPayload.fromNode(node);
    final color = NodeVisuals.color(context, node.type);
    final backgroundLabel = switch (payload.background) {
      'grid' => 'Grid',
      'dots' => 'Dots',
      _ => 'Plain',
    };

    return IgnorePointer(
      child: SizedBox(
        height: 150,
        child: Column(
          key: const ValueKey<String>('canvas-collapsed-preview'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CanvasDocumentView(payload: payload),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  child: Text(
                    '${payload.elements.length} elements',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  backgroundLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherNodeDetails extends StatelessWidget {
  const _WeatherNodeDetails({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = WeatherPayload.fromNode(node);
    final temp = payload.temp.isEmpty
        ? 'ΓÇö'
        : '${payload.temp}${payload.unit}';
    final condition = payload.weather.isEmpty
        ? 'No condition'
        : payload.weather;
    final metadata = <String>[
      if (payload.location.trim().isNotEmpty) payload.location.trim(),
      if (payload.weatherDate.trim().isNotEmpty) payload.weatherDate.trim(),
    ].join(' ┬╖ ');
    final color = NodeVisuals.color(context, node.type);

    IconData weatherIcon() {
      final code = payload.weatherCode.trim().toLowerCase();
      if (code == 'storm') return Icons.thunderstorm_outlined;
      if (code == 'rain') return Icons.water_drop_outlined;
      if (code == 'snow') return Icons.ac_unit_outlined;
      if (code == 'windy') return Icons.air_outlined;
      if (code == 'cloudy') return Icons.cloud_outlined;
      if (code == 'fog') return Icons.foggy;
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                temp,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                condition,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (metadata.isNotEmpty)
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
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
  Widget build(BuildContext context) =>
      _FitDashboardDetails(node: node, onNodeUpdated: onNodeUpdated);
}

@visibleForTesting
Widget buildCollapsedFitnessDetailsForTest(
  MindmapNode node, {
  NodeUpdateCallback? onNodeUpdated,
}) => _FitNodeDetails(node: node, onNodeUpdated: onNodeUpdated);

class _FitDashboardDetails extends StatelessWidget {
  const _FitDashboardDetails({required this.node, required this.onNodeUpdated});

  final MindmapNode node;
  final NodeUpdateCallback? onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final payload = FitPayload.fromNode(node);
    final color = NodeVisuals.color(context, node.type);
    final workout = payload.workout.trim();
    final waterIncrement = switch (payload.waterUnit.trim().toLowerCase()) {
      'ml' => 250.0,
      'cup' || 'cups' => 1.0,
      _ => 0.25,
    };

    void update(FitPayload nextPayload) {
      onNodeUpdated?.call(
        node.copyWith(
          data: nextPayload.toData(node.data),
          updatedAt: DateTime.now(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          key: const ValueKey<String>('fit-collapse-workout'),
          children: [
            Icon(
              payload.completed
                  ? Icons.check_circle_rounded
                  : Icons.fitness_center_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                workout.isEmpty ? 'Daily activity' : workout,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _FitStatusBadge(label: payload.intensity),
            if (payload.syncEnabled) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: payload.syncSource.trim().isEmpty
                    ? 'Health data synced'
                    : 'Synced from ${payload.syncSource.trim()}',
                child: Icon(
                  Icons.sync_rounded,
                  key: const ValueKey<String>('fit-collapse-sync'),
                  size: 14,
                  color: color,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _FitCompactProgress(
          key: const ValueKey<String>('fit-collapse-steps'),
          icon: Icons.directions_walk_rounded,
          label: 'Steps',
          value:
              '${_fitCanvasNumber(payload.steps)} / ${_fitCanvasNumber(payload.stepGoal)}',
          progress: _fitCanvasProgress(payload.steps, payload.stepGoal),
          color: color,
          addKey: const ValueKey<String>('fit-collapse-steps-add'),
          addTooltip: 'Add 1,000 steps',
          onAdd: onNodeUpdated == null
              ? null
              : () => update(
                  payload.copyWith(steps: (payload.steps ?? 0) + 1000),
                ),
        ),
        const SizedBox(height: 6),
        _FitCompactProgress(
          key: const ValueKey<String>('fit-collapse-active'),
          icon: Icons.timer_outlined,
          label: 'Active',
          value:
              '${_fitCanvasNumber(payload.durationMinutes)} / ${_fitCanvasNumber(payload.durationGoalMinutes)} min',
          progress: _fitCanvasProgress(
            payload.durationMinutes,
            payload.durationGoalMinutes,
          ),
          color: color,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _FitMetricChip(
              key: const ValueKey<String>('fit-collapse-water'),
              icon: Icons.water_drop_outlined,
              value: '${_fitCanvasNumber(payload.water)} ${payload.waterUnit}',
              color: color,
              addKey: const ValueKey<String>('fit-collapse-water-add'),
              addTooltip: 'Add water',
              onAdd: onNodeUpdated == null
                  ? null
                  : () => update(
                      payload.copyWith(
                        water: (payload.water ?? 0) + waterIncrement,
                      ),
                    ),
            ),
            _FitMetricChip(
              key: const ValueKey<String>('fit-collapse-calories'),
              icon: Icons.local_fire_department_outlined,
              value: '${_fitCanvasNumber(payload.calories)} kcal',
              color: color,
            ),
            _FitMetricChip(
              key: const ValueKey<String>('fit-collapse-distance'),
              icon: Icons.route_outlined,
              value:
                  '${_fitCanvasNumber(payload.distance)} ${payload.distanceUnit}',
              color: color,
            ),
            if (payload.sleepHours != null)
              _FitMetricChip(
                key: const ValueKey<String>('fit-collapse-sleep'),
                icon: Icons.bedtime_outlined,
                value: '${_fitCanvasNumber(payload.sleepHours)} h',
                color: color,
              ),
            if (payload.restingHeartRate != null)
              _FitMetricChip(
                key: const ValueKey<String>('fit-collapse-heart-rate'),
                icon: Icons.favorite_border_rounded,
                value: '${_fitCanvasNumber(payload.restingHeartRate)} bpm',
                color: color,
              ),
          ],
        ),
      ],
    );
  }
}

class _FitCompactProgress extends StatelessWidget {
  const _FitCompactProgress({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
    this.addKey,
    this.addTooltip,
    this.onAdd,
  });

  final IconData icon;
  final String label;
  final String value;
  final double progress;
  final Color color;
  final Key? addKey;
  final String? addTooltip;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    Text(value, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: color.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ],
            ),
          ),
          if (onAdd != null) ...[
            const SizedBox(width: 4),
            IconButton(
              key: addKey,
              tooltip: addTooltip,
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 15),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    ),
  );
}

class _FitMetricChip extends StatelessWidget {
  const _FitMetricChip({
    super.key,
    required this.icon,
    required this.value,
    required this.color,
    this.addKey,
    this.addTooltip,
    this.onAdd,
  });

  final IconData icon;
  final String value;
  final Color color;
  final Key? addKey;
  final String? addTooltip;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.16)),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(8, 5, onAdd == null ? 8 : 3, 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(value, style: Theme.of(context).textTheme.labelSmall),
          if (onAdd != null) ...[
            const SizedBox(width: 2),
            IconButton(
              key: addKey,
              tooltip: addTooltip,
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 14),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    ),
  );
}

class _FitStatusBadge extends StatelessWidget {
  const _FitStatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.trim().toLowerCase();
    final value = normalized.isEmpty
        ? 'Moderate'
        : '${normalized[0].toUpperCase()}${normalized.substring(1)}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(value, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

double _fitCanvasProgress(double? value, double target) {
  if (value == null || target <= 0) return 0;
  return (value / target).clamp(0, 1).toDouble();
}

String _fitCanvasNumber(double? value) {
  if (value == null) return '0';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
}

class _EventNodeDetails extends StatelessWidget {
  const _EventNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = EventCalendarPayload.fromNode(node);
    final summary = _eventCollapsedSummary(node);
    final details = <String>[
      if (summary.isNotEmpty) summary,
      if (payload.location.trim().isNotEmpty) payload.location.trim(),
    ];
    return _MiniDetailList(items: details);
  }
}

String _eventCollapsedSummary(MindmapNode node) {
  final payload = EventCalendarPayload.fromNode(node);
  final start = [
    payload.startDate.trim(),
    payload.startTime.trim(),
  ].where((value) => value.isNotEmpty).join(' ');
  final end = [
    payload.endDate.trim(),
    payload.endTime.trim(),
  ].where((value) => value.isNotEmpty).join(' ');
  return [start, end].where((value) => value.isNotEmpty).join(' ΓÇô ');
}

class _DecisionNodeDetails extends StatelessWidget {
  const _DecisionNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = DecisionPayload.fromNode(node);
    final hasContent =
        payload.question.trim().isNotEmpty ||
        payload.criteria.isNotEmpty ||
        payload.options.isNotEmpty ||
        payload.rationale.trim().isNotEmpty;
    if (!hasContent) {
      return _MiniDetailList(
        items: node.body
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .take(3)
            .toList(growable: false),
      );
    }
    final theme = Theme.of(context);
    final scores = payload.weightedScores;
    final selected = payload.selectedOption;
    final recommended = payload.options
        .where((option) => option.id == payload.recommendedOptionId)
        .firstOrNull;
    return Container(
      key: const ValueKey<String>('decision-collapsed-preview'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _DecisionPreviewBadge(
                label: _decisionPreviewLabel(payload.status),
              ),
              _DecisionPreviewBadge(label: 'Confidence ${payload.confidence}%'),
              _DecisionPreviewBadge(
                label: 'Decision ${payload.decisionCompleted}/5',
              ),
            ],
          ),
          if (payload.question.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              payload.question.trim(),
              key: const ValueKey<String>('decision-preview-question'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ],
          for (final option in payload.rankedOptions.take(2))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (scores[option.id] case final score?)
                    Text(score.toStringAsFixed(1)),
                ],
              ),
            ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            Text('Selected outcome', style: theme.textTheme.labelMedium),
            Text(
              selected.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ] else if (recommended != null) ...[
            const SizedBox(height: 8),
            Text('Recommended', style: theme.textTheme.labelMedium),
            Text(
              recommended.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (payload.reviewDate.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Review ${payload.reviewDate}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _DecisionPreviewBadge extends StatelessWidget {
  const _DecisionPreviewBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

String _decisionPreviewLabel(String value) => switch (value) {
  'evaluating' => 'Evaluating',
  'decided' => 'Decided',
  'reviewing' => 'Reviewing',
  'reversed' => 'Reversed',
  _ => 'Draft',
};

class _IdeaNodeDetails extends StatelessWidget {
  const _IdeaNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = IdeaPayload.fromNode(node);
    final hasStructuredContent =
        payload.hypothesis.trim().isNotEmpty ||
        payload.evidence.trim().isNotEmpty ||
        payload.nextAction.trim().isNotEmpty ||
        payload.impact.isNotEmpty ||
        payload.effort.isNotEmpty ||
        payload.confidence > 0;
    if (!hasStructuredContent) {
      final lines = node.body
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(3)
          .toList(growable: false);
      return _MiniDetailList(items: lines);
    }

    final theme = Theme.of(context);
    return Column(
      key: const ValueKey<String>('idea-collapsed-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _IdeaPreviewBadge(
              label: _ideaPreviewLabel(payload.maturity),
              color: theme.colorScheme.primary,
            ),
            if (payload.impact.isNotEmpty)
              _IdeaPreviewBadge(
                label: 'Impact ${_ideaPreviewLabel(payload.impact)}',
                color: theme.colorScheme.tertiary,
              ),
            if (payload.effort.isNotEmpty)
              _IdeaPreviewBadge(
                label: 'Effort ${_ideaPreviewLabel(payload.effort)}',
                color: theme.colorScheme.secondary,
              ),
            if (payload.confidence > 0)
              _IdeaPreviewBadge(
                label: '${payload.confidence}% confidence',
                color: theme.colorScheme.primary,
              ),
          ],
        ),
        if (payload.hypothesis.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Hypothesis', style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            payload.hypothesis,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Validation ${payload.validationCompleted}/3',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LinearProgressIndicator(
                key: const ValueKey<String>('idea-collapsed-progress'),
                value: payload.validationCompleted / 3,
                minHeight: 5,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
        if (payload.nextAction.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Next experiment', style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            payload.nextAction,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _IdeaPreviewBadge extends StatelessWidget {
  const _IdeaPreviewBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

String _ideaPreviewLabel(String value) =>
    value.isEmpty ? 'Spark' : '${value[0].toUpperCase()}${value.substring(1)}';

class _QuestionNodeDetails extends StatelessWidget {
  const _QuestionNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = QuestionPayload.fromNode(node);
    final hasStructuredData =
        payload.questionText.trim().isNotEmpty ||
        payload.questionContext.trim().isNotEmpty ||
        payload.possibleAnswers.isNotEmpty ||
        payload.questionSources.isNotEmpty ||
        payload.nextResearchAction.trim().isNotEmpty ||
        payload.questionConfidence > 0;
    if (!hasStructuredData) {
      return _MiniDetailList(
        items: <String>[
          if (payload.investigationStatus.trim().isNotEmpty)
            payload.investigationStatus,
          if (payload.answer.trim().isNotEmpty) payload.answer,
          if (payload.evidence.trim().isNotEmpty) payload.evidence,
        ],
      );
    }
    final theme = Theme.of(context);
    final statusLabel = switch (payload.investigationStatus) {
      'researching' => 'Researching',
      'answered' => 'Answered',
      'blocked' => 'Blocked',
      _ => 'Open',
    };
    return Container(
      key: const ValueKey<String>('question-collapsed-preview'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuestionPreviewChip(label: statusLabel),
              _QuestionPreviewChip(
                label: 'Confidence ${payload.questionConfidence}%',
              ),
              _QuestionPreviewChip(
                label: 'Research ${payload.researchCompleted}/4',
              ),
            ],
          ),
          if (payload.questionText.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              payload.questionText.trim(),
              key: const ValueKey<String>('question-preview-text'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ],
          for (final answer
              in payload.possibleAnswers
                  .where((value) => value.trim().isNotEmpty)
                  .take(2))
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '? ${answer.trim()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (payload.answer.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Accepted answer', style: theme.textTheme.labelMedium),
            Text(
              payload.answer.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ] else if (payload.nextResearchAction.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Next research action', style: theme.textTheme.labelMedium),
            Text(
              payload.nextResearchAction.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionPreviewChip extends StatelessWidget {
  const _QuestionPreviewChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _ContactNodeDetails extends StatelessWidget {
  const _ContactNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = ContactPayload.fromNode(node);
    final contacts = <ContactRecord>[
      ContactRecord(
        id: 'primary',
        name: node.title,
        role: payload.role,
        company: payload.company,
        email: payload.email,
        dialCode: payload.dialCode,
        phone: payload.phone,
      ),
      ...payload.additionalContacts,
    ];
    final selected = contacts
        .where((contact) => payload.collapsedContactIds.contains(contact.id))
        .toList();
    final visible = selected.take(2).toList();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final contact in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Name: ${contact.name.trim().isEmpty ? 'Unnamed contact' : contact.name.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (contact.role.trim().isNotEmpty)
                        Text(
                          'Role: ${contact.role.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (contact.email.trim().isNotEmpty)
                        Text(
                          contact.email.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (contact.phone.trim().isNotEmpty)
                        Text(
                          '${contact.dialCode} ${contact.phone.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (contact.email.trim().isNotEmpty)
                  IconButton.filledTonal(
                    key: ValueKey<String>('contact-copy-email-${contact.id}'),
                    tooltip:
                        'Copy ${contact.name.trim().isEmpty ? 'contact' : contact.name.trim()} email',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: contact.email.trim()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${contact.name.trim().isEmpty ? 'Contact' : contact.name.trim()} email copied',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
              ],
            ),
          ),
        if (selected.length > visible.length)
          Text(
            '+${selected.length - visible.length} more selected',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
      ],
    );
  }
}

class _MetricNodeDetails extends StatelessWidget {
  const _MetricNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = MetricPayload.fromNode(node);
    final value = payload.value;
    final target = payload.target;
    final progress = value == null || target == null || target == 0
        ? 0.0
        : payload.direction == 'atMost'
        ? (target.abs() / value.abs()).clamp(0.0, 1.0)
        : (value / target).clamp(0.0, 1.0);
    final reached = value != null && target != null
        ? payload.direction == 'atMost'
              ? value <= target
              : value >= target
        : false;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _metricCollapsedLabel(node),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        if (target != null) ...[
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 4),
          Text(
            reached
                ? 'Target reached'
                : '${payload.direction == 'atMost' ? 'Maximum' : 'Minimum'} target: $target ${payload.unit}'
                      .trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}

String _metricCollapsedLabel(MindmapNode node) {
  final payload = MetricPayload.fromNode(node);
  final value = payload.value?.toString() ?? 'ΓÇö';
  return '$value ${payload.unit}'.trim();
}

String _expenseCollapsedLabel(MindmapNode node) {
  final payload = ExpensePayload.fromNode(node);
  final amount = payload.amount?.toString() ?? 'ΓÇö';
  final value =
      '${payload.currency.isEmpty ? '' : '${payload.currency} '}$amount';
  return payload.category.isEmpty ? value : '$value ┬╖ ${payload.category}';
}

class _ExpenseNodeDetails extends StatelessWidget {
  const _ExpenseNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = ExpensePayload.fromNode(node);
    final amount = payload.amount?.toString() ?? 'ΓÇö';
    return _MiniDetailList(
      items: [
        '${payload.currency.isEmpty ? '' : '${payload.currency} '}$amount',
        if (payload.category.isNotEmpty) 'Category: ${payload.category}',
        if (payload.merchant.isNotEmpty) 'Merchant: ${payload.merchant}',
        if (payload.payment.isNotEmpty) 'Payment: ${payload.payment}',
        if (payload.receipts.isNotEmpty)
          '${payload.receipts.length} receipt${payload.receipts.length == 1 ? '' : 's'}',
      ],
    );
  }
}

class _ResourceNodeDetails extends StatelessWidget {
  const _ResourceNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final payload = ResourcePayload.fromNode(node);
    final assetCount =
        (payload.primaryAsset == null ? 0 : 1) + payload.relatedAssets.length;
    return _MiniDetailList(
      items: [
        if (payload.folderPath.isNotEmpty)
          'Folder: ${payload.folderPath.join(' / ')}',
        'Assets: $assetCount',
      ],
    );
  }
}

class _BookmarkNodeDetails extends StatelessWidget {
  const _BookmarkNodeDetails({required this.node, this.maxItems});

  final MindmapNode node;
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    final payload = LinkResourcePayload.fromNode(node);
    final items = <String>[
      if (payload.url.trim().isNotEmpty) 'URL: ${_displayUrl(payload.url)}',
      if (payload.description.trim().isNotEmpty)
        'Why saved: ${payload.description.trim()}',
      if (payload.collection.trim().isNotEmpty)
        'Collection: ${payload.collection.trim()}',
    ];
    return _MiniDetailList(
      items: items.take(maxItems ?? items.length).toList(growable: false),
    );
  }
}

class _RoutineNodeDetails extends StatelessWidget {
  const _RoutineNodeDetails({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final steps = node.checklist.map((item) => '├óΓÇá┬╗ ${item.title}').take(3);
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
    final project = PlanPayload.fromNode(node).project;
    if (project.phases.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showProgressLabel = constraints.maxWidth >= 220;
        return Column(
          key: const ValueKey<String>('plan-collapsed-preview'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  _statusIcon(project.status),
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: project.progress,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                if (showProgressLabel) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${project.completedTaskCount}/${project.taskCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            for (final phase in project.phases) ...[
              Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      phase.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (showProgressLabel)
                    Text(
                      '${(phase.progress * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (final milestone in phase.milestones) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          milestone.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                for (final task in milestone.tasks)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, bottom: 3),
                    child: Row(
                      children: [
                        Icon(
                          task.status == ProjectTaskStatus.done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 13,
                          color: task.status == ProjectTaskStatus.done
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              decoration: task.status == ProjectTaskStatus.done
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: task.status == ProjectTaskStatus.done
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 4),
            ],
          ],
        );
      },
    );
  }

  IconData _statusIcon(ProjectPlanStatus status) => switch (status) {
    ProjectPlanStatus.planning => Icons.edit_calendar_outlined,
    ProjectPlanStatus.active => Icons.play_circle_outline,
    ProjectPlanStatus.blocked => Icons.block_outlined,
    ProjectPlanStatus.completed => Icons.check_circle_outline,
    ProjectPlanStatus.archived => Icons.archive_outlined,
  };
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
        for (final m in milestones.take(3))
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
        if (milestones.length > 3)
          Text(
            '+${milestones.length - 3} more',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
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
              child: Text('ΓÇó $g', style: theme.textTheme.bodySmall),
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
    final semantic = AppSemanticColors.of(context);
    if (node.type == NodeType.note) {
      final payload = NotePayload.fromNode(node);
      final indicators = <Widget>[
        if (node.isPinned)
          const Tooltip(
            message: 'Pinned',
            child: Icon(Icons.push_pin, size: 15),
          ),
        if (payload.color != 'neutral')
          Tooltip(
            message: payload.color,
            child: Icon(
              Icons.palette_outlined,
              size: 15,
              color: switch (payload.color) {
                'violet' => semantic.nodeColors[NodeType.goal]!,
                'blue' => semantic.info,
                'green' => semantic.success,
                'amber' => semantic.warning,
                'rose' => semantic.nodeColors[NodeType.journal]!,
                _ => semantic.border,
              },
            ),
          ),
        if (payload.sourceLinks.isNotEmpty)
          Text('${payload.sourceLinks.length} sources'),
        if (payload.attachments.isNotEmpty)
          Text('${payload.attachments.length} files'),
        if (node.relatedNodeIds.isNotEmpty)
          Text('${node.relatedNodeIds.length} related'),
      ];
      if (indicators.isEmpty && node.tags.isEmpty) {
        return const SizedBox.shrink();
      }
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ...indicators,
          for (final tag in node.tags.take(3))
            Text(
              '#$tag',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      );
    }

    final data = _sectionData(node.data, 'link');
    final source = (data['source'] as String?) ?? (data['url'] as String?);
    if (source == null || source.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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

class CollaborationRoomBar extends ConsumerStatefulWidget {
  const CollaborationRoomBar({
    super.key,
    required this.nodes,
    this.followingId,
    this.onFollowChanged,
  });

  final List<MindmapNode> nodes;
  final String? followingId;
  final ValueChanged<String?>? onFollowChanged;

  @override
  ConsumerState<CollaborationRoomBar> createState() =>
      _CollaborationRoomBarState();
}

class _CollaborationRoomBarState extends ConsumerState<CollaborationRoomBar> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final collabState = ref.watch(collaborationProvider);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final compactIconStyle = IconButton.styleFrom(
      minimumSize: Size.square(tokens.minimumTarget),
      maximumSize: Size.square(tokens.minimumTarget),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );

    return SizedBox(
      key: const ValueKey('collab-room-bar'),
      height: tokens.minimumTarget,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: semantic.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusElement),
            side: BorderSide(color: semantic.border),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing[5]),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: semantic.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final rId = collabState.roomId;
                  if (rId != null && rId.isNotEmpty) {
                    final url = 'var-collab://var.app/room/$rId';
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
              if (!_isExpanded) ...[
                const SizedBox(width: 8),
                Text(
                  '${collabState.collaborators.length} peers',
                  style: theme.textTheme.labelSmall,
                ),
              ],
              IconButton(
                key: const ValueKey('collab-room-bar-toggle'),
                style: compactIconStyle,
                icon: Icon(
                  _isExpanded ? Icons.remove : Icons.open_in_full,
                  size: 16,
                ),
                tooltip: _isExpanded
                    ? 'Minimize collaboration tools'
                    : 'Maximize collaboration tools',
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
              ),
              if (_isExpanded) ...[
                VerticalDivider(
                  width: 12,
                  indent: 9,
                  endIndent: 9,
                  color: theme.colorScheme.outlineVariant,
                ),
                for (final peer in collabState.collaborators.values) ...[
                  _PeerAvatar(
                    peer: peer,
                    isFollowing: widget.followingId == peer.id,
                    onTap: () {
                      if (widget.onFollowChanged == null) return;
                      widget.onFollowChanged!(
                        widget.followingId == peer.id ? null : peer.id,
                      );
                    },
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  style: compactIconStyle,
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
                  style: compactIconStyle,
                  icon: const Icon(Icons.share_outlined, size: 16),
                  tooltip: 'Copy collab link',
                  onPressed: () => context.go('/collab'),
                ),
                if (collabState.roomId == null || collabState.roomId!.isEmpty)
                  IconButton(
                    style: compactIconStyle,
                    icon: const Icon(Icons.login, size: 16),
                    tooltip: 'Join with Code',
                    onPressed: () => context.go('/collab'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
        ? ' ΓÇócurrently editing'
        : peer.selectedNodeId != null
        ? ' ΓÇóhas a node selected'
        : '';
    return '$base$activity';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isFollowing ? peer.color : Colors.transparent;
    // Subtle ring tint when peer is actively doing something, even if not
    // followed ΓÇö gives the toolbar some life at a glance.
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
