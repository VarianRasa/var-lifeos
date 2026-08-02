double rankSearchResult({
  required double bm25,
  required DateTime modifiedAt,
  required String workspaceId,
  required String? activeWorkspaceId,
  required DateTime now,
}) {
  final relevance = -bm25;
  final ageHours = now.difference(modifiedAt).inHours.clamp(0, 87600);
  final ageDays = ageHours / 24;
  final recency = 1 / (1 + ageDays / 30);
  final workspaceBoost = workspaceId == activeWorkspaceId ? 0.35 : 0.0;
  return relevance + recency + workspaceBoost;
}
