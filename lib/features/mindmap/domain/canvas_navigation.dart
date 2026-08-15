import 'dart:ui';

import 'canvas_board.dart';
import 'mindmap_node.dart';
import 'node_ui_state_codec.dart';

enum CanvasSearchResultKind { node, canvasObject }

enum CanvasSearchCategory { all, nodes, notesAndText, frames, media, links }

final class CanvasSearchResult {
  const CanvasSearchResult({
    required this.id,
    required this.kind,
    required this.label,
    required this.secondaryLabel,
    required this.searchableText,
    required this.bounds,
    this.nodeId,
    this.objectId,
  });

  final String id;
  final CanvasSearchResultKind kind;
  final String label;
  final String secondaryLabel;
  final String searchableText;
  final Rect bounds;
  final String? nodeId;
  final String? objectId;

  Offset get center => bounds.center;
}

final class CanvasNavigationIndex {
  CanvasNavigationIndex({
    required List<MindmapNode> nodes,
    required CanvasBoard? board,
  }) : entries = List<CanvasSearchResult>.unmodifiable(
         _buildEntries(nodes, board),
       );

  final List<CanvasSearchResult> entries;

  List<CanvasSearchResult> search(
    String query, {
    CanvasSearchCategory category = CanvasSearchCategory.all,
  }) {
    final normalized = _normalize(query);
    final terms = normalized.split(' ').where((term) => term.isNotEmpty);
    final matches = entries
        .where((entry) {
          if (!_matchesCategory(entry, category)) return false;
          return terms.every(entry.searchableText.contains);
        })
        .toList(growable: false);
    matches.sort((left, right) {
      final leftStarts = left.searchableText.startsWith(normalized);
      final rightStarts = right.searchableText.startsWith(normalized);
      if (leftStarts != rightStarts) return leftStarts ? -1 : 1;
      final top = left.bounds.top.compareTo(right.bounds.top);
      return top != 0 ? top : left.bounds.left.compareTo(right.bounds.left);
    });
    return matches;
  }

  CanvasSearchResult? nearest({
    required Offset from,
    required Offset direction,
    Iterable<CanvasSearchResult>? candidates,
  }) {
    if (direction == Offset.zero) return null;
    final length = direction.distance;
    final unit = direction / length;
    CanvasSearchResult? best;
    var bestScore = double.infinity;
    for (final candidate in candidates ?? entries) {
      final delta = candidate.center - from;
      final forward = delta.dx * unit.dx + delta.dy * unit.dy;
      if (forward <= 0) continue;
      final perpendicular = (delta.dx * unit.dy - delta.dy * unit.dx).abs();
      final score = forward + perpendicular * 2;
      if (score < bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  static List<CanvasSearchResult> _buildEntries(
    List<MindmapNode> nodes,
    CanvasBoard? board,
  ) {
    final references = <String, CanvasObject>{
      for (final object in board?.objects ?? const <CanvasObject>[])
        if (object.type == CanvasObjectType.nodeReference &&
            object.mindmapNodeId != null)
          object.mindmapNodeId!: object,
    };
    return <CanvasSearchResult>[
      for (final node in nodes) _nodeEntry(node, references[node.id]),
      for (final object in board?.objects ?? const <CanvasObject>[])
        if (object.type != CanvasObjectType.nodeReference && object.isVisible)
          _objectEntry(object),
    ];
  }

  static CanvasSearchResult _nodeEntry(
    MindmapNode node,
    CanvasObject? reference,
  ) {
    final uiState = NodeUiStateCodec.read(node);
    final geometry = reference?.geometry;
    final bounds = Rect.fromLTWH(
      geometry?.x ?? node.position.dx,
      geometry?.y ?? node.position.dy,
      geometry?.width ?? uiState.width,
      geometry?.height ?? uiState.height,
    );
    final metadata = <String>[
      node.title,
      node.body,
      node.type.label,
      node.project,
      node.area,
      ...node.tags,
    ];
    return CanvasSearchResult(
      id: 'node:${node.id}',
      kind: CanvasSearchResultKind.node,
      label: node.title.trim().isEmpty
          ? 'Untitled ${node.type.label}'
          : node.title,
      secondaryLabel: node.type.label,
      searchableText: _normalize(metadata.join(' ')),
      bounds: bounds,
      nodeId: node.id,
      objectId: reference?.id,
    );
  }

  static CanvasSearchResult _objectEntry(CanvasObject object) {
    final text = <String>[
      for (final key in const <String>[
        'text',
        'title',
        'description',
        'caption',
        'url',
        'altText',
      ])
        if (object.payload[key] is String) object.payload[key]! as String,
    ];
    final fallback = _objectTypeLabel(object.type);
    final label =
        text.where((value) => value.trim().isNotEmpty).firstOrNull ?? fallback;
    return CanvasSearchResult(
      id: 'object:${object.id}',
      kind: CanvasSearchResultKind.canvasObject,
      label: label,
      secondaryLabel: fallback,
      searchableText: _normalize(<String>[fallback, ...text].join(' ')),
      bounds: Rect.fromLTWH(
        object.geometry.x,
        object.geometry.y,
        object.geometry.width,
        object.geometry.height,
      ),
      objectId: object.id,
    );
  }

  static bool _matchesCategory(
    CanvasSearchResult entry,
    CanvasSearchCategory category,
  ) {
    if (category == CanvasSearchCategory.all) return true;
    if (category == CanvasSearchCategory.nodes) {
      return entry.kind == CanvasSearchResultKind.node;
    }
    if (entry.kind != CanvasSearchResultKind.canvasObject) return false;
    return switch (category) {
      CanvasSearchCategory.notesAndText =>
        entry.secondaryLabel == 'Sticky note' || entry.secondaryLabel == 'Text',
      CanvasSearchCategory.frames => entry.secondaryLabel == 'Frame',
      CanvasSearchCategory.media => entry.secondaryLabel == 'Image',
      CanvasSearchCategory.links => entry.secondaryLabel == 'Link preview',
      CanvasSearchCategory.all || CanvasSearchCategory.nodes => false,
    };
  }
}

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

String _objectTypeLabel(CanvasObjectType type) => switch (type) {
  CanvasObjectType.stickyNote => 'Sticky note',
  CanvasObjectType.text => 'Text',
  CanvasObjectType.shape => 'Shape',
  CanvasObjectType.connector => 'Connector',
  CanvasObjectType.freehand => 'Freehand',
  CanvasObjectType.frame => 'Frame',
  CanvasObjectType.image => 'Image',
  CanvasObjectType.linkPreview => 'Link preview',
  CanvasObjectType.column => 'Column',
  CanvasObjectType.boardReference => 'Board',
  CanvasObjectType.nodeReference => 'Node',
  CanvasObjectType.unknown => 'Object',
};

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
