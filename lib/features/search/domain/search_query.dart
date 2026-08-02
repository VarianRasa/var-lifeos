import 'search_document.dart';

final class SearchFilters {
  const SearchFilters({
    this.dateFrom,
    this.dateTo,
    this.sourceKinds = const {},
    this.workspaceIds = const {},
    this.boardIds = const {},
    this.creatorIds = const {},
    this.statuses = const {},
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final Set<SearchSourceKind> sourceKinds;
  final Set<String> workspaceIds;
  final Set<String> boardIds;
  final Set<String> creatorIds;
  final Set<String> statuses;
}

final class SearchQuery {
  const SearchQuery({
    required this.text,
    this.activeWorkspaceId,
    this.filters = const SearchFilters(),
  });

  final String text;
  final String? activeWorkspaceId;
  final SearchFilters filters;
}

bool matchesSearchFilters(SearchDocument document, SearchFilters filters) {
  if (filters.workspaceIds.isNotEmpty &&
      !filters.workspaceIds.contains(document.workspaceId)) {
    return false;
  }
  if (filters.sourceKinds.isNotEmpty &&
      !filters.sourceKinds.contains(document.sourceKind)) {
    return false;
  }
  if (filters.boardIds.isNotEmpty &&
      !filters.boardIds.contains(document.boardId)) {
    return false;
  }
  if (filters.creatorIds.isNotEmpty &&
      !filters.creatorIds.contains(document.creatorId)) {
    return false;
  }
  if (filters.statuses.isNotEmpty &&
      !filters.statuses.contains(document.status)) {
    return false;
  }
  final date = document.date;
  if (filters.dateFrom != null &&
      (date == null || date.isBefore(filters.dateFrom!))) {
    return false;
  }
  if (filters.dateTo != null &&
      (date == null || date.isAfter(filters.dateTo!))) {
    return false;
  }
  return true;
}
