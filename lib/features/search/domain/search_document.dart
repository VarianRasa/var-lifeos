enum SearchSourceKind {
  node,
  board,
  canvasObject,
  comment,
  attachment,
  document,
  imageOcr,
  transcript,
  article,
  bookmark,
}

enum SearchExtractionState { queued, processing, ready, partial, failed }

final class SearchDocument {
  const SearchDocument({
    required this.id,
    required this.sourceId,
    required this.fragmentId,
    required this.sourceKind,
    required this.workspaceId,
    required this.title,
    required this.snippet,
    required this.text,
    required this.modifiedAt,
    this.boardId,
    this.creatorId,
    this.status,
    this.date,
    this.extractionState = SearchExtractionState.ready,
  });

  final String id;
  final String sourceId;
  final String fragmentId;
  final SearchSourceKind sourceKind;
  final String workspaceId;
  final String? boardId;
  final String? creatorId;
  final String? status;
  final String title;
  final String snippet;
  final String text;
  final DateTime? date;
  final DateTime modifiedAt;
  final SearchExtractionState extractionState;
}
