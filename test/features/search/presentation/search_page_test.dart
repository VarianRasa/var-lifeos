import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:var_app/features/search/application/search_providers.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_query.dart';
import 'package:var_app/features/search/domain/search_result.dart';
import 'package:var_app/features/search/presentation/search_page.dart';

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

Widget _searchApp({required List<SearchResult> results}) => ProviderScope(
  overrides: [
    searchResultsProvider.overrideWith((ref, query) async => results),
  ],
  child: const MaterialApp(home: SearchPage(initialQuery: 'launch')),
);

void main() {
  testWidgets('shows query, every filter, preview, and extraction state', (
    tester,
  ) async {
    await tester.pumpWidget(_searchApp(results: [result]));
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

  testWidgets('search exposes loading state without empty copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchResultsProvider.overrideWith(
            (ref, query) => Completer<List<SearchResult>>().future,
          ),
        ],
        child: const MaterialApp(home: SearchPage(initialQuery: 'pending')),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('search-loading')), findsOneWidget);
    expect(find.text('No results'), findsNothing);
  });

  testWidgets('search empty state explains how to recover', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchResultsProvider.overrideWith((ref, query) async => const []),
        ],
        child: const MaterialApp(home: SearchPage(initialQuery: 'missing')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
    expect(find.text('No results for “missing”'), findsOneWidget);
    expect(find.text('Try fewer words or clear filters.'), findsOneWidget);
  });

  testWidgets('reduced motion exposes settled empty state', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(_searchApp(results: const []));
    await tester.pump();

    expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
    expect(find.text('No results for “launch”'), findsOneWidget);
    expect(find.text('Try fewer words or clear filters.'), findsOneWidget);
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('search-empty')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search error state has alert semantics', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchResultsProvider.overrideWith(
            (ref, query) => Future.error(StateError('index unavailable')),
          ),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-error')), findsOneWidget);
    expect(
      find.text('Search could not be completed. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('index unavailable'), findsNothing);
    expect(
      tester
          .getSemantics(find.text('Search unavailable'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
  });

  testWidgets('search controls fit representative widths and text scale', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final width in <double>[320, 768, 1024, 1440]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320 ? 2 : 1;
      await tester.pumpWidget(_searchApp(results: [result]));
      await tester.pumpAndSettle();
      expect(find.text('Launch brief'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('search result is one semantic button with full label', (
    tester,
  ) async {
    await tester.pumpWidget(_searchApp(results: [result]));
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(find.text('Launch brief'));
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.label, contains('Launch brief'));
    expect(semantics.label, contains('Ship global search'));
    final exposedResult = find.bySemanticsLabel(
      RegExp('Launch brief.*Ship global search'),
    );
    expect(exposedResult, findsOneWidget);
    expect(tester.getSemantics(exposedResult).flagsCollection.isButton, isTrue);
  });

  testWidgets('type popup keeps a 44 pixel interactive target', (tester) async {
    await tester.pumpWidget(_searchApp(results: const []));
    await tester.pumpAndSettle();

    final target = find.ancestor(
      of: find.text('Type'),
      matching: find.byType(PopupMenuButton<SearchSourceKind?>),
    );
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
  });

  testWidgets('result tap opens existing calendar destination', (tester) async {
    final nodeResult = SearchResult(
      document: SearchDocument(
        id: 'node:one:main',
        sourceId: 'node one',
        fragmentId: 'main',
        sourceKind: SearchSourceKind.node,
        workspaceId: 'default',
        creatorId: 'Ada',
        status: 'open',
        title: 'Daily task',
        snippet: 'Finish search',
        text: 'Daily task Finish search',
        date: DateTime(2026, 8, 9),
        modifiedAt: DateTime.utc(2026, 8, 9),
        extractionState: SearchExtractionState.ready,
      ),
      rank: 1,
    );
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchPage(initialQuery: 'task'),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) => const SizedBox(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchResultsProvider.overrideWith(
            (ref, query) async => [nodeResult],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Daily task'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-08-09?highlight=node+one',
    );
  });

  testWidgets('query edit replaces search URL', (tester) async {
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (context, state) =>
              SearchPage(initialQuery: state.uri.queryParameters['q'] ?? ''),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchResultsProvider.overrideWith((ref, query) async => const []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-search-query')),
      'launch plan',
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/search?q=launch+plan',
    );
  });
}
