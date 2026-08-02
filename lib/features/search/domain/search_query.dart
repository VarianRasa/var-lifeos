import 'package:collection/collection.dart';

import 'search_document.dart';

const _setEquality = SetEquality<Object?>();

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

  SearchFilters copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDates = false,
    Set<SearchSourceKind>? sourceKinds,
    Set<String>? workspaceIds,
    Set<String>? boardIds,
    Set<String>? creatorIds,
    Set<String>? statuses,
  }) => SearchFilters(
    dateFrom: clearDates ? null : dateFrom ?? this.dateFrom,
    dateTo: clearDates ? null : dateTo ?? this.dateTo,
    sourceKinds: sourceKinds ?? this.sourceKinds,
    workspaceIds: workspaceIds ?? this.workspaceIds,
    boardIds: boardIds ?? this.boardIds,
    creatorIds: creatorIds ?? this.creatorIds,
    statuses: statuses ?? this.statuses,
  );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.dateFrom == dateFrom &&
      other.dateTo == dateTo &&
      _setEquality.equals(other.sourceKinds, sourceKinds) &&
      _setEquality.equals(other.workspaceIds, workspaceIds) &&
      _setEquality.equals(other.boardIds, boardIds) &&
      _setEquality.equals(other.creatorIds, creatorIds) &&
      _setEquality.equals(other.statuses, statuses);

  @override
  int get hashCode => Object.hash(
    dateFrom,
    dateTo,
    _setEquality.hash(sourceKinds),
    _setEquality.hash(workspaceIds),
    _setEquality.hash(boardIds),
    _setEquality.hash(creatorIds),
    _setEquality.hash(statuses),
  );
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

  @override
  bool operator ==(Object other) =>
      other is SearchQuery &&
      other.text == text &&
      other.activeWorkspaceId == activeWorkspaceId &&
      other.filters == filters;

  @override
  int get hashCode => Object.hash(text, activeWorkspaceId, filters);
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
