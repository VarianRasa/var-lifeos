import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/search/application/search_providers.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_query.dart';
import 'package:var_app/features/search/domain/search_result.dart';
import 'package:var_app/features/search/presentation/search_page.dart';

void main() {
  testWidgets('shows query, every filter, preview, and extraction state', (
    tester,
  ) async {
    const query = SearchQuery(text: 'launch');
    final result = SearchResult(
      document: SearchDocument(
        id: 'document:one:main',
        sourceId: 'one',
        fragmentId: 'main',
        sourceKind: SearchSourceKind.document,
        workspaceId: 'project:launch',
        boardId: 'board-one',
        creatorId: 'Ada',
        status: 'open',
        title: 'Launch brief',
        snippet: 'Ship global search',
        text: 'Launch brief Ship global search',
        modifiedAt: DateTime.utc(2026, 8, 3),
        extractionState: SearchExtractionState.partial,
      ),
      rank: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchResultsProvider(query).overrideWith((ref) async => [result]),
        ],
        child: const MaterialApp(home: SearchPage(initialQuery: 'launch')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Creator'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Launch brief'), findsOneWidget);
    expect(find.text('Ship global search'), findsOneWidget);
    expect(find.text('Partial'), findsOneWidget);
  });

  testWidgets('type filter updates search query', (tester) async {
    SearchQuery? observed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchResultsProvider.overrideWith((ref, query) async {
            observed = query;
            return const [];
          }),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('node').last);
    await tester.pumpAndSettle();

    expect(observed?.filters.sourceKinds, {SearchSourceKind.node});
  });
}
