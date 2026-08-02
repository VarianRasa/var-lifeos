import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_query.dart';
import 'package:var_app/features/search/domain/search_ranking.dart';

void main() {
  test('filters reject mismatched workspace before ranking', () {
    final document = SearchDocument(
      id: 'node:1:main',
      sourceId: '1',
      fragmentId: 'main',
      sourceKind: SearchSourceKind.node,
      workspaceId: 'workspace-a',
      title: 'Launch plan',
      snippet: 'Prepare release',
      text: 'Launch plan Prepare release',
      modifiedAt: DateTime.utc(2026, 8, 3),
    );

    expect(
      matchesSearchFilters(
        document,
        const SearchFilters(workspaceIds: {'workspace-b'}),
      ),
      isFalse,
    );
  });

  test('ranking boosts active workspace and recent edits', () {
    final now = DateTime.utc(2026, 8, 3);
    final active = rankSearchResult(
      bm25: -2,
      modifiedAt: now.subtract(const Duration(days: 1)),
      workspaceId: 'active',
      activeWorkspaceId: 'active',
      now: now,
    );
    final stale = rankSearchResult(
      bm25: -2,
      modifiedAt: now.subtract(const Duration(days: 90)),
      workspaceId: 'other',
      activeWorkspaceId: 'active',
      now: now,
    );

    expect(active, greaterThan(stale));
  });
}
