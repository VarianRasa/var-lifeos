import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_query.dart';

void main() {
  test('queries with equal filter values compare equal', () {
    final first = SearchQuery(
      text: 'launch',
      activeWorkspaceId: 'project:launch',
      filters: SearchFilters(
        dateFrom: DateTime.utc(2026, 8, 1),
        sourceKinds: const {SearchSourceKind.node},
        workspaceIds: const {'project:launch'},
      ),
    );
    final second = SearchQuery(
      text: 'launch',
      activeWorkspaceId: 'project:launch',
      filters: SearchFilters(
        dateFrom: DateTime.utc(2026, 8, 1),
        sourceKinds: const {SearchSourceKind.node},
        workspaceIds: const {'project:launch'},
      ),
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}
