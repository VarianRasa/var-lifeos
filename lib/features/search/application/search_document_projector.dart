import '../../mindmap/domain/canvas_board.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_attachment.dart';
import '../../mindmap/domain/node_comment.dart';
import '../domain/search_document.dart';

final class SearchDocumentProjector {
  const SearchDocumentProjector();

  static const _nodeDataKeys = {
    'caption',
    'content',
    'description',
    'notes',
    'quote',
    'source',
    'summary',
    'text',
    'transcript',
    'url',
  };

  List<SearchDocument> projectNode(
    MindmapNode node, {
    required String workspaceId,
  }) {
    final dataText = <String>[
      for (final entry in node.data.entries)
        if (_nodeDataKeys.contains(entry.key)) ..._userText(entry.value),
    ];
    final annotationText = _annotationPinText(node.data['annotations']);
    final text = _join([
      node.title,
      node.body,
      node.type.name,
      node.status.name,
      node.priority.name,
      node.project,
      node.area,
      ...node.tags,
      ...node.contextTags,
      ...node.checklist.map((item) => item.title),
      ...dataText,
      ...annotationText,
    ]);
    return [
      SearchDocument(
        id: 'node:${node.id}:main',
        sourceId: node.id,
        fragmentId: 'main',
        sourceKind: SearchSourceKind.node,
        workspaceId: workspaceId,
        title: node.title,
        snippet: node.body,
        text: text,
        date: node.day,
        modifiedAt: node.updatedAt.toUtc(),
        status: node.status.name,
      ),
    ];
  }

  List<SearchDocument> projectBoard(CanvasBoard board) {
    final workspaceId = board.workspaceName ?? 'daily';
    return [
      SearchDocument(
        id: 'board:${board.id}:main',
        sourceId: board.id,
        fragmentId: 'main',
        sourceKind: SearchSourceKind.board,
        workspaceId: workspaceId,
        boardId: board.id,
        title: board.title,
        snippet: workspaceId,
        text: _join([board.title, workspaceId]),
        modifiedAt: board.updatedAt.toUtc(),
      ),
      for (final object in board.objects)
        ...projectCanvasObject(object, board: board),
    ];
  }

  List<SearchDocument> projectCanvasObject(
    CanvasObject object, {
    required CanvasBoard board,
  }) {
    final workspaceId = board.workspaceName ?? 'daily';
    final payloadText = <String>[
      for (final key in const ['title', 'text', 'body', 'caption', 'url'])
        ..._userText(object.payload[key]),
    ];
    final title = payloadText.firstOrNull ?? object.type.name;
    return [
      SearchDocument(
        id: 'canvasObject:${object.id}:main',
        sourceId: object.id,
        fragmentId: 'main',
        sourceKind: SearchSourceKind.canvasObject,
        workspaceId: workspaceId,
        boardId: board.id,
        title: title,
        snippet: _join(payloadText),
        text: _join([object.type.name, ...payloadText]),
        modifiedAt: object.updatedAt.toUtc(),
      ),
      for (final comment in object.comments)
        SearchDocument(
          id: 'comment:${object.id}:${comment.id}',
          sourceId: object.id,
          fragmentId: comment.id,
          sourceKind: SearchSourceKind.comment,
          workspaceId: workspaceId,
          boardId: board.id,
          creatorId: comment.authorName,
          status: comment.isResolved ? 'resolved' : 'open',
          title: title,
          snippet: comment.body,
          text: _join([comment.body, comment.authorName]),
          date: comment.createdAt.toUtc(),
          modifiedAt: object.updatedAt.toUtc(),
        ),
    ];
  }

  SearchDocument projectNodeComment(
    NodeComment comment, {
    required String workspaceId,
    String? boardId,
    required DateTime modifiedAt,
  }) => SearchDocument(
    id: 'comment:${comment.nodeId}:${comment.id}',
    sourceId: comment.nodeId,
    fragmentId: comment.id,
    sourceKind: SearchSourceKind.comment,
    workspaceId: workspaceId,
    boardId: boardId,
    creatorId: comment.authorUid,
    title: comment.authorDisplayName,
    snippet: comment.body,
    text: _join([comment.body, comment.authorDisplayName]),
    date: comment.createdAt.toUtc(),
    modifiedAt: modifiedAt.toUtc(),
  );

  SearchDocument projectAttachment(
    NodeAttachment attachment, {
    required String sourceId,
    required String workspaceId,
    String? boardId,
  }) => SearchDocument(
    id: 'attachment:$sourceId:${attachment.id}',
    sourceId: sourceId,
    fragmentId: attachment.id,
    sourceKind: SearchSourceKind.attachment,
    workspaceId: workspaceId,
    boardId: boardId,
    title: attachment.fileName,
    snippet: attachment.mimeType,
    text: _join([attachment.fileName, attachment.mimeType]),
    date: attachment.createdAt.toUtc(),
    modifiedAt: attachment.createdAt.toUtc(),
  );
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Iterable<String> _annotationPinText(Object? value) sync* {
  if (value is! Map) return;
  final pins = value['pins'];
  if (pins is! Iterable) return;
  for (final pin in pins) {
    if (pin is Map) yield* _userText(pin['text']);
  }
}

Iterable<String> _userText(Object? value) sync* {
  if (value is String && value.trim().isNotEmpty) {
    yield value.trim();
  } else if (value is Iterable) {
    for (final item in value) {
      yield* _userText(item);
    }
  }
}

String _join(Iterable<String> values) => values
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .join(' ');
